from __future__ import annotations

from datetime import UTC, datetime

import pytest

from relay.validation import CaptionEventValidationError, validate_caption_event


def valid_payload() -> dict[str, object]:
    return {
        "roomName": "A101",
        "trackNumber": 1,
        "createdAt": "2026-04-29T12:34:56.789Z",
        "source": {
            "bundleIdentifier": "io.iplayground.LiveCaptionPortal",
            "appVersion": "1.0",
        },
        "speech": {
            "inputLanguage": "zh-TW",
            "offsetTicks": 120000000,
            "durationTicks": 35000000,
            "text": "歡迎來到今天的活動",
        },
        "captions": {
            "zh-Hant": "歡迎來到今天的活動",
            "en": "Welcome to today's event",
            "ja": "本日のイベントへようこそ",
        },
        "captionMode": "fast",
    }


def validate(payload: object):
    return validate_caption_event(
        payload,
        now=datetime(2026, 4, 29, 12, 35, tzinfo=UTC),
    )


def test_valid_caption_event_is_normalized() -> None:
    payload = valid_payload()
    payload["roomName"] = "  A101  "

    event = validate(payload)

    assert event.room_name == "A101"
    assert event.track_number == 1
    assert event.created_at == datetime(2026, 4, 29, 12, 34, 56, 789000, tzinfo=UTC)
    assert event.source.bundle_identifier == "io.iplayground.LiveCaptionPortal"
    assert event.speech.input_language == "zh-TW"
    assert event.captions["en"] == "Welcome to today's event"
    assert event.caption_modes["fast"].provider is None
    assert event.caption_modes["fast"].captions["en"] == "Welcome to today's event"


def test_caption_event_rejects_legacy_caption_modes() -> None:
    payload = valid_payload()
    payload["captionModes"] = {
        "fast": {
            "provider": "azure-speech",
            "captions": payload["captions"],
        },
        "accurate": {
            "provider": "azure-openai",
            "captions": {
                "zh-Hant": "歡迎各位來到今天的活動",
                "en": "Welcome, everyone, to today's event.",
            },
        },
    }

    with pytest.raises(CaptionEventValidationError) as error:
        validate(payload)

    assert error.value.field == "captionModes"
    assert error.value.reason == "Use captionMode and captionProvider instead."


def test_caption_event_accepts_single_language_accurate_caption_mode() -> None:
    payload = valid_payload()
    payload["captions"] = {
        "ja": "本日のイベントへようこそ",
    }
    payload["captionMode"] = "accurate"
    payload["captionProvider"] = "azure-openai"

    event = validate(payload)

    assert event.captions == {"ja": "本日のイベントへようこそ"}
    assert event.caption_modes["accurate"].provider == "azure-openai"
    assert event.caption_modes["accurate"].captions == {"ja": "本日のイベントへようこそ"}


def test_caption_provider_is_optional_and_not_bound_to_caption_mode() -> None:
    payload = valid_payload()
    payload["captionProvider"] = "  manual-correction.v1  "

    event = validate(payload)

    assert event.caption_modes["fast"].provider == "manual-correction.v1"


def test_blank_caption_provider_is_treated_as_absent() -> None:
    payload = valid_payload()
    payload["captionProvider"] = "  "

    event = validate(payload)

    assert event.caption_modes["fast"].provider is None


def test_room_name_is_required_but_can_be_empty() -> None:
    payload = valid_payload()
    payload.pop("roomName")

    with pytest.raises(CaptionEventValidationError) as error:
        validate(payload)

    assert error.value.field == "roomName"


@pytest.mark.parametrize(
    ("field", "mutate"),
    [
        ("trackNumber", lambda payload: payload.update({"trackNumber": "1"})),
        ("createdAt", lambda payload: payload.update({"createdAt": "not-a-date"})),
        ("source.bundleIdentifier", lambda payload: payload["source"].pop("bundleIdentifier")),
        ("speech.inputLanguage", lambda payload: payload["speech"].update({"inputLanguage": "fr"})),
        ("speech.durationTicks", lambda payload: payload["speech"].update({"durationTicks": 0})),
        ("speech.text", lambda payload: payload["speech"].update({"text": "  "})),
        ("captions.en", lambda payload: payload["captions"].pop("en")),
        ("captions.zh-Hant", lambda payload: payload["captions"].update({"zh-Hant": ""})),
        ("captions", lambda payload: payload["captions"].update({"fr": "Bonjour"})),
        ("captionMode", lambda payload: payload.pop("captionMode")),
        ("captionMode", lambda payload: payload.update({"captionMode": "slow"})),
        ("captionProvider", lambda payload: payload.update({"captionProvider": 123})),
        ("captionProvider", lambda payload: payload.update({"captionProvider": "x" * 51})),
        ("captionProvider", lambda payload: payload.update({"captionProvider": "azure openai"})),
    ],
)
def test_invalid_caption_events_report_field(field: str, mutate) -> None:
    payload = valid_payload()
    mutate(payload)

    with pytest.raises(CaptionEventValidationError) as error:
        validate(payload)

    assert error.value.field == field


def test_rejects_future_created_at() -> None:
    payload = valid_payload()
    payload["createdAt"] = (
        datetime(2026, 4, 29, 12, 45, tzinfo=UTC).isoformat().replace("+00:00", "Z")
    )

    with pytest.raises(CaptionEventValidationError) as error:
        validate(payload)

    assert error.value.field == "createdAt"


def test_rejects_reserved_room_name_characters() -> None:
    payload = valid_payload()
    payload["roomName"] = "A101/main"

    with pytest.raises(CaptionEventValidationError) as error:
        validate(payload)

    assert error.value.field == "roomName"


def test_treats_blank_room_name_as_empty_string() -> None:
    payload = valid_payload()
    payload["roomName"] = "  "

    event = validate(payload)

    assert event.room_name == ""


def test_rejects_non_positive_track_number() -> None:
    payload = valid_payload()
    payload["trackNumber"] = 0

    with pytest.raises(CaptionEventValidationError) as error:
        validate(payload)

    assert error.value.field == "trackNumber"


def test_rejects_unexpected_bundle_identifier() -> None:
    payload = valid_payload()
    payload["source"]["bundleIdentifier"] = "io.example.OtherApp"

    with pytest.raises(CaptionEventValidationError) as error:
        validate(payload)

    assert error.value.field == "source.bundleIdentifier"


def test_rejects_oversized_text_without_leaking_content() -> None:
    payload = valid_payload()
    payload["captions"]["en"] = "x" * 4001

    with pytest.raises(CaptionEventValidationError) as error:
        validate(payload)

    assert error.value.field == "captions.en"
    assert "x" * 100 not in error.value.reason
