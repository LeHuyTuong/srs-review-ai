# Hướng dẫn dán nhãn gold set — cho hai người chấm độc lập

**Viết cho:** hai người ký của WP7 (plan 12) · **Ngày tạo:** 2026-09-29 ·
**Sheet mẫu:** [sheet-template-2026-09-29.csv](sheet-template-2026-09-29.csv)

Bạn sắp làm việc quan trọng nhất của mốc này: hai sheet độc lập của hai người là
**nhãn vàng duy nhất** mà repo sẽ có, và là điều kiện để đo precision/recall của
engine. Plan 10 §3 nói nguyên văn: *"gold set là nơi người khác tự chấm; người tự
dán rồi tự chấm là chữ ký của một gold set vô giá trị"*. Không có đáp án nào nằm
sẵn trong sheet — cả **bốn** cột nhãn đang trống hoàn toàn, và không ai khác điền hộ
bạn.

## Trước khi bắt: ba điều cấm (đọc chậm)

1. **KHÔNG xem kết quả AI của tài liệu này trước khi dán nhãn** (không mở trang
   Báo cáo/lượt chấm OTES trong app). Xem rồi dán thì con số đo được là con số
   của một vòng lặp, không phải của hai người độc lập.
2. **KHÔNG đọc sheet của người kia** cho tới khi cả hai đã nộp. Trao đổi về
   *tiêu chí* thì được, về *từng dòng* thì không.
3. **KHÔNG sửa 5 cột máy** (`source_round`, `unit_id`, `unit_kind`, `stratum`,
   `text`). Sheet chỉ chấm tiêu chí trên **từng unit**; các unit này parse bằng
   parser 1.4.1, nên thân UC bị tách thành `SEC-…` là chuyện có thật trong nguồn —
   bạn chấm **đoạn văn bạn thấy**, đừng chấm giả định "đáng lẽ nó thành UC".

## Bốn bước làm

### Bước 1 — copy sheet, mỗi người một file

Sheet đã rút mẫu **một lần** (seed `20260927`, n=24, phân tầng
6/2/1/0/1/14 — tầng `business_rule` rỗng vì nguồn không có business rule nào).
Lấy mẫu hai lần với seed khác nhau sẽ cho hai tập dòng khác nhau và độ khớp
không tính được. Vì thế:

```
sheet-template-2026-09-29.csv  →  goldset-sheet-A.csv   (người A)
sheet-template-2026-09-29.csv  →  goldset-sheet-B.csv   (người B)
```

Mở bằng Excel/Google Sheets đều được (UTF-8, 9 cột, 24 dòng). Tiêu chí của
sheet này đã chốt là **`unambiguous`** cho mọi dòng — template để trống cả bốn
cột nhãn theo thiết kế, nên bạn **tự điền `unambiguous` vào `criterion_id` trên
từng dòng mình dán nhãn** (một dòng không rơi vào tiêu chí nào thì để trống
cột đó và ghi `note`).

### Bước 2 — điền bốn cột nhãn của mình

| cột | điền gì | luật |
|---|---|---|
| `annotator` | tên bạn (viết liền, không dấu cách đầu/cuối) | **A và B phải khác nhau** — trùng tên thì công cụ từ chối tính |
| `finding` | `present` hoặc `absent` | chỉ hai giá trị này; khác thì bị từ chối |
| `criterion_id` | điền `unambiguous` trên mỗi dòng bạn dán nhãn | template để trống — điền tay; dòng không thuộc tiêu chí nào thì để trống + ghi `note` |
| `note` | ghi khi lưỡng lự | không tính vào độ khớp — cứ ghi thẳng điều bạn không chắc |

**Định nghĩa tiêu chí `unambiguous`** (nguyên văn từ
`server/app/config/criteria.json`): *"The sentence is free of vague adjectives
and adverbs (quickly, user-friendly, appropriate, flexible, hỗ trợ tốt, dễ sử
dụng), undefined pronouns, and open-ended lists (etc., and so on, including but
not limited to)."*

Dịch ý: dòng dữ có **tính từ/trạng từ mơ hồ** (nhanh, thân thiện, linh hoạt,
hỗ trợ tốt, dễ sử dụng, tối ưu, hợp lý…), **đại từ không xác định** (người dùng,
họ, các bên liên quan mà không nêu cụ thể), hoặc **liệt kê mở** (vv., v.v.,
vân vân, such as… without limit) → `present`. Không có dấu hiệu nào trong ba
nhóm → `absent`.

### Bước 3 — dán nhãn thế nào cho khớp nhau

Quy tắc ra quyết định, áp **theo đúng thứ tự**:

1. **Tìm từ mơ hồ trước, đừng đánh giá tổng thể.** Câu hỏi chỉ là "có dấu hiệu
   mơ hồ không", không phải "yêu cầu này viết tốt không".
