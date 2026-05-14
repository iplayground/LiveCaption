from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from azure.core.exceptions import AzureError, ResourceNotFoundError
from azure.data.tables import UpdateMode

from relay.control_state import AzureTableControlEventStateStore
from relay.control_state import ControlStateConfig
from relay.control_state import RelayControlStateError


class FakeTableClient:
    def __init__(self, *, fail: bool = False) -> None:
        self.fail = fail
        self.entities: dict[tuple[str, str], dict[str, Any]] = {}
        self.upsert_modes: list[UpdateMode] = []

    def upsert_entity(self, *, entity: dict[str, Any], mode: UpdateMode) -> None:
        if self.fail:
            raise AzureError("azure failure")
        if not isinstance(mode, UpdateMode):
            raise TypeError("mode must be UpdateMode")
        self.upsert_modes.append(mode)
        self.entities[(entity["PartitionKey"], entity["RowKey"])] = dict(entity)

    def get_entity(self, *, partition_key: str, row_key: str) -> dict[str, Any]:
        if self.fail:
            raise AzureError("azure failure")
        try:
            return self.entities[(partition_key, row_key)]
        except KeyError as error:
            raise ResourceNotFoundError("not found") from error


def make_store(
    table_client: FakeTableClient,
    *,
    now: datetime = datetime(2026, 4, 30, 12, 0, tzinfo=UTC),
) -> AzureTableControlEventStateStore:
    return AzureTableControlEventStateStore(
        table_client_factory=lambda: table_client,
        now_factory=lambda: now,
    )


def test_azure_table_control_state_returns_latest_events_in_viewer_order() -> None:
    table_client = FakeTableClient()
    store = make_store(table_client)

    store.update(
        track_number=1,
        event_name="captionAvailability",
        payload={
            "type": "control",
            "event": "captionAvailability",
            "availableCaptionModes": ["fast"],
            "availableLanguages": ["zh-Hant", "en"],
            "updatedAt": "2026-04-30T11:59:30.000Z",
        },
    )
    store.update(
        track_number=1,
        event_name="portalStatus",
        payload={
            "type": "control",
            "event": "portalStatus",
            "status": "online",
            "updatedAt": "2026-04-30T11:59:00.000Z",
        },
    )

    assert table_client.upsert_modes == [UpdateMode.REPLACE, UpdateMode.REPLACE]
    assert store.latest_for_track(1) == [
        {
            "type": "control",
            "event": "portalStatus",
            "status": "online",
            "updatedAt": "2026-04-30T11:59:00.000Z",
        },
        {
            "type": "control",
            "event": "captionAvailability",
            "availableCaptionModes": ["fast"],
            "availableLanguages": ["zh-Hant", "en"],
            "updatedAt": "2026-04-30T11:59:30.000Z",
        },
    ]


def test_azure_table_control_state_replaces_previous_event_for_same_track() -> None:
    store = make_store(FakeTableClient())

    store.update(
        track_number=1,
        event_name="portalStatus",
        payload={
            "type": "control",
            "event": "portalStatus",
            "status": "online",
            "updatedAt": "2026-04-30T11:59:00.000Z",
        },
    )
    store.update(
        track_number=1,
        event_name="portalStatus",
        payload={
            "type": "control",
            "event": "portalStatus",
            "status": "offline",
            "updatedAt": "2026-04-30T12:00:00.000Z",
        },
    )

    assert store.latest_for_track(1) == [
        {
            "type": "control",
            "event": "portalStatus",
            "status": "offline",
            "updatedAt": "2026-04-30T12:00:00.000Z",
        }
    ]


def test_azure_table_control_state_keeps_tracks_separate() -> None:
    store = make_store(FakeTableClient())

    store.update(
        track_number=1,
        event_name="portalStatus",
        payload={
            "type": "control",
            "event": "portalStatus",
            "status": "online",
            "updatedAt": "2026-04-30T11:59:00.000Z",
        },
    )

    assert store.latest_for_track(2) == []


