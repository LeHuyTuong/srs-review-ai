"""12 ca kiểm thử Lab 3 §7: goal cho ARTEMIS + kiểm GIÁ TRỊ quan sát được.

Kỳ vọng lấy từ fixture `mobile/assets/fixtures/academic.json` (dữ liệu demo
cố định của app). Hằng số đánh dấu `# CALIBRATE` là con số đọc trên máy thật ở
lượt hiệu chuẩn bằng `uiautomator dump`, KHÔNG phải từ lời agent.

Mỗi `check` trả dict {tên kiểm tra: bool}. Không có kiểm tra nào chỉ dựa vào
`succeeded`.
"""

from __future__ import annotations

import os
import sqlite3
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

SERIAL = os.environ.get("ARTEMIS_SERIAL", "UGKFPBYDTGE67HGY")  # realme RMX3686; Xiaomi: 49BEF6B6TCRSJNQW
APP = "com.example.srs_review_ai_mobile"
SYNC_DB = Path(__file__).resolve().parents[1] / "server" / ".cache" / "sync.sqlite3"

# Hiệu chuẩn 06/11/2026 trên Xiaomi bằng uiautomator dump, tài khoản Google đã
# đăng nhập (dữ liệu Firestore, KHÔNG phải fixture — fixture ghi Nguyễn Văn An).
USER = "Le Huy Tuong"
EMAIL = "lehuytuong2005@gmail.com"
DASHBOARD = {
    "courses": 3, "classes": 7, "docs_waiting": 6, "docs_reviewing": 5,
    "registrations_waiting": 0, "projects_to_handle": 10,
}
COURSES_ON_LIST = 4  # màn Môn học có 4 môn trong khi thẻ Tổng quan ghi 3
CLASSES_SE17 = 4  # lọc học kỳ Fall 2026 + Đang giảng dạy, gõ "SE17"
UNREAD_NOTIFICATIONS = 2
COURSE_CODES = {"SWP391", "SWR302", "PRN212", "PRM323-DEMO"}
CLASS_NAMES = {"SE1701", "SE1702", "SE1703", "SE1723", "SE1801", "SE1650", "DEMO323", "SELF323"}
PROJECTS = {
    "Smart Campus Management", "Hospital Management System", "Student Services Portal",
    "Smart Attendance System", "Dormitory Management Platform", "AI Learning Assistant",
    "Event Management System", "Campus Service Portal", "Library Booking System",
    "Clinic Appointment App", "Requirement Tracker", "E-learning Platform SRS",
    "Canteen Ordering System", "Project Review AI — Demo",
}
# Đo trên realme 06/11: "docx, md, pdf" — khác thứ tự default trong code
# (pdf, docx, md) → giá trị fetch từ Firebase Console, không phải default.
RC_MAX_UPLOAD_MB = 30
RC_FILE_TYPES = ["docx", "md", "pdf"]


def _norm(text: Any) -> str:
    return " ".join(str(text or "").split()).casefold()


@dataclass
class Case:
    id: str
    title: str
    flow: str
    goal: str
    schema: str
    check: Callable[[dict, Any], dict[str, bool]]
    relaunch: bool = True
    profile: str = "flash"
    timeout: int = 600
    before: Callable[[], Any] | None = None
    after: Callable[[Any], dict[str, bool]] | None = None
    allow_logout: bool = False

    def report_instruction(self) -> str:
        return (
            (" Không xoá dữ liệu" if self.allow_logout else " Không đăng xuất, không xoá dữ liệu")
            + ", không bấm nút nào ngoài các bước đã nêu. Khi báo hoàn thành, explanation PHẢI là đúng một JSON dạng "
            f"{self.schema}. Nếu không làm được bước nào, vẫn báo JSON và đặt "
            '"error": "<lý do>".'
        )


# --- kiểm tra -----------------------------------------------------------------

def _dashboard(o: dict, _: Any) -> dict[str, bool]:
    return {
        "tên người dùng đúng": _norm(o.get("user")) == _norm(USER),
        **{f"{k} = {v}": o.get(k) == v for k, v in DASHBOARD.items()},
    }


