"""10 ca kiểm thử THEO FLOW (Lab 2 F1/F2/F3 + backend FastAPI) cho ARTEMIS.

Nguồn flow: `mobile/docs/evidence/final-audit/ui-flow-audit.md`
  F1 Academic Management & Project Creation
  F2 AI-Assisted Supervisor Review
  F3 Document Submission, Revision & Approval (phần Supervisor trên Mobile)

Mỗi ca là MỘT hành trình nhiều màn, kết thúc bằng kiểm chéo giữa các màn
(ví dụ số trên Tổng quan đổi sau khi duyệt) và — khi flow chạm backend — kiểm
phía server (DB đồng bộ `server/.cache/sync.sqlite3`, log `POST /review`).

Không có cơ chế reset dữ liệu Firestore, nên mọi kiểm đếm là TƯƠNG ĐỐI
(after = before ± 1) do agent đọc cả hai mốc trong cùng lượt; nhánh lỗi kết
thúc bằng Hủy để không tiêu dữ liệu.
"""

from __future__ import annotations

import re
import sqlite3
import threading
import time
from pathlib import Path
from typing import Any

from cases import SYNC_DB, USER, Case, _norm

SERVER_LOG = Path("/tmp/srs-sync-server.log")


def _int(v: Any) -> int | None:
    if isinstance(v, bool):
        return None
    if isinstance(v, int):
        return v
    m = re.search(r"-?\d+", str(v or ""))
    return int(m.group(0)) if m else None


def _stamp() -> str:
    return time.strftime("%H%M%S")


# --- backend probes -----------------------------------------------------------

def _sync_count(collection: str, needle: str) -> int:
    if not SYNC_DB.exists():
        return 0
    with sqlite3.connect(f"file:{SYNC_DB}?mode=ro", uri=True) as conn:
        return conn.execute(
            "SELECT COUNT(*) FROM sync_records WHERE collection=? AND data LIKE ?",
            (collection, f"%{needle}%"),
        ).fetchone()[0]


def _wait_sync(collection: str, needle: str, seconds: int = 90) -> int:
    deadline = time.monotonic() + seconds
    while True:
        n = _sync_count(collection, needle)
        if n or time.monotonic() > deadline:
            return n
        time.sleep(5)


def _review_posts() -> list[str]:
    if not SERVER_LOG.exists():
        return []
    return [
        line for line in SERVER_LOG.read_text(errors="replace").splitlines()
        if '"POST /review' in line
    ]


def _online(flag: bool) -> None:
    from run_suite import set_sync_online

    set_sync_online(flag)


# --- FL01 F1: tạo dự án (happy path) + đồng bộ FastAPI ------------------------

def _f1_before() -> dict:
    return {"name": f"E2E Flow {_stamp()}"}


def _f1_check(o: dict, ctx: dict) -> dict[str, bool]:
    before, after = _int(o.get("count_before")), _int(o.get("count_after"))
    return {
        "đếm trước/sau đọc được": before is not None and after is not None,
        "danh sách dự án tăng đúng 1": before is not None and after == before + 1,
        "chi tiết mở đúng dự án vừa tạo": _norm(ctx["name"]) in _norm(o.get("detail_title")),
        "chi tiết có lớp": bool(re.search(r"[A-Z]{2,}\d{3,}", str(o.get("class") or ""))),
        "chi tiết có nhóm": "group" in _norm(o.get("group")) or "nhóm" in _norm(o.get("group")),
    }


def _f1_after(ctx: dict) -> dict[str, bool]:
    return {"FastAPI /sync nhận bản ghi dự án mới (≤90s)": _wait_sync("projects", ctx["name"]) >= 1}


# --- FL02 F1: nhánh lỗi — tạo dự án để trống tên rồi Hủy ----------------------

def _f1_err_check(o: dict, _: Any) -> dict[str, bool]:
    before, after = _int(o.get("count_before")), _int(o.get("count_after"))
    return {
        "nút Lưu bị chặn / báo lỗi khi trống tên": o.get("save_blocked") is True
        and bool(str(o.get("error_text") or "").strip()),
        "Hủy không tạo dự án (đếm không đổi)": before is not None and after == before,
    }


# --- FL03 F1: cấu hình học vụ — tìm rỗng → xoá tìm → mở chi tiết lớp ----------

def _f1_search_check(o: dict, _: Any) -> dict[str, bool]:
    return {
        "tìm 'ZZZ999' → 0 lớp": _int(o.get("empty_count")) == 0,
        "thông báo rỗng 'Chưa có lớp nào'": "chưa có lớp nào" in _norm(o.get("empty_message")),
        "xoá tìm → khôi phục 7 lớp": _int(o.get("restored_count")) == 7,
        "mở chi tiết SE1701": "se1701" in _norm(o.get("class_title")),
        "chi tiết có số sinh viên": _int(o.get("students")) is not None,
    }


