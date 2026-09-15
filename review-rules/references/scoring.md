# Scoring — thang 10 điểm artifact-level, severity, gate

**1.5** (theo `RULEBOOK.md`; lịch sử: v0.2 thay thang all-or-nothing của v0.1 bằng **chấm liên tục** · v0.2.1 thêm **luật một-chỗ** §1b sau khi kiểm chéo phát hiện v0.2 vẫn đếm hai lần ở 7 chỗ khác · 1.1 thêm chain 7 · 1.5 thêm D3 ×2 và D4 = n/a). Lý do đổi ghi ở §7; đừng sửa lại về all-or-nothing mà không đọc mục đó, và đừng thêm tiêu chí mà không đọc §1b.

Cùng hình dạng `5 + 2 + 2 + 1` với `app/lib/features/workspace/models/document_verdict.dart`, nhưng **cách tính từng thành phần khác app** — xem §9.

## 1. Severity

| Mức | Nghĩa | Ảnh hưởng điểm | Ví dụ |
|---|---|---|---|
| **red** | Sai làm tài liệu không dùng được / mâu thuẫn logic / vi phạm hard rule | **Gián tiếp**: kéo tỉ lệ của thành phần chứa nó xuống. Không trừ trực tiếp (xem §7). | FK không đường nối; include ngược chiều; NFR không số |
| **amber** | Thiếu / mơ hồ / nghi ngờ, sửa được trong 1 buổi | Gián tiếp, trọng số nửa của red trong công thức tỉ lệ | thiếu multiplicity; thiếu guard; caption sai tên loại |
| **info** | Nghi vấn cần người quyết (necessary/feasible/correct) | Không ảnh hưởng | "UC-021 có cần không?" |

Trừ điểm trực tiếp **chỉ** đến từ hard rule **không có thành phần điểm nào đo** (§6).

## 1b. Luật một-chỗ (thêm ở v0.2.1 — đọc trước khi sửa bất kỳ tiêu chí nào)

> **Mỗi khuyết điểm được chấm đúng MỘT lần, ở MỘT chỗ.**

Đây là luật khó giữ nhất của cả rulebook. Bản v0.1 vi phạm nó bằng cách trừ −1/red **sau khi** red đã kéo thành phần xuống. Bản v0.2 đầu tiên vẫn vi phạm ở 7 chỗ khác (kiểm chéo 2026-09-15): NFR không định lượng bị tính 3 lần (S5 + thành phần NFR + hard rule 6), RTM bị tính 3 lần (kiểm kê mục + thành phần RTM + hard rule 7), ADR 3 lần, ảnh bên thứ ba 4 lần.

Ba hệ quả bắt buộc, đã áp vào §3–§6:

1. **Kiểm kê mục (S1, D1) bỏ qua mục nào đã có thành phần điểm riêng.** RTM có thành phần +1 → không đếm trong S1/D1. ADR có tiêu chí D2 → không đếm trong D1.
2. **Hard rule chỉ phạt khi không thành phần nào đo được nó** (§6). Rule 4 → D3 đo; rule 5 → D2 đo; rule 6 → thành phần NFR đo; rule 7 → thành phần RTM đo **và** kéo theo NOT DONE. Bốn rule này **không phạt điểm**. Chỉ rule 9 và 10 phạt, vì không tiêu chí nào đo chúng.
3. **Một trường/hình chỉ thuộc một tiêu chí.** S4 chỉ xét trường bắt buộc mà thành phần khác không chấm; thành phần diagram loại trừ ảnh chụp màn hình mà hard rule 9/10 đã xử.

**Cùng một chỗ trong tài liệu có thể mang nhiều khuyết điểm KHÁC NHAU.** Luật cấm chấm *cùng một khuyết điểm* hai lần, không cấm chấm hai khuyết điểm khác nhau nằm cùng một trang. Ví dụ mục "5.1 User Interface Design" của OTES mang ba khuyết điểm tách rời: (a) thiếu API contract và validation rule → D1 hạ 0.5; (b) không trả lời câu HOW nào → D3 đếm là không-HOW; (c) trình bày màn hình của Google/Jitsi làm thiết kế của nhóm → hard rule 10. Ba lỗi, ba chỗ chấm, không trùng nhau. Nếu không tách được thành ba câu hỏi khác nhau thì đó là đếm trùng.

