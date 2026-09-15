# Thử nghiệm độ lặp lại — HisWise SDS, rulebook 1.5

**Ngày:** 2026-09-15 · **Tài liệu:** `_HisWise_SDS Document.pdf` (23 trang, 21 hình, không có SRS đi kèm)
**Câu hỏi:** chấm cùng một tài liệu hai lần bằng cùng một bộ luật có ra cùng một điểm không?

## Kết quả

| | Lần 1 (ledger gốc) | Lần 2 (chấm mù) | Lệch |
|---|---|---|---|
| **Điểm /10** | **4.9** | **3.5** | **1.4** |
| Sàn /5 | 2.66 | 2.50 | 0.16 |
| Diagram /2 | — | 0.14 | — |
| Cross-artifact /2 | — | 0.50 | — |
| chain 3 | 0.70 | 0.56 | 0.14 |
| Verdict | NOT DONE | NOT DONE | khớp |

**Kết luận: TRƯỢT.** Ngưỡng chấp nhận được cho một thang 10 điểm là ±0.5. Lệch 1.4 nghĩa là **điểm số của rulebook 1.5 chưa dùng được để tuyên bố mức chất lượng**. Nó vẫn dùng được để xếp hạng khuyết điểm — cả hai lần đều ra NOT DONE, cùng bốn gate FAIL, cùng nhóm lỗi nặng.

## Phương pháp

Người chấm lần 2 là một agent độc lập, bị cấm đọc `reviews/`, chỉ được đọc `review-rules/` + file PDF. Nhận cùng một chỉ dẫn: đọc hết, mọi phân số phải đếm được, không ước lượng.

**Thí nghiệm bị nhiễm một phần — lỗi của tôi.** `RULEBOOK.md` §10 lúc đó ghi thẳng "HisWise 3.71 → 4.9" và "OTES thắng HisWise ở sàn 2.66 vs 1.85, chain 3 0.12 vs 0.70". Người chấm lần 2 buộc phải đọc RULEBOOK nên **đã biết đáp án trước khi chấm**. Nhiễm này đẩy về phía **đồng thuận** — vậy mà vẫn lệch 1.4. Con số thật của một lần chấm mù sạch nhiều khả năng **tệ hơn**, không tốt hơn. Đã sửa: §10 không còn ghi điểm, điểm chỉ nằm trong `reviews/`.

## Bốn chỗ luật gây ra lệch

Người chấm lần 2 tự chỉ ra, kèm biên độ. Đây là danh sách việc cho 1.6.

| # | Chỗ mơ hồ | Hai cách đọc đều hợp lệ | Biên độ /10 |
|---|---|---|---|
| **A1** | **Mẫu đếm của D3** — tiểu mục nào vào mẫu số | "4.b Table Description" có HOW hay không (mô tả quan hệ nhưng không có kiểu/khoá); "2. Use cases" có thuộc khung SDS không | **±0.3 mỗi cái**, nhân đôi vì D3 ×2 |
| **A2** | **D1 cho điểm nửa vời** — §2 có 6 tiểu mục, tài liệu có 2.5 | 1.0 ("có nội dung thật") vs 0.5 ("nửa vời") | **±0.15** |
| **A3** | **Luật khớp message của chain 3** | Tên operation phải khai báo đúng trên class nhận (chặt) vs chấp nhận gần đúng `to_citation`≈`to_citations`, có tính reply message không | **±0.2** |
| **A4** | **g8a khi tài liệu KHÔNG có hệ đánh số hình nào** | 0/21 (không hình nào có số đúng) vs 21/21 (không có số trùng → thoả vô điều kiện) | **±0.37** |

A4 là chỗ tệ nhất: luật viết "số hiệu duy nhất", và một tài liệu **không đánh số gì cả** thoả mãn "duy nhất" theo nghĩa rỗng. Phải viết lại thành hai điều kiện: *có* số hiệu **và** số hiệu duy nhất.

