# Audit hai stash 2026-09-26 — cả hai nằm trọn trong `dev`, và một cái chứa 92 dòng import hỏng

**Ngày:** 2026-09-30 · **Repo:** `srs-review-ai`, nhánh `dev` (HEAD `3a9fc47`, đã push) ·
**Phạm vi:** toàn bộ `git stash list` — 2 mục, đều tạo 2026-09-26 khi nhánh còn tên `main` ·
**Kết luận:** không file nào, dòng nào trong hai stash mà `dev` không có. Ngoài ra `stash@{1}`
chứa 7 file test Dart **không biên dịch được** (92 dòng import hỏng), và **cả hai stash đều
không apply được**. Giữ lại để đối chiếu thì vô hại; `stash pop` là tự bắn vào chân.

## Hai mục cần kiểm

| stash | tiêu đề | base commit | delta của chính nó |
|---|---|---|---|
| `stash@{0}` | `WIP: docs + check_guardrails component-boundaries ADR` (26-09 08:30) | `86a695d` | 5 file, +193/−74 |
| `stash@{1}` | `WIP: app layering refactor (renames + import rewrites)` (26-09 00:21) | `e21e961` | 159 file, +633/−530 |

Cả hai base đều là ancestor của `dev`, tức công việc chúng mô tả **đã được làm tiếp và
commit** trên `dev` (`215da54` → `86a695d` cho refactor, ADR 0013 cho component boundaries).

## Phương pháp (lệnh tái lập)

```sh
git stash show --name-status 'stash@{0}'                 # path + kiểu thay đổi
git rev-parse "stash@{0}:$p" ; git rev-parse "HEAD:$p"   # blob từng path
git diff --diff-filter=D 'stash@{0}' HEAD                # có trong stash mà HEAD không có
git rev-parse 'stash@{0}^3'                              # có kẹt untracked file không
git stash show -p 'stash@{0}' | git apply --check        # còn áp được không (read-only)
git diff -w --numstat 'stash@{0}' HEAD -- "$p"           # chênh lệch *nội dung*, bỏ whitespace
git show 'stash@{0}:$p' | tr -cd '\r' | wc -c            # CRLF thật
```

Hai cổng chung, rỗng/fatal cho **cả hai** stash: `--diff-filter=D` **rỗng** (không file nào
thiếu ở HEAD) và `git rev-parse 'stash@{n}^3'` **fatal** (không stash nào có parent thứ 3 ⇒
không có file untracked nào bị kẹt bên trong).

## `stash@{0}` — 5 file, chỉ 2 dòng thuộc về nó

| file | stash vs HEAD |
|---|---|
| `docs/architecture-refactored.md` | **giống hệt** |
| `docs/arch-flutter-notes.md` | **giống hệt** |
| `docs/arch-server-notes.md` | **giống hệt** |
| `docs/adr/README.md` | HEAD +6/−1 |
| `tools/check_guardrails.py` | HEAD +65/−1 |

Hai dòng "−1" là hai dòng duy nhất thuộc stash mà HEAD không còn, và cả hai là giá trị HEAD
**cố ý đi qua**: `**Số tiếp theo: 0014.**` (nay `0019`) và `Seven rules:` (nay `Eight rules:`
— luật 8 full-screen surfaces là thứ thêm *sau*). HEAD là **superset thật** của stash này:
bản HEAD của guardrails còn có seam `TeacherStore` và `check_full_screen_surfaces()` mà
stash chưa hề có. `git apply --check` fail ngay trên context `Seven rules:`. → không có gì
để cứu.

## `stash@{1}` — 159 path: 130 blob giống hệt, 29 còn lại là dev đi trước

So từng blob: **130/159 giống hệt HEAD**. 29 file khác đều đọc ra được là *bản cũ hơn*:

| file | stash | `dev` |
|---|---|---|
| `workspace_view_model.dart` | 2.063 dòng, 1 class nguyên khối | 696 dòng façade (+7 controller) |
| `contradiction_pass.dart` | regex **ASCII-only** | regex bản ngữ `[A-ZÀ-Ỹ]…`, `_stem` delegate `CrossArtifactChecker.stemOf` |
| `api_service.dart` | — | `ApiException.detail`, `write()/get()` cho teacher |
| `criteria_manager.dart` | `Row` + `Expanded` | `Wrap` (vụ nút "Thêm tiêu chí" còn 28,2 px) |
| `deterministic_finding.dart` | 416 dòng, **LF** | 445 dòng, **CRLF** (449 byte CR) |

