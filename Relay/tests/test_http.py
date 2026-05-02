from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from relay.http import build_health_payload, build_publish_payload
from relay.http import handle_caption_event_request
from relay.http import handle_viewer_negotiate_request
from relay.viewer_access import ViewerAccessError
from relay.webpubsub import ViewerAccessToken
from relay.webpubsub import RelayWebPubSubError
from relay.validation import validate_caption_event

from tests.test_validation import valid_payload


class FakePublisher:
    def __init__(self, *, fail: bool = False) -> None:
        self.fail = fail
        self.payloads: list[dict[str, Any]] = []

    def publish(self, payload: dict[str, Any], *, track_number: int | None = None) -> None:
        if self.fail:
            raise RelayWebPubSubError("boom")
        self.payloads.append({"payload": payload, "track_number": track_number})


class FakeViewerTokenProvider:
    def __init__(self, *, fail: bool = False) -> None:
        self.fail = fail
        self.requests: list[tuple[int | None, datetime | None]] = []

    def get_viewer_access_token(
        self,
        *,
        track_number: int | None = None,
        now: datetime | None = None,
    ) -> ViewerAccessToken:
        self.requests.append((track_number, now))
        if self.fail:
            raise RelayWebPubSubError("boom")
        return ViewerAccessToken(
            url="wss://livecaption.webpubsub.azure.com/client/hubs/livecaption?access_token=fake",
            hub_name="livecaption",
            group_name=(
                f"caption-live-track-{track_number}"
                if track_number is not None
                else "caption-live"
            ),
            expires_at=datetime(2026, 4, 30, 13, 0, tzinfo=UTC),
        )


class FakeViewerAccessCodeVerifier:
    def __init__(self, *, fail: bool = False) -> None:
        self.fail = fail
        self.requests: list[tuple[str | None, datetime | None]] = []

    def verify(self, *, access_code: str | None, now: datetime | None = None) -> None:
        self.requests.append((access_code, now))
        if self.fail:
            raise ViewerAccessError("invalid")


def test_handle_caption_event_request_accepts_valid_payload() -> None:
    publisher = FakePublisher()

    status_code, body = handle_caption_event_request(
        valid_payload(),
        publisher=publisher,
        now=datetime(2026, 4, 29, 12, 35, tzinfo=UTC),
    )

    assert status_code == 202
    assert body == {"accepted": True}
    assert len(publisher.payloads) == 1
    assert publisher.payloads[0]["track_number"] == 1
    assert publisher.payloads[0]["payload"]["trackNumber"] == 1
    assert publisher.payloads[0]["payload"]["captions"]["en"] == "Welcome to today's event"


def test_handle_caption_event_request_returns_sanitized_error() -> None:
    payload = valid_payload()
    payload["captions"]["en"] = ""
    publisher = FakePublisher()

    status_code, body = handle_caption_event_request(
        payload,
        publisher=publisher,
        now=datetime(2026, 4, 29, 12, 35, tzinfo=UTC),
    )

    assert status_code == 400
    assert body["error"]["code"] == "invalid_caption_event"
    assert body["error"]["details"] == [
        {"field": "captions.en", "reason": "Text is required."}
    ]
    assert publisher.payloads == []


def test_handle_caption_event_request_returns_sanitized_publish_error() -> None:
    status_code, body = handle_caption_event_request(
        valid_payload(),
        publisher=FakePublisher(fail=True),
        now=datetime(2026, 4, 29, 12, 35, tzinfo=UTC),
    )

    assert status_code == 502
    assert body == {
        "error": {
            "code": "caption_publish_failed",
            "message": "Caption event could not be published.",
            "details": [],
        }
    }
    assert "Welcome to today's event" not in str(body)


def test_build_publish_payload_omits_source_and_speech_text() -> None:
    event = validate_caption_event(
        valid_payload(),
        now=datetime(2026, 4, 29, 12, 35, tzinfo=UTC),
    )

    payload = build_publish_payload(
        event,
        received_at=datetime(2026, 4, 29, 12, 35, 1, 123000, tzinfo=UTC),
    )

    assert payload["relay"] == {"receivedAt": "2026-04-29T12:35:01.123Z"}
    assert payload["roomName"] == "A101"
    assert payload["trackNumber"] == 1
    assert payload["speech"] == {
        "inputLanguage": "zh-TW",
        "offsetTicks": 120000000,
        "durationTicks": 35000000,
    }
    assert "source" not in payload
    assert "text" not in payload["speech"]


def test_build_publish_payload_keeps_empty_room_name() -> None:
    request_payload = valid_payload()
    request_payload["roomName"] = ""
    event = validate_caption_event(
        request_payload,
        now=datetime(2026, 4, 29, 12, 35, tzinfo=UTC),
    )

    payload = build_publish_payload(
        event,
        received_at=datetime(2026, 4, 29, 12, 35, 1, 123000, tzinfo=UTC),
    )

    assert payload["roomName"] == ""
    assert payload["trackNumber"] == 1