def test_azure_table_control_state_replays_stale_online_as_offline_without_availability() -> None:
    store = make_store(
        FakeTableClient(),
        now=datetime(2026, 4, 30, 12, 2, 1, tzinfo=UTC),
    )

    store.update(
        track_number=1,
        event_name="portalStatus",
        payload={
            "type": "control",
            "event": "portalStatus",
            "status": "online",
            "updatedAt": "2026-04-30T12:00:00.000Z",
        },
    )
    store.update(
        track_number=1,
        event_name="captionAvailability",
        payload={
            "type": "control",
            "event": "captionAvailability",
            "availableCaptionModes": ["fast"],
            "availableLanguages": ["zh-Hant", "en"],
            "updatedAt": "2026-04-30T12:00:00.000Z",
        },
    )

    assert store.latest_for_track(1) == [
        {
            "type": "control",
            "event": "portalStatus",
            "status": "offline",
            "updatedAt": "2026-04-30T12:02:01.000Z",
        }
    ]


def test_azure_table_control_state_omits_availability_when_portal_is_offline() -> None:
    store = make_store(FakeTableClient())

    store.update(
        track_number=1,
        event_name="portalStatus",
        payload={
            "type": "control",
            "event": "portalStatus",
            "status": "offline",
            "updatedAt": "2026-04-30T12:00:00.000Z",
        },
    )
    store.update(
        track_number=1,
        event_name="captionAvailability",
        payload={
            "type": "control",
            "event": "captionAvailability",
            "availableCaptionModes": ["fast"],
            "availableLanguages": ["zh-Hant", "en"],
            "updatedAt": "2026-04-30T12:00:00.000Z",
        },
    )

    assert store.latest_for_track(1) == [
        {
            "type": "control",
            "event": "portalStatus",
            "status": "offline",
            "updatedAt": "2026-04-30T12:00:00.000Z",
        }
    ]


def test_azure_table_control_state_keeps_online_portal_status_with_recent_activity() -> None:
    store = make_store(
        FakeTableClient(),
        now=datetime(2026, 4, 30, 12, 2, 1, tzinfo=UTC),
    )

    store.update(
        track_number=1,
        event_name="portalStatus",
        payload={
            "type": "control",
            "event": "portalStatus",
            "status": "online",
            "updatedAt": "2026-04-30T12:00:00.000Z",
        },
    )
    store.mark_portal_activity(
        track_number=1,
        updated_at="2026-04-30T12:01:30.000Z",
    )

    assert store.latest_for_track(1) == [
        {
            "type": "control",
            "event": "portalStatus",
            "status": "online",
            "updatedAt": "2026-04-30T12:00:00.000Z",
        }
    ]


def test_azure_table_control_state_uses_latest_portal_activity_per_track() -> None:
    store = make_store(
        FakeTableClient(),
        now=datetime(2026, 4, 30, 12, 2, 1, tzinfo=UTC),
    )

    store.update(
        track_number=1,
        event_name="portalStatus",
        payload={
            "type": "control",
            "event": "portalStatus",
            "status": "online",
            "updatedAt": "2026-04-30T12:00:00.000Z",
        },
    )
    store.mark_portal_activity(
        track_number=2,
        updated_at="2026-04-30T12:01:30.000Z",
    )

    assert store.latest_for_track(1) == [
        {
            "type": "control",
            "event": "portalStatus",
            "status": "offline",
            "updatedAt": "2026-04-30T12:02:01.000Z",
        }
    ]


def test_azure_table_control_state_keeps_fresh_online_portal_status() -> None:
    store = make_store(
        FakeTableClient(),
        now=datetime(2026, 4, 30, 12, 1, 29, tzinfo=UTC),
    )

    store.update(
        track_number=1,
        event_name="portalStatus",
        payload={
            "type": "control",
            "event": "portalStatus",
            "status": "online",
            "updatedAt": "2026-04-30T12:00:00.000Z",
        },
    )

    assert store.latest_for_track(1) == [
        {
            "type": "control",
            "event": "portalStatus",
            "status": "online",
            "updatedAt": "2026-04-30T12:00:00.000Z",
        }
    ]


