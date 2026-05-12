from __future__ import annotations

import json
from datetime import UTC, datetime
from typing import Any, Protocol

from relay.models import CaptionEvent
from relay.validation import ALLOWED_CAPTION_MODES, CaptionEventValidationError, validate_caption_event
from relay.viewer_access import ViewerAccessError
from relay.webpubsub import RelayWebPubSubError, ViewerAccessToken


class CaptionEventPublisher(Protocol):
    def publish(
        self,
        payload: dict[str, Any],
        *,
        track_number: int | None = None,
        caption_mode: str | None = None,
    ) -> None:
        pass


class ViewerTokenProvider(Protocol):
    def get_viewer_access_token(
        self,
        *,
        track_number: int | None = None,
        caption_mode: str | None = None,
        now: datetime | None = None,
    ) -> ViewerAccessToken:
        pass


class OperatorTokenProvider(Protocol):
    def get_operator_access_token(
        self,
        *,
        track_number: int | None = None,
        caption_mode: str | None = None,
        now: datetime | None = None,
    ) -> ViewerAccessToken:
        pass


def handle_caption_event_request(
    payload: Any,
    *,
    publisher: CaptionEventPublisher,
    now: datetime | None = None,
) -> tuple[int, dict[str, Any]]:
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
            )
            publisher.publish(
                publish_payload,
                track_number=event.track_number,
                caption_mode=caption_mode,
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


def handle_viewer_negotiate_request(
    access_code: str | None,
    *,
    token_provider: ViewerTokenProvider,
    access_code_verifier: ViewerAccessCodeVerifier,
    track_number: Any = None,
    caption_mode: Any = None,
    access_code_required: bool = True,
    now: datetime | None = None,
) -> tuple[int, dict[str, Any]]:
    try:
        normalized_track_number = validate_viewer_track_number(track_number)
        normalized_caption_mode = validate_caption_mode(caption_mode)
    except ValueError:
        return 400, {
            "error": {
                "code": "invalid_viewer_filter",
                "message": "Viewer filter is invalid.",
                "details": [
                    {
                        "field": "filter",
                        "reason": "Track number or caption mode is invalid.",
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
            caption_mode=normalized_caption_mode,
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
        "group": access.group_name,
        "expiresAt": _format_utc(access.expires_at),
    }


def handle_portal_negotiate_request(
    *,
    token_provider: OperatorTokenProvider,
    track_number: Any = None,
    caption_mode: Any = None,
    now: datetime | None = None,
) -> tuple[int, dict[str, Any]]:
    try:
        normalized_track_number = validate_viewer_track_number(track_number)
        normalized_caption_mode = validate_caption_mode(caption_mode)
    except ValueError:
        return 400, {
            "error": {
                "code": "invalid_portal_filter",
                "message": "Portal filter is invalid.",
                "details": [
                    {
                        "field": "filter",
                        "reason": "Track number or caption mode is invalid.",
                    }
                ],
            }
        }

    try:
        access = token_provider.get_operator_access_token(
            track_number=normalized_track_number,
            caption_mode=normalized_caption_mode,
            now=now,
        )
    except RelayWebPubSubError:
        return 502, {
            "error": {
                "code": "portal_negotiate_failed",
                "message": "Portal connection could not be negotiated.",
                "details": [],
            }
        }

    return 200, {
        "url": access.url,
        "hub": access.hub_name,
        "group": access.group_name,
        "expiresAt": _format_utc(access.expires_at),
    }


class ViewerAccessCodeVerifier(Protocol):
    def verify(self, *, access_code: str | None, now: datetime | None = None) -> None:
        pass


def build_health_payload(*, commit: str | None = None) -> dict[str, str]:
    return {
        "status": "ok",
        "commit": commit or "unknown",
    }


def validate_viewer_track_number(value: Any) -> int | None:
    if value is None or value == "":
        return None
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        raise ValueError("Track number must be a positive integer.")
    return value


def validate_caption_mode(value: Any) -> str | None:
    if value is None or value == "":
        return None
    if not isinstance(value, str) or value not in ALLOWED_CAPTION_MODES:
        raise ValueError("Caption mode is not supported.")
    return value


def build_publish_payload(
    event: CaptionEvent,
    *,
    received_at: datetime,
    caption_mode: str,
) -> dict[str, Any]:
    mode_content = event.caption_modes[caption_mode]
    return {
        "relay": {
            "receivedAt": _format_utc(received_at),
        },
        "captionMode": caption_mode,
        "captionProvider": mode_content.provider,
        "roomName": event.room_name,
        "trackNumber": event.track_number,
        "createdAt": _format_utc(event.created_at),
        "speech": {
            "inputLanguage": event.speech.input_language,
            "offsetTicks": event.speech.offset_ticks,
            "durationTicks": event.speech.duration_ticks,
        },
        "captions": mode_content.captions,
    }


def to_json_response_body(payload: dict[str, Any]) -> str:
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def _format_utc(value: datetime) -> str:
    return value.astimezone(UTC).isoformat(timespec="milliseconds").replace("+00:00", "Z")
