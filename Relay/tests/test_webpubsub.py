from __future__ import annotations

import pytest
from azure.core.exceptions import AzureError

from relay.webpubsub import AzureWebPubSubPublisher, RelayWebPubSubError, WebPubSubConfig


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
    monkeypatch.setattr(publisher, "_group_name", config.group_name)

    publisher.publish({"accepted": True})

    assert client.messages == [
        {
            "group": "caption-live",
            "message": '{"accepted":true}',
            "content_type": "text/plain",
        }
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
    monkeypatch.setattr(publisher, "_group_name", config.group_name)

    publisher.publish({"captions": {"zh-Hant": "你好", "ja": "こんにちは"}})

    assert client.messages == [
        {
            "group": "caption-live",
            "message": '{"captions":{"zh-Hant":"你好","ja":"こんにちは"}}',
            "content_type": "text/plain",
        }
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
    monkeypatch.setattr(publisher, "_group_name", config.group_name)

    with pytest.raises(RelayWebPubSubError):
        publisher.publish({"caption": "do not leak"})


class FakeWebPubSubServiceClient:
    def __init__(self, *, fail: bool = False) -> None:
        self.fail = fail
        self.messages: list[dict[str, object]] = []

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
