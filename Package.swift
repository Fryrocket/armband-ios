// swift-tools-version: 5.10
//
//  Package.swift
//  ArmbandIOS
//
//  SwiftPM manifest so the app logic builds and its tests run without a
//  hand-made .xcodeproj:
//
//    swift build     # host (macOS): every source file incl. CocoaMQTT + views
//    swift test      # host (macOS): 14/14 — Keychain / creds / host / subject
//
//  For a full iOS run (SwiftUI on device + Keychain tests, which need a host
//  app — a bare SwiftPM xctest bundle has no keychain entitlement on iOS and
//  SecItemAdd returns errSecMissingEntitlement / -34018), use the checked-in
//  Xcode project instead:
//
//    xcodebuild test -project ArmbandIOS.xcodeproj -scheme ArmbandIOS \
//      -destination 'platform=iOS Simulator,name=iPhone 17'   # 14/14
//
//  The SwiftUI entry point (Sources/App/ArmbandIOSApp.swift) is excluded:
//  a library target cannot carry `@main`. Add that file to the App target
//  when you create the real iOS app in Xcode (see docs/XCODE_SETUP.md).
//
import PackageDescription

let package = Package(
    name: "ArmbandIOS",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "ArmbandIOS", targets: ["ArmbandIOS"]),
    ],
    dependencies: [
        .package(url: "https://github.com/emqx/CocoaMQTT", from: "2.1.0"),
    ],
    targets: [
        .target(
            name: "ArmbandIOS",
            dependencies: [
                // CocoaMQTT builds for both macOS and iOS, so MQTTClient's real
                // `#if canImport(CocoaMQTT)` path is compile-checked on the host
                // too. No test touches the live socket.
                .product(name: "CocoaMQTT", package: "CocoaMQTT"),
            ],
            path: "Sources",
            exclude: ["App"]
        ),
        .testTarget(
            name: "ArmbandIOSTests",
            dependencies: ["ArmbandIOS"],
            path: "Tests"
        ),
    ]
)
