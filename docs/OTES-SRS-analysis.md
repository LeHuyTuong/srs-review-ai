# Phân tích SRS OTES — tài liệu gốc 217 trang

## 1. Nguồn, phạm vi và giới hạn

- Nguồn: `/Users/lehuytuong/Downloads/OTES_officially_document.docx.pdf`.
- PDF: 217 trang, 28.701.674 bytes, có text layer, không mã hóa.
- SHA-256: `7bc9374ce0ad84a538060294bc1507b7e6b78a851ae8dca9e0e96b7eee608935`.
- Ngày phân tích: 2026-09-09, Asia/Saigon.
- Trang bìa ghi năm 2020; project information trang 11 ghi thời gian May 18–Nov 6, 2020. Không áp điều kiện syllabus SEP490 năm 2026 hồi tố để kết luận tài liệu này đạt/trượt.
- Đây là bộ capstone document, không phải 217 trang SRS thuần. Section C bắt đầu PDF 23; thuộc tính hệ thống ở 153–154, conceptual data dictionary kết thúc phần C ở 155 trước section D. SRS chiếm khoảng 133 trang có tính trang biên dùng chung.
- Các số trang dưới đây là **trang PDF 1-based**, không lấy số trong mục lục/list of tables vì các danh sách đó đã lệch. Đã đối chiếu các mốc C=23, D=155, E=182, F=194 với footer/trang trích xuất.
- Phân tích dựa trên text trích xuất, kiểm kê bảng UC và đọc các đoạn thiết kế/test liên quan. Model hiện tại không hỗ trợ đầu vào ảnh: các lần `read_image` bị từ chối. Đã render và OCR thử các trang 25,154,156,157,181,217; OCR overview trang 25 không đủ chất lượng và không được dùng để khẳng định quan hệ UML. **Chưa hoàn thành kiểm tra trực quan toàn bộ sơ đồ/ảnh**, không suy luận cardinality/mũi tên từ OCR.
- Phân công đọc text: một reviewer đọc PDF 22–98, reviewer khác đọc 99–155; phiên chính đọc phần bối cảnh, thiết kế/test/manual và đối chiếu trực tiếp các trang dẫn chứng trọng yếu. Hai reviewer báo đã xem một số hình, nhưng phiên chính không xác minh độc lập được ảnh nên không đưa kết luận về quan hệ UML từ các báo cáo đó.
- Đây là review đặc tả, không phải kiểm chứng phần mềm OTES đang chạy. Việc dự án bảo vệ thành công là thông tin người dùng cung cấp; không suy ra từ đó rằng mọi requirement hay test đều đúng.

## 2. OTES thực sự giải quyết việc gì?

OTES tích hợp lớp học trực tuyến và thi trong buổi học cho trường đại học/cao đẳng. Điểm khác một ứng dụng họp thông thường là lớp gắn với lịch học, thành viên lớp, quyền giảng viên, điểm danh, chia nhóm và chuyển sang chế độ thi.

Ba bề mặt sản phẩm:

| Bề mặt | Người dùng | Trách nhiệm chính |
|---|---|---|
| Desktop student | Sinh viên | Xem lịch, vào lớp, tương tác, chia sẻ màn hình có giảng viên chấp thuận, làm bài thi |
| Desktop lecturer | Giảng viên | Điều hành lớp, chia nhóm, quản lý media, điểm danh, tạo/giám sát thi, xuất điểm, xem lại video |
| Web admin | Quản trị | Quản lý sinh viên, giảng viên, học kỳ, môn học, lớp học phần, ghi danh và lịch |

Nguồn: trang 11–17, 23–24. `Classroom user` là nhóm hành vi chung cho người tham gia lớp; không nên tự coi đó là một tài khoản quản trị thứ tư. `Unauthorized` là trạng thái trước đăng nhập.

Phụ thuộc quan trọng (trang 15,21,31–32):

- **Jitsi**: nền tảng họp/streaming, không tự xây media server từ đầu.
- **QuizNow**: thi, trả điểm và các khả năng chống gian lận được mô tả.
- **OTES**: điều phối người dùng, lịch, lớp, mode, metadata và hiển thị kết quả.
- Tài liệu nêu .NET Core 3.1, Angular/Electron, CefSharp, MySQL; đây là stack lịch sử của OTES, không phải khuyến nghị mặc định cho app Flutter review SRS.

Luồng nghiệp vụ tổng hợp từ các UC:

