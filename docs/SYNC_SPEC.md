# Sync Specification – armband-ios ↔ Pi

## Goal
Reliably move readings collected on the iPhone to the Raspberry Pi (`armband-ai`) so they enter the same SQLite + quality + model pipeline.

## Offline queue behaviour

1. Every reading received from the armband is immediately written locally with `synced = 0`.
2. App periodically checks reachability of the Pi (MQTT broker).
3. When reachable, batches of unsynced records (limit 300) are sent.
4. On acknowledged success (every id accounted for), records are marked `synced = 1`.

## Batch publish (iOS → Pi)

Topic: `armband/ios/batch`

```json
{
  "source": "ios",
  "device_id": "<stable DeviceIdentity>",
  "batch_id": "<uuid>",
  "count": 300,
  "session_id": "optional-uuid",
  "readings": [
    {
      "id": "<uuid>",
      "ts": "2026-08-09T13:45:12.123Z",
      "motion": 0.12,
      "moving": false,
      "raw940": 1842,
      "filt940": 1842.5,
      "batt": 3.71,
      "trans": "...",
      "bpm": 72,
      "spo2": 98,
      "temp": 33.4
    }
  ]
}
```

## Batch ACK (Pi → iOS)  — Fix Pack 2

Topic: `armband/ios/batch/ack`

```json
{
  "batch_id": "...",
  "status": "ok",
  "count": 300,
  "inserted": 120,
  "duplicates": 180
}
```

- `inserted` = rows the Pi actually wrote this call
- `duplicates` (alias `ignored`) = rows already present (INSERT OR IGNORE)
- Success condition on phone: `inserted + duplicates >= count`
- Missing `duplicates` field is treated as 0 (pre-fix behaviour)
- Non-ok status or partial accounting keeps the batch pending

## Transport

1. **MQTT** – publish to `armband/ios/batch` (current)
2. Future: BLE + bluetooth-central for true offline path across app suspension

## Failure / cancel semantics (Fix Pack 2)

- Publish failure or disconnect → fail-fast, data kept pending, no 15 s stall
- User cancel / intentional disconnect (nil reason) → silent settle, no red UI
- Unexpected disconnect → one error surfaced
- Late ACK after timeout is ignored; re-send path settles cleanly once duplicates are reported
- Repeated partial on the same head id surfaces "Sync wedged" naming the missing ACK field

## Status reporting

- App shows last successful sync time, last batch count, pending count, and lastError
