from __future__ import annotations

import hashlib
import hmac
import os
from dataclasses import dataclass
from datetime import UTC, datetime, time, timedelta

from relay.webpubsub import WebPubSubConfig

ACCESS_CODE_HEADER = "X-LiveCaption-Viewer-Access-Code"
ACCESS_CODE_EXPIRES_AT_HEADER = "X-LiveCaption-Viewer-Access-Expires-At"
ACCESS_CODE_REQUIRED_SETTING = "VIEWER_ACCESS_CODE_REQUIRED"


class ViewerAccessError(ValueError):
    pass


@dataclass(frozen=True)
class ViewerAccess:
    code: str
    expires_at: datetime


def is_viewer_access_code_required(
    values: dict[str, str] | None = None,
) -> bool:
    setting_values = values if values is not None else os.environ
    raw_value = setting_values.get(ACCESS_CODE_REQUIRED_SETTING)
    if raw_value is None:
        return True

    normalized_value = raw_value.strip().lower()
    if normalized_value in {"false", "0", "no", "off"}:
        return False
    if normalized_value in {"true", "1", "yes", "on"}:
        return True

    return True


def build_viewer_access(
    *,
    speech_key: str,
    webpubsub_config: WebPubSubConfig,
    now: datetime | None = None,
) -> ViewerAccess:
    reference_time = (now or datetime.now(UTC)).astimezone(UTC)
    code_date = reference_time.date()
    code = _build_code(
        speech_key=speech_key,
        webpubsub_config=webpubsub_config,
        date_value=code_date.isoformat(),
    )
    expires_at = datetime.combine(code_date + timedelta(days=1), time.min, tzinfo=UTC)
    return ViewerAccess(code=code, expires_at=expires_at)


def verify_viewer_access_code(
    *,
    access_code: str | None,
    speech_keys: tuple[str, ...],
    webpubsub_config: WebPubSubConfig,
    now: datetime | None = None,
) -> None:
    if not access_code:
        raise ViewerAccessError("Viewer access code is missing.")

    normalized_code = access_code.strip()
    if not normalized_code:
        raise ViewerAccessError("Viewer access code is missing.")

    reference_time = (now or datetime.now(UTC)).astimezone(UTC)
    allowed_dates = {
        reference_time.date().isoformat(),
        (reference_time.date() - timedelta(days=1)).isoformat(),
    }
    for speech_key in speech_keys:
        for date_value in allowed_dates:
            expected_code = _build_code(
                speech_key=speech_key,
                webpubsub_config=webpubsub_config,
                date_value=date_value,
            )
            if hmac.compare_digest(normalized_code, expected_code):
                return

    raise ViewerAccessError("Viewer access code is invalid.")


def _build_code(
    *,
    speech_key: str,
    webpubsub_config: WebPubSubConfig,
    date_value: str,
) -> str:
    message = (
        f"viewer-access:{date_value}:{webpubsub_config.hub_name}:{webpubsub_config.group_name}"
    ).encode("utf-8")
    digest = hmac.new(speech_key.encode("utf-8"), message, hashlib.sha256).hexdigest()
    return f"{int(digest[:12], 16) % 1_000_000:06d}"
