from __future__ import annotations

import json
from datetime import UTC, datetime
from threading import Lock
from typing import Any, Protocol

from relay.control_state import AzureTableControlEventStateStore, ControlEventStateStore
from relay.control_state import RelayControlStateError
from relay.models import CaptionEvent, ControlEvent
from relay.validation import CaptionEventValidationError, validate_caption_event, validate_control_event
from relay.viewer_access import ViewerAccessError
from relay.webpubsub import RelayWebPubSubError, ViewerAccessToken
from relay.webpubsub import parse_viewer_track_number_from_user_id


class CaptionEventPublisher(Protocol):
    def publish(
        self,
        payload: dict[str, Any],
        *,
        track_number: int | None = None,
    ) -> None:
        pass

    def publish_to_connection(
        self,
        payload: dict[str, Any],
        *,
        connection_id: str,
    ) -> None:
        pass


class ViewerTokenProvider(Protocol):
    def get_viewer_access_token(
        self,
        *,
        track_number: int,
        now: datetime | None = None,
    ) -> ViewerAccessToken:
        pass


class SessionSequenceStore:
    def __init__(self) -> None:
        self._lock = Lock()
        self._sequences: dict[str, int] = {}

    def next(self, session_id: str) -> int:
        with self._lock:
            sequence = self._sequences.get(session_id, 0) + 1
            self._sequences[session_id] = sequence
            return sequence

    def reset(self, session_id: str) -> None:
        with self._lock:
            self._sequences.pop(session_id, None)


_sequence_store = SessionSequenceStore()


_control_event_state_store = AzureTableControlEventStateStore()


def handle_caption_event_request(
    payload: Any,
    *,
    publisher: CaptionEventPublisher,
    now: datetime | None = None,
    sequence_store: SessionSequenceStore = _sequence_store,
    control_event_state_store: ControlEventStateStore = _control_event_state_store,
) -> tuple[int, dict[str, Any]]:
    if isinstance(payload, dict) and payload.get("type") == "control":
        return handle_control_event_request(
            payload,
            publisher=publisher,
            now=now,
            sequence_store=sequence_store,
            control_event_state_store=control_event_state_store,
        )

    try:
        event = validate_caption_event(payload, now=now)
    except CaptionEventValidationError as error:
        return 400, {
            "error": {
                "code": "invalid_caption_event",
                "message": "Caption event is invalid.",
                "details": [error.as_detail()],
            }
        }

    received_at = now or datetime.now(UTC)
    try:
        for caption_mode in event.caption_modes:
            publish_payload = build_publish_payload(
                event,
                received_at=received_at,
                caption_mode=caption_mode,
                sequence=sequence_store.next(event.session_id),
            )
            publisher.publish(
                publish_payload,
                track_number=event.track_number,
            )
    except RelayWebPubSubError:
        return 502, {
            "error": {
                "code": "caption_publish_failed",
                "message": "Caption event could not be published.",
                "details": [],
            }
        }

    return 202, {"accepted": True}


def handle_control_event_request(
    payload: Any,
    *,
    publisher: CaptionEventPublisher,
    now: datetime | None = None,
    sequence_store: SessionSequenceStore = _sequence_store,
    control_event_state_store: ControlEventStateStore = _control_event_state_store,
) -> tuple[int, dict[str, Any]]:
    try:
        event = validate_control_event(payload, now=now)
    except CaptionEventValidationError as error:
        return 400, {
            "error": {
                "code": "invalid_control_event",
                "message": "Control event is invalid.",
                "details": [error.as_detail()],
            }
        }

    if event.event == "sessionStatus" and event.status == "started" and event.session_id is not None:
        sequence_store.reset(event.session_id)

    publish_payload = build_control_publish_payload(event)
    try:
        control_event_state_store.update(
            track_number=event.track_number,
            event_name=event.event,
            payload=publish_payload,
        )
    except RelayControlStateError:
        return 502, {
            "error": {
                "code": "control_state_update_failed",
                "message": "Control event state could not be saved.",
                "details": [],
            }
        }

    try:
        publisher.publish(
            publish_payload,
            track_number=event.track_number,
        )
    except RelayWebPubSubError:
        return 502, {
            "error": {
                "code": "control_publish_failed",
                "message": "Control event could not be published.",
                "details": [],
            }
        }

    return 202, {"accepted": True}


