# Tổng kết hai phiên làm việc — SRS Review AI

**Ngày:** 2026-09-11 → 2026-09-12
**Trạng thái cuối:** `main` = `origin/main` = `f797e6b` · working tree sạch

---

## 1. Điểm xuất phát và mục tiêu

App Flutter chấm chất lượng tài liệu SRS (đồ án capstone FPTU). Yêu cầu: **review kiến trúc rồi
làm cho chạy được trên mobile**, kiểm thử trên Chrome và build APK.

Kết quả ban đầu của review: kiến trúc **8/10** (rất tốt), nhưng **mức sẵn sàng mobile 4/10**.

---

## 2. Những gì đã làm

### 2.1 Mobile unblock (cấu hình nền tảng)

| File | Thay đổi |
|---|---|
| `app/android/app/src/main/AndroidManifest.xml` | Thêm `uses-permission INTERNET`; thêm `android:networkSecurityConfig` |
| `app/android/app/src/main/res/xml/network_security_config.xml` | **Mới** — `base-config` chặn cleartext; `domain-config` chỉ mở cho `10.0.2.2`, `localhost`, `127.0.0.1` |

**Bug được chứng minh bằng công cụ:** manifest release cũ chỉ có
`DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`, **không có `INTERNET`** → APK release không thể gọi mạng.
Xác minh bằng `aapt2 dump xmltree` đọc trực tiếp bên trong APK.

Quyết định đáng chú ý: đặt config ở `main/` (không phải `debug/`) để APK release cũng chạy được,
nhưng **chỉ mở cleartext cho đúng host dev**, không mở toàn cục.

### 2.2 P1 — làm cứng kiến trúc (4 mục)

| Mục | Thay đổi |
|---|---|
| Tách domain enum | `ReviewStage`/`ReviewProgress`/`ReviewRun` → `data/models/review_progress.dart`; `LoadedDocument` → `data/models/loaded_document.dart`. Thêm luật guardrail `view-no-repositories` |
| `WorkspaceUnit` bất biến | 4 field `non-final` → `final`; thêm `copyWith`; `classify()` → `classified()` |
| Parse trong isolate | `ParseService` dùng `compute()` — hết đứng hình UI với file 28 MB |
| Bỏ state trùng | `DocumentRepository` stateless (bỏ `_current`, `updateRubric`, `clear`) |

### 2.3 P2 — dọn dẹp và hoàn thiện

- Xoá `/legacy/*` và 2 feature (5 file, ~940 dòng) — chỉ còn feature `workspace` (48 → 43 file)
- Xoá field `WorkspaceDestination.route` (chết + sai giá trị)
- `ref.watch` → `ref.read` ngoài `build()`
- **Retry cho dio** (`_withRetry`): chỉ retry lỗi transient, **không** retry 429/422/khi đã huỷ;
  `isProxyUp()` cố tình không retry để pill trạng thái phản hồi ngay

### 2.4 Sửa lỗi a11y sidebar (đáng nhớ nhất)

**Triệu chứng:** screen reader không tới được cột điều hướng trên web.

**Nguyên nhân gốc (không phải thiếu nhãn):** `navigationShell` là một `Navigator` lồng; modal
barrier của nó đánh dấu *"đang chặn semantics của node vẽ trước"*. Cờ này leo ngược lên cây render
tới `Row` của `Scaffold.body` (không có semantic boundary nào) và tại đó xoá sạch mọi sibling —
tức toàn bộ sidebar. Chứng minh bằng thí nghiệm: thay `navigationShell` bằng `Text` thường thì
nhãn hiện lại ngay.

**Cách sửa:** bọc branch content bằng `Semantics(container: true, explicitChildNodes: true)`.

### 2.5 Merge vào `main`

```
ff132e9  Merge branch 'dev'                  (0 conflict)
56a0133  Merge branch 'fix/run-review-cta'   (1 conflict, giữ cải tiến cả hai bên)
5f3efb3  test: import LoadedDocument...
0686426  fix(design-tokens): AppRadius.boxMd
1fd6c59  test: scroll past floating top bar
f797e6b  style: dart format + ruff format
```

Conflict ở `findings_tab.dart` được giải bằng cách giữ **cả hai** cải tiến: null-guard + badge
"N accepted" + tint (từ `dev`) và nhãn `AI review via proxy` + comment (từ branch CTA).

Đã push: `4eaeff4..f797e6b main -> main`.

---

## 3. Kiểm thử — kết quả

| Hạng mục | Kết quả |
|---|---|
| App test | **188/188** (từ 103 lúc bắt đầu) |
| Server test | **50/50** |
| `flutter analyze` | Sạch |
| `dart format --set-exit-if-changed` | OK |
| `ruff check` / `ruff format --check` | All passed / 19 files formatted |
| Guardrails | Pass (172 files) |
| Build web / APK | Cả hai OK (APK 58,6 MB) |
| Import file thật trên Chrome @1077×909 | ✅ 8 unit → modal mở → `Review 8 units` → 0 lỗi |
| Đường Gemini thật (Ask document) | ✅ `gemini-3.5-flash`, 3 trích dẫn *Exact match* |

---

## 4. Các bài học kỹ thuật đáng giữ

1. **`StatefulShellRoute`/`Navigator` lồng:** luôn bọc branch content bằng
   `Semantics(container: true, explicitChildNodes: true)`,否则 cờ blocking sẽ "ăn" mất sidebar.
2. **`cmd | tail; echo $?`** cho exit code của `tail` — từng đọc nhầm 3 lần.
3. **`grep` BSD không hỗ trợ `\|`** — gây ra 5 kết luận sai trong phiên này. Dùng `grep -E`.
4. **Khi test fail nhưng console 0 lỗi:** nghi ngờ script trước, đừng vội kết luận app hỏng.
5. **Đo thay vì đoán:** dùng scratch test in trực tiếp state/rect đã phủ định 5 giả thuyết sai.
6. **Playwright để lại `chrome-headless-shell`** chiếm RAM — dọn bằng `pkill -f chrome-headless-shell`.
7. **Import file trong Flutter web:** input ẩn không tồn tại sẵn, phải bắt `expect_file_chooser`.

---

## 5. Tình trạng CI

Workflow `CI` trên GitHub đang **`disabled_manually`** (tắt thủ công) — vì vậy push không kích hoạt
CI, và remote báo *"Bypassed rule violations — 3 of 3 required status checks are expected"*.

Đã sửa format để **khi bật lại là xanh ngay** (5/5 bước CI đều pass khi đo local).

Bật lại: `gh workflow enable CI`.

---

## 6. Việc còn lại (cần quyết định)

1. **Bật CI** khi muốn (`gh workflow enable CI`).
2. **Dọn file chưa track:** `block1–6.mmd/.svg` (12 file), `docs/arch-flutter-notes.md`,
   `docs/arch-server-notes.md`, `docs/architecture.md`.
3. **APK ký bằng debug keystore** (`CN=Android Debug`) — cần tạo keystore riêng trước khi phát hành.
4. **Test native trên thiết bị thật** — chưa làm được: máy không có Xcode và không có
   Android system-image (phải tải ~1–2 GB hoặc Xcode ~30 GB).
5. **Server preview** `127.0.0.1:8450` đang chạy.