```text
Admin chuẩn bị học kỳ/môn/lớp/thành viên/lịch
 → Người dùng đăng nhập Google, được định tuyến theo vai trò
 → Xem lịch và vào đúng lớp theo lịch
 → Class mode: audio/video/chat/share/điểm danh
 → Group mode: giảng viên phân nhóm, cô lập audio/video giữa nhóm
 → Exam mode: gửi đề qua QuizNow, theo dõi trạng thái, nhận/xuất điểm
```

Đây là bản tổng hợp luồng, không khẳng định tài liệu đã cung cấp state machine đầy đủ cho tất cả chuyển đổi.

## 3. Quy mô use case: đừng đếm unique ID một cách mù quáng

Đếm trường `Use Case No.` trong phần thân SRS, bỏ mục lục, caption và header lặp:

| Nhóm đặc tả | Số bảng |
|---|---:|
| Login | 1 |
| Student | 5 |
| Classroom user | 6 |
| Lecturer | 23 |
| Admin | 28 |
| **Tổng bảng đặc tả** | **63** |

Nhưng chỉ có **52 mã literal khác nhau**, hoặc **51 mã sau chuẩn hóa số** (`UC036` và `UC36` cùng số 36). Đây không phải 51 UC nghiệp vụ: định danh bị trùng/sai.

Ví dụ xác minh trực tiếp:

- `UC02`: Raise hand (29), Student share screen (37).
- `UC04`: View study schedule (33), Join classroom (35), Leave classroom (40), Chat (42), Change grid mode (44), Own microphone (46), Own camera (48), View participant (50).
- `UC021`: Close a group (66) và Kick a student (72–73). Tên bảng thứ hai xuống dòng thành `Use Case` / `Name`, nên regex chỉ nhận chuỗi `Use Case Name` liền nhau còn có thể lấy nhầm tên UC tiếp theo.
- `UC023`: Mute/unmute student microphone (70), Add student to classroom (76).
- `UC38`: Take attendance (78), Export Student (105).
- `UC036`/`UC36`: Drawing (80), Get Students (101).
- Refresh student có header `UC014` ở 55 nhưng trường mã `UC0134` ở 56; kick student out of group có header `UC014` nhưng trường `UC0114` ở 57.

**Ý nghĩa:** một parser dùng map keyed by UC ID rồi giữ bản dài hơn có nguy cơ mất requirement hợp lệ. Định danh nội bộ nên dựa trên vị trí tài liệu/section/occurrence; giữ nguyên mã nguồn và báo duplicate riêng. Không sửa ID gốc âm thầm.

63 bảng cũng không tự chứng minh 63 medium use case, 63 UC đã hoàn thành hay đủ điều kiện bảo vệ. Các khái niệm đó cần phân loại và evidence triển khai độc lập.

## 4. Điểm mạnh nên học

### 4.1 Phân rã theo vai trò và nghiệp vụ thực

Đặc tả không chỉ là danh sách màn hình: có lịch học, điều phối lớp, media giữa nhóm, điểm thi, trạng thái kết nối, dữ liệu admin. Các dependency thực tế được thừa nhận, phù hợp khả năng đội capstone.

### 4.2 Template UC khá đầy đủ

Các bảng thường có ID/version/priority, actor, summary, goal, trigger, precondition, postcondition, actor action/system response, alternatives, exceptions, relationships, business rules. Đây là cấu trúc tốt để review, dù điền đủ heading không đồng nghĩa nội dung đầy đủ.

### 4.3 Một số business rules có giá trị triển khai rõ ràng

- Lịch hiển thị `Not started`, nút Join, `Room expired`, `Not today` (34,97–98).
- Student share screen phải chờ lecturer chấp thuận (38).
- Thành viên khác nhóm không nghe/nhìn nhau; sinh viên mất kết nối quay lại nhóm cũ; người mới vào `none of group` (55).
- Kicked from group chuyển sang `none of group`, không mặc định bị đuổi khỏi lớp (58–59).
- Trạng thái thi gồm `Connected`, `Paper received`, `Submitted`, `Submitted Grade:` (86).
- Import schedules có yêu cầu xóa dữ liệu vừa import nếu lỗi (144); không được kết luận tài liệu hoàn toàn không đề cập rollback.

### 4.4 Có tài liệu downstream để kiểm tra nhất quán

Có thiết kế, data dictionary, UI field specifications, test cases và user manual. Chúng cho phép phát hiện khác biệt giữa requirement, thiết kế và kiểm thử, thay vì chấm từng câu rời rạc.

## 5. Findings ưu tiên, kèm bằng chứng