Khi thêm tiêu chí mới: trước khi thêm, tìm xem **khuyết điểm đó** (không phải vị trí đó) đã bị chấm ở đâu chưa. Nếu rồi thì không thêm.

## 2. Nguyên tắc chấm liên tục

Mọi thành phần điểm là **tỉ lệ đạt × điểm tối đa**, không phải đạt/không đạt.

```
điểm thành phần = (Σ điểm từng tiêu chí con / số tiêu chí con) × điểm tối đa
```

Mỗi tiêu chí con cho một số trong [0, 1]:
- Đếm được → tỉ lệ thật (`18/63 = 0.29`), làm tròn 2 chữ số, **phải ghi phân số trong verdict**.
- Không đếm được → chỉ 3 mức: `0` (không có), `0.5` (có nhưng thiếu/sai), `1` (đạt).

Mọi phân số phải truy được về một dòng trong ledger (hard rule 8). Không ghi "khoảng".

## 3. SRS — 0–10

### Sàn (5 điểm) — 5 tiêu chí con, trọng số bằng nhau

| # | Tiêu chí | Cách đo |
|---|---|---|
| S1 | Khung A–F đủ mục | (mục có nội dung thật, nửa vời = 0.5) / **16 mục**: A.1–A.5, B.1–B.5, C.1–C.3, D, E, F.1. **F.2 RTM không đếm ở đây** — đã có thành phần +1 riêng (luật một-chỗ §1b) |
| S2 | ID hiện diện, duy nhất, đúng mẫu | 0.5 × (số artefact có ID / tổng FR+UC+NFR) + 0.5 × (số ID vừa duy nhất vừa đúng mẫu / tổng) |
| S3 | Ngôn ngữ tiếng Anh | 1 hoặc 0 (bỏ qua tên riêng người/địa danh) |
| S4 | Không placeholder / "N/A hàng loạt" **ở trường không ai chấm** | 1 − (trường bị điền placeholder hoặc N/A ở > 50% bản ghi / **8 trường**: UC ID, Name, Actor, Related FR, Priority, Trigger, Main flow, Relationships). Năm trường Preconditions / Post-Success / Post-Fail / Alternatives / Exceptions **loại trừ** — thành phần "Use case chất lượng" đã chấm. Xem `quality-rules.md` §E |
| S5 | Tỉ lệ **FR** sạch | 1 − (số **FR** statement mang ≥ 1 red từ tính chất 2–5 / tổng FR). **NFR không tính ở đây** — đã có thành phần +2 riêng |

### Cộng điểm

| Thành phần | Max | Tiêu chí con (trọng số bằng nhau) |
|---|---|---|
| Use case chất lượng | 2 | tỉ lệ UC có Preconditions · có Post-Success · có Post-Fail · có ≥1 Alternative · có ≥1 Exception · **nằm trong 3–7 transaction** |
| NFR + data dictionary | 2 | tỉ lệ NFR có số **và** điều kiện đo · tỉ lệ NFR có ID · tỉ lệ 8 CAT ISO 25010 có ≥1 NFR không rỗng · độ đầy cột của data dictionary (cột có / 8 cột chuẩn) · tỉ lệ entity trong UC có entry trong dictionary |
| RTM FR↔UC | 1 | 0.5 × (1 − orphan FR/tổng FR) + 0.5 × (1 − orphan UC/tổng UC); **không có RTM → 0** (luôn 0, không bao giờ ghi n/a — SRS luôn tự có đủ dữ liệu để dựng RTM) |

## 4. SDS — 0–10

### Sàn (5 điểm) — 4 tiêu chí con, **D3 trọng số ×2**

Trọng số: D1 ×1 · D2 ×1 · **D3 ×2** · D4 ×1 → `sàn = 5 × (D1 + D2 + 2×D3 + D4)/5`. D3 nhân đôi vì nó là tiêu chí **duy nhất trong sàn thực sự đọc nội dung**; ba cái kia chỉ hỏi "mục/ADR/SRS có tồn tại không". Không nhân đôi thì một tài liệu đủ tiêu đề nhưng rỗng ruột thắng một tài liệu thiếu tiêu đề nhưng nội dung chắc — đúng cái xảy ra khi so OTES với HisWise ở 1.4 (xem §7).

Khi D4 = `n/a` (không được cấp SRS): `sàn = 5 × (D1 + D2 + 2×D3)/4`.

