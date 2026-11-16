"""Ví dụ tối thiểu: gọi ARTEMIS bằng ArtemisClient trên máy thật.

Chạy (cần `artemis ui --port 8020` đang mở):
    cd /Volumes/SSD/AppData/artemis
    ARTEMIS_BASE_URL=http://127.0.0.1:8020 .venv/bin/python \
        /Volumes/SSD/Dev/active/PRM392_FlutterMobile/srs-review-ai/e2e_test/try_artemis.py

Ba ý chính:
1. `ArtemisClient(base_url, device_serial, default_profile)` — nối daemon + chọn máy.
2. `client.run(goal, locked_app_package=...)` — giao việc bằng ngôn ngữ tự
   nhiên, khoá trong app để agent không đi lạc.
3. Kiểm GIÁ TRỊ agent đọc được, không chỉ `succeeded`.

Vì sao đọc báo cáo từ DB thay vì `result.output`: ở commit ARTEMIS 351ca84,
`agents/outputter` có code nhưng không runner nào gọi, nên `result.output` luôn
`null` (đo 06/11/2026: 2 lượt, cả `enable_outputter=True`). Báo cáo cuối của
agent (`report_task_status.explanation`) được lưu trong
`traces/data_engine.db` bảng `steps` — đó là giá trị quan sát được.
"""

from __future__ import annotations

import asyncio
import json
import os
import re
import sqlite3
import time
from pathlib import Path

from artemis_client import ArtemisClient

SERIAL = "UGKFPBYDTGE67HGY"  # realme RMX3686
APP = "com.example.srs_review_ai_mobile"
ARTEMIS_HOME = Path(os.environ.get("ARTEMIS_HOME", "/Volumes/SSD/AppData/artemis"))
KEYS = ("courses", "classes", "docs_waiting", "docs_reviewing",
        "registrations_waiting", "projects_to_handle")


def final_report(task_id: str) -> str | None:
    """Explanation của lệnh report_task_status cuối cùng (đọc chỉ-đọc)."""
    db = ARTEMIS_HOME / "traces" / "data_engine.db"
    with sqlite3.connect(f"file:{db}?mode=ro", uri=True) as conn:
        rows = conn.execute(
            "SELECT action_taken FROM steps WHERE session_id = ? ORDER BY step_number",
            (task_id,),
        ).fetchall()
    for (raw,) in reversed(rows):
        action = json.loads(raw or "{}")
        if action.get("action") == "report_task_status":
            return action.get("args", {}).get("explanation")
    return None


def parse_json(text: str | None) -> dict | None:
    match = re.search(r"\{.*\}", text or "", re.S)
    if not match:
        return None
    try:
        return json.loads(match.group(0))
    except ValueError:
        return None


async def main() -> int:
    client = ArtemisClient(
        os.environ.get("ARTEMIS_BASE_URL", "http://127.0.0.1:8020"),
        device_serial=SERIAL,
        default_profile="flash",
    )
    started = time.monotonic()
    result = await client.run(
        "Trong app SRS Đánh giá AI, mở tab 'Tổng quan' ở thanh dưới cùng. "
        "Đọc tên người dùng sau 'Xin chào,' và các số trong 6 thẻ thống kê. "
        "Không bấm nút nào khác. Khi báo hoàn thành, explanation PHẢI là đúng "
        'một JSON: {"user": "...", "courses": n, "classes": n, '
        '"docs_waiting": n, "docs_reviewing": n, "registrations_waiting": n, '
        '"projects_to_handle": n}',
        locked_app_package=APP,
        timeout=600,
    )
    elapsed = time.monotonic() - started
    report = final_report(result.task_id)
    observed = parse_json(report)
    print(f"status={result.status} succeeded={result.succeeded} time={elapsed:.1f}s")
    print(f"trace_id={result.task_id}")
    print(f"report={report}")

    checks = {
        "succeeded": result.succeeded,
        "báo cáo là JSON": observed is not None,
        "có tên người dùng": bool(observed and observed.get("user")),
        "6 số là int >= 0": bool(observed) and all(
            isinstance(observed.get(k), int) and observed[k] >= 0 for k in KEYS
        ),
    }
    for name, ok in checks.items():
        print(f"  [{'PASS' if ok else 'FAIL'}] {name}")
    return 0 if all(checks.values()) else 1


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
