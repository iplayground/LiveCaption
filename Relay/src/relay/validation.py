from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Any

from relay.models import CaptionEvent, CaptionSource, SpeechSegment

ALLOWED_INPUT_LANGUAGES = frozenset({"zh-TW", "en-US"})
ALLOWED_OUTPUT_LANGUAGES = frozenset({"zh-Hant", "en", "ja", "ko"})
REQUIRED_OUTPUT_LANGUAGES = frozenset({"zh-Hant", "en"})
EXPECTED_BUNDLE_IDENTIFIER = "io.iplayground.LiveCaptionPortal"

MAX_ROOM_NAME_LENGTH = 80
MAX_TEXT_LENGTH = 4_000
MAX_BODY_FIELD_COUNT = 8
FUTURE_SKEW = timedelta(minutes=5)
CONTROL_CHARACTER_CODES = frozenset(range(0x00, 0x20)) | {0x7F}
ROOM_NAME_FORBIDDEN_CHARACTERS = frozenset({"/", "?", "#"})


class CaptionEventValidationError(ValueError):
    def __init__(self, field: str, reason: str) -> None:
        super().__init__(reason)
        self.field = field
        self.reason = reason

    def as_detail(self) -> dict[str, str]:
        return {"field": self.field, "reason": self.reason}


def validate_caption_event(payload: Any, *, now: datetime | None = None) -> CaptionEvent:
    if not isinstance(payload, dict):
        raise CaptionEventValidationError("body", "Request body must be a JSON object.")

    if len(payload) > MAX_BODY_FIELD_COUNT:
        raise CaptionEventValidationError("body", "Request body contains too many fields.")

    track_number = _required_positive_int(payload, "trackNumber")
    room_name = _validate_room_name(_required_string(payload, "roomName"))

    created_at = _parse_created_at(_required_string(payload, "createdAt"), now=now)
    source = _validate_source(_required_object(payload, "source"))
    speech = _validate_speech(_required_object(payload, "speech"))
    captions = _validate_captions(_required_object(payload, "captions"))

    return CaptionEvent(
        room_name=room_name,
        track_number=track_number,
        created_at=created_at,
        source=source,
        speech=speech,
        captions=captions,
    )


def _validate_room_name(value: str) -> str:
    room_name = value.strip()
    if not room_name:
        return ""
    if len(room_name) > MAX_ROOM_NAME_LENGTH:
        raise CaptionEventValidationError("roomName", "Room name is too long.")
    if any(ord(character) in CONTROL_CHARACTER_CODES for character in room_name):
        raise CaptionEventValidationError("roomName", "Room name contains control characters.")
    if any(character in ROOM_NAME_FORBIDDEN_CHARACTERS for character in room_name):
        raise CaptionEventValidationError("roomName", "Room name contains reserved characters.")
    return room_name


def _parse_created_at(value: str, *, now: datetime | None) -> datetime:
    normalized_value = value.removesuffix("Z") + "+00:00" if value.endswith("Z") else value
    try:
        created_at = datetime.fromisoformat(normalized_value)
    except ValueError as error:
        raise CaptionEventValidationError("createdAt", "Created time must be ISO 8601.") from error

    if created_at.tzinfo is None:
        raise CaptionEventValidationError("createdAt", "Created time must include timezone.")

    created_at = created_at.astimezone(UTC)
    reference_time = (now or datetime.now(UTC)).astimezone(UTC)
    if created_at > reference_time + FUTURE_SKEW:
        raise CaptionEventValidationError("createdAt", "Created time is too far in the future.")

    return created_at


def _validate_source(payload: dict[str, Any]) -> CaptionSource:
    bundle_identifier = _required_string(payload, "bundleIdentifier", prefix="source")
    if bundle_identifier != EXPECTED_BUNDLE_IDENTIFIER:
        raise CaptionEventValidationError(
            "source.bundleIdentifier",
            "Bundle identifier is not allowed.",
        )

    app_version = payload.get("appVersion")
    if app_version is not None and not isinstance(app_version, str):
        raise CaptionEventValidationError("source.appVersion", "App version must be a string.")

    normalized_app_version = app_version.strip() if isinstance(app_version, str) else None
    if normalized_app_version == "":
        normalized_app_version = None

    return CaptionSource(
        bundle_identifier=bundle_identifier,
        app_version=normalized_app_version,
    )


def _validate_speech(payload: dict[str, Any]) -> SpeechSegment:
    input_language = _required_string(payload, "inputLanguage", prefix="speech")
    if input_language not in ALLOWED_INPUT_LANGUAGES:
        raise CaptionEventValidationError(
            "speech.inputLanguage",
            "Input language is not supported.",
        )

    offset_ticks = _required_non_negative_int(payload, "offsetTicks", prefix="speech")
    duration_ticks = _required_non_negative_int(payload, "durationTicks", prefix="speech")
    if duration_ticks <= 0:
        raise CaptionEventValidationError("speech.durationTicks", "Duration must be greater than 0.")

    text = _validate_text(_required_string(payload, "text", prefix="speech"), "speech.text")

    return SpeechSegment(
        input_language=input_language,
        offset_ticks=offset_ticks,
        duration_ticks=duration_ticks,
        text=text,
    )


def _validate_captions(payload: dict[str, Any]) -> dict[str, str]:
    missing_languages = sorted(REQUIRED_OUTPUT_LANGUAGES.difference(payload.keys()))
    if missing_languages:
        raise CaptionEventValidationError(
            f"captions.{missing_languages[0]}",
            f"Required output language {missing_languages[0]} is missing.",
        )

    normalized_captions: dict[str, str] = {}
    for language, text in payload.items():
        if not isinstance(language, str) or language not in ALLOWED_OUTPUT_LANGUAGES:
            raise CaptionEventValidationError("captions", "Output language is not supported.")
        if not isinstance(text, str):
            raise CaptionEventValidationError(f"captions.{language}", "Caption text must be a string.")
        normalized_captions[language] = _validate_text(text, f"captions.{language}")

    return normalized_captions


def _validate_text(value: str, field: str) -> str:
    text = value.strip()
    if not text:
        raise CaptionEventValidationError(field, "Text is required.")
    if len(text) > MAX_TEXT_LENGTH:
        raise CaptionEventValidationError(field, "Text is too long.")
    return text


def _required_object(payload: dict[str, Any], field: str) -> dict[str, Any]:
    value = payload.get(field)
    if not isinstance(value, dict):
        raise CaptionEventValidationError(field, "Field must be a JSON object.")
    return value


def _required_string(payload: dict[str, Any], field: str, *, prefix: str | None = None) -> str:
    value = payload.get(field)
    error_field = f"{prefix}.{field}" if prefix else field
    if not isinstance(value, str):
        raise CaptionEventValidationError(error_field, "Field must be a string.")
    return value


def _required_non_negative_int(payload: dict[str, Any], field: str, *, prefix: str) -> int:
    value = payload.get(field)
    error_field = f"{prefix}.{field}"
    if isinstance(value, bool) or not isinstance(value, int):
        raise CaptionEventValidationError(error_field, "Field must be an integer.")
    if value < 0:
        raise CaptionEventValidationError(error_field, "Field must be non-negative.")
    return value


def _required_positive_int(payload: dict[str, Any], field: str) -> int:
    value = payload.get(field)
    if isinstance(value, bool) or not isinstance(value, int):
        raise CaptionEventValidationError(field, "Field must be an integer.")
    if value <= 0:
        raise CaptionEventValidationError(field, "Field must be greater than 0.")
    return value
