from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from os import environ
from typing import Callable

from azure.core.exceptions import AzureError
from azure.identity import DefaultAzureCredential
from azure.mgmt.cognitiveservices import CognitiveServicesManagementClient


class RelaySpeechKeyError(RuntimeError):
    pass


@dataclass(frozen=True)
class AzureSpeechResourceConfig:
    subscription_id: str
    resource_group: str
    account_name: str

    @classmethod
    def from_environment(cls, env: dict[str, str] | None = None) -> AzureSpeechResourceConfig:
        values = env or environ
        account_id = values.get("AZURE_SPEECH_ACCOUNT_ID", "").strip()
        if not account_id:
            raise RelaySpeechKeyError("Missing Azure Speech resource settings: AZURE_SPEECH_ACCOUNT_ID")

        return _parse_account_resource_id(account_id)


def _parse_account_resource_id(value: str) -> AzureSpeechResourceConfig:
    parts = [part for part in value.strip("/").split("/") if part]
    normalized_parts = [part.lower() for part in parts]

    try:
        subscription_id = parts[normalized_parts.index("subscriptions") + 1]
        resource_group = parts[normalized_parts.index("resourcegroups") + 1]
        provider_index = normalized_parts.index("providers")
        provider_namespace = parts[provider_index + 1]
        resource_type = parts[provider_index + 2]
        account_name = parts[provider_index + 3]
    except (ValueError, IndexError) as error:
        raise RelaySpeechKeyError("AZURE_SPEECH_ACCOUNT_ID must be a valid ARM resource id.") from error

    if (
        provider_namespace.lower() != "microsoft.cognitiveservices"
        or resource_type.lower() != "accounts"
    ):
        raise RelaySpeechKeyError("AZURE_SPEECH_ACCOUNT_ID must reference a Cognitive Services account.")

    return AzureSpeechResourceConfig(
        subscription_id=subscription_id,
        resource_group=resource_group,
        account_name=account_name,
    )


class AzureSpeechKeyProvider:
    def __init__(
        self,
        *,
        config_factory: Callable[[], AzureSpeechResourceConfig] = AzureSpeechResourceConfig.from_environment,
        cache_ttl: timedelta = timedelta(minutes=5),
    ) -> None:
        self._config_factory = config_factory
        self._cache_ttl = cache_ttl
        self._cached_keys: tuple[str, ...] | None = None
        self._cached_at: datetime | None = None

    def get_keys(self, *, now: datetime | None = None) -> tuple[str, ...]:
        reference_time = now or datetime.now(UTC)
        if (
            self._cached_keys
            and self._cached_at
            and reference_time - self._cached_at < self._cache_ttl
        ):
            return self._cached_keys

        config = self._config_factory()
        keys = self._fetch_keys(config)
        self._cached_keys = keys
        self._cached_at = reference_time
        return keys

    def _fetch_keys(self, config: AzureSpeechResourceConfig) -> tuple[str, ...]:
        try:
            credential = DefaultAzureCredential()
            client = CognitiveServicesManagementClient(credential, config.subscription_id)
            account_keys = client.accounts.list_keys(config.resource_group, config.account_name)
        except AzureError as error:
            raise RelaySpeechKeyError("Unable to read Azure Speech keys.") from error

        return _normalize_keys(
            [
                getattr(account_keys, "key1", None),
                getattr(account_keys, "key2", None),
            ]
        )


def _normalize_keys(values: list[object]) -> tuple[str, ...]:
    keys = tuple(value.strip() for value in values if isinstance(value, str) and value.strip())
    if not keys:
        raise RelaySpeechKeyError("Azure Speech account returned no keys.")
    return keys
