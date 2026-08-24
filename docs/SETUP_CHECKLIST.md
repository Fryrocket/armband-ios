# BGM Armband iOS – Setup Checklist

Use this list to go from zero to a running app on your iPhone.

---

## A. Prerequisites

- [ ] Mac with Xcode 15+ installed (iOS 17 SDK or newer)
- [ ] Apple ID added in Xcode (Signing & Capabilities)
- [ ] iPhone (or Simulator) ready
- [ ] Raspberry Pi running Mosquitto (or other MQTT broker) and reachable on local network
- [ ] Know your Pi IP address (e.g. `192.168.1.100`)
- [ ] Armband firmware publishing to topic `armband/ppg` (already working)

---

## B. Create the Xcode project

- [ ] Open Xcode → **File → New → Project**
- [ ] Choose **iOS → App**
- [ ] Product Name: `ArmbandIOS`
- [ ] Interface: **SwiftUI**
- [ ] Language: **Swift**
- [ ] Save the project (e.g. `~/Developer/ArmbandIOS`)

---

## C. Add source code from the repo

- [ ] Clone the repo (if not already):
  ```bash
  git clone https://github.com/Fryrocket/armband-ios.git
  ```
- [ ] In Xcode: right-click project navigator → **Add Files to "ArmbandIOS"…**
- [ ] Select the entire **`Sources`** folder
- [ ] Options: ✅ Copy items if needed · ✅ Create groups · Target: ArmbandIOS
- [ ] Delete the default `ContentView.swift` and `*App.swift` that Xcode generated

---

## D. Add CocoaMQTT package

- [ ] **File → Add Package Dependencies…**
- [ ] URL: `https://github.com/emqx/CocoaMQTT`
- [ ] Dependency Rule: Up to Next Major Version
- [ ] Add to target **ArmbandIOS**

---

## E. Local network permission (Info.plist)

- [ ] Open the target’s **Info** tab (or Info.plist)
- [ ] Add:
  - `Privacy - Local Network Usage Description`  
    Value: `ArmbandIOS needs local network access to talk to the Raspberry Pi and armband.`
  - `Bonjour services` → Item 0: `_mqtt._tcp`

---

## F. Configure Pi connection

- [ ] Open `Sources/App/ArmbandIOSApp.swift`
- [ ] Change the host IP to your real Pi address:
  ```swift
  host: "192.168.x.x"   // ← your Pi IP
  ```
- [ ] If Mosquitto requires auth, write credentials with `KeychainStore.write(account:value:)` (`mqtt_username` / `mqtt_password`). Do not store them in UserDefaults.

---

## G. Build & first run

- [ ] Select your iPhone (or Simulator) as the run destination
- [ ] Product → **Run** (⌘R)
- [ ] On the **Settings** tab confirm MQTT shows Connected (green)
- [ ] When the armband publishes, readings should appear on the **Live** tab
- [ ] Confirm pending count increases and “Dump to Pi” works when connected

---

## H. Optional next improvements

- [ ] Enable Background Modes later (Background fetch / processing)
- [ ] Add CSV / JSON export of sessions
- [ ] Implement real BLE once firmware supports it
- [ ] Add Apple Watch target (future)

---

## I. Troubleshooting

### Build / Xcode issues

| Problem | What to try |
|---------|-------------|
| **Duplicate `ContentView` / `App` symbols** | Delete the default files Xcode created. Keep only the ones from `Sources/`. |
| **“No such module CocoaMQTT”** | File → Packages → Reset Package Caches, then resolve again. Confirm the package is added to the **ArmbandIOS** target. |
| **Signing errors** | Select your Team under Signing & Capabilities. Use your personal Apple ID if you don’t have a paid team. |
| **Files not compiling** | Make sure every `.swift` file is checked under Target Membership for ArmbandIOS. |

### MQTT connection issues

| Problem | What to try |
|---------|-------------|
| **Stays Disconnected (red)** | 1. Confirm Pi IP is correct and reachable (`ping 192.168.x.x` from Mac).<br>2. Confirm Mosquitto is running on the Pi: `sudo systemctl status mosquitto`.<br>3. Check username/password match the broker config.<br>4. On first launch, iOS will ask for Local Network permission — accept it.<br>5. Simulator sometimes has flaky local network; prefer a real iPhone. |
| **“CocoaMQTT package not added yet”** | The `#if canImport(CocoaMQTT)` stub is active. Add the package (step D) and clean build. |
| **Connected but no readings** | 1. Confirm armband is publishing: on Pi run `mosquitto_sub -t armband/ppg -v`.<br>2. Check topic is exactly `armband/ppg`.<br>3. Look at Settings → last error / last message. |
| **Permission denied / Local Network** | Delete the app from the phone, reinstall, and accept the Local Network prompt. Also verify Info.plist keys from step E. |

### Data / UI issues

| Problem | What to try |
|---------|-------------|
| **Readings appear then disappear after restart** | Offline store writes to the app’s Documents folder. If you deleted the app, data is gone. Otherwise check that `ReadingStore.save()` is not failing (Xcode console). |
| **Pending count never drops** | MQTT must be connected for “Dump to Pi” to mark records synced. Check Settings → connection status. |
| **Charts empty** | Need at least a few readings with valid `bpm` / `filt940`. Trigger the armband (finger on sensor or motion wake). |
| **Dump to Pi does nothing** | Pending count must be > 0 and MQTT connected. Watch Xcode console for the batch JSON printout. |

### Network / Pi side quick checks

```bash
# On the Pi
ping -c 3 <phone-or-mac-ip>          # can the Pi see the phone network?
sudo systemctl status mosquitto      # broker running?
mosquitto_sub -t 'armband/#' -v      # see all armband traffic
```

```bash
# From Mac (same network)
ping 192.168.x.x                     # Pi reachable?
nc -vz 192.168.x.x 1883              # MQTT port open?
```

### Still stuck?

1. Clean Build Folder in Xcode (Shift⌘K) then rebuild.
2. Check the Xcode console for MQTT / JSON parse errors.
3. Verify the exact payload with `docs/PROTOCOL.md`.
4. Open an issue or note the console output for next debugging session.

---

## Quick reference

| Item              | Value / Location                          |
|-------------------|-------------------------------------------|
| Repo              | https://github.com/Fryrocket/armband-ios  |
| MQTT topic (in)   | `armband/ppg`                             |
| MQTT topic (out)  | `armband/ios/batch`                       |
| Setup guide       | `docs/XCODE_SETUP.md`                     |
| Protocol details  | `docs/PROTOCOL.md`                        |

**Experimental only – not a medical device.**
