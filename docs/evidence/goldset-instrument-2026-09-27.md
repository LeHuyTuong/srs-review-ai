# Bộ dụng cụ gold set — 2026-09-27 (WP7 của plan 12)

## Trạng thái: **dụng cụ xong, gold set CHƯA có**

| | |
|---|---|
| Bộ dụng cụ | `docs/evidence/scripts/goldset_instrument.py` — chạy được end-to-end |
| Test | `server/tests/test_goldset_instrument.py` — **36 test**, trong đó có test âm chứng minh ngưỡng 80% thật sự chặn |
| Nhãn vàng | **KHÔNG có.** Chưa ai dán, chưa ai ký |
| Số precision/recall | **KHÔNG có.** Không một con số nào trong repo (xem mục cuối) |
| Còn thiếu để đóng M2 | **hai người chấm độc lập** — việc cần con người, không phải code |

Plan 10 §3 nói nguyên văn: *"gold set là nơi người khác tự chấm; người tự dán rồi tự
chấm là chữ ký của một gold set vô giá trị"*. Vì thế WP7 **không thể hoàn thành một
mình**, và tài liệu này **không** tuyên bố nó đã hoàn thành. Nó chỉ nói: khi hai người
ngồi vào, mọi bước đo đã sẵn sàng, không phải viết thêm gì.

Công cụ **thuần stdlib**: không import `server/`, không cần API key, **không tốn quota**
và **không chạm cache thật** (có test `TestIsolation` giữ lời hứa đó — nó quét AST và
chặn mọi import `app.*`).

---

## 1. Hai người chấm: làm đúng bốn bước này

### Bước 1 — rút mẫu (làm **một** lần, rồi copy cho hai người)

Nguồn mẫu là một file JSON có mảng `units` đúng hình dạng `WorkspaceUnit.toJson()`
(`key, id, title, text, kind, section, pageIndex, malformed, selected, status`) — đây
chính là khoá `units` trong payload của một phiên đã chấm ở Lịch sử. File đó cũng nhận
khoá `rounds` nếu muốn trộn nhiều lượt (mỗi phần tử có `label` + `units`).

```bash
# cwd = gốc repo srs-review-ai/
python docs/evidence/scripts/goldset_instrument.py sample \
    --units <file-inventory.json> --out goldset-sheet-A.csv --n 24 --seed 20260927
```

Script in ra **số đếm theo từng tầng** và cách đếm (số unit mang một ID vs số ID khác
nhau — vì "63 bảng / 52 ID xuất hiện / 24 ID duy nhất" là ba con số khác nhau cho cùng
một tài liệu). Nó **từ chối** khi `n` nhỏ hơn số tầng khác rỗng, thay vì trả một mẫu bỏ
trống đúng những tầng khó.

> **Sao chép, đừng lấy mẫu hai lần.** Độ khớp chỉ tính được trên **cùng một tập dòng**.
> Lấy mẫu hai lần với hai seed khác nhau sẽ cho hai tập unit khác nhau ⇒ 0 dòng chung ⇒
> công cụ báo "không có dòng nào được cả hai dán nhãn" và từ chối (đúng như thiết kế).
> Cách làm: rút mẫu **một lần** ra `goldset-sheet-A.csv`, rồi copy thành
> `goldset-sheet-B.csv`.

### Bước 2 — mỗi người điền **file của mình**, độc lập

| cột | ai điền | giá trị |
|---|---|---|
| `source_round`, `unit_id`, `unit_kind`, `stratum`, `text` | máy | **không sửa** — cột `text` bị cắt ở 2000 ký tự |
| `annotator` | người | tên mình. Sheet A và B **phải khác tên** |
| `finding` | người | `present` hoặc `absent` — chỉ hai giá trị, giá trị khác bị từ chối |
| `criterion_id` | người | mã tiêu chí đang chấm, ví dụ `uc_count` (chain 1) |
| `note` | người | ghi chú khi lưỡng lự (không tính vào độ khớp) |

Không xem output của AI trước khi dán nhãn — xem rồi dán thì con số đo được là con số
của một vòng lặp, không phải của hai người.

### Bước 3 — đo độ khớp (ngưỡng 80%)

```bash
python docs/evidence/scripts/goldset_instrument.py agreement \
    --a goldset-sheet-A.csv --b goldset-sheet-B.csv
```

- Ngưỡng **80%** = `AGREEMENT_THRESHOLD` trong `goldset_instrument.py`, và là plan 10 §3
  bước 4 ("chỉ khi hai người khớp trên ≥ 80% mẫu thì mốc đó mới dùng làm gold").