def _courses(o: dict, _: Any) -> dict[str, bool]:
    codes = {str(c).strip() for c in o.get("codes") or []}
    return {
        "đủ đúng 4 mã môn": codes == COURSE_CODES,
        f"số môn = {COURSES_ON_LIST}": o.get("count") == COURSES_ON_LIST,
    }


def _class_search(o: dict, _: Any) -> dict[str, bool]:
    names = [str(n).strip() for n in o.get("results") or []]
    return {
        "chỉ còn lớp chứa 'SE17'": bool(names) and all("SE17" in n for n in names),
        f"đúng {CLASSES_SE17} lớp": len(names) == CLASSES_SE17,
        "kết quả đều là lớp thật": set(names) <= CLASS_NAMES,
    }


def _search_empty(o: dict, _: Any) -> dict[str, bool]:
    return {
        "0 kết quả": o.get("result_count") == 0,
        "hiện thông báo rỗng 'Chưa có lớp nào'": "chưa có lớp nào" in _norm(o.get("empty_message")),
    }


def _project_detail(o: dict, _: Any) -> dict[str, bool]:
    return {
        "mở đúng dự án": _norm(o.get("project")) == _norm("Smart Campus Management"),
        "lớp = SE1701": "se1701" in _norm(o.get("class")),
        "trạng thái = Đang thực hiện": _norm(o.get("status")) == _norm("Đang thực hiện"),
        "tiến độ = 65%": str(o.get("progress")).strip().rstrip("%") == "65",
    }


def _back_native(o: dict, _: Any) -> dict[str, bool]:
    return {
        "đã vào màn chi tiết": _norm(o.get("detail_title")) == _norm("Smart Campus Management"),
        "Back hệ thống đưa về danh sách": o.get("after_back_screen") == "list",
        "app vẫn mở sau Back": o.get("app_still_open") is True,
    }


def _reviews(o: dict, _: Any) -> dict[str, bool]:
    return {
        f"số chờ đánh giá = {DASHBOARD['docs_waiting']}": o.get("waiting") == DASHBOARD["docs_waiting"],
        "mở được một tài liệu": bool(str(o.get("opened_document") or "").strip()),
        "dự án của tài liệu là dự án thật": str(o.get("project") or "").strip() in PROJECTS,
    }


def _notifications(o: dict, _: Any) -> dict[str, bool]:
    titles = [_norm(t) for t in o.get("first_titles") or []]
    return {
        f"chưa đọc = {UNREAD_NOTIFICATIONS}": o.get("unread") == UNREAD_NOTIFICATIONS,
        "thông báo đầu là Group 03 / State Diagram v2": bool(titles)
        and "group 03" in titles[0] and "state diagram v2" in titles[0],
    }


def _profile(o: dict, _: Any) -> dict[str, bool]:
    return {
        "tên đúng": _norm(o.get("name")) == _norm(USER),
        "email đúng": _norm(o.get("email")) == _norm(EMAIL),
        "vai trò Giảng viên": _norm(o.get("role")) == _norm("Giảng viên"),
    }


def _remote_config(o: dict, _: Any) -> dict[str, bool]:
    return {
        f"giới hạn tải lên = {RC_MAX_UPLOAD_MB} MB": o.get("max_upload_mb") == RC_MAX_UPLOAD_MB,
        f"loại tệp = {RC_FILE_TYPES} (đúng thứ tự Console)": [
            _norm(t) for t in o.get("file_types") or []
        ] == RC_FILE_TYPES,
    }


def _form_error(o: dict, _: Any) -> dict[str, bool]:
    return {
        "form KHÔNG được lưu": o.get("saved") is False,
        "lỗi 'Nhập tên học kỳ.'": "nhập tên học kỳ" in _norm(o.get("error_text")),
    }


# --- ca đồng bộ offline: kiểm bằng DB server, không tin lời agent -------------

# Backend chạy trong Docker (SRS_E2E_CONTAINER=srs-review-ai-server-1) thì DB sync nằm trong volume
# của container: đọc bằng `docker exec`, chế độ chỉ đọc. Không có biến này thì đọc file trên host.
SYNC_CONTAINER = os.environ.get("SRS_E2E_CONTAINER", "").strip()
SYNC_DB_IN_CONTAINER = "/data/.cache/sync.sqlite3"
_COUNT_SQL = "SELECT COUNT(*) FROM sync_records WHERE collection=? AND data LIKE ?"