def test_azure_table_control_state_keeps_offline_portal_status_without_ttl() -> None:
    store = make_store(
        FakeTableClient(),
        now=datetime(2026, 4, 30, 12, 10, tzinfo=UTC),
    )

    store.update(
        track_number=1,
        event_name="portalStatus",
        payload={
            "type": "control",
            "event": "portalStatus",
            "status": "offline",
            "updatedAt": "2026-04-30T12:00:00.000Z",
        },
    )

    assert store.latest_for_track(1) == [
        {
            "type": "control",
            "event": "portalStatus",
            "status": "offline",
            "updatedAt": "2026-04-30T12:00:00.000Z",
        }
    ]


def test_azure_table_control_state_omits_online_portal_status_with_invalid_timestamp() -> None:
    store = make_store(FakeTableClient())

    store.update(
        track_number=1,
        event_name="portalStatus",
        payload={
            "type": "control",
            "event": "portalStatus",
            "status": "online",
            "updatedAt": "invalid",
        },
    )

    assert store.latest_for_track(1) == []


def test_azure_table_control_state_allows_custom_portal_online_ttl() -> None:
    table_client = FakeTableClient()
    store = AzureTableControlEventStateStore(
        table_client_factory=lambda: table_client,
        now_factory=lambda: datetime(2026, 4, 30, 12, 2, 1, tzinfo=UTC),
        portal_online_status_ttl=timedelta(minutes=3),
    )

    store.update(
        track_number=1,
        event_name="portalStatus",
        payload={
            "type": "control",
            "event": "portalStatus",
            "status": "online",
            "updatedAt": "2026-04-30T12:00:00.000Z",
        },
    )

    assert store.latest_for_track(1) == [
        {
            "type": "control",
            "event": "portalStatus",
            "status": "online",
            "updatedAt": "2026-04-30T12:00:00.000Z",
        }
    ]


def test_azure_table_control_state_wraps_update_errors() -> None:
    store = make_store(FakeTableClient(fail=True))

    with pytest.raises(RelayControlStateError):
        store.update(
            track_number=1,
            event_name="portalStatus",
            payload={
                "type": "control",
                "event": "portalStatus",
                "status": "online",
                "updatedAt": "2026-04-30T11:59:00.000Z",
            },
        )


def test_azure_table_control_state_wraps_read_errors() -> None:
    store = make_store(FakeTableClient(fail=True))

    with pytest.raises(RelayControlStateError):
        store.latest_for_track(1)


def test_control_state_config_uses_function_storage_table_uri() -> None:
    config = ControlStateConfig.from_environment(
        {
            "AzureWebJobsStorage__tableServiceUri": "https://livecaption.table.core.windows.net/",
        }
    )

    assert config.table_endpoint == "https://livecaption.table.core.windows.net"
    assert config.table_name == "LiveCaptionRelayControlState"


def test_control_state_config_accepts_explicit_table_name() -> None:
    config = ControlStateConfig.from_environment(
        {
            "AzureWebJobsStorage__tableServiceUri": "https://livecaption.table.core.windows.net",
            "RELAY_CONTROL_STATE_TABLE_NAME": "RelayState2",
        }
    )

    assert config.table_name == "RelayState2"


def test_control_state_config_rejects_missing_table_endpoint() -> None:
    with pytest.raises(RelayControlStateError):
        ControlStateConfig.from_environment({})


def test_control_state_config_rejects_invalid_table_name() -> None:
    with pytest.raises(RelayControlStateError):
        ControlStateConfig.from_environment(
            {
                "AzureWebJobsStorage__tableServiceUri": "https://livecaption.table.core.windows.net",
                "RELAY_CONTROL_STATE_TABLE_NAME": "relay-state",
            }
        )
