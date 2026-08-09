# Architecture – armband-ios

## High-level data flow

1. **Armband → Phone**
   - Preferred: BLE GATT characteristics from XIAO ESP32-C3
   - Fallback: MQTT over local Wi-Fi (phone joins same network as Pi or uses a bridge)

2. **Phone local storage**
   - Every reading is written to a local SQLite / Core Data store immediately
   - Readings are marked `synced = false` until successfully delivered to the Pi

3. **Phone → Pi sync**
   - When network to Pi is available, background or manual “Dump” pushes unsynced batches
   - Protocol options (to be decided):
     - MQTT publish to a dedicated topic (e.g. `armband/ios/batch`)
     - Simple HTTP POST endpoint on the Pi
   - On success, mark records as synced (or delete after confirmed write)

4. **Pi side**
   - Existing `armband-ai` logger already accepts MQTT JSON from the armband
   - We will extend it to also accept batches from the iOS app without breaking the current pipeline

## Offline-first design

- App never requires the Pi to be online to record data
- Graphing and session management work entirely offline
- Sync is opportunistic

## Key modules (planned)

| Module              | Responsibility                              |
|---------------------|---------------------------------------------|
| `BluetoothManager`  | CoreBluetooth scanning, connection, parsing |
| `MQTTClient`        | Optional MQTT bridge / Pi communication     |
| `ReadingStore`      | Local persistence + sync queue              |
| `SyncEngine`        | Detect connectivity + push batches          |
| `DashboardView`     | Live metrics + charts                       |
| `SessionManager`    | Start/stop calibration sessions             |

## Security / privacy notes

- All data stays on-device or on the user’s own Pi
- No cloud backend planned for v1
- BLE pairing should be explicit
