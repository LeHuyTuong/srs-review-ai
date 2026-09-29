#!/usr/bin/env python3
"""WP8 gate 3 — holdout HisWise. Posts the units the APP would actually send
(dump carries `selected` from unitFromRequirement, the app's real inventory
mapping) to /review/batch on the local proxy, and prints every number the
AGENTS.md error-channel rule demands: unit_ok/failed per response, per-unit
scores, per-issue verification mix, dropped counts, and the failures channel
verbatim.

2026-09-29 (second run): the driver filters on `selected == true` — the
footer-only backstop lives in the app's inventory layer, so sending the raw
splitter dump would measure a pipeline no user gets. Deselected units are
printed with their reason, never silently dropped.

Approved spend (2026-09-29, Amy): first run 7 units; this rerun ≤ 4 units.
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
    send = [u for u in units if u.get("selected", True)]
    held_back = [u for u in units if not u.get("selected", True)]
    print(f"units in dump: {len(units)}; selected (sent): {len(send)}")
    for u in held_back:
        reasons = []
        if u.get("is_page_footer_only"):
            reasons.append("footer-only")
        if u.get("malformed"):
            reasons.append("malformed")
        print(
            f"  held back: {u['requirement_id']} "
            f"({', '.join(reasons) or 'not selected'}) len={len(u['text'])}"
        )
    if not send:
        print("nothing to send")
        return

    payload = {
        "units": [
            {
                "requirement_id": u["requirement_id"],
                "text": u["text"],
                "section": u["section"],
                "page_index": u["page_index"],
            }
            for u in send
            if u["text"].strip()
        ]
    }
    print(f"POSTing {len(payload['units'])} units to {URL}")
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
    footer_findings = sum(
        1
        for entry in results
        for issue in entry["result"]["issues"]
        if "page" in issue["quote"].lower() and issue["quote"].lower().count("|") >= 1
    )
    print(f"page-pipe-quote findings: {footer_findings}")


if __name__ == "__main__":
    main()
