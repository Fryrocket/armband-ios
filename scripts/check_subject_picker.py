#!/usr/bin/env python3
"""Source-contract check for iOS Subject_ID picker (BGM only).

This Mac has Command Line Tools only (Foundation/SwiftUI will not compile),
so XCTest in Tests/SubjectIDTests.swift is for Fry's Xcode target.
This script verifies the Swift sources match the landed contract.
"""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SUBJECT = ROOT / "Sources" / "Models" / "SubjectID.swift"
READING = ROOT / "Sources" / "Models" / "Reading.swift"
STORE = ROOT / "Sources" / "Store" / "ReadingStore.swift"
SYNC = ROOT / "Sources" / "Store" / "SyncEngine.swift"
SETTINGS = ROOT / "Sources" / "Views" / "ContentView.swift"
DASH = ROOT / "Sources" / "Views" / "DashboardView.swift"
TESTS = ROOT / "Tests" / "SubjectIDTests.swift"


def fail(name: str, detail: str) -> int:
    print(name, "FAIL", detail)
    return 1


def ok(name: str, detail: str = "") -> int:
    print(name, "PASS", detail)
    return 0


def main() -> int:
    failures = 0
    subject = SUBJECT.read_text()
    reading = READING.read_text()
    store = STORE.read_text()
    sync = SYNC.read_text()
    settings = SETTINGS.read_text()
    dash = DASH.read_text()
    tests = TESTS.read_text() if TESTS.exists() else ""

    missing_enum = [
        s
        for s in (
            "enum SubjectID",
            'case subjA = "SUBJ_A"',
            'case subjB = "SUBJ_B"',
            'static let defaultsKey = "subject_id"',
            "static func parse(_ raw: String?)",
        )
        if s not in subject
    ]
    if missing_enum:
        failures += fail("subject enum", f"missing {missing_enum}")
    elif "SUBJ_C" in subject:
        failures += fail("subject enum", "unexpected SUBJ_C — enum is the n=2 pilot")
    else:
        failures += ok("subject enum", "SUBJ_A / SUBJ_B closed set")

    if "var subjectId: String?" not in reading:
        failures += fail("reading model", "missing optional subjectId")
    elif "subjectId: String? = nil" not in reading:
        failures += fail("reading model", "subjectId not optional in init")
    else:
        failures += ok("reading model", "optional subjectId, default nil")

    store_need = (
        "currentSubjectId",
        "func setSubject(_ id: SubjectID?)",
        "r.subjectId = currentSubjectId",
        "SubjectID.parse",
        "SubjectID.defaultsKey",
    )
    missing_s = [s for s in store_need if s not in store]
    if missing_s:
        failures += fail("store stamp", f"missing {missing_s}")
    elif "func startSession()" in store and "currentSubjectId = nil" in store.split("func startSession()")[1][:200]:
        failures += fail("store stamp", "startSession clears subject — re-seat is session, not subject")
    else:
        failures += ok("store stamp", "stamps on add; session start does not clear subject")

    if 'dict["subject_id"] = subj' not in sync:
        failures += fail("dump payload", "per-reading subject_id missing from SyncEngine")
    elif 'payload["subject_id"] = subj' not in sync:
        failures += fail("dump payload", "batch-level subject_id missing from SyncEngine")
    else:
        failures += ok("dump payload", "optional subject_id on batch + reading")

    if "Picker(\"Subject ID\"" not in settings and 'Picker("Subject ID"' not in settings:
        failures += fail("settings picker", "Settings has no Subject ID picker")
    elif "ForEach(SubjectID.allCases)" not in settings:
        failures += fail("settings picker", "picker is not bound to SubjectID.allCases")
    elif "store.setSubject" not in settings:
        failures += fail("settings picker", "picker does not call setSubject")
    else:
        failures += ok("settings picker", "Settings Picker over closed enum")

    if "currentSubjectId" not in dash:
        failures += fail("dashboard", "does not show current subject")
    else:
        failures += ok("dashboard", "shows current subject next to session controls")

    needed_tests = (
        "testParseAcceptsClosedEnumOnly",
        "testAllCasesAreThePilotPair",
        "testDefaultsKeyIsSubjectId",
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