Cộng dồn, biên độ hợp lý của cùng tài liệu này là **3.35 – 4.3**. Con số 4.9 của lần 1 nằm **ngoài** dải đó, nên ngoài bốn chỗ trên còn ít nhất một khác biệt cấu trúc nữa giữa hai lần chấm.

## Việc cho 1.6

1. **A4 trước** — rẻ nhất, biên độ lớn nhất, sửa một câu trong `scoring.md` §4 và `uml25-diagram-policy.md` G8a.
2. **A1** — `scoring.md` §4 D3 đã bắt "phải liệt kê mẫu đếm trong verdict"; chưa đủ. Cần luật quyết định: tiểu mục chỉ có văn xuôi mô tả quan hệ giữa các bảng, không có kiểu/khoá/ràng buộc → **không tính là HOW**. Và: use case **không** thuộc khung SDS, luôn loại khỏi mẫu số D3.
3. **A3** — `scoring.md` §5 chain 3 phải ghi rõ: chỉ đếm **call message**, bỏ reply; khớp **chính xác** tên, sai một ký tự là không khớp (chính cái sai đó là finding).
4. **A2** — định nghĩa "nửa vời": mục có < 50% số tiểu mục mà khung đòi → 0.5.

Sau khi chốt bốn cái, **chạy lại thử nghiệm này**. Rulebook chỉ được gọi là dùng được khi lệch ≤ 0.5.

---

# Vòng 2 — rulebook 1.6, hai người chấm độc lập song song

**Thiết kế tốt hơn vòng 1:** hai agent chấm **cùng lúc**, cùng tài liệu, cùng luật, không ai đọc kết quả của ai và không so với số cũ. Vòng 1 so bản mới với bản cũ nên vẫn dính neo; vòng 2 chỉ hỏi *hai người đọc cùng bộ luật có ra cùng số không*.

## Kết quả: **ĐẠT — lệch 0.26** (ngưỡng 0.5)

| | Người chấm A | Người chấm B | Lệch |
|---|---|---|---|
| **Điểm /10** | **4.58** | **4.84** | **0.26** |
| D1 | 0.50 | 0.50 | **0** |
| D2 | 0.00 | 0.00 | **0** |
| D3 | 6/7 = 0.857 | 6/7 = 0.857 | **0** |
| **Sàn /5** | **2.77** | **2.77** | **0** |
| g8a | 0/21 | 0/21 | **0** |
| g2 | 0/21 | 0/21 | **0** |
| g1 | 5/21 | 10/21 | 0.24 |
| notation | 13/16 | 14/16 | 0.06 |
| chain 3 | 0.238 | 0.52 | 0.28 |
| Verdict | NOT DONE | NOT DONE | khớp |

**Sàn khớp tuyệt đối.** Không chỉ tổng bằng nhau — cả ba tiêu chí, cả mẫu đếm D3 (7 mục), cả danh sách mục bị loại và **lý do loại theo đúng luật nào**, đều trùng từng dòng. Đây là phần vòng 1 lệch nhiều nhất và là phần 1.6 sửa nhiều nhất.

## Bốn chỗ sửa hoạt động thế nào

| | Chỗ sửa | Kết quả đo |
|---|---|---|
| **A1** | Bốn luật quyết định mẫu đếm D3 | **Hết lệch.** Cả hai loại "2. Use cases" (luật 1), "I. Overview" + "4. Database Design" (luật 3), và cùng chấm "4.b Table Description" là không-HOW (luật 2) |
| **A2** | "Nửa vời" = phủ < 50% tiểu mục | **Hết lệch.** Cả hai ra §2 = 2/6 = 0.5, §3 = 3/4 = 1, §4 = 2/4 = 1 |
| **A4** | G8a phải CÓ số hiệu trước khi xét duy nhất | **Hết lệch.** Cả hai ra 0/21, đúng cái chỗ vòng 1 đọc thành 0/21 và 21/21 |
| **A3** | Luật đếm chain 3 | **Gần hết.** Cả hai bỏ đúng 2 hình không đọc được, đếm đúng call message. Còn lệch ở một chỗ mới (dưới) |

