#!/usr/bin/env python3
"""Source-contract check for MQTT credential Settings UI (BGM only).

Credentials must go through KeychainStore.write, never UserDefaults.
"""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CREDS = ROOT / "Sources" / "Store" / "MQTTCredentials.swift"
SETTINGS = ROOT / "Sources" / "Views" / "ContentView.swift"
APP = ROOT / "Sources" / "App" / "ArmbandIOSApp.swift"
TESTS = ROOT / "Tests" / "MQTTCredentialsTests.swift"


def fail(name: str, detail: str) -> int:
    print(name, "FAIL", detail)
    return 1


def ok(name: str, detail: str = "") -> int:
    print(name, "PASS", detail)
    return 0


def main() -> int:
    failures = 0
    creds = CREDS.read_text() if CREDS.exists() else ""
    settings = SETTINGS.read_text()
    app = APP.read_text()
    tests = TESTS.read_text() if TESTS.exists() else ""

    need = (
        "enum MQTTCredentials",
        'usernameAccount = "mqtt_username"',
        'passwordAccount = "mqtt_password"',
        "KeychainStore.write",
        "KeychainStore.delete",
        "KeychainStore.read",
    )
    missing = [s for s in need if s not in creds]
    if missing:
        failures += fail("helper", f"missing {missing}")
    elif "UserDefaults" in creds:
        failures += fail("helper", "MQTTCredentials must not touch UserDefaults")
    else:
        failures += ok("helper", "Keychain read/write/delete only")

    ui_need = (
        "SecureField",
        "MQTTCredentials.save",
        "MQTTCredentials.load",
        "mqtt.updateBroker",
        "Save to Keychain",
    )
    missing_ui = [s for s in ui_need if s not in settings]
    if missing_ui:
        failures += fail("settings ui", f"missing {missing_ui}")
    else:
        failures += ok("settings ui", "SecureField + save to Keychain + updateBroker")

    leaked = []
    if 'forKey: "mqtt_username"' in settings or 'forKey: "mqtt_password"' in settings:
        leaked.append("ContentView UserDefaults mqtt_* keys")
    if "UserDefaults.standard.set" in settings and "mqtt_password" in settings:
        leaked.append("ContentView set mqtt_password")
    if leaked:
        failures += fail("no userdata defaults", str(leaked))
    else:
        failures += ok("no userdata defaults", "Settings does not write mqtt_* to UserDefaults")

    if "KeychainStore.read(account: \"mqtt_username\")" not in app:
        failures += fail("app init", "launch path must still read Keychain")
    else:
        failures += ok("app init", "launch still Keychain-backed")

    needed_tests = (
        "testSaveThenLoadRoundTrips",
        "testEmptyPasswordDeletesKeychainItem",
        "testAccountsAreMqttKeys",
    )
    missing_t = [t for t in needed_tests if t not in tests]
    if missing_t:
        failures += fail("xctest draft", f"missing {missing_t}")
    else:
        failures += ok("xctest draft", "3 cases present (run in Xcode)")

    print("RESULT", "PASS" if failures == 0 else f"FAIL ({failures})")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
