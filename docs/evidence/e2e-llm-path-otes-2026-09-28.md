# WP8 gate 1 — Lượt E2E đầu tiên sau 2026-09-21: **CHƯA CHỨNG MINH ĐƯỢC** (provider 503)

**Ngày:** 2026-09-28 · **Kết luận: không đạt.** Không phải vì code sai, mà vì provider
trả **HTTP 503** liên tục. Bằng chứng này ghi lại **cả những gì đã chứng minh** lẫn
**những gì chưa**, để lần sau không phải đo lại từ đầu.

## Nguồn mẫu và kế hoạch (đo trước, không tốn tiền)

| Mục | Giá trị |
|---|---|
| Tài liệu | `D:\Download\OTES_officially_document.docx_compressed.pdf` — 217 trang, 154.716 ký tự text |
| Bản dùng | bản 2,73 MB; bản 27,37 MB có **lớp text giống hệt** (nén chỉ giảm ảnh) |
| Pipeline | `stripPageNumberFooters` → `TableOfContents.parse` → `RequirementSplitter` → `SrsDocument` — **đúng thứ tự của app** |
| Phiên bản parser | **1.4.4** (`kParserVersion`) |
| Unit | **91** (useCase 63 · section 27 · nonFunctional 1) |
| Unit **có ảnh trang** | **0** (82 `skippedNoDiagramIntent`, 9 `skippedNoCandidatePage`) |
| Ngân sách ảnh | 12 trang — lượt này dùng **0** |
| Số call **dự kiến** | `ceil(91/6) + 0 = 16` |
| Harness | `app/test/wp8_phase0_call_cost_test.dart` (in kế hoạch, xuất unit ra `%TEMP%`) |

## Những gì lượt chạy **CHỨNG MINH ĐƯỢC**

| Số | Ý nghĩa |
|---|---|
| **2** | POST `/review/batch` trả **200 OK** — đường HTTP, batching 6 unit, header `X-User-Id`, proxy thật, cache thật: **đều chạy** |
| **4** | lần `gemini ... exhausted retries` (2 model × 2 lượt) |
| **6** | lần `provider cooldown: all models for 20.0s` |
| **2** | batch kết thúc bằng `batched review of 6 units failed: gemini returned HTTP 503` |
| 53,1s / 203,2s | thời gian mỗi batch — batch 02 dài gấp 4× vì phải chờ hạ nhiệt |

**Kết luận có giá trị nhất của lượt này:** khi provider lỗi, hệ thống **hạ nhiệt và dừng
lại** thay vì đốt tiền đi tiếp. Đó đúng là thứ ADR-0010 hứa, và nó chỉ chứng minh được
bằng một lượt thật gặp lỗi thật.

## Những gì **KHÔNG** chứng minh được — đọc trước khi trích số nào ở đây

1. **Không có kết quả review nào.** Hai batch đều **thất bại**; con số `findings=0` mà
   báo cáo lượt in ra là **vô nghĩa** (xem bên dưới). Không có tờ điểm nào được sinh.
2. **Đường ảnh không được chạy.** `unitsWithImage = 0`: tài liệu này văn xuôi, không
   unit nào trích hình, nên chain 2/3 (phần bám ảnh — thứ rủi ro nhất) **không** được
   kiểm chứng bởi lượt này.
3. **Không chứng minh được hành vi 429 dưới trần sản xuất.** `RATE_LIMIT_PER_DAY` trong
   `server/.env` đang là **2000** (nâng cho dev local), không phải 50. Lượt này vì thế
   **không** nói được gì về hành vi khi chạm trần 50/ngày.
4. **Đường UI không được chứng minh.** Lượt chạy bằng script gọi endpoint, không bấm
   UI. Gọi đây là "E2E" theo nghĩa rộng là sai.

## Bẫy đo được trong chính lượt này: `200` không có nghĩa là "đã chấm"

Batch trả **200 OK** kèm `failed[]` (thiết kế có chủ đích từ plan 9: giữ phần đã trả
tiền). Nên `200` và `findings=0` **không phân biệt được** hai trạng thái:

- *đã chấm và không tìm ra vấn đề nào*, với
- *chưa chấm được unit nào*.

Tài lái lượt chạy in `findings=0` mà **không in `failed`**, và báo cáo lượt đã đọc nó
thành phát hiện. Đây là mẫu "xanh nhưng nói dối", lần này **nó nằm ở báo cáo của chính
người viết luật chống nó**. Bất kỳ ai đọc `POST /review/batch` phải phân biệt hai
trạng thái này **trước khi** báo bất kỳ con số nào; xem `AGENTS.md`.

## Vì sao 503

`gemini-3.5-flash-lite` hết retry → thử `gemini-3.8-flash` → cũng hết retry → cả hai
đều 503. 503 ở phía provider: có thể tạm thời, theo vùng, hết hạn mức, hoặc bản
`flash-lite` không ổn định. **Không có bằng chứng nào trong lượt này cho phép kết luận
nguyên nhân** — nói "provider lỗi" là đúng, nói thêm gì nữa là bịa.

## Lệnh đã chạy

```sh
# 1) kế hoạch (không tốn tiền): in số call dự kiến + xuất danh sách unit
cd app && flutter test test/wp8_phase0_call_cost_test.dart
# 2) proxy thật, log ra ngoài repo
cd server && .venv/Scripts/python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8077
# 3) lượt thật: %TEMP%/otes_run.py — 6 unit/call, header X-User-Id, không tắt pacer
#    kết quả: %TEMP%/otes_e2e_result.json
```

## Còn lại để đóng gate này

Chạy lại khi provider ổn định, hoặc thử model khác (đổi `GEMINI_MODEL` trong `.env` —
là **cấu hình lượt chạy**, không sửa code, nhưng phải ghi rõ vì nó đổi điều kiện thí
nghiệm). Và **dù tất cả xanh**, lượt trên OTES vẫn không chứng minh được **đường ảnh** —
muốn vậy thì cần một tài liệu có unit trích hình.
