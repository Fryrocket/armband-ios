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
//    xcodebuild build -scheme ArmbandIOS \        # iOS: full compile, incl. CocoaMQTT
//      -destination 'platform=iOS Simulator,name=iPhone 17'
//    xcodebuild test  -scheme ArmbandIOS ...      # iOS: 7/14 (see below)
//
//  The 7 Keychain-touching tests FAIL under `xcodebuild test` on iOS: a bare
//  SwiftPM xctest bundle has no host app, so SecItemAdd returns
//  errSecMissingEntitlement (-34018). Run them on the macOS host (`swift test`),
//  or add an iOS test-host app target (a generated .xcodeproj) for a full
//  on-device run. Not a code defect.
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
