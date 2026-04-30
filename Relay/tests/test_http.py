from __future__ import annotations

from datetime import UTC, datetime

from relay.http import build_publish_payload, handle_caption_event_request
from relay.validation import validate_caption_event

from tests.test_validation import valid_payload


def test_handle_caption_event_request_accepts_valid_payload() -> None:
    status_code, body = handle_caption_event_request(
        valid_payload(),
        now=datetime(2026, 4, 29, 12, 35, tzinfo=UTC),
    )

    assert status_code == 202
    assert body == {"accepted": True}


def test_handle_caption_event_request_returns_sanitized_error() -> None:
    payload = valid_payload()
    payload["captions"]["en"] = ""

    status_code, body = handle_caption_event_request(
        payload,
        now=datetime(2026, 4, 29, 12, 35, tzinfo=UTC),
    )

    assert status_code == 400
    assert body["error"]["code"] == "invalid_caption_event"
    assert body["error"]["details"] == [
        {"field": "captions.en", "reason": "Text is required."}
    ]


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
