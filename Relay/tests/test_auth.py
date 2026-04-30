from __future__ import annotations

from datetime import UTC, datetime

import pytest

from relay.auth import RelayAuthenticationError, build_speech_key_signature
from relay.auth import verify_speech_key_signature


def test_valid_speech_key_signature_is_accepted() -> None:
    body = b'{"roomName":"A101"}'
    timestamp = "2026-04-29T12:34:56.789Z"
    signature = build_speech_key_signature(
        speech_key="local-speech-key",
        timestamp=timestamp,
        body=body,
    )

    verify_speech_key_signature(
        speech_key="local-speech-key",
        timestamp=timestamp,
        signature=signature,
        body=body,
        now=datetime(2026, 4, 29, 12, 35, tzinfo=UTC),
    )


@pytest.mark.parametrize(
    ("speech_key", "timestamp", "signature"),
    [
        (None, "2026-04-29T12:34:56.789Z", "sha256=abc"),
        ("local-speech-key", None, "sha256=abc"),
        ("local-speech-key", "2026-04-29T12:34:56.789Z", None),
        ("local-speech-key", "not-a-date", "sha256=abc"),
    ],
)
def test_missing_or_invalid_signature_inputs_are_rejected(
    speech_key: str | None,
    timestamp: str | None,
    signature: str | None,
) -> None:
    with pytest.raises(RelayAuthenticationError):
        verify_speech_key_signature(
            speech_key=speech_key,
            timestamp=timestamp,
            signature=signature,
            body=b"{}",
            now=datetime(2026, 4, 29, 12, 35, tzinfo=UTC),
        )


def test_invalid_signature_is_rejected() -> None:
    with pytest.raises(RelayAuthenticationError):
        verify_speech_key_signature(
            speech_key="local-speech-key",
            timestamp="2026-04-29T12:34:56.789Z",
            signature="sha256=invalid",
            body=b"{}",
            now=datetime(2026, 4, 29, 12, 35, tzinfo=UTC),
        )


def test_stale_signature_is_rejected() -> None:
    timestamp = "2026-04-29T12:20:00.000Z"
    body = b"{}"
    signature = build_speech_key_signature(
        speech_key="local-speech-key",
        timestamp=timestamp,
        body=body,
    )

    with pytest.raises(RelayAuthenticationError):
        verify_speech_key_signature(
            speech_key="local-speech-key",
            timestamp=timestamp,
            signature=signature,
            body=body,
            now=datetime(2026, 4, 29, 12, 35, tzinfo=UTC),
        )
