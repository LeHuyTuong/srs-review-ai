"""Ghép video demo: trái = trang Workspace của ARTEMIS, phải = màn hình điện thoại.

    python3 e2e_test/compose_videos.py <ui.webm> [--out e2e_test/videos] [--log e2e_test/results/<ngày>.jsonl]

- <ui.webm>: video headless của http://127.0.0.1:8020/workspace (giờ bắt đầu = birth time của file).
- Điện thoại: mặc định recording.mp4 mà ARTEMIS tự quay cho từng session. scrcpy của ARTEMIS
  có lúc không khởi động được (FL05 ngày 10/11), nên nên quay liên tục cả lượt bằng
  `scrcpy --no-window --record phone.mkv` rồi truyền `--phone phone.mkv`: cắt cả hai video theo giờ.
- Căn giờ theo sessions.start_time trong traces/data_engine.db (đọc chỉ-đọc).
Session bắt đầu trước khi video UI có thì bỏ qua và in lý do, không ghép lệch.
"""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
import subprocess
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ARTEMIS = Path(os.environ.get("ARTEMIS_HOME", "/Volumes/SSD/AppData/artemis"))
HEIGHT = 1080


def case_names(log: Path | None) -> dict[str, str]:
    if not log or not log.exists():
        return {}
    out = {}
    for line in log.read_text(encoding="utf-8").splitlines():
        row = json.loads(line)
        if row.get("trace_id"):
            verdict = "PASS" if row["passed"] else "FAIL"
            out[row["trace_id"]] = f"{row['case']}-{row['run']}-{verdict}"
    return out


def duration(path: Path) -> float:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    return float(out) if out not in ("", "N/A") else 0.0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("ui")
    ap.add_argument("--out", default=str(Path(__file__).parent / "videos"))
    ap.add_argument("--log")
    ap.add_argument("--phone", help="video điện thoại quay liên tục cả lượt (birth time = giờ bắt đầu)")
    args = ap.parse_args()
    ui = Path(args.ui)
    ui_start = ui.stat().st_birthtime
    ui_len = duration(ui)
    phone_all = Path(args.phone) if args.phone else None
    phone_start = phone_all.stat().st_birthtime if phone_all else 0.0
    phone_len = duration(phone_all) if phone_all else 0.0
    names = case_names(Path(args.log) if args.log else None)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    db = sqlite3.connect(f"file:{ARTEMIS / 'traces/data_engine.db'}?mode=ro", uri=True)
    rows = db.execute(
        "select session_id, start_time, end_time, video_filepath from sessions "
        "where start_time >= ? order by start_time",
        (ui_start - 3600,),
    ).fetchall()
    made = 0
    for sid, start, end, phone in rows:
        label = names.get(sid, sid[:8])
        if start < ui_start:
            print(f"bỏ {label}: bắt đầu trước video Artemis {ui_start - start:.0f}s")
            continue
        dur = (end or start) - start
        if phone_all:
            p_off = start - phone_start
            if p_off < 0 or p_off + dur > phone_len + 5:
                print(f"bỏ {label}: video điện thoại liên tục không phủ session")
                continue
            phone_in = ["-ss", f"{p_off:.2f}", "-t", f"{dur:.2f}", "-i", str(phone_all)]
        elif phone and Path(phone).exists():
            phone_in = ["-t", f"{dur:.2f}", "-i", phone]
        else:
            print(f"bỏ {label}: không có video điện thoại")
            continue
        offset = start - ui_start
        if offset + dur > ui_len + 5:
            print(f"bỏ {label}: video Artemis chưa phủ hết session (cần {offset + dur:.0f}s, có {ui_len:.0f}s)")
            continue
        target = out / f"{label}.mp4"
        cmd = [
            "ffmpeg", "-v", "error", "-y",
            "-ss", f"{offset:.2f}", "-t", f"{dur:.2f}", "-i", str(ui),
            *phone_in,
            "-filter_complex",
            f"[0:v]scale=-2:{HEIGHT},setsar=1[a];[1:v]scale=-2:{HEIGHT},setsar=1[b];[a][b]hstack=inputs=2,fps=30[v]",
            "-map", "[v]", "-c:v", "libx264", "-preset", "veryfast", "-crf", "23", "-pix_fmt", "yuv420p",
            str(target),
        ]
        subprocess.run(cmd, check=True)
        print(f"ok {target}  ({dur:.0f}s)")
        made += 1
    print(f"{made} video")
    return 0 if made else 1


if __name__ == "__main__":
    raise SystemExit(main())
