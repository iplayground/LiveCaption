from __future__ import annotations

import json
import sys
from datetime import UTC
from pathlib import Path

import azure.functions as func

sys.path.append(str(Path(__file__).resolve().parent / "src"))

from relay.auth import SIGNATURE_HEADER, TIMESTAMP_HEADER, RelayAuthenticationError
from relay.auth import verify_speech_key_signature
from relay.http import build_health_payload
from relay.http import handle_caption_event_request
from relay.http import handle_viewer_negotiate_request
from relay.http import to_json_response_body
from relay.speech_keys import AzureSpeechKeyProvider, RelaySpeechKeyError
from relay.viewer_access import ACCESS_CODE_EXPIRES_AT_HEADER
from relay.viewer_access import ACCESS_CODE_HEADER
from relay.viewer_access import build_viewer_access
from relay.viewer_access import is_viewer_access_code_required
from relay.viewer_access import verify_viewer_access_code
from relay.webpubsub import AzureWebPubSubPublisher, AzureWebPubSubViewerTokenProvider
from relay.webpubsub import RelayWebPubSubError, WebPubSubConfig

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)
speech_key_provider = AzureSpeechKeyProvider()
web_pubsub_publisher = AzureWebPubSubPublisher()
viewer_token_provider = AzureWebPubSubViewerTokenProvider()
ROOT_REDIRECT_URL = "https://github.com/iplayground/LiveCaption"
BUILD_INFO_PATH = Path(__file__).resolve().parent / "build-info.json"


@app.route(route="api/health", methods=["GET"])
def health(req: func.HttpRequest) -> func.HttpResponse:
    return func.HttpResponse(
        to_json_response_body(build_health_payload(commit=_read_build_commit())),
        status_code=200,
        mimetype="application/json",
    )


@app.route(route="{*path}", methods=["GET"])
def root(req: func.HttpRequest) -> func.HttpResponse:
    if req.route_params.get("path"):
        status_code = 404
        body = {
            "error": {
                "code": "not_found",
                "message": "Endpoint is not found.",
                "details": [],
            }
        }
        return func.HttpResponse(
            to_json_response_body(body),
            status_code=status_code,
            mimetype="application/json",
        )

    return func.HttpResponse(status_code=302, headers={"Location": ROOT_REDIRECT_URL})


@app.route(route="api/caption-events", methods=["HEAD", "POST"])
def caption_events(req: func.HttpRequest) -> func.HttpResponse:
    body_bytes = req.get_body()
    try:
        speech_keys = speech_key_provider.get_keys()
        _verify_with_any_speech_key(
            speech_keys=speech_keys,
            timestamp=req.headers.get(TIMESTAMP_HEADER),
            signature=req.headers.get(SIGNATURE_HEADER),
            body=body_bytes,
        )
    except (RelayAuthenticationError, RelaySpeechKeyError):
        return _json_response(
            {
                "error": {
                    "code": "unauthorized",
                    "message": "Request is not authorized.",
                    "details": [],
                }
            },
            status_code=401,
        )
    else:
        if req.method == "HEAD":
            try:
                viewer_access = build_viewer_access(
                    speech_key=speech_keys[0],
                    webpubsub_config=WebPubSubConfig.from_environment(),
                )
            except (RelayWebPubSubError, RelaySpeechKeyError):
                return func.HttpResponse(status_code=502)

            return func.HttpResponse(
                status_code=204,
                headers={
                    ACCESS_CODE_HEADER: viewer_access.code,
                    ACCESS_CODE_EXPIRES_AT_HEADER: _format_utc(viewer_access.expires_at),
                },
            )

        try:
            payload = req.get_json()
        except ValueError:
            status_code = 400
            body = {
                "error": {
                    "code": "invalid_json",
                    "message": "Request body must be valid JSON.",
                    "details": [],
                }
            }
        else:
            status_code, body = handle_caption_event_request(
                payload,
                publisher=web_pubsub_publisher,
            )

    return _json_response(body, status_code=status_code)


@app.route(route="api/viewer/negotiate", methods=["POST"])
def viewer_negotiate(req: func.HttpRequest) -> func.HttpResponse:
    status_code, body = handle_viewer_negotiate_request(
        req.headers.get(ACCESS_CODE_HEADER),
        token_provider=viewer_token_provider,
        access_code_verifier=RelayViewerAccessCodeVerifier(),
        track_number=_read_track_number(req),
        rejected_fields=_read_rejected_viewer_negotiate_fields(req),
        access_code_required=is_viewer_access_code_required(),
    )
    return _json_response(body, status_code=status_code)


def _verify_with_any_speech_key(
    *,
    speech_keys: tuple[str, ...],
    timestamp: str | None,
    signature: str | None,
    body: bytes,
) -> None:
    last_error: RelayAuthenticationError | None = None
    for speech_key in speech_keys:
        try:
            verify_speech_key_signature(
                speech_key=speech_key,
                timestamp=timestamp,
                signature=signature,
                body=body,
            )
            return
        except RelayAuthenticationError as error:
            last_error = error

    raise last_error or RelayAuthenticationError("No Azure Speech key is available.")


def _read_build_commit() -> str | None:
    try:
        payload = json.loads(BUILD_INFO_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None

    commit = payload.get("commit")
    if isinstance(commit, str) and commit:
        return commit
    return None


class RelayViewerAccessCodeVerifier:
    def verify(self, *, access_code: str | None, now=None) -> None:
        speech_keys = speech_key_provider.get_keys(now=now)
        verify_viewer_access_code(
            access_code=access_code,
            speech_keys=speech_keys,
            webpubsub_config=WebPubSubConfig.from_environment(),
            now=now,
        )


def _read_track_number(req: func.HttpRequest):
    return _read_request_body_field(req, "trackNumber")


def _read_rejected_viewer_negotiate_fields(req: func.HttpRequest) -> list[str]:
    body_bytes = req.get_body()
    if not body_bytes:
        return []

    try:
        payload = req.get_json()
    except ValueError:
        return []

    if not isinstance(payload, dict):
        return []

    rejected_names = ("captionMode", "captionModes", "language", "languages")
    return [name for name in rejected_names if name in payload]


def _read_request_body_field(req: func.HttpRequest, field: str):
    body_bytes = req.get_body()
    if not body_bytes:
        return None

    try:
        payload = req.get_json()
    except ValueError:
        return False

    if not isinstance(payload, dict):
        return False
    return payload.get(field)


def _json_response(payload: dict, *, status_code: int) -> func.HttpResponse:
    return func.HttpResponse(
        to_json_response_body(payload),
        status_code=status_code,
        mimetype="application/json",
    )


def _format_utc(value) -> str:
    return value.astimezone(UTC).isoformat(timespec="milliseconds").replace("+00:00", "Z")
