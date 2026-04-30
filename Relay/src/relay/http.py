from __future__ import annotations

import json
from datetime import UTC, datetime
from typing import Any, Protocol

from relay.models import CaptionEvent
from relay.validation import CaptionEventValidationError, validate_caption_event
from relay.webpubsub import RelayWebPubSubError


class CaptionEventPublisher(Protocol):
    def publish(self, payload: dict[str, Any]) -> None:
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

    publish_payload = build_publish_payload(event, received_at=now or datetime.now(UTC))
    try:
        publisher.publish(publish_payload)
    except RelayWebPubSubError:
        return 502, {
            "error": {
                "code": "caption_publish_failed",
                "message": "Caption event could not be published.",
                "details": [],
            }
        }

    return 202, {"accepted": True}


def build_health_payload(*, commit: str | None = None) -> dict[str, str]:
    return {
        "status": "ok",
        "commit": commit or "unknown",
    }


def build_publish_payload(event: CaptionEvent, *, received_at: datetime) -> dict[str, Any]:
    return {
        "relay": {
            "receivedAt": _format_utc(received_at),
        },
        "roomName": event.room_name,
        "trackNumber": event.track_number,
        "createdAt": _format_utc(event.created_at),
        "speech": {
            "inputLanguage": event.speech.input_language,
            "offsetTicks": event.speech.offset_ticks,
            "durationTicks": event.speech.duration_ticks,
        },
        "captions": event.captions,
    }


def to_json_response_body(payload: dict[str, Any]) -> str:
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def _format_utc(value: datetime) -> str:
    return value.astimezone(UTC).isoformat(timespec="milliseconds").replace("+00:00", "Z")
