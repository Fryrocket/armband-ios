# Armband iOS – BGM Companion App

**Part of the [BGM](https://github.com/Fryrocket/BGM) experimental wearable project.**

iOS companion app for the 940 nm PPG armband (`armband-ppg-940nm`) and Raspberry Pi edge host (`armband-ai`).

> ⚠️ Experimental research only. **Not a medical device.** Do not use for treatment decisions.

## Goals

- Receive live or buffered data from the armband
- Show graphs (HR, SpO₂, temperature, motion, 940 nm)
- Store everything offline on the iPhone when the Pi is unreachable
- Dump / sync stored data to the Pi when connection returns
- Support calibration session workflow

## Connection Strategy (decided)

**Hybrid approach:**

1. **Primary (mobile / offline)** → BLE from the XIAO ESP32-C3  
   Phone works anywhere and stores data locally.

2. **Secondary (home network)** → MQTT client that can also subscribe to `armband/ppg`

3. **Sync path** → Phone pushes batches to Pi (`armband/ios/batch` or HTTP) when the Pi is reachable.

The current firmware only speaks MQTT. Adding a matching BLE characteristic is a future firmware task.

## Exact firmware payload (confirmed)

Topic: `armband/ppg`

```json
{
  "bpm": 72,          // -1 = invalid
  "spo2": 98,         // -1 = invalid
  "temp": 33.4,       // -1.0 = not yet valid
  "motion": 10.85,
  "moving": false,
  "raw940": 1842,
  "filt940": 1839.2,
  "batt": 3.71,
  "trans": "none",
  "conn_ms": 1840,
  "boot": 42
}
```

See `docs/PROTOCOL.md` for full details.

## Current scaffolding (2026-08-09)

```
armband-ios/
├── README.md
├── docs/
│   ├── ARCHITECTURE.md
│   ├── PROTOCOL.md          ← exact JSON from firmware
│   ├── SYNC_SPEC.md
│   └── REQUIREMENTS.md
└── Sources/
    ├── Models/
    │   └── Reading.swift    ← data model + JSON parser
    ├── Store/
    │   └── ReadingStore.swift ← offline store + pending queue
    └── Views/
        └── DashboardView.swift ← metric cards + Swift Charts
```

## Next implementation steps

1. Create Xcode project and drop the `Sources` files in
2. Implement MQTT client (or BLE once firmware supports it)
3. Wire `ReadingStore` + `DashboardView`
4. Implement real `SyncEngine` dump to Pi
5. Add session export (CSV/JSON)

## Related Repos

| Repo | Role |
|------|------|
| [BGM](https://github.com/Fryrocket/BGM) | Umbrella |
| [armband-ppg-940nm](https://github.com/Fryrocket/armband-ppg-940nm) | Firmware |
| [armband-ai](https://github.com/Fryrocket/armband-ai) | Pi 5 + Hailo |

## License

GNU GPLv3 or later.
