# ADR-0008 — Không dùng KiraAI làm provider chính; giữ làm fallback vision có điều kiện

**Status:** Accepted
**Date:** 2026-09-15
**Deciders:** Amy
**Related:** ADR-0004 (model selection), ADR-0005 (run cap vs quota), `docs/plans/7-review-engine-v2-2026-09-15.md` §3, RULEBOOK hard rule 9

## Context

App hiện chỉ có một provider thật: Gemini (`server/app/llm/router.py`, `GeminiProvider`). Ràng buộc đã ghi ở ADR-0005: **50 request/ngày/người**, và đó là lý do có run cap 40 unit. Pass vision (đọc diagram) là phần ngốn quota nhất.

KiraAI (`https://kiraai.vn`) là một **API gateway/proxy của Việt Nam**, tương thích SDK OpenAI, base URL `https://kiraai.vn/api/v1`, bán lại ~47 model của nhiều hãng. Câu hỏi đặt ra: có model nào ở đó đọc được SRS/SDS **và** diagram tốt hơn hoặc rẻ hơn Gemini không.

### Điều đã xác minh (2026-09-15, từ trang chính thức kiraai.vn)

| Model | Nhà cung cấp | Dữ liệu đầu vào | Context | Chi phí |
|---|---|---|---|---|
| `kira-3.5-pro` | Kira (own) | **Text · Image · PDF · Audio · Video** | 1.000.000 in / 65.536 out | $0.96 / $6.54 per 1M |
| `kira-3.5-flash` | Kira | *(chưa xác minh — mất kết nối browser)* | 1.0M | $0.35 / $2.12 |
| `deepseek-v4-flash-vision-exp` | Partner | **Text · Image** | 1.000.000 in / 128.000 out | 7.020đ / 28.080đ per 1M |
| `qwen3.5-omni-plus` | Partner | **Text only** (bất chấp chữ "Omni") | 100.000 / 8.192 | 22.000đ / 140.000đ per 1M |
| `mimo-v2.5-free`, `hy3-free`, `qwen3.8-flash-free`, `glm-5.3-free` | Partner | Text (thẻ modality "Text") | — | **Free** |

**Ba sự thật quyết định:**

1. **Model free đều là text.** Bốn model hậu tố `-free` là nhóm miễn phí thật; không cái nào nhận ảnh. Kỳ vọng ban đầu ("kiraai đang có rất nhiều model free img") **không đúng** với *image input*; "free img" ở Kira là *image generation* (`kira-3.0-image`), không phải đọc ảnh.
2. **Gói token chỉ áp cho `kira-*`.** Trang giá ghi rõ: *"Các gói trên chỉ áp dụng cho model Kira (các model có tiền tố `kira-`). Để sử dụng các model đối tác (GPT, DeepSeek, Claude,...), bạn cần nạp tiền vào ví VND"*. Nên `deepseek-v4-flash-vision-exp` — model vision Partner duy nhất xác minh được — **luôn tốn tiền thật**.
3. **`kira-3.5-pro` gần như chắc chắn là Gemini bán lại.** Hồ sơ kỹ thuật trùng khít: 1M context, đầu vào Text/Image/**PDF**/Audio/Video, đầu ra 65.536 token. Không dòng model nào khác có PDF + audio + video native với 1M context. Meta-description của chính trang models liệt kê *"Kira, Qwen, Gemini, Claude, OpenAI, DeepSeek"*. **Đây là suy luận từ thông số, không phải xác nhận từ nhà cung cấp** — nhưng nếu đúng thì KiraAI không "ăn được Gemini", nó **là** Gemini cộng một lớp trung gian và một khoản markup.

### Rủi ro riêng tư — yếu tố quyết định

Cùng ngày, review CarbonX SRS phát hiện **email Gmail cá nhân thật** trong ảnh chụp trang admin (p51, p53), kèm số dư ví và số tiền rút theo từng người — đây chính là vi phạm hard rule 9 mà rulebook vừa đặt ra.

Pass vision hoạt động bằng cách **gửi ảnh trang tài liệu lên model**. Đi qua KiraAI nghĩa là:

- Tài liệu sinh viên chứa PII thật đi qua một proxy bên thứ ba trước khi tới nhà cung cấp gốc — **hai nơi giữ dữ liệu thay vì một**.
- Trang admin của chính KiraAI (quan sát được trong DOM công khai) có màn hình log ghi **"Prompt Đầu Vào (Input Messages)"** và **"Dữ Liệu Phản Hồi Đầu Ra"** theo từng request. Người vận hành đọc được toàn văn mọi thứ ta gửi.
- Nền tảng do **một cá nhân** vận hành (Huy Kira, Đà Nẵng); footer ghi *"Site đang trong quá trình đăng ký với bộ công thương"*.

