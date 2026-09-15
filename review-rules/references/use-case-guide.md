# Use case guide — include/extend và các trường khó của bảng use case

**Thêm ở rulebook 1.2** (2026-09-15). Amy chỉ ra hai chỗ sinh viên hỏng nhiều nhất: nhầm include/extend trong UC diagram, và không biết điền Preconditions / Post-conditions / Alternatives / Exceptions nên để "N/A". OTES hỏng cả hai (UC-05, UC-09, UC-16, UC-19).

Luận điểm của file này: **hai lỗi đó là một bệnh** — tách use case theo *nút bấm* thay vì theo *mục tiêu người dùng* (Cockburn: use case là goal của actor, không phải function của hệ thống). UC một bước thì không có nhánh để viết Alternatives; hàng chục UC vụn phải gom về một hub "Manage X" rồi không biết gọi mũi tên là gì. Chữa gốc là **gộp UC cho đúng cỡ** (3–7 transaction); include/extend và Alternatives tự đúng theo.

---

## Phần 1 — include, extend, generalization

### 1.1 Nghĩa theo UML 2.5

| Quan hệ | Nghĩa | Base có chạy được nếu bỏ nó? | Có điều kiện? | Chiều mũi tên |
|---|---|---|---|---|
| **«include»** | Hành vi của UC được include **luôn nằm trong** hành vi của base. Base **không hoàn chỉnh** nếu thiếu | **Không** | Không — luôn chạy | base **→** included (đường đứt, mũi tên hở) |
| **«extend»** | Hành vi của extension được **chèn vào** base tại một *extension point*, **khi điều kiện đúng**. Base **hoàn chỉnh** dù không có nó | **Có** | **Có** — phải ghi condition + extension point | extension **→** base (đường đứt, mũi tên hở) |
| **Generalization** | UC con là *một cách cụ thể* để làm UC cha (Pay by card ⊲ Pay) | — | — | con → cha, tam giác rỗng, đường liền |

Mẹo nhớ chiều: **mũi tên trỏ vào thứ không biết đến thứ kia.** Base *biết* mình cần included → base trỏ tới included. Base *không biết* có extension → extension trỏ tới base.

### 1.2 Ba câu hỏi quyết định — hỏi đúng thứ tự

Với mỗi cặp UC (A, X) mà sinh viên định nối:

**Câu 1 — X có đáng là một UC riêng không?**
X được dùng ở ≥ 2 UC khác nhau, **hoặc** X tự thân dài ≥ 3 transaction và có goal riêng? Không đủ một trong hai → **không tách**. Viết X thành step trong main flow của A. *Đây là câu bị bỏ qua nhiều nhất; 80% include/extend trong capstone không nên tồn tại.*

**Câu 2 — Bỏ X ra, A có hoàn thành goal không?**
Không → **«include»**. Có → sang câu 3.

**Câu 3 — X chỉ chạy khi có điều kiện gì đó?**
Có → **«extend»**, ghi rõ `Condition: {…}` và `Extension point: <tên>` trong compartment của A. Không có điều kiện mà A vẫn hoàn thành không cần X → X **không liên quan** A; nối X thẳng vào actor.

### 1.3 Sáu lỗi hay gặp — kèm ví dụ OTES

