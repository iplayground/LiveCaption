from __future__ import annotations

import re
from datetime import UTC, datetime, timedelta
from typing import Any

from relay.models import CaptionEvent, CaptionModeContent, CaptionSource, ControlEvent, SpeechSegment

ALLOWED_INPUT_LANGUAGES = frozenset({"zh-TW", "en-US"})
ALLOWED_OUTPUT_LANGUAGES = frozenset({"zh-Hant", "en", "ja", "ko"})
REQUIRED_OUTPUT_LANGUAGES = frozenset({"zh-Hant", "en"})
ALLOWED_CAPTION_MODES = frozenset({"fast", "accurate"})
EXPECTED_BUNDLE_IDENTIFIER = "io.iplayground.LiveCaptionPortal"

MAX_ROOM_NAME_LENGTH = 80
MAX_SESSION_ID_LENGTH = 80
MAX_CAPTION_PROVIDER_LENGTH = 50
MAX_TEXT_LENGTH = 4_000
MAX_BODY_FIELD_COUNT = 10
FUTURE_SKEW = timedelta(minutes=5)
CONTROL_CHARACTER_CODES = frozenset(range(0x00, 0x20)) | {0x7F}
ROOM_NAME_FORBIDDEN_CHARACTERS = frozenset({"/", "?", "#"})
CAPTION_PROVIDER_PATTERN = re.compile(r"^[A-Za-z0-9._-]+$")
SESSION_ID_PATTERN = re.compile(r"^[A-Za-z0-9._:-]+$")
CONTROL_EVENTS = frozenset({"portalStatus", "sessionStatus", "captionAvailability"})
PORTAL_STATUS_VALUES = frozenset({"online", "offline"})
SESSION_STATUS_VALUES = frozenset({"started", "stopped"})


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

    if "captionModes" in payload:
        raise CaptionEventValidationError("captionModes", "Use captionMode and captionProvider instead.")

    track_number = _required_positive_int(payload, "trackNumber")
    room_name = _validate_room_name(_required_string(payload, "roomName"))
    session_id = _validate_session_id(_required_string(payload, "sessionId"))

    created_at = _parse_created_at(_required_string(payload, "createdAt"), now=now)
    source = _validate_source(_required_object(payload, "source"))
    speech = _validate_speech(_required_object(payload, "speech"))
    caption_mode = _validate_caption_mode(payload.get("captionMode"))
    caption_provider = _validate_caption_provider(payload.get("captionProvider"))
    captions = _validate_captions(
        _required_object(payload, "captions"),
        require_required_languages=caption_mode == "fast",
    )
    caption_modes = {
        caption_mode: CaptionModeContent(
            provider=caption_provider,
            captions=captions,
        )
    }

    return CaptionEvent(
        room_name=room_name,
        track_number=track_number,
        session_id=session_id,
        created_at=created_at,
        source=source,
        speech=speech,
        captions=captions,
        caption_modes=caption_modes,
    )


