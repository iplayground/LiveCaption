from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest
from azure.core.exceptions import AzureError

from relay.webpubsub import AzureWebPubSubPublisher
from relay.webpubsub import AzureWebPubSubViewerTokenProvider
from relay.webpubsub import RelayWebPubSubError
from relay.webpubsub import WebPubSubConfig


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
    assert config.operator_group_name == "caption-operator"


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
        {
            "group": "caption-operator",
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
            "group": "caption-live",
            "message": '{"trackNumber":2}',
            "content_type": "text/plain",
        },
        {
            "group": "caption-live-track-2",
            "message": '{"trackNumber":2}',
            "content_type": "text/plain",
        },
        {
            "group": "caption-operator",
            "message": '{"trackNumber":2}',
            "content_type": "text/plain",
        },
        {
            "group": "caption-operator-track-2",
            "message": '{"trackNumber":2}',
            "content_type": "text/plain",
        },
    ]


def test_webpubsub_publisher_sends_payload_to_caption_mode_groups(
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

    publisher.publish({"captionMode": "accurate"}, track_number=2, caption_mode="accurate")

    assert client.messages == [
        {
            "group": "caption-live-accurate",
            "message": '{"captionMode":"accurate"}',
            "content_type": "text/plain",
        },
        {
            "group": "caption-live-accurate-track-2",
            "message": '{"captionMode":"accurate"}',
            "content_type": "text/plain",
        },
        {
            "group": "caption-operator-accurate",
            "message": '{"captionMode":"accurate"}',
            "content_type": "text/plain",
        },
        {
            "group": "caption-operator-accurate-track-2",
            "message": '{"captionMode":"accurate"}',
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
        {
            "group": "caption-operator",
            "message": '{"captions":{"zh-Hant":"你好","ja":"こんにちは"}}',
            "content_type": "text/plain",
        },
    ]
    assert "\\u" not in client.messages[0]["message"]


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


def test_viewer_token_provider_generates_receive_only_group_token(
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
        now=datetime(2026, 4, 30, 12, 0, tzinfo=UTC),
    )

    assert access.url == "wss://livecaption.webpubsub.azure.com/client/hubs/livecaption?access_token=fake"
    assert access.hub_name == "livecaption"
    assert access.group_name == "caption-live"
    assert access.expires_at == datetime(2026, 4, 30, 13, 0, tzinfo=UTC)
    assert client.access_token_requests == [
        {
            "minutes_to_expire": 60,
            "groups": ["caption-live"],
        }
    ]


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

    assert access.group_name == "caption-live-track-2"
    assert client.access_token_requests == [
        {
            "minutes_to_expire": 60,
            "groups": ["caption-live-track-2"],
        }
    ]


def test_viewer_token_provider_generates_caption_mode_track_group_token(
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
        caption_mode="accurate",
        now=datetime(2026, 4, 30, 12, 0, tzinfo=UTC),
    )

    assert access.group_name == "caption-live-accurate-track-2"
    assert client.access_token_requests == [
        {
            "minutes_to_expire": 60,
            "groups": ["caption-live-accurate-track-2"],
        }
    ]


def test_viewer_token_provider_generates_operator_track_group_token(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    config = WebPubSubConfig(
        endpoint="https://livecaption.webpubsub.azure.com",
        hub_name="livecaption",
        group_name="caption-live",
        operator_group_name="caption-operator",
    )
    client = FakeWebPubSubServiceClient()
    provider = AzureWebPubSubViewerTokenProvider(
        config_factory=lambda: config,
        token_ttl=timedelta(minutes=60),
    )
    monkeypatch.setattr(provider, "_client", client)
    monkeypatch.setattr(provider, "_config", config)

    access = provider.get_operator_access_token(
        track_number=2,
        now=datetime(2026, 4, 30, 12, 0, tzinfo=UTC),
    )

    assert access.group_name == "caption-operator-track-2"
    assert client.access_token_requests == [
        {
            "minutes_to_expire": 60,
            "groups": ["caption-operator-track-2"],
        }
    ]


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
        provider.get_viewer_access_token(now=datetime(2026, 4, 30, 12, 0, tzinfo=UTC))


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
        provider.get_viewer_access_token(now=datetime(2026, 4, 30, 12, 0, tzinfo=UTC))


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

    def get_client_access_token(
        self,
        *,
        minutes_to_expire: int,
        groups: list[str],
    ) -> object:
        if self.fail:
            raise AzureError("azure failure")
        self.access_token_requests.append(
            {
                "minutes_to_expire": minutes_to_expire,
                "groups": groups,
            }
        )
        return self.token_response
