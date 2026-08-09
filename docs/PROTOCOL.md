# Protocol – Current Armband Data Format

Extracted from `armband-ppg-940nm/firmware/Armband_Full.ino` (2026-08).

## MQTT Topic
`armband/ppg`

## JSON Payload (exact fields)

```json
{
  "bpm": 72,          // Heart rate (integer). -1 if no finger / invalid
  "spo2": 98,         // SpO₂ percent (integer). -1 if invalid
  "temp": 33.4,       // Temperature °C (float). -1.0 if not yet valid
  "motion": 10.85,    // Filtered motion magnitude (float)
  "moving": false,    // Boolean – currently above motion threshold
  "raw940": 1842,     // Raw 940 nm ADC average (integer)
  "filt940": 1839.2,  // EMA-filtered 940 nm value (float)
  "batt": 3.71,       // Battery voltage (float)
  "trans": "none",    // "still_to_moving" | "moving_to_still" | "none"
  "conn_ms": 1840,    // WiFi+MQTT connect time this wake (ms)
  "boot": 42          // RTC boot counter (unsigned)
}
```

## Notes for iOS parser

- Treat `bpm == -1` or `spo2 == -1` as “no valid reading”.
- `temp == -1.0` means temperature has not been read yet this wake.
- `moving` is the primary motion flag; `motion` gives the continuous magnitude.
- `filt940` is the preferred 940 nm channel for models / graphs.
- `trans` is useful for logging state changes.

## Recommended approach for the phone

**Hybrid connection strategy:**

1. **Primary (mobile / offline)**: BLE GATT from the XIAO ESP32-C3  
   → Phone stores everything locally and can work anywhere.

2. **Secondary (home / Pi network)**: MQTT client on the phone  
   → Can also subscribe to `armband/ppg` when on the same Wi-Fi as the Pi.

3. **Sync path**: Phone → Pi batch dump (MQTT topic `armband/ios/batch` or HTTP) when the Pi is reachable.

The firmware currently only does MQTT. Adding a simple BLE characteristic that publishes the same JSON (or binary equivalent) is a future firmware enhancement.