def sync_count(collection: str, needle: str) -> int:
    if SYNC_CONTAINER:
        code = (
            "import os,sqlite3,sys\n"
            f"p={SYNC_DB_IN_CONTAINER!r}\n"
            "if not os.path.exists(p): print(0); sys.exit()\n"
            "c=sqlite3.connect('file:'+p+'?mode=ro',uri=True)\n"
            "print(c.execute(sys.argv[1],(sys.argv[2],sys.argv[3])).fetchone()[0])"
        )
        out = subprocess.run(
            ["docker", "exec", SYNC_CONTAINER, "python", "-c", code, _COUNT_SQL, collection, f"%{needle}%"],
            capture_output=True, text=True, timeout=30,
        )
        return int(out.stdout.strip() or 0) if out.returncode == 0 else 0
    if not SYNC_DB.exists():
        return 0
    with sqlite3.connect(f"file:{SYNC_DB}?mode=ro", uri=True) as conn:
        return conn.execute(_COUNT_SQL, (collection, f"%{needle}%")).fetchone()[0]


def _sync_rows(name: str) -> int:
    return sync_count("semesters", name)


def _offline_before() -> dict:
    from run_suite import set_sync_online  # tránh import vòng lúc nạp module

    name = f"E2E {time.strftime('%H%M%S')}"
    set_sync_online(False)
    return {"name": name}


def _offline_after(ctx: dict) -> dict[str, bool]:
    from run_suite import set_sync_online

    name = ctx["name"]
    while_offline = _sync_rows(name)
    set_sync_online(True)
    deadline = time.monotonic() + 90  # backoff trần 60s + một lượt
    online = 0
    while time.monotonic() < deadline and online == 0:
        time.sleep(5)
        online = _sync_rows(name)
    return {
        "server CHƯA có khi offline": while_offline == 0,
        "server có đúng 1 bản ghi sau khi online lại (≤90s)": online == 1,
    }


def _offline_check(o: dict, ctx: Any) -> dict[str, bool]:
    return {"agent thấy học kỳ vừa tạo trong danh sách": _norm(ctx["name"]) in _norm(o.get("created"))}