**Định nghĩa "nửa vời" (1.6, chỗ mơ hồ A2)** — dùng cho cả S1 và D1, không được đoán:

> Một mục được **0.5** khi nó có nội dung thật nhưng **phủ < 50% số tiểu mục mà khung đòi** cho mục đó (`sds-outline.md` / `srs-outline.md` là khung). Phủ ≥ 50% → **1**. Không có mục, hoặc chỉ có tiêu đề không nội dung → **0**.

Phải **ghi phân số tiểu mục** trong verdict (`§2 "2.5/6 tiểu mục → 0.5"`), không ghi mỗi kết quả. Trước 1.6 luật chỉ nói "nửa vời = 0.5" mà không nói nửa vời là gì; hai người chấm cho §2 của cùng một tài liệu 1.0 và 0.5, chênh 0.15 điểm.

**Luật `n/a` chung (áp cho mọi thành phần, cả SRS lẫn SDS — nơi duy nhất định nghĩa):** một thành phần hoặc tiêu chí con ghi `n/a` **bị loại khỏi mẫu số**, không phải cho 0. Cho 0 là phạt tài liệu vì thiếu sót của **bộ test** (không cấp SRS, không có vision, không có test plan), không phải của tài liệu. Hệ quả: thang tối đa tụt xuống và **verdict phải ghi rõ thang mới** — không có SRS → RTM SDS `n/a` → thang 9; không có vision → diagram `n/a` → thang 8; không có cả hai → thang 7. Chỉ ba trường hợp này được ghi `n/a`. **RTM của SRS không bao giờ `n/a`** (SRS luôn tự đủ dữ liệu dựng RTM) — thiếu là 0.

| # | Tiêu chí | Cách đo |
|---|---|---|
| D1 | Đủ mục viewpoint | (mục có nội dung thật = 1, **nửa vời = 0.5**, không có = 0) / **5 mục**: §1 Intro & design goals, §2 Architecture, §3 Detailed design, §4 Data design, §5 Interface design. **§6 ADR và §7 RTM không đếm ở đây** — đã có D2 và thành phần +1 riêng (luật một-chỗ §1b) |
| D2 | Công nghệ có ADR | số công nghệ có ADR / số tên công nghệ xuất hiện ở §2–5 |
| D3 | Có HOW, không WHAT-only | số tiểu mục trả lời ≥1 trong 4 câu (`viewpoints.md` §2) / tổng tiểu mục. **Mẫu đếm**: mọi tiểu mục **có nội dung** thuộc **§1–§5** của khung `sds-outline.md`, ánh xạ theo **tiêu đề thật** của tài liệu chứ không theo số hiệu tài liệu tự đặt (tài liệu hợp nhất hay đánh số khác). Không đếm: tiêu đề nhóm đứng một mình (không thể trả lời câu HOW → đếm vào là phạt oan), §6 ADR và §7 RTM (đã có D2 và thành phần RTM), mục ngoài khung 7 mục. **Phải liệt kê ra mẫu đếm trong verdict** — nếu người khác không dựng lại được mẫu số thì tiêu chí này không dùng được. **Bốn luật quyết định (1.6, chỗ mơ hồ A1)** ở ngay dưới bảng |
| D4 | Nạp được SRS | 0.5 × (SRS xác định được: 1/0) + 0.5 × (tỉ lệ ID FR/UC trong SDS resolve được về SRS). Tài liệu hợp nhất: SRS luôn xác định được → 0.5 chắc chắn, nhưng **tỉ lệ resolve vẫn đo bình thường**. **Nếu người chấm KHÔNG ĐƯỢC CẤP SRS** (chỉ nhận mỗi SDS): ghi `n/a`, **loại D4 khỏi trung bình** và chấm sàn trên 3 tiêu chí — cho 0 là phạt tài liệu vì thiếu sót của bộ test, không phải của tài liệu (bài học HisWise 1.5) |

**Bốn luật quyết định cho mẫu đếm D3** (1.6, chỗ mơ hồ A1 — D3 trọng số ×2 nên mỗi lần đoán sai ở đây đắt gấp đôi chỗ khác):

