# Rà các script đo: những phép đo tự-làm-hỏng (2026-09-30)

Phạm vi: `docs/evidence/scripts/*.py` (20 file) + `tools/*.py`. Câu hỏi: còn phép đo nào
tự-làm-hỏng kiểu `grep '\r'` (khớp chữ `r`) hay bị escape che mất kết quả, và chúng có
che mất kết quả thật không.

Kết luận ngắn: **bốn lớp lỗi có thật, một trong đó nằm ngay trong script guardrail**.
Ba lớp còn lại là script đo chết giữa chừng / báo số sai. Có **hai lớp đo được là sạch**
(mục 5) nên lần sau không phải đo lại. Và chính lượt rà này cũng tự-làm-hỏng **năm phép
đo** (mục 6) — đó là phần đáng đọc nhất.

## 1. Lớp A — script đo chết vì console cp1258 (mất cả lượt, không chỉ mất dòng cuối)

Đo sống của prod console trên máy này (stdout là cp1258, không ép UTF-8, chỉ đọc exit code):

| ký tự | trong script nào | `print` trần |
|---|---|---|
| U+2713 `✓` | `otes_probe`, `otes_full_probe`, `r24_trace_classification` | **exit=1** |
| U+2265 `≥` | `hw_fk_probe` | **exit=1** |
| U+2192 `→` | `hw_vision_probe` | **exit=1** |
| U+1EA1 `ạ` | (tiếng Việt nói chung) | **exit=1** |
| U+00B7 `·` | cùng chỗ với `✓` | exit=0 (sống) |

Điểm chết người không phải là crash, mà là **vị trí** crash:

- `otes_probe` / `otes_full_probe` / `hw_fk_probe`: vòng in marker nằm **trước**
  `OUT.write_text(...)` → chết là mất **toàn bộ JSON của lượt**, và một lượt đã trả tiền
  LLM xong.
- `hw_vision_probe`: chết ở **`print` đầu tiên**, trước cả khi gửi request → script chưa
  làm gì đã đỏ.
- `r24`: JSON đã ghi trước nên chỉ mất phần tally in ra.

5 file có literal như vậy đi thẳng ra stdout mà không có guard; 7 file đã được thêm guard
trong lượt này (`if hasattr(sys.stdout, "reconfigure")` — đúng cách `AGENTS.md` chỉ).
Hai file khác (`hiswise_holdout_batch.py`, `otes_report_decompose.py`) **đã có** guard từ
trước — nên đây không phải luật mới, chỉ là luật chưa được áp đủ.

Đo được và ghi rõ để khỏi nghi oan: `goldset_instrument.py` có **rất nhiều** tiếng Việt
trong source (49× U+00E3, 88× U+1ED9…) nhưng **0** trong argument của `print` → nó không
chết. `probe_vision_reality.py` có U+1EF9 nhưng chỉ nằm trong regex `[A-Za-z0-9À-ỹ]`.

## 2. Lớp B — số báo sai: mẫu số và kênh lỗi

`otes_probe` / `otes_full_probe` in `UCs reviewed: {len(sample)}` và chia trung bình cho
`max(len(sample), 1)`, trong khi unit lỗi chỉ được `print(...)` ra stderr rồi `continue` —
**kênh lỗi không đi vào kết quả**. Đo bằng stub (2/5 unit trả 503):

| | trước | sau |
|---|---|---|
| dòng reviewed | `UCs reviewed: 5` | `UCs reviewed: 3 / 5 (failed: 2)` |
| Score avg | `3` | `6` |
| danh sách lỗi | (chỉ trên stderr) | in kèm trong aggregate + `failed[]` trong JSON |

Sai **gấp đôi** (3 thay vì 6) ở đúng chỗ người đọc báo cáo hay trích nhất. Cùng lớp:
`r25_class_vision.py` in `Pages probed: {len(PAGES)}` trong khi `results` chỉ append khi
thành công; `hw_fk_probe.py` in `Total FKs across 4 quadrants` trong khi
`if not png.exists(): continue` **im lặng bỏ qua** quadrant thiếu.

## 3. Lớp C — abort ở lỗi đầu tiên, vứt cả lượt