def validate_control_event(payload: Any, *, now: datetime | None = None) -> ControlEvent:
    if not isinstance(payload, dict):
        raise CaptionEventValidationError("body", "Request body must be a JSON object.")

    event_type = _required_string(payload, "type")
    if event_type != "control":
        raise CaptionEventValidationError("type", "Control event type must be control.")

    track_number = _required_positive_int(payload, "trackNumber")
    event = _required_string(payload, "event")
    if event not in CONTROL_EVENTS:
        raise CaptionEventValidationError("event", "Control event is not supported.")

    updated_at = _parse_created_at(_required_string(payload, "updatedAt"), now=now)
    status = _validate_control_status(payload.get("status"), event=event)
    session_id = _validate_optional_session_id(payload.get("sessionId"), event=event)
    available_caption_modes = _validate_available_caption_modes(
        payload.get("availableCaptionModes"),
        event=event,
    )
    available_languages = _validate_available_languages(
        payload.get("availableLanguages"),
        event=event,
    )

    return ControlEvent(
        track_number=track_number,
        event=event,
        status=status,
        session_id=session_id,
        available_caption_modes=available_caption_modes,
        available_languages=available_languages,
        updated_at=updated_at,
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


def _validate_session_id(value: str) -> str:
    session_id = value.strip()
    if not session_id:
        raise CaptionEventValidationError("sessionId", "Session id is required.")
    if len(session_id) > MAX_SESSION_ID_LENGTH:
        raise CaptionEventValidationError("sessionId", "Session id is too long.")
    if SESSION_ID_PATTERN.fullmatch(session_id) is None:
        raise CaptionEventValidationError("sessionId", "Session id contains unsupported characters.")
    return session_id


def _validate_optional_session_id(value: Any, *, event: str) -> str | None:
    if value is None:
        if event == "sessionStatus":
            raise CaptionEventValidationError("sessionId", "Session id is required.")
        return None
    if not isinstance(value, str):
        raise CaptionEventValidationError("sessionId", "Session id must be a string.")
    return _validate_session_id(value)


def _validate_control_status(value: Any, *, event: str) -> str | None:
    if event == "captionAvailability":
        if value is not None:
            raise CaptionEventValidationError("status", "Caption availability does not use status.")
        return None

    if not isinstance(value, str):
        raise CaptionEventValidationError("status", "Status is required.")

    normalized_status = value.strip()
    allowed_values = PORTAL_STATUS_VALUES if event == "portalStatus" else SESSION_STATUS_VALUES
    if normalized_status not in allowed_values:
        raise CaptionEventValidationError("status", "Status is not supported.")
    return normalized_status


def _validate_available_caption_modes(value: Any, *, event: str) -> list[str] | None:
    if event != "captionAvailability":
        if value is not None:
            raise CaptionEventValidationError(
                "availableCaptionModes",
                "Only captionAvailability uses available caption modes.",
            )
        return None

    if not isinstance(value, list) or not value:
        raise CaptionEventValidationError("availableCaptionModes", "At least one caption mode is required.")

    normalized_modes: list[str] = []
    for item in value:
        if not isinstance(item, str):
            raise CaptionEventValidationError("availableCaptionModes", "Caption mode must be a string.")
        mode = item.strip()
        if mode not in ALLOWED_CAPTION_MODES:
            raise CaptionEventValidationError("availableCaptionModes", "Caption mode is not supported.")
        if mode not in normalized_modes:
            normalized_modes.append(mode)

    return normalized_modes


def _validate_available_languages(value: Any, *, event: str) -> list[str] | None:
    if event != "captionAvailability":
        if value is not None:
            raise CaptionEventValidationError(
                "availableLanguages",
                "Only captionAvailability uses available languages.",
            )
        return None

    if not isinstance(value, list) or not value:
        raise CaptionEventValidationError("availableLanguages", "At least one language is required.")

    normalized_languages: list[str] = []
    for item in value:
        if not isinstance(item, str):
            raise CaptionEventValidationError("availableLanguages", "Language must be a string.")
        language = item.strip()
        if language not in ALLOWED_OUTPUT_LANGUAGES:
            raise CaptionEventValidationError("availableLanguages", "Language is not supported.")
        if language not in normalized_languages:
            normalized_languages.append(language)

    return normalized_languages


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


def _validate_captions(
    payload: dict[str, Any],
    *,
    require_required_languages: bool,
) -> dict[str, str]:
    if not payload:
        raise CaptionEventValidationError("captions", "At least one caption language is required.")

    missing_languages = sorted(REQUIRED_OUTPUT_LANGUAGES.difference(payload.keys()))
    if require_required_languages and missing_languages:
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


def _validate_caption_mode(value: Any) -> str:
    if value is None:
        raise CaptionEventValidationError("captionMode", "Caption mode is required.")
    if not isinstance(value, str):
        raise CaptionEventValidationError("captionMode", "Caption mode must be a string.")

    normalized_mode = value.strip()
    if normalized_mode not in ALLOWED_CAPTION_MODES:
        raise CaptionEventValidationError("captionMode", "Caption mode is not supported.")

    return normalized_mode


def _validate_caption_provider(value: Any) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str):
        raise CaptionEventValidationError("captionProvider", "Caption provider must be a string.")

    normalized_provider = value.strip()
    if not normalized_provider:
        return None
    if len(normalized_provider) > MAX_CAPTION_PROVIDER_LENGTH:
        raise CaptionEventValidationError("captionProvider", "Caption provider is too long.")
    if CAPTION_PROVIDER_PATTERN.fullmatch(normalized_provider) is None:
        raise CaptionEventValidationError(
            "captionProvider",
            "Caption provider contains unsupported characters.",
        )

    return normalized_provider


def _validate_text(value: str, field: str) -> str:
    text = value.strip()
    if not text:
        raise CaptionEventValidationError(field, "Text is required.")
    if len(text) > MAX_TEXT_LENGTH:
        raise CaptionEventValidationError(field, "Text is too long.")
    return text


def _required_object(payload: dict[str, Any], field: str, *, prefix: str | None = None) -> dict[str, Any]:
    value = payload.get(field)
    error_field = f"{prefix}.{field}" if prefix else field
    if not isinstance(value, dict):
        raise CaptionEventValidationError(error_field, "Field must be a JSON object.")
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
