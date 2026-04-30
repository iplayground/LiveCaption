from __future__ import annotations

import hashlib
import hmac
from datetime import UTC, datetime, timedelta

SIGNATURE_HEADER = "x-livecaption-signature"
TIMESTAMP_HEADER = "x-livecaption-timestamp"
SIGNATURE_PREFIX = "sha256="
MAX_TIMESTAMP_SKEW = timedelta(minutes=5)


class RelayAuthenticationError(ValueError):
    pass


def verify_speech_key_signature(
    *,
    speech_key: str | None,
    timestamp: str | None,
    signature: str | None,
    body: bytes,
    now: datetime | None = None,
) -> None:
    if not speech_key:
        raise RelayAuthenticationError("Relay speech key is not configured.")
    if not timestamp:
        raise RelayAuthenticationError("Signature timestamp is missing.")
    if not signature:
        raise RelayAuthenticationError("Signature is missing.")

    request_time = _parse_timestamp(timestamp)
    reference_time = (now or datetime.now(UTC)).astimezone(UTC)
    if abs(reference_time - request_time) > MAX_TIMESTAMP_SKEW:
        raise RelayAuthenticationError("Signature timestamp is outside the allowed window.")

    expected_signature = build_speech_key_signature(
        speech_key=speech_key,
        timestamp=timestamp,
        body=body,
    )
    if not hmac.compare_digest(signature, expected_signature):
        raise RelayAuthenticationError("Signature is invalid.")


def build_speech_key_signature(*, speech_key: str, timestamp: str, body: bytes) -> str:
    message = timestamp.encode("utf-8") + b"." + body
    digest = hmac.new(speech_key.encode("utf-8"), message, hashlib.sha256).hexdigest()
    return f"{SIGNATURE_PREFIX}{digest}"


def _parse_timestamp(value: str) -> datetime:
    normalized_value = value.removesuffix("Z") + "+00:00" if value.endswith("Z") else value
    try:
        parsed = datetime.fromisoformat(normalized_value)
    except ValueError as error:
        raise RelayAuthenticationError("Signature timestamp is invalid.") from error

    if parsed.tzinfo is None:
        raise RelayAuthenticationError("Signature timestamp must include timezone.")

    return parsed.astimezone(UTC)