Sẽ là mâu thuẫn nếu rulebook đánh red CarbonX vì lộ email, rồi chính app lại đẩy đúng những email đó qua một proxy bên thứ ba.

### Ràng buộc của chính dự án

Quyết định số 1 của rulebook là chạy **local**; adapter ghi *"Chạy hoàn toàn local … không gọi mạng"*. Và `docs/plans/7-review-engine-v2` §2 đo được rằng **tám check giá trị cao nhất đều thuần text**, còn vision là ô yếu nhất — 4/18 hình HisWise và 9/9 sơ đồ CarbonX **con người cũng không đọc nổi**, nên model nào cũng vô dụng ở đó.

## Options considered

| Option | Ưu | Nhược |
|---|---|---|
| **A. Đổi provider chính sang KiraAI** | Một base URL, nhiều model, có thể rẻ hơn | PII qua bên thứ ba; `kira-3.5-pro` nhiều khả năng chỉ là Gemini + markup; thêm một điểm hỏng; không kiểm chứng được model thật bên dưới |
| **B. Không dùng, giữ Gemini** (chọn) | Giữ đường dữ liệu ngắn nhất; không thêm bên thứ ba đọc được tài liệu; không phải viết code chưa test | Vẫn kẹt trần 50 request/ngày |
| **C. Thêm làm fallback vision, chỉ cho tài liệu đã khử PII** | Gỡ nghẽn quota cho Pass B khi Gemini hết lượt | Phải có bước khử PII đáng tin trước; chưa có |
| **D. Do nothing — không đánh giá** | Không tốn công | Bỏ lỡ một hướng gỡ trần quota |

## Decision

**Chọn B, mở đường cho C.**

1. **Không** đưa KiraAI vào `router.py` làm provider chính. Gemini vẫn là provider duy nhất của Pass B.
2. Ưu tiên gỡ nghẽn quota bằng cách **giảm số lời gọi**, không bằng cách đổi nhà cung cấp: Pass A deterministic (`plans/7` §3) xử lý tám check thuần text **không tốn quota**, và quyết định đúng những hình nào cần gửi lên Pass B. Trên HisWise, Pass A một mình đã ra 8/12 red.
3. **Điều kiện để mở option C sau này** — cả ba phải đạt:
   - Có bước khử PII chạy trước Pass B, và được kiểm trên một tài liệu có PII thật (CarbonX là fixture sẵn có).
   - Xác nhận được model thật bên dưới `kira-3.5-pro` (hỏi trực tiếp nhà cung cấp, hoặc so dấu vân tay đầu ra với Gemini).
   - Đo thật: cùng 10 hình diagram, so ledger KiraAI với ledger Gemini theo cột ID+Quote. Không "chắc là tốt hơn".

## Consequences

**Tốt**
- Đường dữ liệu không dài thêm; số bên đọc được tài liệu sinh viên không tăng.
- App nhất quán với hard rule 9 mà chính nó đang dùng để chấm người khác.
- Không thêm code chưa chạy test (shell hỏng cả session 2026-09-15 nên không test được — thêm provider lúc này là thêm nợ).

**Xấu / nợ kỹ thuật**
- Trần 50 request/ngày còn nguyên. Giảm tải là việc của Pass A, chưa làm.
- Chưa xác minh `kira-3.5-flash`, `kira-2.5-pro`, `kira-2.5-flash`, `gpt-4o-mini` có nhận ảnh không (mất kết nối browser giữa chừng). Nếu mở lại option C thì phải xác minh nốt.

**Phải làm tiếp**
- `plans/7` việc 1–3, 6–7: các check thuần text, không cần provider nào.
- Nếu sau này thêm provider: `router.py` đã thiết kế sẵn cho việc đó (*"Adding a provider means adding a class and one line here"*), thêm `KiraProvider` + `kira_api_key` vào `config.py` theo đúng mẫu `gemini_api_key`; key **chỉ** ở `server/.env` (guardrail `tools/check_guardrails.py` fail build nếu literal dạng API key lọt vào cây mã).

## Verification

Quyết định này đúng khi, sau khi làm xong Pass A của `plans/7`:
- Số lời gọi LLM mỗi lần review **giảm dưới 50** trên một tài liệu cỡ OTES (94 hình) — tức trần quota không còn là nút thắt và option A/C mất lý do tồn tại.
- Nếu vẫn vượt 50, mở lại option C với ba điều kiện ở trên.

Đo bằng: đếm request tới `/review` và `/diagram` trong một lần chạy đầy đủ trên fixture OTES.