# --- FL04 F2: AI review → duyệt → Tổng quan giảm 1 + FastAPI /review ----------

def _f2_before() -> dict:
    return {"posts": len(_review_posts())}


def _f2_check(o: dict, _: Any) -> dict[str, bool]:
    before, after = _int(o.get("waiting_before")), _int(o.get("waiting_after"))
    score = _int(o.get("ai_score"))
    return {
        "AI trả điểm hợp lệ 0–100": score is not None and 0 <= score <= 100,
        "trạng thái sau cùng = Đã duyệt": "đã duyệt" in _norm(o.get("final_status")),
        "Tổng quan: chờ đánh giá giảm đúng 1": before is not None and after == before - 1,
        "lịch sử có mục duyệt": "duyệt" in _norm(o.get("history_last")),
    }


def _f2_after(ctx: dict) -> dict[str, bool]:
    new = _review_posts()[ctx["posts"]:]
    return {
        "FastAPI nhận POST /review": bool(new),
        "POST /review trả 200": any(" 200 " in line for line in new),
    }


# --- FL05 F2: nhánh lỗi — Yêu cầu sửa với ghi chú trống ----------------------

def _f2_err_check(o: dict, _: Any) -> dict[str, bool]:
    return {
        "xác nhận bị chặn khi ghi chú trống": o.get("confirm_blocked") is True,
        "Hủy giữ nguyên trạng thái Đang đánh giá": "đang đánh giá" in _norm(o.get("status_after_cancel")),
    }


# --- FL06 F2: backend sập giữa lúc chạy AI → báo lỗi → có mạng → thử lại OK ---

RECONNECT_AFTER_S = 120


def _f2_down_before() -> dict:
    _online(False)
    timer = threading.Timer(RECONNECT_AFTER_S, _online, args=(True,))
    timer.daemon = True
    timer.start()
    return {"posts": len(_review_posts()), "timer": timer}


def _f2_down_check(o: dict, _: Any) -> dict[str, bool]:
    score = _int(o.get("retry_score"))
    return {
        "lần 1 hiện lỗi (không treo, không điểm giả)": bool(str(o.get("first_error") or "").strip())
        and o.get("first_score") in (None, "", "null"),
        "có nút 'Thử lại Đánh giá AI'": o.get("retry_button_seen") is True,
        "thử lại sau khi có mạng → có điểm 0–100": score is not None and 0 <= score <= 100,
    }


def _f2_down_after(ctx: dict) -> dict[str, bool]:
    ctx["timer"].cancel()
    _online(True)
    return {"FastAPI nhận POST /review sau khi nối lại": len(_review_posts()) > ctx["posts"]}


# --- FL07 F3: dự án → tài liệu → lịch sử phiên bản → lịch sử đánh giá ---------

def _f3_check(o: dict, _: Any) -> dict[str, bool]:
    versions = o.get("versions") or []
    return {
        "mở đúng Smart Campus Management": _norm("Smart Campus Management") in _norm(o.get("project")),
        "đọc được tài liệu đã duyệt x/y": bool(re.fullmatch(r"\s*\d+\s*/\s*\d+\s*", str(o.get("approved_ratio") or ""))),
        "có ít nhất 1 phiên bản dạng vN": bool(versions) and all(re.search(r"v\d+", str(v), re.I) for v in versions),
        "lịch sử đánh giá có mục": _int(o.get("history_entries")) not in (None, 0),
    }


# --- FL08 F3/Thông báo: lọc Hạn nộp → chi tiết → Back hệ thống (native) -------

def _notif_check(o: dict, _: Any) -> dict[str, bool]:
    return {
        "chi tiết có lớp SE1701": "se1701" in _norm(o.get("detail_class")),
        "Back hệ thống về đúng feed đang lọc": "hạn nộp" in _norm(o.get("filter_after_back")),
        "app vẫn mở": o.get("app_still_open") is True,
    }


# --- FL09 Offline: tạo học kỳ khi mất FastAPI → có mạng → server nhận ---------

def _sync_before() -> dict:
    name = f"E2E {_stamp()}"
    _online(False)
    return {"name": name}


def _sync_check(o: dict, ctx: dict) -> dict[str, bool]:
    return {"học kỳ vừa tạo hiện ngay trên máy": _norm(ctx["name"]) in _norm(o.get("created"))}


