"""Chạy bộ ca kiểm thử Lab 3 §7 bằng ArtemisClient trên máy thật.

    cd /Volumes/SSD/AppData/artemis
    ARTEMIS_BASE_URL=http://127.0.0.1:8020 .venv/bin/python \
        /Volumes/SSD/Dev/active/PRM392_FlutterMobile/srs-review-ai/e2e_test/run_suite.py \
        --runs 3 [--only TC01,TC08]

Mỗi lượt:
1. `setup` đưa app về điều kiện đầu (force-stop + mở lại, bật/tắt mạng sync).
2. ArtemisClient giao goal; goal bắt agent trả đúng một JSON trong
   `report_task_status.explanation`.
3. Đọc JSON đó từ `traces/data_engine.db` (chỉ đọc; `result.output` luôn null
   ở ARTEMIS 351ca84) và assert TỪNG giá trị với kỳ vọng. `succeeded=True` mà
   giá trị sai → FAIL.
4. Ghi một dòng JSONL vào `e2e_test/results/<ngày>.jsonl`.

Cuối cùng in bảng: ca / số lượt / tỉ lệ đạt / thời gian trung bình / trace ID.
"""

from __future__ import annotations

import argparse
import asyncio
import datetime as dt
import json
import os
import statistics
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from artemis_client import ArtemisClient  # noqa: E402
from cases import APP, CASES, SERIAL, Case  # noqa: E402
from try_artemis import final_report, parse_json  # noqa: E402

RESULTS = Path(__file__).resolve().parent / "results"


TRACE_ROOT = Path(os.environ.get("ARTEMIS_HOME", "/Volumes/SSD/AppData/artemis")) / "traces"


def adb(*args: str) -> str:
    out = subprocess.run(
        ["adb", "-s", SERIAL, *args], capture_output=True, text=True, timeout=60
    )
    return out.stdout + out.stderr


def relaunch() -> None:
    adb("shell", "am", "force-stop", APP)
    adb("shell", "monkey", "-p", APP, "-c", "android.intent.category.LAUNCHER", "1")
    time.sleep(6)


def set_sync_online(online: bool) -> None:
    if online:
        # App build trỏ 127.0.0.1:8010; SRS_E2E_HOST_PORT=8000 chuyển sang server Docker.
        adb("reverse", "tcp:8010", f"tcp:{os.environ.get('SRS_E2E_HOST_PORT', '8010')}")
    else:
        adb("reverse", "--remove", "tcp:8010")


TRACE_DB = Path(os.environ.get("ARTEMIS_HOME", "/Volumes/SSD/AppData/artemis")) / "traces/data_engine.db"


async def stop_running(client: ArtemisClient) -> None:
    import sqlite3

    with sqlite3.connect(f"file:{TRACE_DB}?mode=ro", uri=True) as db:
        ids = [r[0] for r in db.execute("select session_id from sessions where status='running'")]
    for session_id in ids:
        try:
            await client.stop(session_id)
        except Exception as exc:  # không để việc dọn dẹp làm hỏng báo cáo
            print(f"stop {session_id} failed: {exc!r}", flush=True)


async def run_once(client: ArtemisClient, case: Case, run_no: int) -> dict:
    set_sync_online(True)
    if case.relaunch:
        relaunch()
    context = case.before() if case.before else None
    started = time.monotonic()
    error = None
    try:
        result = await client.run(
            (case.goal.format(**context) if isinstance(context, dict) else case.goal)
            + case.report_instruction(),
            locked_app_package=APP,
            timeout=case.timeout,
            profile=case.profile,
        )
        status, succeeded, task_id = result.status, result.succeeded, result.task_id
    except Exception as exc:  # daemon/timeout: lượt này FAIL, ghi lý do
        status, succeeded, task_id, error = "error", False, None, repr(exc)
        # Hết giờ phía client KHÔNG dừng task trên daemon: task mồ côi chạy tiếp
        # và chặn lượt sau (đã gặp 2 lần ngày 06/11). Dừng mọi task đang chạy.
        await stop_running(client)
    elapsed = time.monotonic() - started
    report = final_report(task_id) if task_id else None
    observed = parse_json(report)
    checks = case.check(observed or {}, context)
    if case.after:
        checks.update(case.after(context))
    checks = {"ARTEMIS succeeded": bool(succeeded), "báo cáo là JSON": observed is not None, **checks}
    passed = all(checks.values())
    set_sync_online(True)
    return {
        "case": case.id,
        "run": run_no,
        "at": dt.datetime.now().isoformat(timespec="seconds"),
        "trace_id": task_id,
        "status": status,
        "seconds": round(elapsed, 1),
        "observed": observed,
        "report": report,
        "checks": checks,
        "passed": passed,
        "error": error,
        "video": find_video(task_id),
    }


def find_video(task_id: str | None) -> str | None:
    """ARTEMIS tự quay scrcpy thành traces/web_<ts>_<id8>_<verdict>_<time>/recording.mp4."""
    if not task_id:
        return None
    hits = sorted(TRACE_ROOT.glob(f"web_*_{task_id[:8]}_*/recording.mp4"))
    return str(hits[-1]) if hits else None


def table(rows: list[dict]) -> str:
    lines = [
        "| Ca | Lượt | Đạt | Tỉ lệ | TB (s) | Trace ID |",
        "|---|---|---|---|---|---|",
    ]
    for case in {r["case"]: None for r in rows}:
        mine = [r for r in rows if r["case"] == case]
        if not mine:
            continue
        ok = sum(r["passed"] for r in mine)
        avg = statistics.mean(r["seconds"] for r in mine)
        traces = ", ".join(f"`{(r['trace_id'] or 'none')[:8]}`" for r in mine)
        lines.append(
            f"| {case} | {len(mine)} | {ok} | {ok / len(mine):.0%} | {avg:.1f} | {traces} |"
        )
    return "\n".join(lines)


async def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--only", default="")
    parser.add_argument("--suite", choices=("functions", "flows"), default="flows")
    args = parser.parse_args()
    wanted = {c.strip() for c in args.only.split(",") if c.strip()}
    if args.suite == "flows":
        from flows import FLOWS as pool
    else:
        pool = CASES
    cases = [c for c in pool if not wanted or c.id in wanted]

    client = ArtemisClient(
        os.environ.get("ARTEMIS_BASE_URL", "http://127.0.0.1:8020"),
        device_serial=SERIAL,
        default_profile="flash",
    )
    RESULTS.mkdir(exist_ok=True)
    log = RESULTS / f"{dt.date.today().isoformat()}.jsonl"
    rows: list[dict] = []
    for case in cases:
        for run_no in range(1, args.runs + 1):
            row = await run_once(client, case, run_no)
            rows.append(row)
            with log.open("a", encoding="utf-8") as fh:
                fh.write(json.dumps(row, ensure_ascii=False) + "\n")
            failed = [k for k, v in row["checks"].items() if not v]
            verdict = "PASS" if row["passed"] else "FAIL " + "; ".join(failed)
            print(f"{case.id} #{run_no} {row['seconds']}s {row['trace_id']} {verdict}", flush=True)
    print()
    print(table(rows))
    print(f"\nlog: {log}")
    return 0 if all(r["passed"] for r in rows) else 1


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
