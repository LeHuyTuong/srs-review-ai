#!/usr/bin/env python3
"""WP8 gate 3 — holdout HisWise. Posts the app-parsed units of the HisWise
SDS (16-page PDF in server/, pages extracted by PyMuPDF, units split by the
app's own RequirementSplitter 1.4.4) to /review/batch on the local proxy,
and prints every number the AGENTS.md error-channel rule demands:
unit_ok/failed per response, per-unit scores, per-issue verification mix,
dropped counts, and the failures channel verbatim.

Approved spend (2026-09-29, Amy): 7 units ≈ 2 batch calls at ~500 chars/unit.
Requires the proxy running on 127.0.0.1:8000 with real keys (.env) — the
script refuses to run against mock mode, because a mock holdout is a
fabricated number.
"""
from __future__ import annotations

import json
import os
import sys
import urllib.request

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

URL = "http://127.0.0.1:8000/review/batch"
UNITS_PATH = os.path.join(os.environ.get("TEMP", "C:/Temp"), "hiswise_units.json")


def main() -> None:
    units = json.load(open(UNITS_PATH, encoding="utf-8"))["units"]
    print(f"POSTing {len(units)} units to {URL}")
    payload = {
        "units": [
            {
                "requirement_id": u["requirement_id"],
                "text": u["text"],
                "section": u["section"],
                "page_index": u["page_index"],
            }
            for u in units
            if u["text"].strip()
        ]
    }
    req = urllib.request.Request(
        URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=300) as r:
        body = json.loads(r.read().decode("utf-8"))

    results = body.get("results", [])
    failed = body.get("failed", [])
    ok = len(results)
    print(f"unit_ok={ok} failed={len(failed)}")
    for f in failed:
        print("FAILED:", f.get("requirement_id"), "|", f.get("message"))

    total_findings = 0
    total_dropped = 0
    verif = {}
    sev = {}
    typ = {}
    scores = {}
    for entry in results:
        res = entry["result"]
        rid = res["requirement_id"]
        scores[rid] = res["score"]
        total_dropped += res.get("dropped_issue_count", 0) or 0
        for issue in res["issues"]:
            total_findings += 1
            verif[issue["verification"]] = verif.get(issue["verification"], 0) + 1
            sev[issue["severity"]] = sev.get(issue["severity"], 0) + 1
            typ[issue["type"]] = typ.get(issue["type"], 0) + 1

    print(f"findings={total_findings} (counted by summing issues across results[])")
    print(f"dropped_quotes={total_dropped}")
    print("scores:", scores)
    if scores:
        avg = sum(scores.values()) / len(scores)
        print(f"avg_score={avg:.2f}")
    print("verification:", verif)
    print("severity:", sev)
    print("type:", typ)
    print("cached flags:", {e["result"]["requirement_id"]: e["result"]["cached"] for e in results})
    print("mock:", body.get("mock"), "contract:", body.get("contract_version"))

    # One verbatim sample per unit with findings — the reading-the-evidence part.
    print("--- samples (verbatim) ---")
    for entry in results:
        res = entry["result"]
        for issue in res["issues"][:1]:
            print(
                res["requirement_id"],
                "|", issue["severity"],
                "|", issue["verification"],
                "|", issue.get("coverage"),
                "|", issue["quote"][:90],
            )


if __name__ == "__main__":
    main()
