from __future__ import annotations

import json
from dataclasses import dataclass
from os import environ
from typing import Any, Callable, Protocol

from azure.core.exceptions import AzureError

CONTROL_EVENT_ORDER = ("portalStatus", "sessionStatus", "captionAvailability")
DEFAULT_CONTROL_STATE_TABLE_NAME = "LiveCaptionRelayControlState"


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
    ) -> None:
        self._config_factory = config_factory
        self._table_client_factory = table_client_factory
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
            payloads: list[dict[str, Any]] = []
            for event_name in CONTROL_EVENT_ORDER:
                entity = self._get_entity_or_none(
                    table_client,
                    partition_key=_partition_key(track_number),
                    row_key=event_name,
                )
                if entity is None:
                    continue
                raw_payload = entity.get("payload")
                if not isinstance(raw_payload, str):
                    raise RelayControlStateError("Relay control state payload is invalid.")
                payload = json.loads(raw_payload)
                if not isinstance(payload, dict):
                    raise RelayControlStateError("Relay control state payload is invalid.")
                payloads.append(payload)
            return payloads
        except (AzureError, ImportError, TypeError, ValueError, json.JSONDecodeError) as error:
            raise RelayControlStateError("Unable to read Relay control state.") from error

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