Dòng cuối là bài học đo lường: `git diff --numstat` báo **416 dòng bị xoá**, nhưng
`git diff -w` chỉ còn **31/2** — phần lớn "chênh lệch" chỉ là LF→CRLF. Đừng đọc numstat thô
thành "mất 416 dòng".

Cùng lớp đó: `findings_tab.dart`, `workspace_modals.dart`, `report_strings.dart`,
`review_models.dart`, `api_service_retry_test.dart` — mọi dòng chỉ-có-trong-stash đều là giá
trị cũ đã bị thay (`'Khớp chính xác'` inline → helper dùng chung; `kContractVersion = '1.0.0'`
→ contract version mới; `'contract_version': '1.0.0'` trong fixture test).

### 7 file test trong stash bị hỏng import (92 dòng)

| file trong stash | dòng hỏng |
|---|---|
| `app/test/blueprint_checks_test.dart` | 15 |
| `app/test/vision_review_service_test.dart` | 15 |
| `app/test/verdict_twins_test.dart` | 14 |
| `app/test/document_verdict_test.dart` | 12 |
| `app/test/format_layout_checks_test.dart` | 12 |
| `app/test/header_footer_checks_test.dart` | 12 |
| `app/test/quality_checks_test.dart` | 12 |

Dạng hỏng: `iiiiimimport 'package:…'`, `ort 'package:…'`, `port 'package:…'` — dấu vết một
script rewrite import chạy hỏng (đúng lớp lỗi "str_replace nuốt newline" mà `AGENTS.md` đã
ghi). Trên HEAD: `git grep -nE '^(i+im.*import|ort |port )' HEAD -- 'app/**'` → **0 file**,
working tree cũng 0. Tức 92 dòng đó là rác của lần rewrite, không phải nội dung bị mất.

## Bốn cái bẫy khi tự kiểm lại

1. **`grep '\r'` và `awk '/\r$/'` trên Git Bash không nhận ra CR** — chúng khớp chữ `r`.
   Lần đầu tôi kết luận sai chiều CRLF vì đúng chuyện này. Thước đo đúng:
   `tr -cd '\r' | wc -c`, hoặc `od -c` trên đuôi file.
2. **`git diff --numstat <stash> HEAD` đếm theo dòng, không theo nghĩa** — đổi line-ending
   làm cả file hiện ra như bị xoá sạch. Luôn chạy thêm `git diff -w`.
3. **`git stash show -p <stash> -- <path>` không nhận pathspec** (`Too many revisions
   specified`). Xem diff của stash trên một path: `git diff 'stash@{n}^1' 'stash@{n}' -- <path>`.
4. **`--diff-filter=D` rỗng một mình chưa đủ kết luận** — phải cộng với `^3` fatal và so
   blob, mới nói được "không file nào, untracked nào chỉ tồn tại trong stash".

## Cơ chế đằng sau bẫy #2 (đo được)

`git config --show-origin core.autocrlf` → `file:C:/Program Files/Git/etc/gitconfig	true`,
tức **mọi repo trên máy này** chạy autocrlf=true: working tree nhận CRLF lúc checkout trong
khi blob lưu LF. Đo 5 file bất kỳ (`review_models.dart`, `criteria_manager.dart`,
`providers.dart`, `workspace_models_test.dart`, `contradiction_pass.dart`): blob HEAD **CR=0**
nhưng working tree **344–861 byte CR** — đúng trạng thái bình thường đó, không phải lỗi.

Ngoại lệ duy nhất trên HEAD: `app/lib/deterministic_checks/models/deterministic_finding.dart`
— blob **có 449 byte CR / 445 dòng**, còn blob của stash là **0**. Đó là toàn bộ lý do numstat
báo 416 dòng bị xoá ở file này. Quét cả HEAD (`git grep -l -e "$(printf '\r')"` rồi lọc đuôi
nhị phân): **58 blob có byte CR nhưng chỉ 1 là văn bản** — chính file đó. Nên đây là ngoại lệ
đã đóng băng trong history, không phải chuyện thường; đừng suy ra "repo này CRLF".