1. **Use case KHÔNG thuộc khung SDS.** Mục liệt kê/mô tả use case luôn **loại khỏi mẫu số D3**, kể cả khi tài liệu đặt nó trong SDS. Use case là WHAT theo định nghĩa; tính nó vào là cầm chắc một tiểu mục không-HOW mà tài liệu không có cách nào sửa.
2. **Văn xuôi mô tả quan hệ, không có kiểu/khoá/ràng buộc → KHÔNG tính là HOW.** "Bảng này lưu các đoạn text trích từ tài liệu để index" trả lời *cái gì*, không trả lời *như thế nào*. Muốn tính là HOW thì phải có ít nhất một trong: kiểu dữ liệu, khoá, ràng buộc, enum, index.
3. **Tiêu đề nhóm đứng một mình → loại khỏi mẫu số** (đã có từ 1.0, nhắc lại vì hay quên). Không thể trả lời câu HOW nào thì tính vào là phạt oan.
4. **Ánh xạ theo tiêu đề thật, không theo số hiệu tài liệu tự đặt** (đã có từ 1.0). Tài liệu đánh số 1–7 không liên quan gì tới khung 1–7.

Không luật nào ở trên xử được trường hợp đang xét → ghi `info: mẫu đếm D3 có mục không quyết được: <tên mục>` và **loại khỏi mẫu số**, không tự đoán.

### Cộng điểm

| Thành phần | Max | Tiêu chí con |
|---|---|---|
| Diagram pass UML 2.5 | 2 | **`notation` chỉ chấm lỗi NỘI TẠI của hình** *(1.6, chỗ mơ hồ A5 — luật một-chỗ)*: cú pháp, ký hiệu, phần tử thiếu nhãn, quan hệ vẽ sai loại. **Mọi lỗi liên-artefact ("lifeline không có class", "tập state ≠ enum dictionary", "bảng ↔ data dictionary") KHÔNG tính ở đây** — chain 1/2/3/4 đã đo chúng theo tỉ lệ. Danh sách câu hỏi từng loại trong `uml25-diagram-policy.md` có dòng "Cross-artifact:" ở cuối; dòng đó **chỉ để reviewer ghi finding**, không vào `notation`. **Hình không đọc được → loại khỏi cả tử lẫn mẫu** (giống chain 3 luật 4), không cho 0. · **trọng số 1-1-1-3**: G1 caption đúng loại (w1) · G2 dòng đọc-hiểu (w1) · G8a số hiệu duy nhất (w1) · **0 red theo câu hỏi của loại đó (w3)**. Công thức `(g1 + g2 + g8a + 3×notation)/6`. Trọng số 3 vì ba tiêu chí đầu chỉ đếm caption; nếu để ngang nhau thì chúng che mất tiêu chí thật sự đọc notation (bài học OTES: G1 0.81 + G8a 0.96 kéo điểm lên dù chỉ 6/85 hình sạch red). **G8b (hình dùng lại) không tính điểm** — cần mắt người, chỉ báo finding |
| Cross-artifact | 2 | trung bình tỉ lệ đạt của **7 chain** (§5) |
| RTM FR↔design | 1 | (1/3) × (1 − orphan FR/tổng FR) + (1/3) × (1 − orphan element/tổng element) + (1/3) × (test case trỏ được về UC/FR / tổng test case). Không có RTM → 0. Tài liệu không có test plan → chấm hai số hạng đầu, ghi rõ "thang 2/3" |

## 5. Bảy chain cross-artifact (SDS) — mỗi chain cho một tỉ lệ

| # | Chain | Tỉ lệ đo cái gì | App hiện có? |
|---|---|---|---|
| 1 | Naming drift | số khái niệm chỉ có **một** cách viết / tổng khái niệm chung giữa ≥2 artefact | ✅ `crossArtifactName` |
| 2 | FK matrix | số FK vừa khớp kiểu vừa khớp data dictionary / tổng FK | ❌ (probe r20) |
| 3 | Sequence ↔ Class | 0.5 × (lifeline là class / tổng lifeline) + 0.5 × (message là operation khai báo / tổng message). **Luật đếm chặt ở dưới bảng** | ❌ — **port bước 2** |
| 4 | Status vocabulary | số cột trạng thái có enum liệt kê **và** khớp state machine / tổng cột trạng thái | ❌ |
| 5 | CRUD / endpoint coverage | 0.5 × (UC có ≥1 endpoint / tổng UC) + 0.5 × (bảng có ≥1 UC ghi vào / tổng bảng) | ❌ |
| 6 | C4 ↔ UML | số phần tử C4 có đối ứng UML (people↔actor, container↔artifact, component↔package) / tổng phần tử C4; không có C4 và không có Deployment → 0 | ❌ |
| **7** | **Sequence ↔ kiến trúc khai báo** *(1.1)* | trung bình 5 tỉ lệ ở `architecture-patterns.md` §3: 7a style khai báo + ADR · 7b lifeline thuộc vai của style · 7c message đúng chiều (luật robustness ECB + luật chiều của style) · 7d ranh giới container có protocol · 7e class diagram có tầng/package của style, dependency đúng chiều | ❌ — 7b/7c/7d thuần text sau khi có lifeline list; 7e cần package trong class diagram |

