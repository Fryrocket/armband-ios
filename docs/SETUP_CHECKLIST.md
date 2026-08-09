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
- [ ] Set `username` / `password` if your Mosquitto broker requires auth

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

## Quick reference

| Item              | Value / Location                          |
|-------------------|-------------------------------------------|
| Repo              | https://github.com/Fryrocket/armband-ios  |
| MQTT topic (in)   | `armband/ppg`                             |
| MQTT topic (out)  | `armband/ios/batch`                       |
| Setup guide       | `docs/XCODE_SETUP.md`                     |
| Protocol details  | `docs/PROTOCOL.md`                        |

**Experimental only – not a medical device.**