`hw_text_probe.py` và `hw_vision_probe.py` gặp `URLError` đầu tiên là `return 2`. Đo bằng
stub với unit **đầu** trả 503:

| | trước | sau |
|---|---|---|
| `hw_text_probe` | exit=2, `json_exists=False` — không unit nào được thử | exit=1, `json=valid`, `reviewed 2 / 4 (failed: 2)` |
| `hw_vision_probe` | `UnicodeEncodeError` (U+2192) ở print đầu | chạy hết, JSON hợp lệ |

Trạng thái "đã chạy nhưng không đo gì" và "chưa chạy" trước đây **không phân biệt được**;
giờ failure được ghi vào chính file JSON đó.

## 4. Lớp D — ghi cuối lượt vào `/tmp`, và trên Windows `/tmp` là `D:\tmp`

Bản trước của `hw_vision_probe` chết `FileNotFoundError: '/tmp/hw_vision_probe.json'` **sau
khi đã gọi LLM xong** (Python trên Windows đọc `/tmp` thành `<drive>:\tmp`; đo trực tiếp:
`os.path.abspath('/tmp')` → `D:\tmp`, còn Git Bash `cp /tmp/...` lại ghi vào
`…\AppData\Local\Temp`). 10 file đã thêm `OUT.parent.mkdir(parents=True, exist_ok=True)`
ngay trước lượt ghi.

Cùng lượt: 15 site ghi file trong 10 script đều đã khai `encoding="utf-8"` (quét bằng AST:
14 site có `encoding=`, 1 site là `json.dump` vào handle đã mở với `encoding="utf-8"`).
Lưu ý phân biệt hai mức: `Path.write_text(json.dumps(...))` **không** `encoding=` chỉ thật
sự chết khi payload có ký tự ngoài ASCII **và** `ensure_ascii=False` — đo được là nó ném
`UnicodeEncodeError` (cp1258). Với `ensure_ascii` mặc định (`True`) thì JSON là ASCII nên
defect này **tiềm ẩn**, không phải lời nói dối đang chạy. Vá vì rẻ, nhưng đừng ghi nó như
một bug đã gây hậu quả.

## 5. Lớp nặng nhất — `tools/check_guardrails.py` có thể **pass rỗng**

`index_blobs()` và `git_tracked_files()` gặp lỗi git thì `return []`; `main()` in
`All guardrails passed across {len(files)} files.` với `files` đến từ `rglob` (không qua
git). Đo: chạy với `PATH=/nonexistent` (git không tồn tại — đúng cảnh CI thiếu git):

| | trước | sau |
|---|---|---|
| git có trên PATH | 9/9 ok, **exit 0** | 9/9 ok, **exit 0** |
| git **không** có | 9/9 ok, **exit 0** — "passed across 719 files" | **exit 1**, 2 vi phạm `input-unavailable` (secrets, line endings) |

Luật "line endings" ở lượt đó đọc **0 blob** và được ghi là `ok`. Cùng họ lỗi còn hai chỗ
nữa đã vá: `cat-file --batch` parse dở (thiếu blob) trước đây `break` im lặng → giờ raise
nếu `len(blobs) != len(entries)`; `read_lines()` trả `[]` cho file không decode được UTF-8
→ giờ fallback `errors="replace"` để vẫn quét (file latin-1 chứa secret trước đây được
**bỏ qua trong im lặng**); và `collect_files()` rỗng thì từ chối in pass.

Hồi quy (đo lại đủ hai chiều):

- chèn 1 blob CRLF vào index (`git -c core.autocrlf=false add`) → `[FAIL] line endings`,
  `[line-endings] probe-crlf-tmp.dart:1`, exit 1 ✓ (không mất khả năng phát hiện)
- gỡ probe, cây sạch → 9/9 ok, exit 0 ✓ (không hồi quy)

Lệnh tái lập:

```sh
server/.venv/Scripts/python.exe tools/check_guardrails.py   # 9/9 ok, exit 0
PATH=/nonexistent server/.venv/Scripts/python.exe tools/check_guardrails.py   # exit 1
```

## 6. Những lớp đo được là SẠCH (đừng đo lại)