**Luật đếm chain 3** (1.6, chỗ mơ hồ A3 — trước đó hai người chấm ra 0.56 và 0.70 trên cùng tài liệu, khác nhau ở nửa message):

1. **Chỉ đếm call message. Bỏ reply** (mũi tên đứt trả về). Reply không phải lời gọi operation nên không có gì để đối chiếu.
2. **Khớp TÊN CHÍNH XÁC, phân biệt chữ hoa thường.** `to_citation` **không** khớp `to_citations`. Lệch một ký tự chính là finding — đó là cái chain 3 sinh ra để bắt, chấp nhận "gần đúng" là xoá luôn giá trị của nó.
   **Hai thứ được chuẩn hoá TRƯỚC khi so, và chỉ hai thứ này** *(1.6, chỗ mơ hồ A7)*: (a) **hậu tố quy ước áp đều cho mọi lifeline trong cùng một hình** — `:chat_routes.py` ↔ class `chat_routes`: đó là quy ước ký hiệu của tác giả, không phải drift, và chỉ được bỏ khi **mọi** lifeline trong hình đó đều mang hậu tố ấy; (b) **tiền tố người nhận** — `ragClientService.ingest(x)` so bằng `ingest`. Ngoài hai cái đó, so nguyên văn. Phải ghi vào ledger đã chuẩn hoá cái gì.
3. **Lifeline không phải class thì mọi message gửi tới nó đều không khớp**, không bỏ qua. Một message gửi tới `Database` khi không có class `Database` là hai lỗi (lifeline + message), không phải một.
4. **Hình không đọc được → loại cả hình khỏi tử số VÀ mẫu số**, ghi vào coverage. Không đoán nội dung, cũng không tính là 0.
5. **Ghi rõ mẫu**: liệt kê tên các sequence diagram đã đếm và số đã loại. Hai phân số phải dựng lại được.

Thành phần cross-artifact = **trung bình 7 chain** (1.1; trước là 6). Chain 7 không đếm trùng chain 3: chain 3 hỏi lifeline *có class không*, chain 7 hỏi lifeline *đúng vai chưa* và message *đúng chiều chưa*.

## 6. Hard rule — phạt trực tiếp

Phạt trực tiếp **chỉ dành cho hard rule mà không thành phần điểm nào đo được** — luật một-chỗ §1b. Mỗi rule như vậy bị vi phạm: **−0.5**, tối đa **−2.0** toàn tài liệu. Phạt tính **một lần cho mỗi rule**, không nhân theo số lần vi phạm.

| Hard rule (RULEBOOK §5) | Ai đo | Phạt |
|---|---|---|
| 1, 2, 3, 8 | — (nói về hành vi reviewer, không phải tài liệu) | không |
| 4 — Design ≠ Requirements | **D3** đo tỉ lệ tiểu mục có HOW | **không** |
| 5 — Công nghệ phải có ADR | **D2** đo tỉ lệ công nghệ có ADR | **không** |
| 6 — NFR phải định lượng | **thành phần NFR +2** đo tỉ lệ NFR có số + điều kiện | **không** |
| 7 — RTM là gate cuối | **thành phần RTM +1** đo orphan; chế tài là **NOT DONE** | **không** |
| **9 — không PII thật** | không tiêu chí nào đo | **−0.5** |
| **10 — ảnh bên thứ ba không phải thiết kế của mình** | không tiêu chí nào đo | **−0.5** |

Trần −2.0 giữ nguyên để chỗ cho hard rule thêm sau. Với hai rule hiện tại, phạt tối đa thực tế là −1.0.

