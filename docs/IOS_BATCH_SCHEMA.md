# BGM iOS Phase 3 — batch payload schema

Orca ≠ BGM. This file is BGM only.

Pin: `Fryrocket/armband-ios` @ `c4af287837318ad15babf4d0bd31b7933be6493d`
Ingest: `Fryrocket/armband-ai` `src/armband_ai/logger.py` `_handle_ios_batch` @ `c7578e5`

Startup blocker is gone. Raw SyncEngine:
https://raw.githubusercontent.com/Fryrocket/armband-ios/c4af287837318ad15babf4d0bd31b7933be6493d/Sources/Store/SyncEngine.swift

## MQTT

| Direction | Topic | QoS |
|-----------|-------|-----|
| Phone → Pi | `armband/ios/batch` | 1 |
| Pi → phone | `armband/ios/batch/ack` | 1 |
| Firmware live | `armband/ppg` | 0 (phone subscribe; no RTC on firmware) |

Default broker in `MQTTClient`: `192.168.1.100:1883`. Mock locally with `localhost:1883`.

## Batch JSON (phone publish)

Top-level (always):

| Field | Type | Notes |
|-------|------|--------|
| `source` | string | `"ios"` |
| `device_id` | string | `DeviceIdentity.current` |
| `batch_id` | string | UUID, used as ACK key |
| `count` | int | `readings.count` (pre-halve if oversized) |
| `readings` | array | see below |
| `session_id` | string UUID, optional | `store.currentSessionId` if a session is open |
| `subject_id` | string, optional | Closed enum `SUBJ_A` / `SUBJ_B`. Omitted when unset. |

Per reading (always):

| Field | Type | Source |
|-------|------|--------|
| `id` | UUID string | phone UUID → Pi `source_id` / row `id` |
| `ts` | ISO-8601 fractional | `yyyy-MM-ddTHH:mm:ss.SSSXXXXX` |
| `motion` | number | |
| `moving` | bool | |
| `raw940` | int | |
| `filt940` | number | |
| `batt` | number | battery volts |
| `trans` | string | default `"none"` |

Per reading (omitted if nil):

| Field | Type |
|-------|------|
| `bpm` | int |
| `spo2` | int |
| `temp` | number |
| `session_id` | UUID string |
| `subject_id` | `SUBJ_A` / `SUBJ_B` |

Size guard: if serialized payload > 32768 bytes and batch has >1 reading, phone halves and retries. Single-reading oversize fails honestly.

## ACK JSON (Pi publish)

```json
{"batch_id":"...","status":"ok","count":N,"inserted":n,"duplicates":d}
```

Phone success: `inserted + duplicates >= ids.count`. Missing `duplicates` treated as 0. Non-ok `status` uses `error` or `message`.

## Session minting (DashboardView)

- `Start Session` → `store.startSession()` mints `currentSessionId = UUID()`
- `Stop Session` → `currentSessionId = nil`
- `add(_:)` stamps `reading.sessionId` from current session if unset
- Dump is a **separate** button (`Dump to Pi` / `Cancel`). Start Session does not auto-dump.

## Ingest match (`logger.py`)

Pi prefers **per-reading** `session_id`, falls back to batch-level. Maps phone fields 1:1 (`bpm/spo2/temp/motion/moving/raw940/filt940/batt/trans/ts/id`) plus `source`, `batch_id`, `device_id`. Idempotent insert via `source_id`. **Matches.** `connectMs` / `bootCount` live on firmware PPG path only, not on iOS dump. Optional `subject_id` is on the wire; ingest does not yet copy it into a first-class column (session→subject map still used for fits).

## Dashboard / live path

`DashboardView` binds `ReadingStore` + `SyncEngine`. Live MQTT PPG is not wired in this view file; Dump uses MQTT only if `MQTTClient.isConnected`. Offline testing needs a mock broker **and** a connected MQTTClient (or a test double).

Run offline ACK mock: `python3 scripts/mock_ios_batch.py`
