from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from relay.http import SessionSequenceStore, build_health_payload, build_publish_payload
from relay.http import build_control_publish_payload
from relay.http import handle_caption_event_request
from relay.http import handle_viewer_negotiate_request
from relay.viewer_access import ViewerAccessError
from relay.webpubsub import ViewerAccessToken
from relay.webpubsub import RelayWebPubSubError
from relay.validation import validate_caption_event, validate_control_event

from tests.test_validation import valid_payload


class FakePublisher:
    def __init__(self, *, fail: bool = False) -> None:
        self.fail = fail
        self.payloads: list[dict[str, Any]] = []

    def publish(
        self,
        payload: dict[str, Any],
        *,
        track_number: int | None = None,
    ) -> None:
        if self.fail:
            raise RelayWebPubSubError("boom")
        self.payloads.append(
            {"payload": payload, "track_number": track_number}
        )


class FakeViewerTokenProvider:
    def __init__(self, *, fail: bool = False) -> None:
        self.fail = fail
        self.requests: list[tuple[int, datetime | None]] = []

    def get_viewer_access_token(
        self,
        *,
        track_number: int,
        now: datetime | None = None,
    ) -> ViewerAccessToken:
        self.requests.append((track_number, now))
        if self.fail:
            raise RelayWebPubSubError("boom")
        return ViewerAccessToken(
            url="wss://livecaption.webpubsub.azure.com/client/hubs/livecaption?access_token=fake",
            hub_name="livecaption",
            group_name=f"caption-live-track-{track_number}",
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
    assert publisher.payloads[0]["payload"]["type"] == "caption"
    assert publisher.payloads[0]["payload"]["sessionId"] == "2026-04-29T12:34:00.000"
    assert publisher.payloads[0]["payload"]["sequence"] == 1
    assert publisher.payloads[0]["payload"]["captionMode"] == "fast"
    assert "captionProvider" not in publisher.payloads[0]["payload"]
    assert publisher.payloads[0]["payload"]["captions"]["en"] == "Welcome to today's event"


def test_handle_caption_event_request_rejects_legacy_caption_modes() -> None:
    payload = valid_payload()
    payload["captionModes"] = {
        "fast": {
            "provider": "azure-speech",
            "captions": payload["captions"],
        },
        "accurate": {
            "provider": "azure-openai",
            "captions": {
                "zh-Hant": "歡迎各位來到今天的活動",
                "en": "Welcome, everyone, to today's event.",
            },
        },
    }
    publisher = FakePublisher()

    status_code, body = handle_caption_event_request(
        payload,
        publisher=publisher,
        now=datetime(2026, 4, 29, 12, 35, tzinfo=UTC),
    )

    assert status_code == 400
    assert body["error"]["details"] == [
        {"field": "captionModes", "reason": "Use captionMode and captionProvider instead."}
    ]
    assert publisher.payloads == []


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
        caption_mode="fast",
        sequence=42,
    )

    assert payload["type"] == "caption"
    assert payload["sessionId"] == "2026-04-29T12:34:00.000"
    assert payload["sequence"] == 42
    assert payload["captionMode"] == "fast"
    assert "captionProvider" not in payload
    assert payload["offsetTicks"] == 120000000
    assert payload["durationTicks"] == 35000000
    assert "source" not in payload
    assert "speech" not in payload
    assert "text" not in payload


def test_build_publish_payload_preserves_caption_provider_when_present() -> None:
    request_payload = valid_payload()
    request_payload["captionProvider"] = "manual-correction.v1"
    event = validate_caption_event(
        request_payload,
        now=datetime(2026, 4, 29, 12, 35, tzinfo=UTC),
    )

    payload = build_publish_payload(
        event,
        received_at=datetime(2026, 4, 29, 12, 35, 1, 123000, tzinfo=UTC),
        caption_mode="fast",
        sequence=1,
    )

    assert payload["captionProvider"] == "manual-correction.v1"


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
        caption_mode="fast",
        sequence=1,
    )

    assert payload["sessionId"] == "2026-04-29T12:34:00.000"
    assert "roomName" not in payload


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