- **`grep/awk/sed` với needle CR: 0** trong cả hai thư mục. Và lượt quét của tôi cho ra
  **10 hit, cả 10 là dương tính giả** — vì `needle = chr(92) + 'r'` rồi dò bằng regex khớp
  luôn chữ `r` trong `from`, `fallback`, `results`. Tức cái bẫy `grep '\r'` mà `AGENTS.md`
  ghi đã tái hiện **trong chính script đi tìm nó**.
- **`^`/`$` mà thiếu `re.MULTILINE` trong `findall/finditer/sub/split`: 0.** Hai site từng
  bị gắn cờ (`table-position-probe-*.py`, `annotate_test_failures.py`) dùng `.match` theo
  từng dòng nên đúng.
- **`except` nuốt lỗi trong `tools/`**: 5 handler trong `check_guardrails.py` (đã xử ở mục
  5) + 1 handler trong `annotate_test_failures.py:43` in `::error::` ra log (nhìn thấy
  được, không phải nuốt).

## 7. Năm phép đo của lượt này tự-làm-hỏng (đọc trước khi tin bất cứ số nào ở trên)

1. **Harness tự sửa điều kiện đang đo.** Driver gọi `sys.stdout.reconfigure(utf-8)` ở đầu
   file → cùng process nên probe thừa hưởng stdout UTF-8, và bản BEFORE của
   `hw_vision_probe` **vượt qua** đúng cái `print` U+2192 mà nó phải chết ở đó (chết muộn
   hơn, bằng `FileNotFoundError`). Bỏ dòng reconfigure khỏi driver thì BEFORE mới chết đúng
   chỗ: `UnicodeEncodeError: '\u2192'`. **Harness phải tái lập điều kiện, không được cải
   thiện nó.**
2. **`$?` sau dấu `|`.** `python script.py | tail` rồi `echo $?` đọc exit code của `tail`,
   nên lượt đo "thiếu git" đầu tiên báo `exit=0` cho cả hai trường hợp — suýt thì kết luận
   ngược. Đo lại bằng redirect ra file rồi mới đọc `$?`.
3. **Đo chính cái mình vừa vô hiệu hoá.** Lượt đầu hỏi "ký tự này có crash không" bằng một
   script đã gọi `reconfigure(errors='replace')` → dĩ nhiên "in được". Đo lại bằng 4 tiến
   trình riêng, không reconfigure: cả 4 đều `exit=1`.
4. **Regex neo quá chặt → âm tính giả.** Quét "chia cho mẫu số" neo `//\s*len(sample)` nên
   bỏ sót đúng hai site thật (`score_total // max(len(sample), 1)`); kết quả 0 site báo cáo
   là "sạch" trong khi lỗi nằm ngay đó.
5. **Scan theo dòng cho cấu trúc nhiều dòng.** Cùng lúc báo "9 site ghi thiếu `encoding`"
   trong khi `encoding=` nằm ở dòng **đóng** của `write_text(json.dumps({...}, encoding=))`.
   AST mới đúng: 0 site thiếu.

## 8. Giới hạn của lượt đo này (nói rõ để không ai trích quá)

- Chạy end-to-end được 5 script (`otes_probe`, `otes_full_probe`, `hw_text_probe`,
  `hw_vision_probe`, `r24_trace_classification`) bằng stub **localhost port 8765** — không
  gọi LLM, không tốn quota, không đụng port 8000 (port đang bận, đã kiểm trước).
- `hw_fk_probe.py` **không chạy được ở đây**: nó gọi thẳng
  `generativelanguage.googleapis.com` bằng `GEMINI_API_KEY`. Lỗi `≥` của nó được chứng
  minh ở tầng cơ chế (in U+2265 ra console này → exit=1), không phải end-to-end.
- `hw_full_uc_probe` / `hw_vision_sweep` / `r25` / `r29` cần PNG/OCR tại đường dẫn máy tác
  giả (`/Users/lehuytuong/…`) nên chỉ xác nhận bằng `py_compile` + cùng hình dạng sửa.