| # | Lỗi | Ví dụ thật | Sửa |
|---|---|---|---|
| 1 | **Đường liền có mũi tên giữa hai UC, không stereotype** | Figure 18: "Refresh student → Manage examination"; Figure 24–27: "Kick a student → Manage classroom" | Không phải quan hệ UML nào. Quyết theo §1.2; phần lớn rơi vào lỗi 2 |
| 2 | **Hub "Manage X" + n mũi tên** — functional decomposition | "Manage classroom", "Manage examination" xuất hiện ~10 hình, **không có bảng đặc tả** (UC-16) | "Manage X" không phải goal của ai. Hai cách: (a) bỏ hub, mỗi UC nối thẳng actor; (b) "Manage students" **là** UC thật, Import/Export/Delete là **alternative flows** bên trong nó — cách (b) đồng thời chữa "UC 1 bước" |
| 3 | **Dùng extend cho bước bắt buộc** | Figure 40 (Admin): mọi quan hệ đều «extend», kể cả Import/Export/Delete | Import students không thể xảy ra mà không có Upload Excel → «include», không phải extend |
| 4 | **Dùng include cho thứ có điều kiện** | Login «include» Forgot password (phổ biến) | Forgot password chỉ chạy khi user quên → «extend» Login, condition {user clicks Forgot} |
| 5 | **Login làm included UC ở mọi UC** | 20+ UC đều include Login | Đăng nhập là **precondition** ("User is signed in"), không phải include. Chỉ include khi UC thật sự chứa bước đăng nhập giữa luồng |
| 6 | **Chiều ngược** | «extend» vẽ từ base ra extension | Xem mẹo nhớ §1.1 |

### 1.4 Actor generalization — cái OTES thiếu

"Classroom user" xuất hiện trong 7 hình và 12 tên bảng nhưng không được định nghĩa (UC-15). Đúng cách: vẽ actor `Classroom user`, hai actor `Lecturer` và `Student` **tổng quát hoá lên** nó (tam giác rỗng trỏ về Classroom user), khai báo trong B.3. Mọi UC chung (Chat, Mute mic, Leave classroom) nối vào Classroom user; UC riêng nối vào actor con. Hệ ngoài (Jitsi, Quiznow) vẽ hộp `«external system»` hoặc actor có stereotype, **không** vẽ hình người.

### 1.5 Luật reviewer đếm được (bổ sung `uml25-diagram-policy.md` §8)

| Kiểm | Kết luận |
|---|---|
| Cạnh UC→UC đường liền hoặc không stereotype | red |
| «extend» không có condition hoặc extension point ghi ở đâu đó (compartment/note/bảng UC) | amber |
| «include» mà UC được include chỉ có **một** base và < 3 transaction | amber "inline vào base" |
| UC có ≥ 3 cạnh trỏ vào và **không có bảng đặc tả** | red (hub giả) |
| Cùng một UC được include ở ≥ 3 base **và** tên là Login/Authenticate | amber → chuyển thành precondition |
| Actor xuất hiện trong hình nhưng không có trong B.3 | red (UC-15) |

---

## Phần 2 — Các trường khó của bảng use case

### 2.1 Preconditions — trạng thái ĐÚNG trước khi bắt đầu

Là **assertion về trạng thái**, hệ thống tin là đúng và **không kiểm lại** trong main flow. Không phải trigger, không phải hành động.

| | Ví dụ |
|---|---|
| ✗ Sai — là trigger | "Lecturer clicks Create exam" |
| ✗ Sai — là hành động | "Lecturer logs in" |
| ✗ Sai — không kiểm được | "System is ready" |
| ✗ Sai — N/A | Mọi UC đều có ít nhất điều kiện về phiên và quyền |
| ✓ Đúng | "Lecturer is signed in" · "Lecturer owns subject class SC-01" · "Classroom status = ONGOING" · "Exam status = PUBLISHED and current time within exam window" |

Test: viết được thành `assert <biến> == <giá trị>` không? Không → không phải precondition.

### 2.2 Post-condition — Success (Cockburn: *success guarantee*)

Trạng thái hệ thống **sau khi main flow xong**: bản ghi nào thay đổi, giá trị nào, ai được thông báo. Tester kiểm bằng query hoặc quan sát.

| | Ví dụ |
|---|---|
| ✗ Sai — lặp lại tên UC | "Exam is created" |
| ✗ Sai — mô tả UI | "Success message is shown" |
| ✓ Đúng | "Exam record exists with status = DRAFT, owner = Lecturer, question_count = n" · "Attendance row for (student, schedule) has status = PRESENT" |

### 2.3 Post-condition — Fail (Cockburn: *minimal guarantee*)

