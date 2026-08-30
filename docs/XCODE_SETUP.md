# Xcode Setup Guide – Armband iOS

> **The repo now ships `ArmbandIOS.xcodeproj`.** Just open it:
> `open ArmbandIOS.xcodeproj`, pick a simulator, ⌘R. CocoaMQTT resolves via
> SPM automatically; the local-network Info.plist keys and the XCTest host
> app are already wired. `xcodebuild test -project ArmbandIOS.xcodeproj
> -scheme ArmbandIOS -destination 'platform=iOS Simulator,name=iPhone 17'`
> → 14/14.
>
> The manual steps below are kept only as a reference for rebuilding the
> project from scratch or adding it to a larger workspace.

## 1. Create the Xcode project

1. Open **Xcode**
2. File → New → Project
3. Choose **iOS → App**
4. Settings:
   - Product Name: `ArmbandIOS`
   - Team: your Apple ID / team
   - Organization Identifier: `com.fryrocket` (or your own)
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Storage: None (we use our own store)
5. Save it somewhere convenient (e.g. `~/Developer/ArmbandIOS`)

## 2. Add the source files from this repo

1. Clone or download this repository:
   ```bash
   git clone https://github.com/Fryrocket/armband-ios.git
   ```
2. In Xcode, right-click the project navigator → **Add Files to "ArmbandIOS"…**
3. Select the entire `Sources` folder from the cloned repo
4. Options:
   - ✅ Copy items if needed
   - ✅ Create groups
   - Add to target: ArmbandIOS
5. Delete the default `ContentView.swift` and `ArmbandIOSApp.swift` that Xcode generated (we already have our own versions).

## 3. Add CocoaMQTT package

1. In Xcode: File → Add Package Dependencies…
2. Paste: `https://github.com/emqx/CocoaMQTT`
3. Dependency Rule: Up to Next Major Version
4. Add the package to the ArmbandIOS target

## 4. Configure Info.plist (local network)

Because we talk to a local Pi, add this key to Info.plist (or the target’s Info tab):

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>ArmbandIOS needs local network access to talk to the Raspberry Pi and armband.</string>
<key>NSBonjourServices</key>
<array>
  <string>_mqtt._tcp</string>
</array>
```

## 5. Set your Pi IP

Open `Sources/App/ArmbandIOSApp.swift` and change:

```swift
host: "192.168.1.100"   // ← put your real Pi IP here
```

MQTT username/password live in the Keychain (`KeychainStore`). Call `KeychainStore.write(account:value:)` with `mqtt_username` / `mqtt_password` — do not put them in UserDefaults. Any leftover plaintext keys are migrated on launch.

## 6. Build & Run

1. Select a real iPhone (or Simulator)
2. Product → Run (⌘R)
3. On the Settings tab you should see MQTT connection status
4. When the armband publishes to `armband/ppg`, readings should appear on the Live tab and be stored offline

## 7. Optional – enable Background Modes later

For background sync you can later enable:
- Background fetch
- Background processing

---

That’s it. The core offline store, dashboard, and MQTT path are ready to extend.
