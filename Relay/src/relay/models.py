from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime


@dataclass(frozen=True)
class CaptionSource:
    bundle_identifier: str
    app_version: str | None


@dataclass(frozen=True)
class SpeechSegment:
    input_language: str
    offset_ticks: int
    duration_ticks: int
    text: str


@dataclass(frozen=True)
class CaptionModeContent:
    provider: str | None
    captions: dict[str, str]


@dataclass(frozen=True)
class CaptionEvent:
    room_name: str
    track_number: int
    created_at: datetime
    source: CaptionSource
    speech: SpeechSegment
    captions: dict[str, str]
    caption_modes: dict[str, CaptionModeContent]