Mức ưu tiên dưới đây là đánh giá review, không phải điểm giảng viên.

### H1 — Trùng/sai định danh gây mất traceability

**Nguồn:** 29,33–50,55–57,66–78,80,101,105; xem mục 3.

Các chức năng khác nhau chia sẻ mã. Tác động: test mapping sai, review nhầm, parser overwrite. Cần tách stable internal ID khỏi source ID, lập bảng remap có người xác nhận. Đếm và cảnh báo, không tự gộp.

### H2 — Phạm vi quản lý dữ liệu tự mâu thuẫn

**Nguồn:** 17 so với 13 và 23.

Trang 17 phần `should not do`: “does not support managing schedules, lecturers’ and students’ information”. Trong khi admin requirements ghi chính các chức năng quản lý lịch, giảng viên và sinh viên.

Cần chốt in-scope, out-of-scope, delegated-to-external cho từng chức năng. Đây là mâu thuẫn nghiệp vụ mạnh, không chỉ lỗi tiếng Anh.

**Không gộp một false positive vào đây:** câu “does not score for the exam” ở 17 không nhất thiết mâu thuẫn việc hiển thị điểm; UC03 ở 32 nói nhận điểm từ QuizNow. Cần làm rõ ranh giới “tự chấm” và “nhận/lưu/hiển thị điểm”, không kết luận chắc chắn lỗi logic.

### H3 — Import ghi danh có nguy cơ làm mất dữ liệu, rollback chưa đủ rõ

**Nguồn:** UC46, 120–122.

Business rules ở 122 nói sẽ “remove all student class” hiện có khi import, và khi lỗi sẽ xóa các bản ghi vừa thêm.

Có cleanup không có nghĩa đã mô tả phục hồi dữ liệu cũ. Chưa rõ replace toàn hệ thống hay lớp/học kỳ được chọn, snapshot/transaction khôi phục gì, import trùng xử lý thế nào.

**Khuyến nghị:** xác định scope replace; validate toàn bộ file trước; commit nguyên tử; khi fail giữ dữ liệu trước import; trả lỗi theo dòng. Đây là yêu cầu đề xuất, không khẳng định OTES thực tế mất dữ liệu.

### H4 — Security/Reliability có heading nhưng không có nội dung

**Nguồn:** 153–154; Security và Reliability để trống giữa các heading có nội dung.

Có precondition theo role trong các UC, nhưng chưa đủ cho đặc tả chất lượng toàn hệ thống: phiên đăng nhập, quyền vào lớp, quyền media, quyền xem điểm/video, phục hồi lỗi dịch vụ.

UC03 yêu cầu mở camera và chống gian lận (32), lưu video tại máy giảng viên (93–94); cần mô tả thông báo/đồng ý theo chính sách áp dụng, ai xem, lưu bao lâu, bảo vệ/xóa bản ghi. Đây là khoảng trống requirement, không phải bằng chứng hệ thống đã vi phạm luật hay có lỗ hổng runtime.

### H5 — Luồng thi thiếu contract lỗi và tiêu chí hoàn tất đủ chặt

**Nguồn:** UC03 (31–32), UC027 (82–84), UC028 (85–86), interface (180–181), manual (217).

- UC03 postcondition success chỉ nói exam view xuất hiện, dù flow còn submit, nhận điểm và gửi lecturer.
- Submit fail chỉ thông báo chưa nộp; chưa rõ giữ bài, retry, chống nộp trùng, late submission, reconnect và nguồn thời gian.
- User requirements nhắc lấy lại attempt khi mạng lỗi (24), nhưng UC thi được dẫn chưa mô tả contract recovery đủ kiểm thử.
- Create exam nêu time start/end/duration; chưa có quan hệ validation giữa ba trường, giới hạn thời gian hoặc trường hợp ngoài slot.
- Flow ghi Mark Component là file (83), business rules nói chọn cột điểm (84), UI là dropdown (180). Cần thống nhất kiểu dữ liệu.
- QuizNow không sẵn sàng hoặc trả điểm trễ thì OTES chuyển trạng thái và thông báo thế nào chưa rõ trong các flow được dẫn.

**Đề xuất:** đặc tả state machine của exam/attempt, nguồn authoritative của score/submit, timeout và retry policy; không tự sáng tác ngưỡng rồi gán là requirement gốc.

### H6 — “Delete” chưa nhất quán giữa xóa vật lý và vô hiệu hóa

**Nguồn:** Delete schedule (145–146); đối chiếu Delete student in class (123) và Delete subject class (153).