- Sàn **20 dòng** = `MIN_LABELLED_SAMPLES` (plan 10 §3: "20–30 mẫu"). 100% trên 4 dòng
  không phải đồng thuận, mà là hai người cùng bỏ trống phần khó. Hạ sàn được bằng
  `--min-labelled` khi thật cần — nhưng cờ đó hiện trong `--help`, và nếu hạ thì phải
  ghi con số đã hạ vào tài liệu kết quả.
- Mã thoát: **0** = tin cậy được, **1** = chưa đủ tin cậy (đã từ chối), **2** = sai đầu
  vào.

### Bước 4 — precision/recall (**chỉ khi** bước 3 đã đạt)

```bash
python docs/evidence/scripts/goldset_instrument.py score \
    --a goldset-sheet-A.csv --b goldset-sheet-B.csv --system goldset-sheet-system.csv
```

Đặt kết quả vào `docs/evidence/goldset/<tài liệu>-<loại-finding>-<ngày>.md` theo AC-C của
plan 10: nguồn mẫu, số mẫu, tỉ lệ khớp hai người, precision, recall — **số nào cũng
được, kể cả kém**. Sheet đã ký sẽ không bị ghi đè: lệnh `sample` từ chối ghi lên file đã
tồn tại (thoát mã 2) trừ khi có `--force`.

---

## 2. Số đo: hai sheet **lệch nhau tự dựng** — đây KHÔNG phải gold set

Để chứng minh ngưỡng 80% thật sự chặn, test dựng hai sheet **do chính tôi viết ra** trên
10 dòng tự chế (`u01`…`u10`, tiêu chí `uc_count`), rồi đo:

| ca | số dòng khớp | tỉ lệ | kết luận của công cụ |
|---|---|---|---|
| B đánh ngược 4 dòng (`u03,u04,u07,u08`) | 6/10 | **60,0%** | `reliable=False` — `CHƯA ĐỦ TIN CẬY`, mã thoát 1 |
| B đánh ngược 3 dòng (`u01,u02,u03`) | 7/10 | **70,0%** | `reliable=False` — nêu rõ "dưới ngưỡng 80%" |
| A và B giống nhau, 10 dòng | 10/10 | 100,0% | vẫn `reliable=False` — **dưới sàn 20 dòng** |
| A và B giống nhau, 10 dòng, `--min-labelled 10` | 10/10 | 100,0% | `reliable=True` (chỉ khi hạ sàn **tường minh**) |
| Hai sheet không chung dòng nào | 0/0 | `None` | `reliable=False` — "0 dòng" **không** phải 100% |

**Vì sao 60% là con số đúng:** 10 dòng, mỗi dòng một nhãn `present`/`absent`; bốn dòng bị
người B đánh ngược lại thì bốn dòng đó bất đồng, sáu dòng còn lại trùng nhau ⇒
`agreed=6`, `disagreed=4`, `6/10 = 0.6`. Mẫu số là số dòng **cả hai** người dán nhãn;
dòng chỉ một người dán bị đếm riêng ở `unlabelled` và **không** được tính là đồng thuận
im lặng (có test riêng cho ca này: B để trống 4 dòng A đã dán ⇒ `unlabelled=4`).

Khi độ khớp dưới ngưỡng, `precision_recall()` ném `GoldSetNotReliableError` **trước khi
đọc sheet hệ thống**, và lệnh `score` thoát mã 1 **không in một con số nào** (test khẳng
định không có `precision=` và không có `TP=` trong output). Gọi `precision_recall()` mà
**quên** truyền kết quả độ khớp cũng bị từ chối — nếu không, đường tắt vòng qua ngưỡng
80% lại mở.

## 3. Những gì **chưa** có (nói thẳng, không lấp ô trống)

- **Không có sheet nào được ký.** Không có file nhãn vàng nào trong repo.
- **Không có số precision/recall nào.** Không phải "chưa công bố" — là **chưa đo**, vì
  chưa có nhãn vàng để đo.
- **Không có kết luận nào về độ chính xác của engine** trong tài liệu này, và không được
  rút ra từ 36 test ở trên: chúng kiểm tra **dụng cụ đo**, không đo engine.
- **AC-12.13** (bộ dụng cụ có test âm) — **đạt**, bằng chứng là test âm ở mục 2.
  **M2 / AC-C của plan 10 vẫn MỞ** cho tới khi có hai người ký.

## 4. Chạy lại mọi thứ trong tài liệu này

```bash
# 36 test của bộ dụng cụ (cwd = gốc repo)
cd server && .venv/Scripts/python.exe -m pytest tests/test_goldset_instrument.py

# cả bộ server
cd server && .venv/Scripts/python.exe -m pytest tests
```
