from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest
from azure.core.exceptions import AzureError

from relay.webpubsub import AzureWebPubSubPublisher
from relay.webpubsub import AzureWebPubSubViewerTokenProvider
from relay.webpubsub import RelayWebPubSubError
from relay.webpubsub import WebPubSubConfig
from relay.webpubsub import build_viewer_user_id
from relay.webpubsub import parse_viewer_track_number_from_user_id


def test_webpubsub_config_reads_environment() -> None:
    config = WebPubSubConfig.from_environment(
        {
            "AZURE_WEBPUBSUB_ENDPOINT": " https://livecaption.webpubsub.azure.com/ ",
            "AZURE_WEBPUBSUB_HUB_NAME": "livecaption",
            "AZURE_WEBPUBSUB_GROUP_NAME": "caption-live",
        }
    )

    assert config.endpoint == "https://livecaption.webpubsub.azure.com"
    assert config.hub_name == "livecaption"
    assert config.group_name == "caption-live"


def test_webpubsub_config_requires_values() -> None:
    with pytest.raises(RelayWebPubSubError) as error:
        WebPubSubConfig.from_environment({})

    assert "AZURE_WEBPUBSUB_ENDPOINT" in str(error.value)
    assert "AZURE_WEBPUBSUB_HUB_NAME" in str(error.value)
    assert "AZURE_WEBPUBSUB_GROUP_NAME" in str(error.value)


def test_webpubsub_config_requires_https_endpoint() -> None:
    with pytest.raises(RelayWebPubSubError):
        WebPubSubConfig.from_environment(
            {
                "AZURE_WEBPUBSUB_ENDPOINT": "http://livecaption.webpubsub.azure.com",
                "AZURE_WEBPUBSUB_HUB_NAME": "livecaption",
                "AZURE_WEBPUBSUB_GROUP_NAME": "caption-live",
            }
        )


def test_webpubsub_publisher_sends_payload_to_configured_group(monkeypatch: pytest.MonkeyPatch) -> None:
    config = WebPubSubConfig(
        endpoint="https://livecaption.webpubsub.azure.com",
        hub_name="livecaption",
        group_name="caption-live",
    )
    client = FakeWebPubSubServiceClient()
    publisher = AzureWebPubSubPublisher(config_factory=lambda: config)
    monkeypatch.setattr(publisher, "_client", client)
    monkeypatch.setattr(publisher, "_config", config)

    publisher.publish({"accepted": True})

    assert client.messages == [
        {
            "group": "caption-live",
            "message": '{"accepted":true}',
            "content_type": "text/plain",
        },
    ]


