"""Điều khiển điện thoại bằng adb cho lượt test tay (agent tự đi flow, không qua Artemis).

    python3 e2e_test/phone.py dump                 # liệt kê phần tử có chữ: [i] (x,y) text
    python3 e2e_test/phone.py tap "Đánh giá"        # bấm phần tử đầu tiên chứa chữ đó
    python3 e2e_test/phone.py tap "Duyệt" 2         # bấm lần xuất hiện thứ 2
    python3 e2e_test/phone.py xy 540 2270           # bấm toạ độ
    python3 e2e_test/phone.py type "E2E duyệt"      # gõ vào ô đang focus
    python3 e2e_test/phone.py swipe up|down         # cuộn
    python3 e2e_test/phone.py back | home | launch
    python3 e2e_test/phone.py rec start FL04 | rec stop   # scrcpy quay ra e2e_test/videos/manual/<FL>.mp4

Ra đời 11/11/2026: Artemis qua 9router trả 429/503 làm FL04–FL11 hết giờ.
"""

from __future__ import annotations

import os
import re
import signal
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

SERIAL = os.environ.get("ARTEMIS_SERIAL", "49BEF6B6TCRSJNQW")
APP = "com.example.srs_review_ai_mobile"
OUT = Path(__file__).resolve().parent / "videos" / "manual"
PIDFILE = Path("/tmp/phone_rec.pid")


def adb(*args: str, timeout: int = 60) -> str:
    r = subprocess.run(["adb", "-s", SERIAL, *args], capture_output=True, text=True, timeout=timeout)
    return r.stdout + r.stderr


def nodes() -> list[tuple[str, int, int]]:
    for _ in range(3):
        out = adb("exec-out", "uiautomator", "dump", "/dev/tty")
        start = out.find("<?xml")
        end = out.rfind("</hierarchy>")
        if start >= 0 and end > start:
            break
        time.sleep(1)
    else:
        raise SystemExit("uiautomator dump failed: " + out[:200])
    root = ET.fromstring(out[start : end + len("</hierarchy>")])
    found = []
    for n in root.iter("node"):
        label = (n.get("text") or "").strip() or (n.get("content-desc") or "").strip()
        if not label:
            continue
        m = re.findall(r"\d+", n.get("bounds", ""))
        if len(m) != 4:
            continue
        x1, y1, x2, y2 = map(int, m)
        found.append((label.replace("\n", " ⏎ "), (x1 + x2) // 2, (y1 + y2) // 2))
    return found


def main(argv: list[str]) -> None:
    cmd = argv[0] if argv else "dump"
    if cmd == "dump":
        for i, (label, x, y) in enumerate(nodes()):
            print(f"[{i}] ({x},{y}) {label[:140]}")
    elif cmd == "tap":
        needle, nth = argv[1], int(argv[2]) if len(argv) > 2 else 1
        all_nodes = nodes()
        # Khớp nguyên chữ trước: "Đánh giá" phải là tab, không phải ô thống kê chứa chữ đó.
        hits = [n for n in all_nodes if n[0].lower() == needle.lower()] or [
            n for n in all_nodes if needle.lower() in n[0].lower()
        ]
        if len(hits) < nth:
            raise SystemExit(f"NOT FOUND: {needle!r} (hits={len(hits)})")
        label, x, y = hits[nth - 1]
        adb("shell", "input", "tap", str(x), str(y))
        print(f"tap ({x},{y}) {label[:80]}")
    elif cmd == "find":
        # find "<chữ>" [top]: (về đầu danh sách nếu có 'top') rồi cuộn xuống tới khi thấy, tối đa 15 lần.
        needle = argv[1].lower()
        if len(argv) > 2 and argv[2] == "top":
            for _ in range(8):
                adb("shell", "input", "swipe", "540", "700", "540", "2000", "150")
        for _ in range(15):
            hits = [n for n in nodes() if needle in n[0].lower()]
            if hits and 300 < hits[0][2] < 2150:
                print(f"found ({hits[0][1]},{hits[0][2]}) {hits[0][0][:100]}")
                return
            adb("shell", "input", "swipe", "540", "1700", "540", "1000", "400")
            time.sleep(0.8)
        raise SystemExit(f"NOT FOUND after scrolling: {argv[1]!r}")
    elif cmd == "xy":
        adb("shell", "input", "tap", argv[1], argv[2])
    elif cmd == "type":
        # adb input text: khoảng trắng phải là %s; chữ có dấu không gõ được qua input text.
        text = argv[1]
        if any(ord(c) > 127 for c in text):
            raise SystemExit("input text không gõ được ký tự Unicode; dùng ASCII")
        adb("shell", "input", "text", text.replace(" ", "%s"))
    elif cmd == "swipe":
        up = argv[1] == "up"
        adb("shell", "input", "swipe", "540", "1900" if up else "700", "540", "700" if up else "1900", "350")
    elif cmd == "back":
        adb("shell", "input", "keyevent", "KEYCODE_BACK")
    elif cmd == "home":
        adb("shell", "input", "keyevent", "KEYCODE_HOME")
    elif cmd == "launch":
        adb("shell", "am", "force-stop", APP)
        adb("shell", "monkey", "-p", APP, "-c", "android.intent.category.LAUNCHER", "1")
    elif cmd == "rec" and argv[1] == "start":
        OUT.mkdir(parents=True, exist_ok=True)
        dest = OUT / f"{argv[2]}.mp4"
        p = subprocess.Popen(
            ["scrcpy", "--serial", SERIAL, "--no-window", "--no-audio", "--record", str(dest),
             "--video-bit-rate", "4M"],
            stdout=open(f"/tmp/phone_rec_{argv[2]}.log", "w"), stderr=subprocess.STDOUT,
        )
        PIDFILE.write_text(f"{p.pid} {dest}")
        time.sleep(2)
        print(f"recording {dest} pid={p.pid}")
    elif cmd == "rec" and argv[1] == "stop":
        pid, dest = PIDFILE.read_text().split(" ", 1)
        os.kill(int(pid), signal.SIGTERM)  # TERM chốt file; SIGINT không dừng --no-window
        time.sleep(2)
        PIDFILE.unlink()
        print(f"saved {dest} ({Path(dest).stat().st_size // 1024} KB)")
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