def _sync_after(ctx: dict) -> dict[str, bool]:
    offline = _sync_count("semesters", ctx["name"])
    _online(True)
    online = _wait_sync("semesters", ctx["name"])
    return {
        "server CHƯA có khi offline": offline == 0,
        "server có đúng 1 bản ghi sau khi có mạng (≤90s)": online == 1,
    }


# --- FL10 Phiên: hồ sơ + Remote Config → đăng xuất → Back → đăng nhập Google --

def _auth_check(o: dict, _: Any) -> dict[str, bool]:
    return {
        "hồ sơ đúng người": _norm(o.get("profile_name")) == _norm(USER),
        "Remote Config hiện 30 MB": _int(o.get("rc_max_upload_mb")) == 30,
        "sau đăng xuất, Back KHÔNG quay lại màn đã đăng nhập": o.get("back_after_logout_screen") in ("login", "launcher"),
        "đăng nhập lại qua hộp chọn tài khoản Google (native)": o.get("used_google_account_picker") is True,
        "đăng nhập lại → lời chào đúng người": _norm(USER) in _norm(o.get("greeting_after_login")),
    }


SEARCH = "gõ 'Smart Campus' vào ô tìm kiếm"

FLOWS: list[Case] = [
    Case(
        "FL01", "F1 · Tạo dự án mới → chi tiết → đồng bộ FastAPI", "Lab 2 F1 + backend /sync",
        "Mở tab 'Dự án', đọc số trên dòng 'N dự án' (count_before). Bấm 'Tạo dự án', đặt tên dự án đúng là "
        "'{name}', giữ lớp/nhóm mặc định, bấm 'Lưu'. Quay về danh sách, đọc lại số 'N dự án' (count_after). "
        "Mở dự án vừa tạo, đọc tiêu đề, lớp và nhóm trên màn chi tiết.",
        '{"count_before": n, "count_after": n, "detail_title": "...", "class": "...", "group": "..."}',
        _f1_check, before=_f1_before, after=_f1_after, timeout=900,
    ),
    Case(
        "FL02", "F1 · Tạo dự án để trống tên (nhánh lỗi) → Hủy", "Lab 2 F1 · lỗi",
        "Mở tab 'Dự án', đọc số 'N dự án' (count_before). Bấm 'Tạo dự án', để TRỐNG tên dự án, thử bấm 'Lưu'. "
        "Cho biết nút Lưu có bị chặn/báo lỗi không và chép lỗi. Bấm 'Hủy', đọc lại 'N dự án' (count_after).",
        '{"count_before": n, "save_blocked": true|false, "error_text": "...", "count_after": n}',
        _f1_err_check,
    ),
    Case(
        "FL03", "F1 · Lớp học: tìm rỗng → xoá tìm → mở chi tiết lớp", "Lab 2 F1 · tìm kiếm",
        "Mở tab 'Tài khoản', bấm 'Lớp học'. Gõ 'ZZZ999' vào ô tìm kiếm phía trên nút lọc; đọc số 'N lớp' "
        "(empty_count) và thông báo ở giữa (empty_message). Xoá hết chữ trong ô tìm, đọc lại 'N lớp' "
        "(restored_count). Bấm 'Xem lớp' của lớp SE1701, đọc tiêu đề và số sinh viên.",
        '{"empty_count": n, "empty_message": "...", "restored_count": n, "class_title": "...", "students": n}',
        _f1_search_check, timeout=900,
    ),
    Case(
        "FL04", "F2 · Mở yêu cầu → chạy AI → Duyệt → Tổng quan giảm 1", "Lab 2 F2 + backend /review",
        "Mở tab 'Tổng quan', đọc số 'Tài liệu chờ đánh giá' (waiting_before). Mở tab 'Đánh giá', bấm vào thẻ "
        "yêu cầu đầu tiên đang 'Chờ giảng viên đánh giá'. Bắt đầu đánh giá, chạy Đánh giá AI và chờ tới khi "
        "có điểm (ai_score). Bấm Duyệt, nhập ghi chú 'E2E duyệt', xác nhận. Đọc trạng thái cuối (final_status) "
        "và mục mới nhất trong lịch sử đánh giá (history_last). Quay lại tab 'Tổng quan', đọc lại số "
        "'Tài liệu chờ đánh giá' (waiting_after).",
        '{"waiting_before": n, "ai_score": n, "final_status": "...", "history_last": "...", "waiting_after": n}',
        _f2_check, before=_f2_before, after=_f2_after, timeout=1200, profile="flash",
    ),
    Case(
        "FL05", "F2 · Yêu cầu sửa với ghi chú trống (nhánh lỗi) → Hủy", "Lab 2 F2 · lỗi",
        "Mở tab 'Đánh giá', đổi bộ lọc sang yêu cầu 'Đang đánh giá', mở thẻ đầu tiên. Bấm 'Yêu cầu sửa', để "
        "TRỐNG ghi chú, thử xác nhận. Cho biết nút xác nhận có bị chặn không. Bấm 'Hủy', đọc trạng thái hiện tại.",
        '{"confirm_blocked": true|false, "status_after_cancel": "..."}',
        _f2_err_check, timeout=900,
    ),
    Case(
        "FL06", "F2 · Backend AI mất kết nối → lỗi → có mạng → Thử lại thành công", "Lab 2 F2 · lỗi backend",
        "Mở tab 'Đánh giá', đổi bộ lọc sang 'Đang đánh giá', mở thẻ đầu tiên, chạy Đánh giá AI. Lần này server "
        "đang mất kết nối: chép nguyên văn lỗi hiện ra (first_error), ghi first_score = null nếu không có điểm, "
        "cho biết có nút 'Thử lại Đánh giá AI' không. ĐỢI ĐỦ 3 PHÚT rồi bấm 'Thử lại Đánh giá AI', chờ có điểm "
        "(retry_score). Không duyệt, không yêu cầu sửa.",
        '{"first_error": "...", "first_score": null, "retry_button_seen": true|false, "retry_score": n}',
        _f2_down_check, before=_f2_down_before, after=_f2_down_after, timeout=1200,
    ),
    Case(
        "FL07", "F3 · Dự án → Tài liệu → Lịch sử phiên bản → Lịch sử đánh giá", "Lab 2 F3 (phần Supervisor)",
        f"Mở tab 'Dự án', {SEARCH}, mở 'Smart Campus Management'. Đọc dòng 'Tài liệu được duyệt: x/y' "
        "(approved_ratio). Vào 'Tài liệu', mở tài liệu 'Sequence Diagram', bấm 'Lịch sử phiên bản' và chép "
        "tên các phiên bản (v1, v2…). Quay lại, bấm 'Xem lịch sử đánh giá' và đếm số mục.",
        '{"project": "...", "approved_ratio": "x/y", "versions": ["..."], "history_entries": n}',
        _f3_check, timeout=900,
    ),
    Case(
        "FL08", "F3 · Thông báo lọc 'Hạn nộp' → chi tiết → nút Back hệ thống", "Lab 2 F3 + Android native Back",
        "Mở tab 'Thông báo', bấm bộ lọc 'Hạn nộp', bấm 'Xem chi tiết' của thông báo đầu tiên, đọc lớp trên màn "
        "chi tiết. Nhấn nút BACK của hệ thống Android (không dùng mũi tên trong app). Cho biết bộ lọc nào "
        "đang được chọn sau khi Back và app còn mở không.",
        '{"detail_class": "...", "filter_after_back": "...", "app_still_open": true|false}',
        _notif_check,
    ),
    Case(
        "FL09", "Offline: tạo học kỳ khi mất FastAPI → có mạng → server nhận", "SQLite outbox → /sync/push",
        "Mở tab 'Tài khoản', bấm 'Học kỳ', bấm 'Tạo học kỳ'. Gõ tên đúng là '{name}', ở 'Ngày kết thúc' chọn "
        "một ngày bất kỳ sau ngày bắt đầu, giữ nguyên ô khác, bấm 'Lưu'. Đọc lại tên học kỳ vừa xuất hiện.",
        '{"created": "..."}',
        _sync_check, before=_sync_before, after=_sync_after, timeout=900,
    ),
    Case(
        "FL10", "Phiên: hồ sơ + Remote Config → đăng xuất → Back → đăng nhập Google", "Auth + RC + native picker",
        "Mở tab 'Tài khoản', đọc họ tên (profile_name), cuộn xuống dòng 'Remote Config' đọc số MB. Bấm "
        "'Đăng xuất'. Nhấn nút BACK hệ thống một lần, cho biết đang ở màn đăng nhập ('login'), launcher "
        "('launcher') hay màn đã đăng nhập ('app'). Mở lại app nếu cần, bấm 'Đăng nhập bằng Google', trong hộp "
        "chọn tài khoản của Android chọn tài khoản lehuytuong2005@gmail.com. Đọc lời chào trên Tổng quan.",
        '{"profile_name": "...", "rc_max_upload_mb": n, "back_after_logout_screen": "login|launcher|app", '
        '"used_google_account_picker": true|false, "greeting_after_login": "..."}',
        _auth_check, timeout=900, allow_logout=True,
    ),
]
