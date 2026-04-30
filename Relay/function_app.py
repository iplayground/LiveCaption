from __future__ import annotations

import sys
from pathlib import Path

import azure.functions as func

sys.path.append(str(Path(__file__).resolve().parent / "src"))

from relay.auth import SIGNATURE_HEADER, TIMESTAMP_HEADER, RelayAuthenticationError
from relay.auth import verify_speech_key_signature
from relay.http import handle_caption_event_request
from relay.http import to_json_response_body
from relay.speech_keys import AzureSpeechKeyProvider, RelaySpeechKeyError

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)
speech_key_provider = AzureSpeechKeyProvider()
ROOT_REDIRECT_URL = "https://github.com/iplayground/LiveCaption"


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


@app.route(route="api/caption-events", methods=["POST"])
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
        status_code = 401
        body = {
            "error": {
                "code": "unauthorized",
                "message": "Request is not authorized.",
                "details": [],
            }
        }
    else:
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
            status_code, body = handle_caption_event_request(payload)

    return func.HttpResponse(
        to_json_response_body(body),
        status_code=status_code,
        mimetype="application/json",
    )


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