def test_handle_viewer_negotiate_request_returns_track_receive_url() -> None:
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
    assert body == {
        "url": "wss://livecaption.webpubsub.azure.com/client/hubs/livecaption?access_token=fake",
        "hub": "livecaption",
        "expiresAt": "2026-04-30T13:00:00.000Z",
    }
    assert provider.requests == [(2, now)]
    assert verifier.requests == [("123456", now)]


def test_handle_viewer_negotiate_request_requires_track_number() -> None:
    provider = FakeViewerTokenProvider()
    verifier = FakeViewerAccessCodeVerifier()

    status_code, body = handle_viewer_negotiate_request(
        "123456",
        token_provider=provider,
        access_code_verifier=verifier,
        now=datetime(2026, 4, 30, 12, 0, tzinfo=UTC),
    )

    assert status_code == 400
    assert body["error"]["details"] == [
        {"field": "trackNumber", "reason": "Track number must be a positive integer."}
    ]
    assert provider.requests == []
    assert verifier.requests == []


def test_handle_viewer_negotiate_request_rejects_caption_preferences() -> None:
    provider = FakeViewerTokenProvider()
    verifier = FakeViewerAccessCodeVerifier()

    status_code, body = handle_viewer_negotiate_request(
        "123456",
        token_provider=provider,
        access_code_verifier=verifier,
        track_number=2,
        rejected_fields=["captionMode"],
        now=datetime(2026, 4, 30, 12, 0, tzinfo=UTC),
    )

    assert status_code == 400
    assert body["error"]["details"] == [
        {
            "field": "captionMode",
            "reason": "Caption preferences are not accepted by viewer negotiate.",
        }
    ]
    assert provider.requests == []
    assert verifier.requests == []


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
        track_number=1,
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
        track_number=1,
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
        track_number=1,
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
        track_number=1,
        access_code_required=False,
        now=now,
    )

    assert status_code == 200
    assert body["url"].startswith("wss://livecaption.webpubsub.azure.com/")
    assert provider.requests == [(1, now)]
    assert verifier.requests == []


def test_handle_control_event_request_publishes_control_payload() -> None:
    publisher = FakePublisher()

    status_code, body = handle_caption_event_request(
        {
            "type": "control",
            "trackNumber": 1,
            "event": "sessionStatus",
            "status": "started",
            "sessionId": "2026-04-29T12:34:00.000",
            "updatedAt": "2026-04-29T12:34:00.000Z",
        },
        publisher=publisher,
        now=datetime(2026, 4, 29, 12, 35, tzinfo=UTC),
        sequence_store=SessionSequenceStore(),
    )

    assert status_code == 202
    assert body == {"accepted": True}
    assert publisher.payloads == [
        {
            "track_number": 1,
            "payload": {
                "type": "control",
                "event": "sessionStatus",
                "status": "started",
                "sessionId": "2026-04-29T12:34:00.000",
                "updatedAt": "2026-04-29T12:34:00.000Z",
            },
        }
    ]


def test_build_control_publish_payload_keeps_viewer_shape() -> None:
    event = validate_control_event(
        {
            "type": "control",
            "trackNumber": 1,
            "event": "captionAvailability",
            "availableCaptionModes": ["fast", "accurate"],
            "availableLanguages": ["zh-Hant", "en"],
            "updatedAt": "2026-04-29T12:34:00.000Z",
        },
        now=datetime(2026, 4, 29, 12, 35, tzinfo=UTC),
    )

    assert build_control_publish_payload(event) == {
        "type": "control",
        "event": "captionAvailability",
        "availableCaptionModes": ["fast", "accurate"],
        "availableLanguages": ["zh-Hant", "en"],
        "updatedAt": "2026-04-29T12:34:00.000Z",
    }