Điều hệ thống **vẫn đảm bảo dù thất bại** ở bất kỳ exception nào: không có dữ liệu rác, rollback, log, người dùng đang ở đâu.

| | Ví dụ |
|---|---|
| ✗ Sai | "Show error message" (đó là step trong exception, không phải trạng thái) |
| ✓ Đúng | "No exam record created; entered form data retained on screen; failure logged with reason" |

Thiếu Fail = tài liệu không nói gì về tính toàn vẹn dữ liệu khi lỗi → amber (UC-07).

### 2.4 Alternatives vs Exceptions — ranh giới

| | Alternative flow | Exception |
|---|---|---|
| Kết quả | **Vẫn đạt goal**, hoặc đạt một goal hợp lệ khác | **Không đạt goal** |
| Ai gây ra | Lựa chọn của actor, hoặc trạng thái dữ liệu hợp lệ khác | Lỗi: validation, quyền, mạng, hệ ngoài |
| Ví dụ | Import: actor chọn nhập tay thay upload file · Take exam: đã có attempt chưa nộp → tiếp tục thay vì tạo mới | Import: file sai định dạng · Take exam: ngoài giờ thi; mất kết nối |
| Đánh số | `A1`, `A2` — "At step 3, if …: 3a … 3b … Resume at step 4" | `E1`, `E2` — mark `[Exception 1]` inline tại step; "UC ends" hoặc "resume at step N" |

**Khi nào "Alternatives: N/A" là thật?** Chỉ khi main flow **không có bất kỳ quyết định nào**. Nhưng UC không có quyết định thì gần như chắc chắn 1–2 bước → **quá nhỏ**, gộp vào UC khác. Luật: `Alternatives = N/A` **và** `steps < 3` cùng xuất hiện → amber "UC quá nhỏ, gộp", đếm vào `quality-rules.md` §E.

### 2.5 Step — ba luật

1. Mỗi hàng đúng **một** Actor Action **hoặc** một System Response. Không "Lecturer enters data and system saves" trên một hàng.
2. System Response phải **quan sát được**: hiển thị gì, lưu gì, đổi status gì. "System processes the request" (OTES p42) → không ai kiểm được.
3. Giá trị status đổi ghi tường minh: `sets status = PUBLISHED` — chuỗi này sau đó phải có trong data dictionary và state machine (chain 4).

Đếm transaction: một transaction = một vòng actor→system→phản hồi có nghĩa, **hoặc** một lần ghi DB. Login 3 bước = 3 transaction. "Click Get students → list shows" = 1 transaction → không đủ là UC.

---

## Phần 3 — Ví dụ viết lại từ OTES

### 3.1 UC "Take exam" (UC03, p31) viết đủ

OTES gốc: 4 step, Alternatives N/A, 2 exception, precondition có nhưng post-condition không nêu trạng thái dữ liệu. FR gốc có "Regains students attempt if the network has trouble" — đó chính là một alternative flow đang bị bỏ.

```
UC-003 · Take exam
Actor:        Student
Related FR:   FR-EXAM-02 (take exam), FR-EXAM-07 (resume attempt after disconnect)
Priority:     Must
Trigger:      Student selects a PUBLISHED exam in the current classroom.
Preconditions:
  - Student is signed in and is a member of the subject class.
  - Exam status = PUBLISHED and current time is within [start_time, end_time].
Relationships:
  - «extend» by UC-031 Flag suspicious behavior — condition {alt-tab or window blur detected}, extension point "during exam".

Main flow
| Step | Actor Action                                  | System Response                                                            |
|------|-----------------------------------------------|----------------------------------------------------------------------------|
| 1    | Student opens the exam                        | System creates Attempt with status = IN_PROGRESS, started_at = now [Exception 1] |
| 2    | Student answers questions                     | System autosaves each answer within 2 s of change                          |
| 3    | Student clicks Submit                         | System validates all required questions answered [Exception 2]             |
| 4    |                                               | System sets Attempt.status = SUBMITTED, submitted_at = now, computes score  |
| 5    |                                               | System shows confirmation with submitted_at and question count             |

Alternative flows
  A1 — Resume existing attempt (at step 1): if an Attempt with status = IN_PROGRESS exists for this student and exam,
       1a. System reopens that Attempt and restores saved answers. Resume at step 2.
  A2 — Time expires (at step 2): when now ≥ end_time,
       2a. System auto-submits the current answers. Continue at step 4.

Exceptions
  E1 — Attempt limit reached (step 1): exam.max_attempts already used → System shows "No attempts left"; UC ends.
  E2 — Unanswered required questions (step 3): System lists them; Student may return to step 2 or confirm submit → step 4.

Post-condition — Success:
  Attempt.status = SUBMITTED; every answer persisted; score computed; Lecturer can see the attempt in results.
Post-condition — Fail:
  Attempt remains IN_PROGRESS with all autosaved answers intact (resumable via A1); no score recorded; failure logged.
```

