#!/usr/bin/env python3
"""Source-contract: MQTT broker host Settings field (BGM only).

Host is not a secret — UserDefaults `mqtt_host`. Credentials stay Keychain.
"""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HOST = ROOT / "Sources" / "Store" / "MQTTHost.swift"
SETTINGS = ROOT / "Sources" / "Views" / "ContentView.swift"
APP = ROOT / "Sources" / "App" / "ArmbandIOSApp.swift"
TESTS = ROOT / "Tests" / "MQTTHostTests.swift"
CREDS = ROOT / "Sources" / "Store" / "MQTTCredentials.swift"


def fail(name: str, detail: str) -> int:
    print(name, "FAIL", detail)
    return 1


def ok(name: str, detail: str = "") -> int:
    print(name, "PASS", detail)
    return 0


def main() -> int:
    failures = 0
    host = HOST.read_text() if HOST.exists() else ""
    settings = SETTINGS.read_text()
    app = APP.read_text()
    tests = TESTS.read_text() if TESTS.exists() else ""
    creds = CREDS.read_text() if CREDS.exists() else ""

    need = (
        "enum MQTTHost",
        'defaultsKey = "mqtt_host"',
        'fallback = "192.168.1.100"',
        "UserDefaults",
    )
    missing = [s for s in need if s not in host]
    if missing:
        failures += fail("helper", f"missing {missing}")
    elif "KeychainStore" in host:
        failures += fail("helper", "host must not use Keychain")
    else:
        failures += ok("helper", "UserDefaults mqtt_host + fallback")

    if 'TextField("Broker host"' not in settings and "TextField(\"Broker host\"" not in settings:
        failures += fail("settings ui", "no Broker host field")
    elif "MQTTHost.save" not in settings or "MQTTHost.load" not in settings:
        failures += fail("settings ui", "does not call MQTTHost.save/load")
    elif "Save host" not in settings:
        failures += fail("settings ui", "no Save host button")
    else:
        failures += ok("settings ui", "Broker host field + Save host")

    if "MQTTHost.load" not in app:
        failures += fail("app init", "launch must load MQTTHost")
    elif 'defaults.string(forKey: "mqtt_host")' in app:
        failures += fail("app init", "still reads mqtt_host inline instead of MQTTHost.load")
    else:
        failures += ok("app init", "launch uses MQTTHost.load")

    if "UserDefaults" in creds:
        failures += fail("creds split", "MQTTCredentials must stay Keychain-only")
    else:
        failures += ok("creds split", "credentials still Keychain-only")

    needed_tests = (
        "testLoadFallsBackWhenMissing",
        "testSaveRoundTrips",
        "testEmptySaveUsesFallback",
        "testDefaultsKey",
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