Trang 146 flow nói xóa schedule khỏi database nhưng business rules nói schedule sau xóa có status `disable`; còn có câu “Delete a semester request” trong UC schedule. Các bảng khác có soft-delete rõ hơn.

Cần thống nhất hard/soft delete, dữ liệu lịch sử attendance/score, bản ghi tham chiếu và query filter. Đây là nguy cơ hai lập trình viên triển khai khác nhau.

### M1 — NFR có con số nhưng chưa đủ đo lường

**Nguồn:** 153–154.

- 90% người dùng thấy thoải mái: thiếu population, task và phương pháp khảo sát.
- Error 0.1%, serious error 0.01%: thiếu denominator và định nghĩa serious.
- 24/7: mô tả lịch cung cấp dịch vụ, chưa phải availability SLO có downtime budget.
- Average khoảng 2 giây cho mọi chức năng: thiếu workload, số lớp/sinh viên, mạng/phần cứng, phân vị và loại thao tác. Video streaming khác import file, không nên dùng một chỉ tiêu mơ hồ chung.

Đề xuất viết theo mẫu thao tác + điều kiện tải + metric + ngưỡng + cách test. Ngưỡng cụ thể phải được stakeholder chấp thuận.

### M2 — Tên/caption/goal có dấu vết copy-paste

**Nguồn:** 37–38,117–119,146,155,158.

- Share screen caption vẫn là Raise hand (37–38).
- UC044 tên Export nhưng summary/flow là Get list, BR lại nói download Excel (117–118); UC045 mới là export (119).
- Design overview gọi hệ thống “RLBR” (155), C# dictionary có caption “java server” (158).

Không kết luận về tác giả; đây là mismatch nội dung có thể kiểm tra. Ưu tiên những mismatch làm thay đổi hành vi hơn typo thuần túy.

### M3 — Nền tảng triển khai chưa thống nhất

**Nguồn:** 13,16–18,154,195–196.

Lecturer có nơi ghi Windows/macOS, có nơi thêm Linux. Server hardware ban đầu Ubuntu 18.04 nhưng installation requirements nói Windows/Windows Server; manual còn dùng Docker Linux container. Có thể là các môi trường khác nhau, nhưng tài liệu chưa phân biệt rõ dev/test/production và support matrix.

### H7 — Test evidence chưa bao phủ rủi ro đã mô tả

**Nguồn:** 187–194.

Trang 188 loại Login/Logout và nhiều admin import/export/delete khỏi phạm vi test. Bảng kết quả phần sau chủ yếu các thao tác lớp/thi; các ô Pass là kết quả được ghi trong tài liệu, không phải mình chạy lại. Mã MR bị dùng lại giữa nhóm lecturer và classroom user.

Cần trace Requirement → Rule → Test; ưu tiên quyền truy cập, import replace/rollback, mất mạng khi nộp bài, lệch state media giữa các mode, QuizNow timeout, dữ liệu lịch sử sau xóa. Không lấy số UC hoặc số ô Pass để tuyên bố đã kiểm thử đủ.

## 6. Những điều không nên kết luận quá tay

1. “Bảo vệ thành công” không đồng nghĩa SRS hoàn hảo; ngược lại, phát hiện lỗi tài liệu không phủ nhận thành quả dự án.
2. OTES **không thiếu toàn bộ xử lý reconnect**: group mode ở 55 đã có quy tắc quay lại nhóm cũ. Khoảng trống lớn hơn là lifecycle của exam attempt.
3. OTES **không thiếu toàn bộ rollback**: các import có đề cập cleanup. Vấn đề là tính nguyên tử, dữ liệu cũ và scope chưa rõ.
4. “Không tự chấm điểm” và “hiển thị điểm QuizNow” có thể hoàn toàn nhất quán.
5. Microphone unmuted trong exam (92) không tự chứng minh sinh viên nghe được nhau: trạng thái capture và quyền nhận audio là hai khái niệm khác nhau. Cần media routing matrix mới chốt được.
6. 63 bảng đặc tả không bằng 63 medium UC hoàn thành. Đừng biến F7 thành quyết định bảo vệ tự động.
7. Quote tìm thấy trong tài liệu chỉ chứng minh nguồn trích tồn tại; không chứng minh nhận xét AI đúng ngữ nghĩa.
8. Chưa xác nhận UML cardinality hay text–diagram mismatch vì chưa xem ảnh trực tiếp.

## 7. Bài học thực tế cho app review SRS của bạn

Giữ phạm vi **review requirement**, không phải xây lại hệ thống OTES.

