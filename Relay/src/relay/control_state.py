from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from os import environ
from typing import Any, Callable, Protocol

from azure.core.exceptions import AzureError

CONTROL_EVENT_ORDER = ("portalStatus", "sessionStatus", "captionAvailability")
DEFAULT_CONTROL_STATE_TABLE_NAME = "LiveCaptionRelayControlState"
DEFAULT_PORTAL_ONLINE_STATUS_TTL = timedelta(seconds=90)


class RelayControlStateError(RuntimeError):
    pass


class ControlEventStateStore(Protocol):
    def update(
        self,
        *,
        track_number: int,
        event_name: str,
        payload: dict[str, Any],
    ) -> None:
        pass

    def latest_for_track(self, track_number: int) -> list[dict[str, Any]]:
        pass

    def mark_portal_activity(self, *, track_number: int, updated_at: str) -> None:
        pass


@dataclass(frozen=True)
class ControlStateConfig:
    table_endpoint: str
    table_name: str

    @classmethod
    def from_environment(cls, env: dict[str, str] | None = None) -> ControlStateConfig:
        values = env or environ
        table_endpoint = (
            values.get("RELAY_CONTROL_STATE_TABLE_ENDPOINT")
            or values.get("AzureWebJobsStorage__tableServiceUri")
            or ""
        ).strip()
        table_name = (
            values.get("RELAY_CONTROL_STATE_TABLE_NAME")
            or DEFAULT_CONTROL_STATE_TABLE_NAME
        ).strip()

        if not table_endpoint:
            raise RelayControlStateError(
                "Missing Relay control state setting: AzureWebJobsStorage__tableServiceUri"
            )
        if not table_endpoint.startswith("https://"):
            raise RelayControlStateError("Relay control state table endpoint must be an HTTPS URL.")
        if not _is_valid_table_name(table_name):
            raise RelayControlStateError("Relay control state table name is invalid.")

        return cls(
            table_endpoint=table_endpoint.rstrip("/"),
            table_name=table_name,
        )


