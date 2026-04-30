from __future__ import annotations

import json
from dataclasses import dataclass
from os import environ
from typing import Any, Callable

from azure.core.exceptions import AzureError


class RelayWebPubSubError(RuntimeError):
    pass


@dataclass(frozen=True)
class WebPubSubConfig:
    endpoint: str
    hub_name: str
    group_name: str

    @classmethod
    def from_environment(cls, env: dict[str, str] | None = None) -> WebPubSubConfig:
        values = env or environ
        endpoint = values.get("AZURE_WEBPUBSUB_ENDPOINT", "").strip()
        hub_name = values.get("AZURE_WEBPUBSUB_HUB_NAME", "").strip()
        group_name = values.get("AZURE_WEBPUBSUB_GROUP_NAME", "").strip()

        missing_fields = [
            name
            for name, value in (
                ("AZURE_WEBPUBSUB_ENDPOINT", endpoint),
                ("AZURE_WEBPUBSUB_HUB_NAME", hub_name),
                ("AZURE_WEBPUBSUB_GROUP_NAME", group_name),
            )
            if not value
        ]
        if missing_fields:
            raise RelayWebPubSubError(
                f"Missing Azure Web PubSub settings: {', '.join(missing_fields)}"
            )

        if not endpoint.startswith("https://"):
            raise RelayWebPubSubError("AZURE_WEBPUBSUB_ENDPOINT must be an HTTPS URL.")

        return cls(endpoint=endpoint.rstrip("/"), hub_name=hub_name, group_name=group_name)


class AzureWebPubSubPublisher:
    def __init__(
        self,
        *,
        config_factory: Callable[[], WebPubSubConfig] = WebPubSubConfig.from_environment,
    ) -> None:
        self._config_factory = config_factory
        self._client: Any | None = None
        self._group_name: str | None = None

    def publish(self, payload: dict[str, Any]) -> None:
        client, group_name = self._get_client()
        try:
            client.send_to_group(
                group=group_name,
                message=json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
                content_type="text/plain",
            )
        except AzureError as error:
            raise RelayWebPubSubError("Unable to publish caption event.") from error

    def _get_client(self) -> tuple[Any, str]:
        if self._client and self._group_name:
            return self._client, self._group_name

        config = self._config_factory()
        try:
            from azure.identity import DefaultAzureCredential
            from azure.messaging.webpubsubservice import WebPubSubServiceClient

            self._client = WebPubSubServiceClient(
                endpoint=config.endpoint,
                hub=config.hub_name,
                credential=DefaultAzureCredential(),
            )
        except (AzureError, ImportError) as error:
            raise RelayWebPubSubError("Unable to create Azure Web PubSub client.") from error

        self._group_name = config.group_name
        return self._client, self._group_name