### Ưu tiên 1: giữ đúng dữ liệu trước khi chấm

- Tách section C khỏi bộ capstone có nhiều report.
- Parser giữ UC xuyên nhiều trang, bảng nhiều cột, actor action/system response.
- Giữ raw source ID, occurrence ID, section path, page range và text spans.
- Cảnh báo duplicate/source-name mismatch, không xóa occurrence.
- 63 bảng / 52 literal ID / 51 normalized ID là fixture kiểm đếm từ nguồn này, không phải tự động sửa thành một con số “đúng” duy nhất.

### Ưu tiên 2: review theo hai cấp

- **Trong một UC:** thiếu trường, postcondition không đạt goal, exception không giải quyết lỗi, BR thiếu điều kiện, input không có validation.
- **Giữa các phần:** scope vs feature; UC vs UI; import/delete vs data dictionary; rule vs test. Review từng requirement cô lập sẽ bỏ qua các lỗi mạnh nhất của OTES.

### Ưu tiên 3: phân biệt luật chắc chắn với phán đoán

- Deterministic: ID trùng, heading rỗng, trường template thiếu, citation/page coverage.
- Heuristic: language, transaction estimate, độ testable, mâu thuẫn ngữ nghĩa.
- Human review: tính đủ của nghiệp vụ, hướng sửa, mức độ nghiêm trọng.

F9 không nên đếm động từ hay số dòng như transaction chính thức; OTES có UC action rất ngắn nhưng BR về mode/permissions phức tạp. F8 không được coi tên người Việt trong metadata là requirement không viết bằng tiếng Anh.

### Ưu tiên 4: finding có cấu trúc và có khả năng phản biện

```text
finding_id, kind, severity, confidence
source_locations[] = page + section + occurrence + quote
reason, impact, suggested_change
status = open / accepted / dismissed
```

Mâu thuẫn cần ít nhất hai vị trí dẫn nguồn. Missing requirement nên bám heading/flow hiện hữu và ghi “chưa thấy trong phạm vi X”, không tạo quote cho một câu không tồn tại. Export ghi coverage text/image và trạng thái provisional rubric.

### Bộ ví dụ đánh giá ban đầu

- True positives: UC04 trùng; Security/Reliability rỗng; UC044 Get/Export mismatch; scope quản lý dữ liệu mâu thuẫn; delete schedule ambiguity; import replace thiếu restore rõ ràng.
- Hard negatives: nhận điểm QuizNow không phải tự chấm; group reconnect đã được mô tả; import có cleanup; audio unmute không đồng nghĩa broadcast mọi người.
- Đánh giá: precision finding có người xác nhận, coverage UC, citation accuracy, lỗi bị bỏ sót. Không gọi tài liệu bảo vệ thành công là “golden clean SRS”. Đây là tài liệu benchmark thực tế cần gán nhãn.

### Ví dụ hướng sửa một requirement rủi ro cao

**Đề xuất cho UC46 — cần stakeholder xác nhận, không phải nội dung nguyên bản:**

> Admin nhập danh sách sinh viên cho lớp học phần đã chọn. Hệ thống kiểm tra toàn bộ file trước khi cập nhật. Chỉ thay thế ghi danh trong lớp học phần đó khi toàn bộ dữ liệu hợp lệ. Nếu kiểm tra hoặc cập nhật thất bại, giữ nguyên toàn bộ ghi danh trước thao tác và trả danh sách dòng lỗi. Ghi danh của lớp khác không thay đổi.

Các tiêu chí quan sát được: import thành công chỉ đổi lớp được chọn; lỗi giữa chừng không làm mất dữ liệu cũ; một dòng sai không gây cập nhật một phần; file có studentCode không tồn tại bị từ chối với số dòng. Chính sách duplicate/retry và có cho phép thay lớp đang thi hay không vẫn cần quyết định riêng.

## 8. Kết luận

OTES là ví dụ tốt về **phân rã chức năng cho một dự án tích hợp thực tế**, đặc biệt ở lớp học theo lịch và business rules chia nhóm. Yếu điểm lớn là **traceability, nhất quán giữa các phần, chất lượng NFR và xử lý lỗi nghiệp vụ quan trọng**.

Với app review của bạn, giá trị không nằm ở việc cho một điểm 7/10 không có căn cứ. Demo thuyết phục hơn là: tìm đúng một lỗi thật, dẫn cả hai trang, giải thích hậu quả, đề xuất sửa có giới hạn, đồng thời không báo nhầm những chỗ tài liệu đã xử lý đúng.