def test_webpubsub_publisher_also_sends_payload_to_track_group(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    config = WebPubSubConfig(
        endpoint="https://livecaption.webpubsub.azure.com",
        hub_name="livecaption",
        group_name="caption-live",
    )
    client = FakeWebPubSubServiceClient()
    publisher = AzureWebPubSubPublisher(config_factory=lambda: config)
    monkeypatch.setattr(publisher, "_client", client)
    monkeypatch.setattr(publisher, "_config", config)

    publisher.publish({"trackNumber": 2}, track_number=2)

    assert client.messages == [
        {
            "group": "caption-live-track-2",
            "message": '{"trackNumber":2}',
            "content_type": "text/plain",
        },
    ]


def test_webpubsub_publisher_preserves_non_ascii_text(monkeypatch: pytest.MonkeyPatch) -> None:
    config = WebPubSubConfig(
        endpoint="https://livecaption.webpubsub.azure.com",
        hub_name="livecaption",
        group_name="caption-live",
    )
    client = FakeWebPubSubServiceClient()
    publisher = AzureWebPubSubPublisher(config_factory=lambda: config)
    monkeypatch.setattr(publisher, "_client", client)
    monkeypatch.setattr(publisher, "_config", config)

    publisher.publish({"captions": {"zh-Hant": "你好", "ja": "こんにちは"}})

    assert client.messages == [
        {
            "group": "caption-live",
            "message": '{"captions":{"zh-Hant":"你好","ja":"こんにちは"}}',
            "content_type": "text/plain",
        },
    ]
    assert "\\u" not in client.messages[0]["message"]


def test_webpubsub_publisher_sends_payload_to_connection(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    config = WebPubSubConfig(
        endpoint="https://livecaption.webpubsub.azure.com",
        hub_name="livecaption",
        group_name="caption-live",
    )
    client = FakeWebPubSubServiceClient()
    publisher = AzureWebPubSubPublisher(config_factory=lambda: config)
    monkeypatch.setattr(publisher, "_client", client)
    monkeypatch.setattr(publisher, "_config", config)

    publisher.publish_to_connection({"type": "control"}, connection_id="connection-1")

    assert client.connection_messages == [
        {
            "connection_id": "connection-1",
            "message": '{"type":"control"}',
            "content_type": "text/plain",
        }
    ]


def test_webpubsub_publisher_wraps_azure_errors(monkeypatch: pytest.MonkeyPatch) -> None:
    config = WebPubSubConfig(
        endpoint="https://livecaption.webpubsub.azure.com",
        hub_name="livecaption",
        group_name="caption-live",
    )
    publisher = AzureWebPubSubPublisher(config_factory=lambda: config)
    monkeypatch.setattr(publisher, "_client", FakeWebPubSubServiceClient(fail=True))
    monkeypatch.setattr(publisher, "_config", config)

    with pytest.raises(RelayWebPubSubError):
        publisher.publish({"caption": "do not leak"})


def test_viewer_token_provider_generates_track_group_token(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    config = WebPubSubConfig(
        endpoint="https://livecaption.webpubsub.azure.com",
        hub_name="livecaption",
        group_name="caption-live",
    )
    client = FakeWebPubSubServiceClient()
    provider = AzureWebPubSubViewerTokenProvider(
        config_factory=lambda: config,
        token_ttl=timedelta(minutes=60),
    )
    monkeypatch.setattr(provider, "_client", client)
    monkeypatch.setattr(provider, "_config", config)

    access = provider.get_viewer_access_token(
        track_number=2,
        now=datetime(2026, 4, 30, 12, 0, tzinfo=UTC),
    )

    request = client.access_token_requests[0]
    assert access.group_name == "caption-live-track-2"
    assert request["minutes_to_expire"] == 60
    assert request["groups"] == ["caption-live-track-2"]
    assert parse_viewer_track_number_from_user_id(request["user_id"]) == 2


def test_viewer_user_id_encodes_track_number() -> None:
    user_id = build_viewer_user_id(12)

    assert parse_viewer_track_number_from_user_id(user_id) == 12
    assert parse_viewer_track_number_from_user_id("viewer-track-0-invalid") is None
    assert parse_viewer_track_number_from_user_id("operator") is None


def test_viewer_token_provider_rejects_invalid_token_response(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    config = WebPubSubConfig(
        endpoint="https://livecaption.webpubsub.azure.com",
        hub_name="livecaption",
        group_name="caption-live",
    )
    provider = AzureWebPubSubViewerTokenProvider(config_factory=lambda: config)
    monkeypatch.setattr(provider, "_client", FakeWebPubSubServiceClient(token_response={}))
    monkeypatch.setattr(provider, "_config", config)

    with pytest.raises(RelayWebPubSubError):
        provider.get_viewer_access_token(track_number=1, now=datetime(2026, 4, 30, 12, 0, tzinfo=UTC))


def test_viewer_token_provider_wraps_azure_errors(monkeypatch: pytest.MonkeyPatch) -> None:
    config = WebPubSubConfig(
        endpoint="https://livecaption.webpubsub.azure.com",
        hub_name="livecaption",
        group_name="caption-live",
    )
    provider = AzureWebPubSubViewerTokenProvider(config_factory=lambda: config)
    monkeypatch.setattr(provider, "_client", FakeWebPubSubServiceClient(fail=True))
    monkeypatch.setattr(provider, "_config", config)

    with pytest.raises(RelayWebPubSubError):
        provider.get_viewer_access_token(track_number=1, now=datetime(2026, 4, 30, 12, 0, tzinfo=UTC))


class FakeWebPubSubServiceClient:
    def __init__(self, *, fail: bool = False, token_response: object | None = None) -> None:
        self.fail = fail
        self.token_response = (
            token_response
            if token_response is not None
            else {
                "url": "wss://livecaption.webpubsub.azure.com/client/hubs/livecaption?access_token=fake"
            }
        )
        self.messages: list[dict[str, object]] = []
        self.connection_messages: list[dict[str, object]] = []
        self.access_token_requests: list[dict[str, object]] = []

    def send_to_group(self, *, group: str, message: str, content_type: str) -> None:
        if self.fail:
            raise AzureError("azure failure")
        self.messages.append(
            {
                "group": group,
                "message": message,
                "content_type": content_type,
            }
        )

    def send_to_connection(
        self,
        *,
        connection_id: str,
        message: str,
        content_type: str,
    ) -> None:
        if self.fail:
            raise AzureError("azure failure")
        self.connection_messages.append(
            {
                "connection_id": connection_id,
                "message": message,
                "content_type": content_type,
            }
        )

    def get_client_access_token(
        self,
        *,
        minutes_to_expire: int,
        groups: list[str],
        user_id: str,
    ) -> object:
        if self.fail:
            raise AzureError("azure failure")
        self.access_token_requests.append(
            {
                "minutes_to_expire": minutes_to_expire,
                "groups": groups,
                "user_id": user_id,
            }
        )
        return self.token_response
