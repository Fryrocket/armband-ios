# BGM iOS App – Requirements & Feature List
**Date**: 2026-08-09
**Repo**: https://github.com/Fryrocket/armband-ios

## Primary Goals
1. Read data from the 940 nm PPG armband (BLE preferred)
2. Display live graphs and metrics on iPhone
3. Store all readings locally when the Pi is offline
4. Dump / sync stored data to the Raspberry Pi when connection becomes available
5. Support calibration session workflow

## Must-have (v0.1)
- [ ] Connect to armband via BLE
- [ ] Parse and display: Heart Rate, SpO₂, Temperature, Motion, 940 nm value, Battery
- [ ] Live multi-series graphs (Swift Charts)
- [ ] Offline storage of every reading
- [ ] Manual “Sync / Dump to Pi” button
- [ ] Automatic background sync when Pi is reachable
- [ ] Session start / stop (for calibration collection)
- [ ] Show pending (unsynced) record count
- [ ] Basic connection status (connected / disconnected / syncing)

## Should-have (v0.2)
- [ ] Export session as CSV or JSON
- [ ] Quality indicators (still / motion, simple score)
- [ ] Low battery warning from armband
- [ ] Dark mode + Dynamic Type support
- [ ] Remember last connected armband

## Nice-to-have (later)
- [ ] Apple Watch support
- [ ] Enter Libre / fingerstick reference values in-app
- [ ] Push notifications for disconnect or large backlog cleared
- [ ] Simple historical day/week view

## Technical Constraints
- Offline-first design
- No cloud backend in v1
- Data stays on user’s devices (phone + personal Pi)
- Compatible with existing MQTT JSON format used by armband-ai as much as possible

## Related
- Firmware: armband-ppg-940nm
- Pi host: armband-ai
- Umbrella: BGM
