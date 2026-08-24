#!/usr/bin/env python3
"""Offline mock of iOS batch → Pi ACK (BGM only). No Mosquitto required.

Replays the SyncEngine JSON shape against the logger.py ACK contract:
success iff inserted + duplicates >= count.
"""
from __future__ import annotations

import json
import uuid
from datetime import datetime, timezone

MAX_PAYLOAD = 32768


def iso_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def make_reading(*, session_id: str | None, with_vitals: bool = True) -> dict:
    row = {
        "id": str(uuid.uuid4()),
        "ts": iso_now(),
        "motion": 0.1,
        "moving": False,
        "raw940": 12000,
        "filt940": 11850.5,
        "batt": 3.91,
        "trans": "none",
    }
    if with_vitals:
        row["bpm"] = 72
        row["spo2"] = 98
        row["temp"] = 36.4
    if session_id:
        row["session_id"] = session_id
    return row


def make_batch(n: int, *, session_open: bool) -> dict:
    sid = str(uuid.uuid4()) if session_open else None
    readings = [make_reading(session_id=sid) for _ in range(n)]
    payload: dict = {
        "source": "ios",
        "device_id": "test-device-id",
        "batch_id": str(uuid.uuid4()),
        "count": n,
        "readings": readings,
    }
    if sid:
        payload["session_id"] = sid
    return payload


def mock_ingest(batch: dict) -> dict:
    """Stand-in for ArmbandLogger._handle_ios_batch (seen set = duplicates)."""
    seen: set[str] = getattr(mock_ingest, "_seen", set())
    readings = batch.get("readings") or []
    batch_sid = batch.get("session_id")
    inserted = 0
    duplicates = 0
    for r in readings:
        if not isinstance(r, dict):
            continue
        rid = str(r.get("id") or "")
        _ = r.get("session_id") or batch_sid
        if rid in seen:
            duplicates += 1
        else:
            seen.add(rid)
            inserted += 1
    mock_ingest._seen = seen
    return {
        "batch_id": str(batch.get("batch_id") or ""),
        "status": "ok",
        "count": len(readings),
        "inserted": inserted,
        "duplicates": duplicates,
    }


def phone_success(ack: dict, sent_count: int) -> bool:
    inserted = int(ack.get("inserted") or 0)
    duplicates = int(ack.get("duplicates") or 0)
    return inserted + duplicates >= sent_count and ack.get("status") == "ok"


def required_fields_ok(batch: dict) -> list[str]:
    errs = []
    for k in ("source", "device_id", "batch_id", "count", "readings"):
        if k not in batch:
            errs.append(f"missing top {k}")
    if batch.get("source") != "ios":
        errs.append("source != ios")
    for i, r in enumerate(batch.get("readings") or []):
        for k in ("id", "ts", "motion", "moving", "raw940", "filt940", "batt", "trans"):
            if k not in r:
                errs.append(f"reading[{i}] missing {k}")
    return errs


def main() -> int:
    mock_ingest._seen = set()
    failures = 0

    b1 = make_batch(3, session_open=True)
    errs = required_fields_ok(b1)
    size = len(json.dumps(b1, separators=(",", ":")))
    ack1 = mock_ingest(b1)
    ok1 = not errs and phone_success(ack1, 3) and ack1["inserted"] == 3
    print("session batch", "PASS" if ok1 else "FAIL", "bytes", size, "ack", ack1, "errs", errs)
    failures += not ok1

    ack2 = mock_ingest(b1)
    ok2 = phone_success(ack2, 3) and ack2["duplicates"] == 3 and ack2["inserted"] == 0
    print("replay duplicates", "PASS" if ok2 else "FAIL", ack2)
    failures += not ok2

    b3 = make_batch(2, session_open=False)
    assert "session_id" not in b3
    ack3 = mock_ingest(b3)
    ok3 = phone_success(ack3, 2) and ack3["inserted"] == 2
    print("no-session batch", "PASS" if ok3 else "FAIL", ack3)
    failures += not ok3

    huge = make_batch(1, session_open=False)
    huge["readings"][0]["padding"] = "x" * (MAX_PAYLOAD + 8)
    raw = json.dumps(huge)
    ok4 = len(raw.encode()) > MAX_PAYLOAD
    print("oversize single detected", "PASS" if ok4 else "FAIL", "bytes", len(raw.encode()))
    failures += not ok4

    print("RESULT", "PASS" if failures == 0 else f"FAIL ({failures})")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
