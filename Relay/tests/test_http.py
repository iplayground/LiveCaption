from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from relay.http import build_health_payload, build_publish_payload
from relay.http import handle_caption_event_request
from relay.webpubsub import RelayWebPubSubError
from relay.validation import validate_caption_event

from tests.test_validation import valid_payload


class FakePublisher:
    def __init__(self, *, fail: bool = False) -> None:
        self.fail = fail
        self.payloads: list[dict[str, Any]] = []

    def publish(self, payload: dict[str, Any]) -> None:
        if self.fail:
            raise RelayWebPubSubError("boom")
        self.payloads.append(payload)


def test_handle_caption_event_request_accepts_valid_payload() -> None:
    publisher = FakePublisher()

    status_code, body = handle_caption_event_request(
        valid_payload(),
        publisher=publisher,
        now=datetime(2026, 4, 29, 12, 35, tzinfo=UTC),
    )

    assert status_code == 202
    assert body == {"accepted": True}
    assert len(publisher.payloads) == 1
    assert publisher.payloads[0]["trackNumber"] == 1
    assert publisher.payloads[0]["captions"]["en"] == "Welcome to today's event"


def test_handle_caption_event_request_returns_sanitized_error() -> None:
    payload = valid_payload()
    payload["captions"]["en"] = ""
    publisher = FakePublisher()

    status_code, body = handle_caption_event_request(
        payload,
        publisher=publisher,
        now=datetime(2026, 4, 29, 12, 35, tzinfo=UTC),
    )

    assert status_code == 400
    assert body["error"]["code"] == "invalid_caption_event"
    assert body["error"]["details"] == [
        {"field": "captions.en", "reason": "Text is required."}
    ]
    assert publisher.payloads == []


def test_handle_caption_event_request_returns_sanitized_publish_error() -> None:
    status_code, body = handle_caption_event_request(
        valid_payload(),
        publisher=FakePublisher(fail=True),
        now=datetime(2026, 4, 29, 12, 35, tzinfo=UTC),
    )

    assert status_code == 502
    assert body == {
        "error": {
            "code": "caption_publish_failed",
            "message": "Caption event could not be published.",
            "details": [],
        }
    }
    assert "Welcome to today's event" not in str(body)


def test_build_publish_payload_omits_source_and_speech_text() -> None:
    event = validate_caption_event(
        valid_payload(),
        now=datetime(2026, 4, 29, 12, 35, tzinfo=UTC),
    )

    payload = build_publish_payload(
        event,
        received_at=datetime(2026, 4, 29, 12, 35, 1, 123000, tzinfo=UTC),
    )

    assert payload["relay"] == {"receivedAt": "2026-04-29T12:35:01.123Z"}
    assert payload["roomName"] == "A101"
    assert payload["trackNumber"] == 1
    assert payload["speech"] == {
        "inputLanguage": "zh-TW",
        "offsetTicks": 120000000,
        "durationTicks": 35000000,
    }
    assert "source" not in payload
    assert "text" not in payload["speech"]


def test_build_publish_payload_keeps_empty_room_name() -> None:
    request_payload = valid_payload()
    request_payload["roomName"] = ""
    event = validate_caption_event(
        request_payload,
        now=datetime(2026, 4, 29, 12, 35, tzinfo=UTC),
    )

    payload = build_publish_payload(
        event,
        received_at=datetime(2026, 4, 29, 12, 35, 1, 123000, tzinfo=UTC),
    )

    assert payload["roomName"] == ""
    assert payload["trackNumber"] == 1


def test_build_health_payload_includes_commit() -> None:
    assert build_health_payload(commit="abc123") == {
        "status": "ok",
        "commit": "abc123",
    }


def test_build_health_payload_defaults_to_unknown_commit() -> None:
    assert build_health_payload() == {
        "status": "ok",
        "commit": "unknown",
    }
