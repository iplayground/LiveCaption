from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
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
    operator_group_name: str = "caption-operator"

    @classmethod
    def from_environment(cls, env: dict[str, str] | None = None) -> WebPubSubConfig:
        values = env or environ
        endpoint = values.get("AZURE_WEBPUBSUB_ENDPOINT", "").strip()
        hub_name = values.get("AZURE_WEBPUBSUB_HUB_NAME", "").strip()
        group_name = values.get("AZURE_WEBPUBSUB_GROUP_NAME", "").strip()
        operator_group_name = values.get(
            "AZURE_WEBPUBSUB_OPERATOR_GROUP_NAME",
            "caption-operator",
        ).strip()

        missing_fields = [
            name
            for name, value in (
                ("AZURE_WEBPUBSUB_ENDPOINT", endpoint),
                ("AZURE_WEBPUBSUB_HUB_NAME", hub_name),
                ("AZURE_WEBPUBSUB_GROUP_NAME", group_name),
                ("AZURE_WEBPUBSUB_OPERATOR_GROUP_NAME", operator_group_name),
            )
            if not value
        ]
        if missing_fields:
            raise RelayWebPubSubError(
                f"Missing Azure Web PubSub settings: {', '.join(missing_fields)}"
            )

        if not endpoint.startswith("https://"):
            raise RelayWebPubSubError("AZURE_WEBPUBSUB_ENDPOINT must be an HTTPS URL.")

        return cls(
            endpoint=endpoint.rstrip("/"),
            hub_name=hub_name,
            group_name=group_name,
            operator_group_name=operator_group_name,
        )


@dataclass(frozen=True)
class ViewerAccessToken:
    url: str
    hub_name: str
    group_name: str
    expires_at: datetime


class AzureWebPubSubPublisher:
    def __init__(
        self,
        *,
        config_factory: Callable[[], WebPubSubConfig] = WebPubSubConfig.from_environment,
    ) -> None:
        self._config_factory = config_factory
        self._client: Any | None = None
        self._config: WebPubSubConfig | None = None

    def publish(
        self,
        payload: dict[str, Any],
        *,
        track_number: int | None = None,
        caption_mode: str | None = None,
    ) -> None:
        client, config = self._get_client()
        target_groups = []
        if caption_mode == "fast":
            target_groups.append(config.group_name)
            if track_number is not None:
                target_groups.append(
                    build_track_group_name(config.group_name, track_number=track_number)
                )
            target_groups.append(config.operator_group_name)
            if track_number is not None:
                target_groups.append(
                    build_track_group_name(config.operator_group_name, track_number=track_number)
                )

        target_groups.append(
            _build_group_name(config.group_name, track_number=None, caption_mode=caption_mode)
        )
        if track_number is not None:
            target_groups.append(
                _build_group_name(
                    config.group_name,
                    track_number=track_number,
                    caption_mode=caption_mode,
                )
            )
        target_groups.append(
            _build_group_name(config.operator_group_name, track_number=None, caption_mode=caption_mode)
        )
        if track_number is not None:
            target_groups.append(
                _build_group_name(
                    config.operator_group_name,
                    track_number=track_number,
                    caption_mode=caption_mode,
                )
            )

        target_groups = list(dict.fromkeys(target_groups))

        try:
            message = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
            for target_group in target_groups:
                client.send_to_group(
                    group=target_group,
                    message=message,
                    content_type="text/plain",
                )
        except AzureError as error:
            raise RelayWebPubSubError("Unable to publish caption event.") from error

    def _get_client(self) -> tuple[Any, WebPubSubConfig]:
        if self._client and self._config:
            return self._client, self._config

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

        self._config = config
        return self._client, self._config


class AzureWebPubSubViewerTokenProvider:
    def __init__(
        self,
        *,
        config_factory: Callable[[], WebPubSubConfig] = WebPubSubConfig.from_environment,
        token_ttl: timedelta = timedelta(minutes=60),
    ) -> None:
        self._config_factory = config_factory
        self._token_ttl = token_ttl
        self._client: Any | None = None
        self._config: WebPubSubConfig | None = None

    def get_viewer_access_token(
        self,
        *,
        track_number: int | None = None,
        caption_mode: str | None = None,
        now: datetime | None = None,
    ) -> ViewerAccessToken:
        client, config = self._get_client()
        reference_time = (now or datetime.now(UTC)).astimezone(UTC)
        expires_at = reference_time + self._token_ttl
        minutes_to_expire = max(1, int(self._token_ttl.total_seconds() // 60))
        group_name = _build_group_name(
            config.group_name,
            track_number=track_number,
            caption_mode=caption_mode,
        )

        try:
            token = client.get_client_access_token(
                minutes_to_expire=minutes_to_expire,
                groups=[group_name],
            )
        except AzureError as error:
            raise RelayWebPubSubError("Unable to generate viewer access token.") from error

        url = _extract_client_access_url(token)
        return ViewerAccessToken(
            url=url,
            hub_name=config.hub_name,
            group_name=group_name,
            expires_at=expires_at,
        )

    def get_operator_access_token(
        self,
        *,
        track_number: int | None = None,
        caption_mode: str | None = None,
        now: datetime | None = None,
    ) -> ViewerAccessToken:
        client, config = self._get_client()
        reference_time = (now or datetime.now(UTC)).astimezone(UTC)
        expires_at = reference_time + self._token_ttl
        minutes_to_expire = max(1, int(self._token_ttl.total_seconds() // 60))
        group_name = _build_group_name(
            config.operator_group_name,
            track_number=track_number,
            caption_mode=caption_mode,
        )

        try:
            token = client.get_client_access_token(
                minutes_to_expire=minutes_to_expire,
                groups=[group_name],
            )
        except AzureError as error:
            raise RelayWebPubSubError("Unable to generate operator access token.") from error

        url = _extract_client_access_url(token)
        return ViewerAccessToken(
            url=url,
            hub_name=config.hub_name,
            group_name=group_name,
            expires_at=expires_at,
        )

    def _get_client(self) -> tuple[Any, WebPubSubConfig]:
        if self._client and self._config:
            return self._client, self._config

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

        self._config = config
        return self._client, self._config


def _extract_client_access_url(token: object) -> str:
    if isinstance(token, dict):
        url = token.get("url")
    else:
        url = getattr(token, "url", None)

    if not isinstance(url, str) or not url:
        raise RelayWebPubSubError("Azure Web PubSub returned an invalid viewer access token.")
    return url


def build_track_group_name(base_group_name: str, *, track_number: int) -> str:
    return f"{base_group_name}-track-{track_number}"


def build_caption_mode_group_name(base_group_name: str, *, caption_mode: str) -> str:
    return f"{base_group_name}-{caption_mode}"


def _build_group_name(
    base_group_name: str,
    *,
    track_number: int | None,
    caption_mode: str | None,
) -> str:
    group_name = (
        build_caption_mode_group_name(base_group_name, caption_mode=caption_mode)
        if caption_mode
        else base_group_name
    )
    if track_number is None:
        return group_name
    return build_track_group_name(group_name, track_number=track_number)
