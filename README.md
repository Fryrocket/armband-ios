# Armband iOS – BGM Companion App

**Part of the [BGM](https://github.com/Fryrocket/BGM) experimental wearable project.**

iOS companion app for the 940 nm PPG armband and Raspberry Pi edge host.

> ⚠️ Experimental research only. **Not a medical device.**

## What works right now (scaffolding)

| Feature | Status |
|---------|--------|
| Exact firmware JSON parser | ✅ Done |
| Offline storage + pending queue | ✅ Done |
| Live metric cards + Swift Charts | ✅ Done |
| MQTT client skeleton (CocoaMQTT) | ✅ Done |
| Dump-to-Pi batch engine | ✅ Done |
| Settings + connection status | ✅ Done |
| Session start/stop | ✅ Done |
| Xcode setup guide | ✅ Done |
| Real BLE | ⏳ Future (needs firmware support) |
| Background sync | ⏳ Next |

## Quick start

1. Follow **[docs/XCODE_SETUP.md](docs/XCODE_SETUP.md)** – creates the Xcode project and wires everything.
2. Change the Pi IP in `Sources/App/ArmbandIOSApp.swift`.
3. Add the CocoaMQTT package.
4. Run on your iPhone.

## Repository layout

```
armband-ios/
├── README.md
├── docs/
│   ├── XCODE_SETUP.md      ← start here
│   ├── PROTOCOL.md         ← exact armband JSON
│   ├── ARCHITECTURE.md
│   ├── SYNC_SPEC.md
│   └── REQUIREMENTS.md
└── Sources/
    ├── App/
    │   └── ArmbandIOSApp.swift
    ├── Models/
    │   └── Reading.swift
    ├── Store/
    │   ├── ReadingStore.swift
    │   └── SyncEngine.swift
    ├── Networking/
    │   └── MQTTClient.swift
    └── Views/
        ├── ContentView.swift
        └── DashboardView.swift
```

## Connection strategy

- **Primary (mobile)**: BLE (future – needs firmware change)
- **Secondary (home)**: MQTT → subscribe to `armband/ppg`
- **Sync**: Phone → Pi batch dump on topic `armband/ios/batch`

## Related repos

- [BGM](https://github.com/Fryrocket/BGM) – umbrella
- [armband-ppg-940nm](https://github.com/Fryrocket/armband-ppg-940nm) – firmware
- [armband-ai](https://github.com/Fryrocket/armband-ai) – Pi + Hailo

## License

GNU GPLv3 or later.
