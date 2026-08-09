# Sync Specification – armband-ios ↔ Pi

## Goal
Reliably move readings collected on the iPhone to the Raspberry Pi (`armband-ai`) so they enter the same SQLite + quality + model pipeline.

## Offline queue behaviour

1. Every reading received from the armband is immediately written locally with `synced = 0`.
2. App periodically checks reachability of the Pi (MQTT broker or HTTP health endpoint).
3. When reachable, batches of unsynced records are sent.
4. On acknowledged success, records are marked `synced = 1` (or deleted).

## Batch format (proposed JSON)

```json
{
  "source": "ios",
  "device_id": "iphone-xxxx",
  "session_id": "optional-uuid",
  "batch_id": "uuid",
  "readings": [
    {
      "ts": "2026-08-09T13:45:12.123Z",
      "hr": 72,
      "spo2": 98,
      "temp_c": 33.4,
      "motion": 0.12,
      "filt940": 1842.5,
      "battery_v": 3.71,
      "quality_flags": 0
    }
  ]
}
```

## Transport options (priority order)

1. **MQTT** – publish to `armband/ios/batch` (preferred if Pi MQTT broker is already running)
2. **HTTP POST** – simple endpoint on Pi (e.g. `/api/v1/ios-batch`)
3. Manual export (CSV/JSON) as fallback

## Conflict / duplicate handling

- Use unique `batch_id` + original timestamp
- Pi side should be idempotent (ignore already-seen timestamps from same source)

## Status reporting

- App shows last successful sync time and number of pending records
- Optional push notification when a large backlog is cleared