2. **Một dấu hiệu là đủ** để `present`. Không cần ba dấu hiệu mới kể.
3. **Lưu ý hai cái bẫy của tiếng Việt** (nguyên văn có trong nguồn):
   - dấu cách thừa trước dấu câu (`clear , intuitive`) — **không** phải mơ hồ;
   - `reminiscent` (GUI "nhớ lại điều gì") là từ mơ hồ thật — `present`.
4. **Danh sách tính năng trần trụi** (`● Manage a semester. ● Manage
   subject-class.`…) **không** mơ hồ: không có tính từ mơ hồ, không đại từ mơ hồ,
   không liệt kê mở → `absent`, dù nó cũng không phải yêu cầu tốt về mặt khác.
   Tiêu chí này **không** chấm tính đầy đủ hay kiểm chứng được — đó là
   `complete` / `verifiable`, hai tiêu chí khác.
5. **`etc.` / `vân vân` / `such as` mở tận cùng** → `present` (liệt kê mở).
6. Khi hai đọc đều hợp lệ và bạn thật sự không quyết được → dán nhãn theo **đọc
   đầu tiên của bạn** rồi ghi `note` rõ hai cách đọc. `note` không tính vào độ
   khớp, nhưng nó là dữ liệu cho vòng sau.

**Ba ví dụ tự chế (không nằm trong sheet, không phải đáp án):**

| text | finding | vì sao |
|---|---|---|
| `The system shall respond quickly to any search request.` | `present` | "quickly" — tính từ/trạng từ mơ hồ |
| `The system shall return search results within 2 seconds for 95% of requests.` | `absent` | có ngưỡng đo; không từ mơ hồ, không liệt kê mở |
| `The system shall support common document formats such as PDF, DOCX, etc.` | `present` | "common" mơ hồ **và** "etc." liệt kê mở — một dấu hiệu là đủ |

### Bước 4 — đo độ khớp, rồi (nếu đạt) precision/recall

Đã kiểm sẵn cho bạn: hai bản template **chưa điền** chạy `agreement` bị từ chối
với thông báo rõ ("không có tên người chấm ở cột `annotator`", exit 2) — nên đừng
ngạc nhiên khi chạy trước khi điền, và đó cũng là bằng chứng bộ guard hoạt động.

```bash
# cwd = gốc repo srs-review-ai/
python docs/evidence/scripts/goldset_instrument.py agreement \
    --a docs/evidence/goldset/goldset-sheet-A.csv \
    --b docs/evidence/goldset/goldset-sheet-B.csv
```

- **≥ 80% khớp và ≥ 20 dòng cả hai dán** → tin cậy (exit 0). Dưới ngưỡng → exit 1
  và **không có một con số precision nào được in** — đó là thiết kế, không phải lỗi.
- Hạ sàn bằng `--min-labelled` chỉ khi thật cần, và **phải ghi con số đã hạ** vào
  kết quả.
- Chỉ khi bước trên đạt mới chạy:

```bash
python docs/evidence/scripts/goldset_instrument.py score \
    --a docs/evidence/goldset/goldset-sheet-A.csv \
    --b docs/evidence/goldset/goldset-sheet-B.csv \
    --system docs/evidence/goldset/goldset-sheet-system.csv
```

`sheet-system` là sheet **engine** tự dán (cùng 24 dòng, cùng cột nhãn) — nói với
người chạy proxy/app để sinh; đừng tự dán hộ máy. Kết quả ghi vào
`docs/evidence/goldset/otes-unambiguous-<ngày>.md` theo AC-C của plan 10: nguồn
mẫu, số mẫu, tỉ lệ khớp hai người, precision, recall — **số nào cũng được, kể cả
kém**; giấu số kém là vi phạm hard rule 3 (honest boundary) của RULEBOOK.

## Nộp sheet ở đâu

Giữ đúng tên `goldset-sheet-A.csv` / `goldset-sheet-B.csv` trong
`docs/evidence/goldset/`, và **không ghi đè template** — lệnh `sample` cũng tự
từ chối ghi đè file tồn tại. Khi cả hai file đã nộp và `agreement` ra exit 0,
dòng "còn thiếu hai người ký" của WP7 trong `docs/plans/12-…md` mới được gỡ —
bởi chính người chạy, không phải bởi người ký.

## Câu hỏi nhanh

- **Tôi chấm sai một dòng, sửa lại được không?** Được, trước khi nộp. Sau khi
  `agreement` đã chạy và đã ghi kết quả thì không sửa — sửa sau khi đo là làm
  hỏng phép đo.
- **Dòng tôi không hiểu nội dung (thuật ngữ chuyên ngành)?** Vẫn dán nhãn theo
  dấu hiệu hình thức (từ mơ hồ / đại từ / liệt kê mở) — tiêu chí này chấm hình
  thức ngôn ngữ, không đòi hiểu nghiệp vụ.
- **Có cần chấm cả 24 dòng không?** Có. Sàn 20 dòng là tối thiểu để đo; bỏ trống
  phần khó là cách nhanh nhất để hai người "khớp" giả tạo.