**Hard rule 7** không phạt điểm nhưng vẫn kéo trạng thái **NOT DONE**, độc lập với điểm — một tài liệu 8/10 mà RTM có orphan vẫn là NOT DONE.

**Tài liệu hợp nhất**: rule 9 và 10 là vi phạm ở cấp tài liệu, phạt **một lần**, tính cho ledger của mục chứa ảnh vi phạm. Không phạt cả hai ledger.

Điểm cuối cùng kẹp trong [0, 10].

## 7. Vì sao bỏ "−1 mỗi red" của v0.1

Lần chạy OTES 2026-09-14 (`reviews/OTES-…-ledger.md`) cho cả SRS và SDS **0/10**, dù hai tài liệu chênh nhau rõ rệt về chất lượng. Ba nguyên nhân, đã sửa:

1. **Sàn all-or-nothing.** Đúng cái bug rulebook đã chê `document_verdict.dart` (§9). Một tài liệu thiếu glossary là trượt sàn hoàn toàn, bằng với tài liệu không có gì. → §2 chấm liên tục.
2. **Đếm hai lần, dạng 1.** Khi thành phần chấm theo tỉ lệ, mỗi red **đã** kéo tỉ lệ xuống rồi; trừ thêm −1/red là tính lỗi đó hai lần, và với 37 red thì mọi tài liệu đều về 0. → phạt trực tiếp chỉ còn ở hard rule.
3. **Đếm hai lần, dạng 2** — chỉ lộ ra ở vòng kiểm chéo thứ hai. Bỏ −1/red rồi mà NFR vẫn bị tính 3 lần (S5 + thành phần NFR + hard rule 6), RTM 3 lần, ADR 3 lần, ảnh bên thứ ba 4 lần. → **§1b luật một-chỗ**: kiểm kê mục bỏ qua mục đã có thành phần riêng; hard rule chỉ phạt khi không thành phần nào đo được nó.

Thang mới phải thoả **test phân biệt**: hai tài liệu khác chất lượng phải ra hai điểm khác nhau. Chấm lại OTES: v0.1 cho 0.0 / 0.0 · v0.2 cho 3.5 / 1.4 · **v0.2.1 cho SRS 4.5 và SDS 2.7** — xem `reviews/OTES-…-rescore-v0.2.md`.

**Bài học vận hành:** lỗi đếm-hai-lần không biến mất khi bỏ cơ chế gây ra nó — nó chuyển chỗ. Cả hai lần đều do kiểm chéo độc lập tìm ra, không phải tác giả tự thấy. Mọi lần sửa file này phải kèm một vòng verify độc lập.

**Luật verify (1.5, sau lần trượt độ lặp lại):** mọi thay đổi thang điểm phải kèm **một vòng chấm mù độc lập** — người chấm thứ hai không được đọc `reviews/`, và **điểm của lần chấm trước không được nằm trong bất kỳ file nào người chấm bắt buộc phải đọc** (đó là lý do §10 của RULEBOOK không còn ghi điểm). Đạt = lệch ≤ 0.5/10. Lần đo đầu tiên: **trượt, lệch 1.4** — `reviews/HisWise-SDS-repeatability-2026-09-15.md`, kèm bốn chỗ luật gây ra lệch (A1–A4) đang chờ 1.6.

## 8. Gate theo phase — không qua gate không sang phase sau

**Đây là nơi duy nhất định nghĩa gate.** Checklist chỉ được trích lại nguyên văn, không được thêm điều kiện; hai bên lệch nhau thì bảng này thắng.