## Ba chỗ mơ hồ MỚI, cả hai người chấm tự nêu độc lập

Cả hai đều xếp cái đầu là **lỗ lớn nhất còn lại**, lớn hơn bất kỳ cái nào trong A1–A4. Hai người không trao đổi với nhau.

| # | Chỗ mơ hồ | Biên độ | Đã sửa trong 1.6 |
|---|---|---|---|
| **A5** | `notation` và chain đếm trùng nhau. Danh sách câu hỏi từng loại kết thúc bằng dòng "Cross-artifact: mọi lifeline phải là class" — đúng cái chain 3 đo. §1b cấm chấm một khuyết điểm hai lần nhưng không nói bên nào giữ | **0.31–0.44** | ✅ `notation` chỉ chấm lỗi nội tại; dòng "Cross-artifact" chỉ để ghi finding |
| **A6** | Tiêu đề mục có tính là caption cho G1 không? 1.6 sửa G8a cho trường hợp "không có số hiệu" nhưng bỏ quên G1 với trường hợp "không có caption" | **0.24** | ✅ Heading không phải caption — tổng quát hoá đúng nguyên tắc của A4 |
| **A7** | Chain 3 luật 2 gặp hậu tố quy ước: `:chat_routes.py` vs class `chat_routes`. Đọc nguyên văn thì trượt, nhưng đó là quy ước ký hiệu áp đều, không phải drift | **0.28** | ✅ Chỉ chuẩn hoá hai thứ: hậu tố áp đều cho mọi lifeline trong hình, và tiền tố người nhận |

**Ba cái này CHƯA ĐƯỢC ĐO LẠI.** Chúng được viết sau vòng 2, dựa trên báo cáo của vòng 2. Phải chạy vòng 3 mới biết có hiệu quả không — và phải đo, không được suy đoán, vì đó chính là bài học của cả file này.

Còn lại chưa sửa, cả hai đều nêu: **định nghĩa "một hình"** (hai khung sequence dưới một tiêu đề là 1 hay 2 — mọi phân số diagram lấy số này làm mẫu), **mẫu số của chain 1** ("khái niệm" là gì), và **chain 2 mắc đúng lỗi mà A4 vừa sửa cho G8a** (không có data dictionary thì 14 FK đúng kiểu và 14 FK đảo chiều cùng ra 0/14).

## Lỗ hổng quy trình tự phát hiện

Cả hai người chấm đều báo: `RULEBOOK.md` §10 vẫn in điểm của lần chạy trước cho **đúng tài liệu này**, trong file họ bắt buộc phải đọc. Chính luật verify của 1.5 cấm điều đó, và tôi đã vi phạm luật mình vừa viết. Đã gỡ — §10 nay chỉ trỏ sang `reviews/`.

Đáng chú ý: cả hai vẫn ra số **lệch khỏi** con số bị lộ (4.58 và 4.84 so với 4.9 bị lộ), và mỗi người rơi về một phía của các bất đồng đã bị lộ chứ không rơi vào giữa — dấu hiệu của suy luận độc lập thật, không phải bám neo.

---

## Bài học vận hành

Đây là lần thứ ba trong dự án mà **một vòng kiểm tra độc lập tìm ra lỗi mà tác giả không tự thấy** (lần 1: thang all-or-nothing cho 0/10; lần 2: bảy chỗ đếm hai lần; lần 3: không lặp lại được). Ba lần, ba lỗi khác loại, không lần nào tác giả tự phát hiện.

Luật rút ra, thêm vào `scoring.md` §7: **mọi thay đổi thang điểm phải kèm một vòng chấm mù độc lập, và thông tin về điểm cũ không được nằm trong file mà người chấm bắt buộc phải đọc.**
