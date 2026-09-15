# Use case template — bảng Step | Actor Action | System Response

Một UC = một bảng. Mọi trường bắt buộc trừ khi ghi (optional). Reviewer chấm từng trường theo cột "Check". **Cách điền các trường khó** (Preconditions, hai Post-condition, Alternatives vs Exceptions, khi nào N/A là thật) và **hai ví dụ viết lại từ OTES** → `references/use-case-guide.md` §2–§3.

| Trường | Nội dung | Check |
|---|---|---|
| **UC ID** | `UC-NNN`, cố định từ pass đầu | đúng mẫu, không trùng (`duplicateIds`) |
| **Name** | Động từ + đối tượng: "Submit assignment" | không phải danh từ ("Assignment") |
| **Actor(s)** | Primary actor; secondary nếu có | tồn tại trong Use Case diagram và B.3 (`missingActor`) |
| **Related FR** | `FR-<EPIC>-NN`, ≥ 1 | có trong D; vào RTM |
| **Priority** | Must / Should / Could / Won't (hoặc High/Med/Low nhất quán toàn tài liệu) | có (`missingPriority`) |
| **Trigger** | Sự kiện bắt đầu | 1 câu, có actor |
| **Preconditions** | Trạng thái kiểm tra được TRƯỚC khi chạy | mỗi dòng đo được ("User is logged in as Lecturer") |
| **Main flow** | bảng 3 cột dưới | 3–7 transaction (`ucSize`); mỗi step 1 hành động |
| **Alternative flows** | nhánh hợp lệ khác main (`A1`, `A2`…), ghi step rẽ + step quay về | ≥ 1 nếu UC có quyết định; mỗi A có "resume at step N" |
| **Exceptions** | lỗi (`E1`, `E2`…), tương ứng mark `[Exception N]` inline | số E == số mark; mỗi E có hành vi hệ thống + kết thúc |
| **Post-condition — Success** | trạng thái đo được sau khi xong | có (`missingPostcondition`) |
| **Post-condition — Fail** | trạng thái sau khi exception; dữ liệu rollback? | có — thiếu = amber |
| **Business rules** (optional) | `BR-NN` tham chiếu | tồn tại nếu trích |
| **Relationships** | `«include» / «extend» / generalization tới UC nào` | tồn tại trong UC diagram; điền "N/A" ở > 50% số bảng → red (quality-rules §E) |
| **Notes / Open issues** (optional) | | không chứa TBD trong bản nộp |

**Chia nhóm cho việc chấm** (`scoring.md` §1b): 5 trường **Preconditions, Post-condition Success, Post-condition Fail, Alternative flows, Exceptions** do thành phần "Use case chất lượng" chấm. 8 trường còn lại — **UC ID, Name, Actor, Related FR, Priority, Trigger, Main flow, Relationships** — do tiêu chí sàn S4 chấm. Không trường nào bị chấm hai lần.

## Main flow

```
| Step | Actor Action                                    | System Response                                              |
|------|-------------------------------------------------|--------------------------------------------------------------|
| 1    | Lecturer selects "Create quiz" on course page   | System displays quiz form with default duration 30 min       |
| 2    | Lecturer enters title, duration, questions      | System validates fields [Exception 1]                        |
| 3    | Lecturer clicks "Publish"                       | System saves quiz, sets status = PUBLISHED, notifies students |
```

Luật cột:
- Mỗi hàng đúng **một** Actor Action **hoặc** một System Response (hàng chỉ có 1 cột điền được nếu là bước hệ thống tự làm).
- Actor Action bắt đầu bằng tên actor + động từ. System Response bắt đầu bằng "System".
- `[Exception N]` đặt **inline** ở đúng cell phát sinh, không chỉ ở cuối bảng.
- Không mô tả UI chi tiết (màu nút, vị trí) — đó là mockup, không phải UC.
- Không có bước "System does nothing" / "System processes" (unclear scope — `ambiguousWording`).
- Giá trị status ghi trong System Response (`status = PUBLISHED`) phải khớp data dictionary F.1 → sau này khớp State machine trong SDS.

## Ví dụ Exception

```
E1 — Validation failed (at step 2)
  System highlights invalid fields with message per field; Lecturer stays on form.
  Post-condition (Fail): no quiz record created.
```

## Đếm transaction (`ucSize`, syllabus 3–7)

Transaction = 1 tương tác người dùng có phản hồi hệ thống, hoặc 1 DB write. Ví dụ trên = 3. UC < 3 → nghi "quá nhỏ, gộp vào UC khác?"; > 7 → nghi "tách?". Chỉ amber.

**Alternatives = N/A và steps < 3 cùng lúc** → đây là cùng một bệnh (UC tách theo nút bấm): amber "UC quá nhỏ, gộp", đếm vào `quality-rules.md` §E. Cách gộp: `use-case-guide.md` §3.2.