class AzureTableControlEventStateStore:
    def __init__(
        self,
        *,
        config_factory: Callable[[], ControlStateConfig] = ControlStateConfig.from_environment,
        table_client_factory: Callable[[], Any] | None = None,
        now_factory: Callable[[], datetime] = lambda: datetime.now(UTC),
        portal_online_status_ttl: timedelta = DEFAULT_PORTAL_ONLINE_STATUS_TTL,
    ) -> None:
        self._config_factory = config_factory
        self._table_client_factory = table_client_factory
        self._now_factory = now_factory
        self._portal_online_status_ttl = portal_online_status_ttl
        self._table_client: Any | None = None

    def update(
        self,
        *,
        track_number: int,
        event_name: str,
        payload: dict[str, Any],
    ) -> None:
        try:
            table_client = self._get_table_client()
            table_client.upsert_entity(
                entity={
                    "PartitionKey": _partition_key(track_number),
                    "RowKey": event_name,
                    "payload": json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
                },
                mode=self._replace_mode(),
            )
        except (AzureError, ImportError, TypeError, ValueError) as error:
            raise RelayControlStateError("Unable to update Relay control state.") from error

    def latest_for_track(self, track_number: int) -> list[dict[str, Any]]:
        try:
            table_client = self._get_table_client()
            portal_activity_updated_at = self._portal_activity_updated_at(
                table_client,
                track_number=track_number,
            )
            now = self._now_factory()
            payloads: list[dict[str, Any]] = []
            is_portal_offline = False
            for event_name in CONTROL_EVENT_ORDER:
                entity = self._get_entity_or_none(
                    table_client,
                    partition_key=_partition_key(track_number),
                    row_key=event_name,
                )
                if entity is None:
                    continue
                if event_name == "captionAvailability" and is_portal_offline:
                    continue
                raw_payload = entity.get("payload")
                if not isinstance(raw_payload, str):
                    raise RelayControlStateError("Relay control state payload is invalid.")
                payload = json.loads(raw_payload)
                if not isinstance(payload, dict):
                    raise RelayControlStateError("Relay control state payload is invalid.")
                if _is_portal_online_status(payload):
                    updated_at = _latest_timestamp(payload.get("updatedAt"), portal_activity_updated_at)
                    if updated_at is None:
                        continue
                    if now.astimezone(UTC) - updated_at > self._portal_online_status_ttl:
                        payload = _synthetic_portal_offline_status(now)
                if _is_portal_offline_status(payload):
                    is_portal_offline = True
                payloads.append(payload)
            return payloads
        except (AzureError, ImportError, TypeError, ValueError, json.JSONDecodeError) as error:
            raise RelayControlStateError("Unable to read Relay control state.") from error

    def mark_portal_activity(self, *, track_number: int, updated_at: str) -> None:
        try:
            table_client = self._get_table_client()
            table_client.upsert_entity(
                entity={
                    "PartitionKey": _partition_key(track_number),
                    "RowKey": "portalActivity",
                    "updatedAt": updated_at,
                },
                mode=self._replace_mode(),
            )
        except (AzureError, ImportError, TypeError, ValueError) as error:
            raise RelayControlStateError("Unable to update Relay control state.") from error

    def _get_table_client(self) -> Any:
        if self._table_client is not None:
            return self._table_client

        if self._table_client_factory is not None:
            self._table_client = self._table_client_factory()
            return self._table_client

        config = self._config_factory()
        try:
            from azure.data.tables import TableServiceClient
            from azure.identity import DefaultAzureCredential

            service_client = TableServiceClient(
                endpoint=config.table_endpoint,
                credential=DefaultAzureCredential(),
            )
            self._table_client = service_client.create_table_if_not_exists(
                table_name=config.table_name
            )
        except (AzureError, ImportError) as error:
            raise RelayControlStateError("Unable to create Relay control state client.") from error

        return self._table_client

    def _portal_activity_updated_at(self, table_client: Any, *, track_number: int) -> str | None:
        entity = self._get_entity_or_none(
            table_client,
            partition_key=_partition_key(track_number),
            row_key="portalActivity",
        )
        if entity is None:
            return None

        updated_at = entity.get("updatedAt")
        return updated_at if isinstance(updated_at, str) else None

    @staticmethod
    def _replace_mode() -> Any:
        from azure.data.tables import UpdateMode

        return UpdateMode.REPLACE

    @staticmethod
    def _get_entity_or_none(
        table_client: Any,
        *,
        partition_key: str,
        row_key: str,
    ) -> dict[str, Any] | None:
        from azure.core.exceptions import ResourceNotFoundError

        try:
            return table_client.get_entity(partition_key=partition_key, row_key=row_key)
        except ResourceNotFoundError:
            return None


def _partition_key(track_number: int) -> str:
    return f"track-{track_number}"


def _is_valid_table_name(value: str) -> bool:
    return 3 <= len(value) <= 63 and value.isalnum() and value[0].isalpha()


def _is_portal_online_status(payload: dict[str, Any]) -> bool:
    return payload.get("event") == "portalStatus" and payload.get("status") == "online"


def _is_portal_offline_status(payload: dict[str, Any]) -> bool:
    return payload.get("event") == "portalStatus" and payload.get("status") == "offline"


def _synthetic_portal_offline_status(now: datetime) -> dict[str, Any]:
    return {
        "type": "control",
        "event": "portalStatus",
        "status": "offline",
        "updatedAt": _format_utc(now),
    }


def _latest_timestamp(*values: Any) -> datetime | None:
    timestamps = [
        timestamp
        for value in values
        if (timestamp := _parse_utc_timestamp(value)) is not None
    ]
    if not timestamps:
        return None
    return max(timestamps)


def _parse_utc_timestamp(value: Any) -> datetime | None:
    if not isinstance(value, str):
        return None

    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None

    if parsed.tzinfo is None:
        return None
    return parsed.astimezone(UTC)


def _format_utc(value: datetime) -> str:
    return value.astimezone(UTC).isoformat(timespec="milliseconds").replace("+00:00", "Z")