- `ruff check docs/evidence/scripts` còn **8 lỗi, y như bản trước khi sửa** (F541…
  pre-existing, và CI không lint thư mục này vì CI đặt `working-directory: server`).
  `ruff check tools/check_guardrails.py`: `All checks passed!`

## 9. Bước CI mới: `tools/report_line_endings.py` (số CR theo từng file đổi)

Luật 9 chặn blob văn bản mang CR, nhưng "1 violation" không cho biết *vì sao* nó quan
trọng. Tool mới in, theo từng file của lượt push: CR trong worktree / blob base / blob rev,
số CR trần, và churn (`raw` so với `-w`) — tức khoảng cách giữa "một luật vừa đỏ" và "file
này sẽ biến mọi lần sửa một dòng về sau thành diff cả file". Nó được ghép vào job
`guardrails` của `.github/workflows/ci.yml` với `if: always()` (lượt push làm luật 9 đỏ
chính là lượt cần đọc số) và `fetch-depth: 0` trên checkout — mặc định depth 1 để
`github.event.before` lẫn `HEAD^` không resolve được.

Nó tách hai cơ chế, vì chỉ một trong hai là hiển nhiên:

| verdict | nghĩa |
|---|---|
| `blob-cr` | blob đang lưu mang CR → mọi diff về sau là diff cả file, `numstat` đếm mỗi dòng là vừa xoá vừa thêm |
| `blob-cr + N bare CR` | trong blob có N CR **không** theo sau LF → git đọc file là `-text`, và `autocrlf=true` **không bao giờ** chuẩn hoá nó (đúng cơ chế của `deterministic_finding.dart`) |
| `worktree-bare-cr` | CR trần mới chỉ nằm trên đĩa: cảnh báo sớm, vì lần `git add` tới là nó vào blob |
| `note: worktree CRLF, blob LF` | trạng thái bình thường của clone có `core.autocrlf=true` — **không phải lỗi**, không tính là fail |

Bốn cảnh đã đo:

| cảnh | kết quả đo được |
|---|---|
| `HEAD` vs `HEAD^` (lượt push thường) | 2 dòng; `wt_cr` của `AGENTS.md` = 88 nhưng `rev_cr` = 0 → `note`, exit 0 |
| `--rev 6f85c23^` (bản **trước** khi chuẩn hoá `deterministic_finding.dart`) | **exit 1**, `rev_cr=449`, `FAIL blob-cr + 4 bare CR in the blob` — tool tái lập đúng bug lịch sử |
| repo tạm: 1 file CRLF thuần + 1 file CR trần (commit với `core.autocrlf=false`) | **exit 1**, hai verdict khác nhau: `FAIL blob-cr: 3 CR` và `FAIL blob-cr + 1 bare CR` |
| base không resolve (`0000…0`; `HEAD^` ở repo một commit; git không có trên PATH) | base vắng → in rõ "measuring every tracked file … instead of just the changed ones"; git vắng → `NOT MEASURED` + **exit 1** |

Ba điều ghi lại để không phải đo lại:

- **`tools/` nằm trong `SKIP_DIRS` của `check_guardrails.py`** (đo: `tools` ∈ SKIP_DIRS),
  nên 8 luật nội dung **không quét chính thư mục của nó**; chỉ luật 9 phủ được, vì luật 9
  đọc index chứ không đi qua `collect_files()`. Một secret nằm trong `tools/` sẽ không bị
  luật secrets bắt.
- Ruff format trên `tools/` còn nợ **2 file** (`check_guardrails.py`,
  `annotate_test_failures.py`) và **cả hai đã nợ từ HEAD** — đo bằng cách format bản
  `git show HEAD:tools/…` ra thư mục tạm — không phải do lượt này.
- Trong repo có một file **rỗng tên `=`** được track từ 2026-09-15 (`git ls-files` khớp
  `=`); không phải của lượt này, nó chỉ lộ ra vì tool in mọi path trong bảng.

Lệnh tái lập:

```sh
python tools/report_line_endings.py                              # push thường
python tools/report_line_endings.py --rev 6f85c23^ --base $(git rev-list --max-parents=0 HEAD)
LINE_ENDINGS_BASE=0000000000000000000000000000000000000000 python tools/report_line_endings.py
```
