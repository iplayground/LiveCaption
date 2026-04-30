from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest

from relay.speech_keys import AzureSpeechKeyProvider, AzureSpeechResourceConfig, RelaySpeechKeyError


def test_speech_resource_config_reads_account_resource_id() -> None:
    config = AzureSpeechResourceConfig.from_environment(
        {
            "AZURE_SPEECH_ACCOUNT_ID": (
                " /subscriptions/subscription-id/resourceGroups/iplayground/"
                "providers/Microsoft.CognitiveServices/accounts/<speech-account-name> "
            ),
        }
    )

    assert config.subscription_id == "subscription-id"
    assert config.resource_group == "iplayground"
    assert config.account_name == "<speech-account-name>"


def test_speech_resource_config_accepts_case_insensitive_arm_segments() -> None:
    config = AzureSpeechResourceConfig.from_environment(
        {
            "AZURE_SPEECH_ACCOUNT_ID": (
                "/SUBSCRIPTIONS/subscription-id/RESOURCEGROUPS/iplayground/"
                "PROVIDERS/Microsoft.CognitiveServices/ACCOUNTS/<speech-account-name>"
            ),
        }
    )

    assert config.subscription_id == "subscription-id"
    assert config.resource_group == "iplayground"
    assert config.account_name == "<speech-account-name>"


def test_speech_resource_config_requires_values_missing_from_environment() -> None:
    with pytest.raises(RelaySpeechKeyError):
        AzureSpeechResourceConfig.from_environment({})


def test_speech_resource_config_rejects_non_cognitive_services_resource() -> None:
    with pytest.raises(RelaySpeechKeyError):
        AzureSpeechResourceConfig.from_environment(
            {
                "AZURE_SPEECH_ACCOUNT_ID": (
                    "/subscriptions/subscription-id/resourceGroups/iplayground/"
                    "providers/Microsoft.Storage/storageAccounts/livecaption"
                ),
            }
        )


def test_speech_key_provider_caches_keys(monkeypatch: pytest.MonkeyPatch) -> None:
    config = AzureSpeechResourceConfig(
        subscription_id="subscription-id",
        resource_group="iplayground",
        account_name="<speech-account-name>",
    )
    provider = AzureSpeechKeyProvider(
        config_factory=lambda: config,
        cache_ttl=timedelta(minutes=5),
    )
    fetch_count = 0

    def fetch_keys(received_config: AzureSpeechResourceConfig) -> tuple[str, ...]:
        nonlocal fetch_count
        fetch_count += 1
        assert received_config == config
        return ("speech-key",)

    monkeypatch.setattr(provider, "_fetch_keys", fetch_keys)

    now = datetime(2026, 4, 29, 12, 0, tzinfo=UTC)
    assert provider.get_keys(now=now) == ("speech-key",)
    assert provider.get_keys(now=now + timedelta(minutes=1)) == ("speech-key",)
    assert fetch_count == 1
