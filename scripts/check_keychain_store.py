#!/usr/bin/env python3
"""Source-contract check for MQTT credentials in Keychain (BGM only).

This Mac has Command Line Tools only (Foundation/Security will not compile),
so XCTest in Tests/KeychainStoreTests.swift is for Fry's Xcode target.
This script verifies the Swift sources match the landed contract.
"""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "Sources" / "App" / "ArmbandIOSApp.swift"
STORE = ROOT / "Sources" / "Store" / "KeychainStore.swift"
TESTS = ROOT / "Tests" / "KeychainStoreTests.swift"


def fail(name: str, detail: str) -> int:
    print(name, "FAIL", detail)
    return 1


def ok(name: str, detail: str = "") -> int:
    print(name, "PASS", detail)
    return 0


def main() -> int:
    failures = 0
    app = APP.read_text()
    store = STORE.read_text()
    tests = TESTS.read_text() if TESTS.exists() else ""

    required_store = (
        "enum KeychainStore",
        "kSecClassGenericPassword",
        "kSecAttrAccessibleAfterFirstUnlock",
        "SecItemCopyMatching",
        "SecItemAdd",
        "SecItemUpdate",
        "SecItemDelete",
        "static func read(account: String)",
        "static func write(account: String, value: String)",
        "static func delete(account: String)",
        "static func migrateLegacyUserDefaults",
        '"mqtt_username"',
        '"mqtt_password"',
    )
    missing = [s for s in required_store if s not in store]
    if missing:
        failures += fail("keychain helper", f"missing {missing}")
    else:
        failures += ok("keychain helper", "generic-password + AfterFirstUnlock")

    if "defaults.string(forKey: \"mqtt_username\")" in app or "defaults.string(forKey: \"mqtt_password\")" in app:
        failures += fail("app init", "still reads mqtt credentials from UserDefaults")
    elif "KeychainStore.migrateLegacyUserDefaults" not in app:
        failures += fail("app init", "missing migrateLegacyUserDefaults call")
    elif 'KeychainStore.read(account: "mqtt_username")' not in app:
        failures += fail("app init", "mqtt_username not read from Keychain")
    elif 'KeychainStore.read(account: "mqtt_password")' not in app:
        failures += fail("app init", "mqtt_password not read from Keychain")
    else:
        failures += ok("app init", "migrate then Keychain read")

    # Migration must not drop plaintext until Keychain write succeeds.
    if "defaults.removeObject(forKey: account)" not in store:
        failures += fail("migrate safety", "does not remove UserDefaults keys")
    elif "if write(account: account, value: legacy)" not in store:
        failures += fail("migrate safety", "removes UserDefaults without successful write")
    else:
        failures += ok("migrate safety", "remove UserDefaults only after write")

    leaked = []
    for path in (ROOT / "Sources").rglob("*.swift"):
        if path.name == "KeychainStore.swift":
            continue
        text = path.read_text()
        if 'forKey: "mqtt_username"' in text or 'forKey: "mqtt_password"' in text:
            leaked.append(str(path.relative_to(ROOT)))
        if "UserDefaults.standard.set" in text and "mqtt_password" in text:
            leaked.append(str(path.relative_to(ROOT)))
    if leaked:
        failures += fail("no plaintext writes", f"{leaked}")
    else:
        failures += ok("no plaintext writes", "Sources no longer set mqtt_* in UserDefaults")

    needed_tests = (
        "testWriteThenReadRoundTrips",
        "testWriteTwiceUpdatesInPlace",
        "testDeleteRemovesValue",
        "testDeleteOfMissingKeyIsNotAnError",
    )
    missing_t = [t for t in needed_tests if t not in tests]
    if missing_t:
        failures += fail("xctest draft", f"missing {missing_t}")
    else:
        failures += ok("xctest draft", "4 cases present (run in Xcode)")

    print("RESULT", "PASS" if failures == 0 else f"FAIL ({failures})")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