Đếm: 5 step → 5 transaction (trong 3–7). Alternatives có thật (2), Exceptions có thật (2), extend có condition + extension point, status vocabulary (`IN_PROGRESS`, `SUBMITTED`) sẵn cho state machine `SM-Attempt`.

### 3.2 Gộp 4 UC Admin thành một — chữa cả "UC 1 bước" và hub giả

OTES gốc: UC036 Get Students · UC037 Import Students · UC038 Export Student · UC039 Delete Student — mỗi cái 1 step, Alternatives N/A, cùng trỏ vào một hub không có bảng. Viết lại:

```
UC-036 · Manage students
Actor:        Admin
Trigger:      Admin opens Students page.
Preconditions: Admin is signed in with role = ADMIN.
Relationships: «include» UC-090 Upload Excel file (shared with UC-041 Manage lecturers, UC-057 Manage schedules).

Main flow (view — the goal every visit shares)
| 1 | Admin opens Students page          | System lists students (paged 50, sorted by code) with Import / Export / Delete actions |
| 2 | Admin filters by semester or class | System refreshes the list                                                              |

Alternative flows
  A1 — Import (at step 2): Admin clicks Import →  include::UC-090 Upload Excel file → System validates rows [E1]
       → System inserts new students, updates existing by code, shows summary (n inserted / n updated / n rejected). Resume at step 1.
  A2 — Export (at step 2): Admin clicks Export → System generates .xlsx of the current filter → browser downloads. Resume at step 2.
  A3 — Delete (at step 2): Admin selects students, clicks Delete → System asks confirmation → on confirm sets isdisable = true
       (soft delete) [E2]. Resume at step 1.

Exceptions
  E1 — Invalid rows: System rejects only invalid rows, lists row number + reason; valid rows still imported.
  E2 — Student has active enrolment: System refuses delete for that student, lists the class. Others proceed.

Post-condition — Success: Student table reflects the chosen action; audit row written (who, when, action, count).
Post-condition — Fail: No partial writes except those explicitly reported in the summary; audit row written with status = FAILED.
```

Từ **4 UC 1-bước + 1 hub giả + 4 mũi tên không tên** → **1 UC 2 bước + 3 alternative thật + 1 include có lý** (Upload Excel dùng chung ≥ 3 nơi). Số UC giảm nhưng số transaction thật tăng; gate ≥ 20 vẫn qua vì OTES có 63.

---

## Phần 4 — Nguồn

- OMG UML 2.5.1 §18 Use Cases — include (`Include`), extend (`Extend`, `ExtensionPoint`, condition); tóm tại [uml-diagrams.org — use case include](https://www.uml-diagrams.org/use-case-include.html) và [use case extend](https://www.uml-diagrams.org/use-case-extend.html)
- Alistair Cockburn, *Writing Effective Use Cases* (2001) — goal-level, success guarantee / minimal guarantee, extension numbering `3a`, "use cases are not functional decomposition"
- Ivar Jacobson, *Use-Case 2.0* (2011) — slice, tránh include/extend quá sớm