## Nếu sau này muốn dùng lại nội dung

Đọc `git stash show -p`, **không** `pop`: cả hai fail `apply --check` — `stash@{0}` vì context
`Seven rules:` đã đổi, `stash@{1}` vì `app/lib/data/checks/*.dart: No such file or directory`
(đường cũ đã bị move). Muốn xoá thì `git stash drop` an toàn: không nội dung nào không tái
tạo được, và bản note này là bản ghi lại của phép kiểm.

Đã đóng gói thành `tools/audit_stashes.py` (2026-09-30): một lệnh là ra đúng bảng này, và nó
tái lập được từng số đo tay ở trên — 159 file (130 trùng / 29 khác), **92 dòng import hỏng trong
7 file**, apply fail, và `NOT CONTAINED` kèm **exit 1** khi stash chứa file mà HEAD không có
(đo bằng `git stash create` — commit dạng stash không đụng `stash list`).

## Cập nhật cùng ngày: cột CR hai bên, và bịt lỗ pass rỗng

Bảng theo từng file giờ kết thúc bằng hai cột, **cả hai phía** (`stash/HEAD`):

| cột | nghĩa |
|---|---|
| `CR st/HEAD` | mọi byte 0x0D. Blob mang CR làm mọi lần sửa một dòng về sau thành diff cả file, và `numstat` đếm mỗi dòng là xoá + thêm — chính là "416 dòng" ở bẫy #2 |
| `bare st/HEAD` | CR **không** theo sau LF. Một CR trần là đủ để git đọc file là `-text`, và autocrlf không bao giờ chuẩn hoá `-text` — cơ chế đã giữ 445 CRLF + 4 CR trần trong blob đó |

Đo trong repo tạm (`/tmp/le-stash`, commit với `core.autocrlf=false` để blob giữ CRLF), stash có
`a.dart` CRLF thuần, `c.dart` một CR trần, `b.dart` file mới:

```
  file    raw +/-  content +/-  CR st/HEAD  bare st/HEAD
  a.dart  3/3      1/1          3/0          0/0
  c.dart  2/2      2/2          1/0          1/0
  VERDICT: NOT CONTAINED -- 1 file(s) exist only in this stash
    missing in HEAD: b.dart
```

`a.dart` cho thấy hai mặt của cùng một chuyện: `CR st/HEAD = 3/0` (stash CRLF, HEAD LF) và churn
`raw 3/3` so với `content 1/1` — 3 dòng theo numstat nhưng chỉ 1 dòng theo `-w`. `c.dart` tách
riêng cơ chế CR trần: `bare 1/0` dù `content` sạch. Lượt đó exit 1 vì `b.dart` (đúng đường
`--diff-filter=D`).

**Bịt lỗ pass rỗng (đo trước khi vá).** Bản cũ nuốt mọi lỗi git: chạy ở thư mục không phải repo
→ `stash list` fail → danh sách rỗng → in `no stashes to audit` và **exit 0**. Bốn đường đo lại:

| cảnh | trước | sau |
|---|---|---|
| không phải git repo | `no stashes to audit`, **exit 0** | `stash audit NOT MEASURED: git stash list ... failed (128): fatal: not a git repository`, **exit 1** |
| `git` không có trên PATH | traceback | `NOT MEASURED: git not found`, exit 1 |
| stash list rỗng **thật** | không phân biệt được với dòng trên | `no stashes to audit (git stash list is empty)`, exit 0 |
| ref không tồn tại (`stash@{9}`) | `skipped` + exit 1 | như cũ |

`cat-file --batch` parse dở giờ raise thay vì `break` — nếu không, phần so blob sẽ báo
"identical" cho những blob chưa hề đọc. Cùng lớp với luật "input unreadable ≠ input empty" của
`tools/check_guardrails.py`; `git diff --diff-filter=D <stash> HEAD` cũng được nâng lên mức
bắt buộc, vì đó mới là phép đo quyết định verdict.
