# Armband iOS – BGM Companion App

**Part of the [BGM](https://github.com/Fryrocket/BGM) experimental wearable project.**

iOS companion app for the 940 nm PPG armband (`armband-ppg-940nm`) and Raspberry Pi edge host (`armband-ai`).

## Goals

- **Receive** live or buffered data from the armband (via BLE or MQTT bridge)
- **Store** readings offline on the iPhone when the Pi is unreachable
- **Graph** heart rate, SpO₂, temperature, motion, and experimental 940 nm reflectance
- **Sync / dump** stored data to the Raspberry Pi when connection is restored
- Provide a clean mobile dashboard for calibration sessions and quality monitoring

> ⚠️ Experimental research only. **Not a medical device.** Do not use for treatment decisions.

## Architecture

```
Armband (ESP32-C3)
        │
        │  BLE (preferred for phone)  or  MQTT (via local network / Pi)
        ▼
   iPhone App (this repo)
        │  • Local Core Data / SQLite store
        │  • Charts (Swift Charts)
        │  • Offline queue
        │
        │  When Pi is reachable → MQTT or HTTP dump
        ▼
Raspberry Pi 5 + Hailo (`armband-ai`)
        │
        └── SQLite + quality gates + models + Streamlit
```

## Planned Features (v0.1)

### Core
- [ ] BLE connection to XIAO ESP32-C3 (or MQTT client as fallback)
- [ ] Real-time display of HR, SpO₂, Temp, Motion, 940 nm channel
- [ ] Local persistent storage (Core Data or SQLite) with offline queue
- [ ] Automatic / manual sync to Pi when network is available
- [ ] Swift Charts for live + historical graphs

### Dashboard
- [ ] Live metrics cards
- [ ] Multi-line time-series graphs (HR, SpO₂, 940 nm, motion)
- [ ] Quality indicators (still fraction, clean streak style feedback)
- [ ] Session recording (start/stop calibration sessions)

### Data Management
- [ ] Export CSV / JSON of stored sessions
- [ ] Manual “Dump to Pi” button
- [ ] Background sync when possible
- [ ] Clear local data after successful upload

### Nice-to-haves (later)
- [ ] Apple Watch complication / glanceable HR
- [ ] Notification when armband disconnects or battery is low
- [ ] Simple Libre / fingerstick pairing notes entry
- [ ] Dark mode + large-text accessibility

## Tech Stack (planned)

- **Language**: Swift 5.9+
- **UI**: SwiftUI + Swift Charts
- **Storage**: Core Data or GRDB (SQLite)
- **Networking**: 
  - CoreBluetooth for direct armband connection
  - MQTT (CocoaMQTT or similar) for Pi bridge
- **Minimum iOS**: 17.0 (or 16 if needed)

## Repository Structure (initial)

```
armband-ios/
├── README.md
├── docs/
│   ├── ARCHITECTURE.md
│   ├── BLE_PROTOCOL.md
│   └── SYNC_SPEC.md
├── App/                    (Xcode project will live here later)
└── ...
```

## Related Repos

| Repo | Role |
|------|------|
| [BGM](https://github.com/Fryrocket/BGM) | Umbrella project |
| [armband-ppg-940nm](https://github.com/Fryrocket/armband-ppg-940nm) | ESP32-C3 firmware |
| [armband-ai](https://github.com/Fryrocket/armband-ai) | Pi 5 + Hailo host |

## Status

**2026-08-09** – Repository created. Requirements and architecture being defined.  
No Xcode project committed yet – scaffolding phase.

## License

GNU GPLv3 or later (same family as the rest of BGM).

Experimental personal research project.
