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
| Xcode setup guide + **checklist** | ✅ Done |
| Real BLE | ⏳ Future (needs firmware support) |
| Background sync | ⏳ Next |

## Quick start

1. Follow the **[Setup Checklist](docs/SETUP_CHECKLIST.md)** (or the longer [XCODE_SETUP.md](docs/XCODE_SETUP.md))
2. Change the Pi IP in `Sources/App/ArmbandIOSApp.swift`
3. Add the CocoaMQTT package
4. Run on your iPhone

## Repository layout

```
armband-ios/
├── README.md
├── docs/
│   ├── SETUP_CHECKLIST.md  ← start here (checkbox list)
│   ├── XCODE_SETUP.md
│   ├── PROTOCOL.md
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
    │   ├── SyncEngine.swift
    │   ├── DeviceIdentity.swift
    │   └── KeychainStore.swift
    ├── Networking/
    │   └── MQTTClient.swift
    └── Views/
        ├── ContentView.swift
        └── DashboardView.swift
```

## File index

**Sources**
- [Sources/App/ArmbandIOSApp.swift](Sources/App/ArmbandIOSApp.swift) — app entry, dependency wiring, scene-phase flush
- [Sources/Models/Reading.swift](Sources/Models/Reading.swift) — data model + firmware JSON parser
- [Sources/Models/SubjectID.swift](Sources/Models/SubjectID.swift)
- [Sources/Networking/MQTTClient.swift](Sources/Networking/MQTTClient.swift) — CocoaMQTT wrapper, delegate proxy
- [Sources/Store/DeviceIdentity.swift](Sources/Store/DeviceIdentity.swift) — stable per-install device id
- [Sources/Store/KeychainStore.swift](Sources/Store/KeychainStore.swift)
- [Sources/Store/ReadingStore.swift](Sources/Store/ReadingStore.swift) — offline store, debounced saves, pending queue
- [Sources/Store/SyncEngine.swift](Sources/Store/SyncEngine.swift) — batch dump, ACK handling, cancellation
- [Sources/Views/ContentView.swift](Sources/Views/ContentView.swift) — tab shell + settings
- [Sources/Views/DashboardView.swift](Sources/Views/DashboardView.swift) — metric cards + Swift Charts

**Docs**
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- [docs/IOS_BATCH_SCHEMA.md](docs/IOS_BATCH_SCHEMA.md)
- [docs/PROTOCOL.md](docs/PROTOCOL.md) — firmware JSON payload
- [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)
- [docs/SETUP_CHECKLIST.md](docs/SETUP_CHECKLIST.md) — start here
- [docs/SYNC_SPEC.md](docs/SYNC_SPEC.md) — batch + ACK contract
- [docs/XCODE_SETUP.md](docs/XCODE_SETUP.md)

**Scripts**
- [scripts/check_keychain_store.py](scripts/check_keychain_store.py)
- [scripts/check_subject_picker.py](scripts/check_subject_picker.py)
- [scripts/generate_changelog.py](scripts/generate_changelog.py)
- [scripts/mock_ios_batch.py](scripts/mock_ios_batch.py)
- [scripts/update_file_index.py](scripts/update_file_index.py)

**Config**
- [LICENSE](LICENSE)

**Other**
- [Tests/KeychainStoreTests.swift](Tests/KeychainStoreTests.swift)
- [Tests/SubjectIDTests.swift](Tests/SubjectIDTests.swift)

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
