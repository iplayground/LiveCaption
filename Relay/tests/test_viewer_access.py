from __future__ import annotations

from datetime import UTC, datetime

import pytest

from relay.viewer_access import build_viewer_access, is_viewer_access_code_required
from relay.viewer_access import verify_viewer_access_code
from relay.viewer_access import ViewerAccessError
from relay.webpubsub import WebPubSubConfig


def test_build_viewer_access_returns_stable_daily_code() -> None:
    access = build_viewer_access(
        speech_key="speech-secret",
        webpubsub_config=config(),
        now=datetime(2026, 4, 30, 12, 0, tzinfo=UTC),
    )

    assert access.code.isdigit()
    assert len(access.code) == 6
    assert access.expires_at == datetime(2026, 5, 1, 0, 0, tzinfo=UTC)
    assert access == build_viewer_access(
        speech_key="speech-secret",
        webpubsub_config=config(),
        now=datetime(2026, 4, 30, 23, 59, tzinfo=UTC),
    )


def test_verify_viewer_access_code_accepts_current_code() -> None:
    access = build_viewer_access(
        speech_key="speech-secret",
        webpubsub_config=config(),
        now=datetime(2026, 4, 30, 12, 0, tzinfo=UTC),
    )

    verify_viewer_access_code(
        access_code=access.code,
        speech_keys=("speech-secret",),
        webpubsub_config=config(),
        now=datetime(2026, 4, 30, 13, 0, tzinfo=UTC),
    )


def test_verify_viewer_access_code_accepts_previous_day_code_for_boundary() -> None:
    access = build_viewer_access(
        speech_key="speech-secret",
        webpubsub_config=config(),
        now=datetime(2026, 4, 30, 23, 59, tzinfo=UTC),
    )

    verify_viewer_access_code(
        access_code=access.code,
        speech_keys=("speech-secret",),
        webpubsub_config=config(),
        now=datetime(2026, 5, 1, 0, 1, tzinfo=UTC),
    )


def test_verify_viewer_access_code_rejects_invalid_code() -> None:
    with pytest.raises(ViewerAccessError):
        verify_viewer_access_code(
            access_code="000000",
            speech_keys=("speech-secret",),
            webpubsub_config=config(),
            now=datetime(2026, 4, 30, 12, 0, tzinfo=UTC),
        )


def test_is_viewer_access_code_required_defaults_to_true() -> None:
    assert is_viewer_access_code_required({}) is True


@pytest.mark.parametrize("value", ["true", "1", "yes", "on", " TRUE "])
def test_is_viewer_access_code_required_accepts_true_values(value: str) -> None:
    assert is_viewer_access_code_required({"VIEWER_ACCESS_CODE_REQUIRED": value}) is True


@pytest.mark.parametrize("value", ["false", "0", "no", "off", " FALSE "])
def test_is_viewer_access_code_required_accepts_false_values(value: str) -> None:
    assert is_viewer_access_code_required({"VIEWER_ACCESS_CODE_REQUIRED": value}) is False


def test_is_viewer_access_code_required_fails_closed_for_invalid_value() -> None:
    assert is_viewer_access_code_required({"VIEWER_ACCESS_CODE_REQUIRED": "standard"}) is True


def config() -> WebPubSubConfig:
    return WebPubSubConfig(
        endpoint="https://livecaption.webpubsub.azure.com",
        hub_name="livecaption",
        group_name="caption-live",
    )