def handle_viewer_negotiate_request(
    access_code: str | None,
    *,
    token_provider: ViewerTokenProvider,
    access_code_verifier: ViewerAccessCodeVerifier,
    track_number: Any = None,
    rejected_fields: list[str] | None = None,
    access_code_required: bool = True,
    now: datetime | None = None,
) -> tuple[int, dict[str, Any]]:
    if rejected_fields:
        return 400, {
            "error": {
                "code": "invalid_viewer_filter",
                "message": "Viewer filter is invalid.",
                "details": [
                    {
                        "field": rejected_fields[0],
                        "reason": "Caption preferences are not accepted by viewer negotiate.",
                    }
                ],
            }
        }

    try:
        normalized_track_number = validate_viewer_track_number(track_number)
    except ValueError:
        return 400, {
            "error": {
                "code": "invalid_viewer_filter",
                "message": "Viewer filter is invalid.",
                "details": [
                    {
                        "field": "trackNumber",
                        "reason": "Track number must be a positive integer.",
                    }
                ],
            }
        }

    if access_code_required:
        try:
            access_code_verifier.verify(access_code=access_code, now=now)
        except ViewerAccessError:
            return 403, {
                "error": {
                    "code": "viewer_access_denied",
                    "message": "Viewer access code is invalid.",
                    "details": [],
                }
            }

    try:
        access = token_provider.get_viewer_access_token(
            track_number=normalized_track_number,
            now=now,
        )
    except RelayWebPubSubError:
        return 502, {
            "error": {
                "code": "viewer_negotiate_failed",
                "message": "Viewer connection could not be negotiated.",
                "details": [],
            }
        }

    return 200, {
        "url": access.url,
        "hub": access.hub_name,
        "expiresAt": _format_utc(access.expires_at),
    }


def handle_webpubsub_connected_event_request(
    *,
    headers: dict[str, str],
    publisher: CaptionEventPublisher,
    control_event_state_store: ControlEventStateStore = _control_event_state_store,
) -> tuple[int, dict[str, Any]]:
    event_type = _read_header(headers, "ce-type")
    if event_type != "azure.webpubsub.sys.connected":
        return 204, {}

    user_id = _read_header(headers, "ce-userid")
    connection_id = _read_header(headers, "ce-connectionid")
    if user_id is None or connection_id is None:
        return 204, {}

    track_number = parse_viewer_track_number_from_user_id(user_id)
    if track_number is None:
        return 204, {}

    try:
        for control_payload in control_event_state_store.latest_for_track(track_number):
            publisher.publish_to_connection(
                control_payload,
                connection_id=connection_id,
            )
    except (RelayControlStateError, RelayWebPubSubError):
        return 502, {
            "error": {
                "code": "viewer_state_replay_failed",
                "message": "Viewer connection state could not be published.",
                "details": [],
            }
        }

    return 204, {}


class ViewerAccessCodeVerifier(Protocol):
    def verify(self, *, access_code: str | None, now: datetime | None = None) -> None:
        pass


def build_health_payload(*, commit: str | None = None) -> dict[str, str]:
    return {
        "status": "ok",
        "commit": commit or "unknown",
    }


def validate_viewer_track_number(value: Any) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        raise ValueError("Track number must be a positive integer.")
    return value


def build_publish_payload(
    event: CaptionEvent,
    *,
    received_at: datetime,
    caption_mode: str,
    sequence: int,
) -> dict[str, Any]:
    mode_content = event.caption_modes[caption_mode]
    payload: dict[str, Any] = {
        "type": "caption",
        "sessionId": event.session_id,
        "sequence": sequence,
        "captionMode": caption_mode,
        "createdAt": _format_utc(event.created_at),
        "offsetTicks": event.speech.offset_ticks,
        "durationTicks": event.speech.duration_ticks,
        "captions": mode_content.captions,
    }

    if mode_content.provider is not None:
        payload["captionProvider"] = mode_content.provider

    return payload


def build_control_publish_payload(event: ControlEvent) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "type": "control",
        "event": event.event,
        "updatedAt": _format_utc(event.updated_at),
    }

    if event.status is not None:
        payload["status"] = event.status
    if event.session_id is not None:
        payload["sessionId"] = event.session_id
    if event.available_caption_modes is not None:
        payload["availableCaptionModes"] = event.available_caption_modes
    if event.available_languages is not None:
        payload["availableLanguages"] = event.available_languages

    return payload


def to_json_response_body(payload: dict[str, Any]) -> str:
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def _format_utc(value: datetime) -> str:
    return value.astimezone(UTC).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _read_header(headers: dict[str, str], name: str) -> str | None:
    normalized_name = name.lower()
    for key, value in headers.items():
        if key.lower() == normalized_name and value:
            return value
    return None