CASES: list[Case] = [
    Case(
        "TC01", "Tổng quan: lời chào + 6 thẻ thống kê", "Lab 2 · Dashboard",
        "Trong app, mở tab 'Tổng quan' ở thanh dưới cùng. Đọc tên sau 'Xin chào,' và số trong 6 thẻ thống kê.",
        '{"user": "...", "courses": n, "classes": n, "docs_waiting": n, "docs_reviewing": n, '
        '"registrations_waiting": n, "projects_to_handle": n}',
        _dashboard,
    ),
    Case(
        "TC02", "Danh sách môn học", "Lab 2 · Môn học",
        "Mở tab 'Tài khoản', bấm mục 'Môn học & Đợt học'. Cuộn hết danh sách, đọc mã của mọi môn học.",
        '{"count": n, "codes": ["..."]}',
        _courses,
    ),
    Case(
        "TC03", "Tìm lớp có kết quả", "Lab 2 · Tìm kiếm",
        "Mở tab 'Tài khoản', bấm mục 'Lớp học'. Gõ 'SE17' vào ô tìm kiếm phía trên nút lọc (giữ nguyên bộ lọc). Cuộn hết, đọc tên mọi lớp còn hiển thị.",
        '{"results": ["..."]}',
        _class_search,
    ),
    Case(
        "TC04", "Tìm lớp không có kết quả (nhánh lỗi/rỗng)", "Nhánh thay thế · Tìm kiếm",
        "Mở tab 'Tài khoản', bấm mục 'Lớp học'. Gõ 'ZZZ999' vào ô tìm kiếm phía trên nút lọc. Đếm số lớp còn hiển thị và chép nguyên văn thông báo hiện ở giữa danh sách.",
        '{"result_count": n, "empty_message": "..."}',
        _search_empty,
    ),
    Case(
        "TC05", "Chi tiết dự án", "Lab 2 · Dự án → chi tiết",
        "Mở tab 'Dự án'. Gõ 'Smart Campus' vào ô tìm kiếm, bấm vào thẻ dự án 'Smart Campus Management'. Trên màn chi tiết, đọc tên dự án, lớp, trạng thái và phần trăm tiến độ.",
        '{"project": "...", "class": "...", "status": "...", "progress": "n%"}',
        _project_detail,
    ),
    Case(
        "TC06", "Nút Back hệ thống Android (tương tác native)", "Android native · Back",
        "Mở tab 'Dự án', gõ 'Smart Campus' vào ô tìm kiếm, bấm vào thẻ 'Smart Campus Management', ghi lại tiêu đề màn chi tiết. Sau đó nhấn nút BACK của hệ thống Android (không dùng nút mũi tên trong app). Cho biết màn hình sau khi Back là danh sách dự án ('list') hay màn khác ('other'), và app còn mở không.",
        '{"detail_title": "...", "after_back_screen": "list|other", "app_still_open": true|false}',
        _back_native,
    ),
    Case(
        "TC07", "Tab Đánh giá: hàng chờ + mở một tài liệu", "Lab 2 · Đánh giá",
        "Mở tab 'Đánh giá'. Đọc số yêu cầu đánh giá đang chờ (dòng 'N yêu cầu đánh giá'). Bấm vào thẻ yêu cầu đầu tiên (không bấm 'Đánh giá ngay'), đọc tên tài liệu và tên dự án trên màn mở ra.",
        '{"waiting": n, "opened_document": "...", "project": "..."}',
        _reviews,
    ),
    Case(
        "TC08", "Thông báo", "Lab 2 · Thông báo",
        "Mở tab 'Thông báo'. Đọc số thông báo chưa đọc (dòng 'N thông báo chưa đọc') và chép nguyên văn tiêu đề 3 thông báo đầu. Không bấm vào thông báo nào.",
        '{"unread": n, "first_titles": ["..."]}',
        _notifications,
    ),
    Case(
        "TC09", "Hồ sơ tài khoản", "Lab 2 · Tài khoản",
        "Mở tab 'Tài khoản'. Đọc họ tên, email và vai trò của người dùng.",
        '{"name": "...", "email": "...", "role": "..."}',
        _profile,
    ),
    Case(
        "TC10", "Giá trị Remote Config trên màn hình", "Lab 3 · Remote Config",
        "Mở tab 'Tài khoản', cuộn xuống khu 'KHU VỰC DEMO LAB 3', tìm dòng 'Remote Config'. Đọc giới hạn tải lên (số MB) và danh sách loại tệp theo đúng thứ tự hiển thị.",
        '{"max_upload_mb": n, "file_types": ["..."]}',
        _remote_config,
    ),
    Case(
        "TC11", "Form tạo học kỳ để trống (nhánh lỗi validate)", "Nhánh lỗi · Form",
        "Mở tab 'Tài khoản', bấm mục 'Học kỳ', bấm 'Tạo học kỳ'. Để TRỐNG ô 'Tên học kỳ', bấm 'Lưu'. Chép nguyên văn dòng thông báo lỗi trên form, cho biết học kỳ có được tạo không, rồi bấm 'Hủy'.",
        '{"saved": true|false, "error_text": "..."}',
        _form_error,
    ),
    Case(
        "TC12", "Tạo học kỳ khi mất mạng → tự đồng bộ khi có mạng", "Offline sync (SQLite outbox)",
        "Mở tab 'Tài khoản', bấm mục 'Học kỳ', bấm 'Tạo học kỳ'. Gõ tên đúng là '{name}', ở 'Ngày kết thúc' chọn một ngày bất kỳ sau ngày bắt đầu, giữ nguyên các ô khác, bấm 'Lưu'. Đọc lại tên học kỳ vừa xuất hiện trong danh sách.",
        '{"created": "..."}',
        _offline_check,
        timeout=900,
        before=_offline_before,
        after=_offline_after,
    ),
]