| Tài liệu | Phase | Gate |
|---|---|---|
| SRS | P1 → P2 | Có stakeholder/actor list + scope in/out |
| | P2 → P3 | ≥ 90% FR có ID đúng mẫu `FR-<EPIC>-NN` **và** priority |
| | P3 → P4 | **Gate số lượng (chặn)**: ≥ 20 UC có bảng đặc tả (syllabus TDA). Hai điều kiện sau **đo và ghi finding nhưng KHÔNG chặn phase**: ≥ 70% UC nằm trong 3–7 transaction · UC diagram qua G1–G8 với 0 red |
| | P4 → P5 | 100% NFR có số **và** điều kiện đo; data dictionary phủ entity trong UC |
| | P5 done | RTM FR↔UC 0 orphan; ambiguity scan 0 red; 0 placeholder |
| SDS | P1 → P2 | SRS xác định được, ID FR/UC resolve ≥ 90%. **Không có SRS → gate FAIL nhưng vẫn chạy P2–P5**, RTM ghi n/a |
| | P2 → P3 | C4 L1+L2 (hoặc Component+Deployment UML), ADR cho style + mọi stack |
| | P3 → P4 | Class + SEQ cho mọi FR high + SM cho entity có cột trạng thái; **chain 3 ≥ 0.9 và chain 4 (state ↔ enum) 0 red** |
| | P4 → P5 | ERD 0 red; data dictionary đủ 8 cột; API contract phủ UC |
| | P5 done | RTM 0 orphan hai chiều; ADR phủ 100% công nghệ; **mỗi test case trỏ về ≥1 UC/FR** |

**Gate số lượng UC bỏ trần 25** (v0.1 đặt 20–25). Lý do: OTES có 63 UC vẫn "trượt" vì vượt trần, trong khi vấn đề thật là 45/63 UC nằm **ngoài** dải 3–7 transaction (phần lớn chỉ có 1). Số lượng và kích thước là hai chuyện; trộn vào một ngưỡng thì che mất lỗi thật. `rubric.json` cần bump version khi đồng bộ.

## 9. Đối chiếu với app — giữ gì, lệch gì

**Weights per-requirement — ĐÃ ĐỔI (Q6, ký 2026-09-15):**

| Tiêu chí | rubric.json v2 (app hiện tại) | **Rulebook 1.5** | Vì sao |
|---|---|---|---|
| clear | .30 | **.25** | |
| testable | .30 | **.40** | Lỗi phổ biến nhất trong OTES: 44/44 FR+NFR không viết được test case. Tester không biết khi nào "xong" thì mọi tính chất khác vô nghĩa |
| complete | .25 | **.20** | |
| consistent | .15 | **.15** | |

Dùng khi chấm **từng dòng** requirement (per-requirement 0–10, `contracts/review.schema.json`), **không** cộng vào thang artifact ở trên. App chưa theo — xem `adapters/app-port-map.md` §5 việc B. Vẫn là đề xuất có chủ định; khi hội đồng công bố bảng thật → thay số.

**Giữ nguyên từ app:**
- `pass_mark 5.0`, `warn 6.0`, `min_per_part 2.0`. Quote fuzzy ≥ 0.92 (`verify.py`).
- Đổi số nào ở đây → bump `version` trong RULEBOOK **và** rubric.json (cache key server băm version — quên bump thì verdict cache cũ được phục vụ như của rubric mới).

**Lệch đã biết giữa rulebook 1.5 và `document_verdict.dart`:**

| Điểm | Rulebook 1.5 | App hiện tại | Hướng xử |
|---|---|---|---|
| Sàn SRS | 5 tiêu chí chấm **liên tục** | 7 bucket all-or-nothing — một `ucSize` amber cũng làm sàn = 0 | Port §3 sang app; đây giờ là lỗi giống nhau ở hai nơi, sửa một lần |
| Trừ điểm | Chỉ hard rule, tối đa −2 | −1 mỗi **ledger row** red thuộc `ERD-` / `SM-` / `SEQ-CLS-` (hằng `deductingFamilies`) | **Bug `FLOW-` đã sửa 2026-09-15**: prefix đó chưa bao giờ được sinh, nên từ bản đầu tới hôm đó mọi state-machine và sequence red đều trừ 0 điểm. Nay có test chặn: mọi prefix trong danh sách phải khớp một `DiagramKind.family` thật. **Vẫn lệch**: app trừ theo row còn rulebook chỉ trừ ở hard rule 9/10 — hai mô hình khác nhau, hợp nhất ở port bước 3 |
| Severity | red / amber / info | `high / medium / low`; `placeholderTbd` = medium | Map high→red, medium→amber, low→info; nâng `placeholderTbd` lên high |
| Cột ledger | 9 cột (ledger-format §2) | không có Quote / Rule / Suggested rewrite | Cột app là **subset** |
| Traceability | tính thật từ RTM | null vĩnh viễn | bật khi có `rtmOrphan` |
| Gate UC | count ≥ 20, size riêng | `ucCount` 20–25 gộp một check | Tách trong `rubric.json`, bump version |