def test_build_health_payload_includes_commit() -> None:
    assert build_health_payload(commit="abc123") == {
        "status": "ok",
        "commit": "abc123",
    }


def test_build_health_payload_defaults_to_unknown_commit() -> None:
    assert build_health_payload() == {
        "status": "ok",
        "commit": "unknown",
    }


def test_handle_viewer_negotiate_request_returns_receive_url() -> None:
    provider = FakeViewerTokenProvider()
    verifier = FakeViewerAccessCodeVerifier()
    now = datetime(2026, 4, 30, 12, 0, tzinfo=UTC)

    status_code, body = handle_viewer_negotiate_request(
        "123456",
        token_provider=provider,
        access_code_verifier=verifier,
        now=now,
    )

    assert status_code == 200
    assert body == {
        "url": "wss://livecaption.webpubsub.azure.com/client/hubs/livecaption?access_token=fake",
        "hub": "livecaption",
        "group": "caption-live",
        "expiresAt": "2026-04-30T13:00:00.000Z",
    }
    assert provider.requests == [(None, now)]
    assert verifier.requests == [("123456", now)]


def test_handle_viewer_negotiate_request_accepts_track_filter() -> None:
    provider = FakeViewerTokenProvider()
    verifier = FakeViewerAccessCodeVerifier()
    now = datetime(2026, 4, 30, 12, 0, tzinfo=UTC)

    status_code, body = handle_viewer_negotiate_request(
        "123456",
        token_provider=provider,
        access_code_verifier=verifier,
        track_number=2,
        now=now,
    )

    assert status_code == 200
    assert body["group"] == "caption-live-track-2"
    assert provider.requests == [(2, now)]


def test_handle_viewer_negotiate_request_rejects_invalid_track_filter() -> None:
    provider = FakeViewerTokenProvider()
    verifier = FakeViewerAccessCodeVerifier()

    status_code, body = handle_viewer_negotiate_request(
        "123456",
        token_provider=provider,
        access_code_verifier=verifier,
        track_number="2",
        now=datetime(2026, 4, 30, 12, 0, tzinfo=UTC),
    )

    assert status_code == 400
    assert body["error"]["code"] == "invalid_viewer_filter"
    assert provider.requests == []
    assert verifier.requests == []


def test_handle_viewer_negotiate_request_returns_sanitized_error() -> None:
    status_code, body = handle_viewer_negotiate_request(
        "123456",
        token_provider=FakeViewerTokenProvider(fail=True),
        access_code_verifier=FakeViewerAccessCodeVerifier(),
        now=datetime(2026, 4, 30, 12, 0, tzinfo=UTC),
    )

    assert status_code == 502
    assert body == {
        "error": {
            "code": "viewer_negotiate_failed",
            "message": "Viewer connection could not be negotiated.",
            "details": [],
        }
    }


def test_handle_viewer_negotiate_request_rejects_invalid_access_code() -> None:
    status_code, body = handle_viewer_negotiate_request(
        "bad",
        token_provider=FakeViewerTokenProvider(),
        access_code_verifier=FakeViewerAccessCodeVerifier(fail=True),
        now=datetime(2026, 4, 30, 12, 0, tzinfo=UTC),
    )

    assert status_code == 403
    assert body == {
        "error": {
            "code": "viewer_access_denied",
            "message": "Viewer access code is invalid.",
            "details": [],
        }
    }


def test_handle_viewer_negotiate_request_requires_access_code() -> None:
    verifier = FakeViewerAccessCodeVerifier(fail=True)

    status_code, body = handle_viewer_negotiate_request(
        None,
        token_provider=FakeViewerTokenProvider(),
        access_code_verifier=verifier,
        now=datetime(2026, 4, 30, 12, 0, tzinfo=UTC),
    )

    assert status_code == 403
    assert body["error"]["code"] == "viewer_access_denied"
    assert verifier.requests == [(None, datetime(2026, 4, 30, 12, 0, tzinfo=UTC))]


def test_handle_viewer_negotiate_request_skips_access_code_when_disabled() -> None:
    provider = FakeViewerTokenProvider()
    verifier = FakeViewerAccessCodeVerifier(fail=True)
    now = datetime(2026, 4, 30, 12, 0, tzinfo=UTC)

    status_code, body = handle_viewer_negotiate_request(
        None,
        token_provider=provider,
        access_code_verifier=verifier,
        access_code_required=False,
        now=now,
    )

    assert status_code == 200
    assert body["url"].startswith("wss://livecaption.webpubsub.azure.com/")
    assert provider.requests == [(None, now)]
    assert verifier.requests == []
