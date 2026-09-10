# Roadmap build SRS Review AI — học gì, làm gì, chứng minh bằng gì

Cập nhật: 2026-09-10. **Planning only: chưa triển khai các mốc bên dưới.**

## Understanding

Xây tiếp app có sẵn để sinh viên nhập PDF/DOCX SRS, xem cây section/requirement,
review text và sơ đồ, nhận findings có nguồn, rồi xuất báo cáo.
Flutter chạy desktop local; FastAPI giữ API key và gọi model trên Vercel.
Không biến project thành một nền tảng RAG tổng quát hay công cụ chấm điểm chính thức.

## Existing Code

| Đã có để tái sử dụng | Chưa được xem là đã giải quyết |
|---|---|
| Flutter MVVM, Riverpod, Dio, màn hình desktop, mock | Luồng PDF thật phải được kiểm end-to-end trên desktop đích |
| Syncfusion PDF text extraction; DOCX archive/XML | Text đọc được không đồng nghĩa đúng thứ tự, đúng ô bảng hoặc đọc được hình |
| `RequirementSplitter`, `SrsDocument` | Probe đã tái hiện mất occurrence trùng mã và mất bước đánh số |
| `SyllabusChecks`: F7/F8/F9 | Chỉ có ý nghĩa nếu đầu vào đúng và đúng syllabus đang áp dụng |
| FastAPI `/health`, `/rubric`, `/review`, `/ask` | Chưa chứng minh triển khai Vercel và luồng ảnh thật đã đạt |
| Quote verification, cache process-local, rate limiter, CI | Quote đúng không chứng minh diễn giải đúng; cache/RAM không bền khi scale |

Nguồn: [phân tích OTES](OTES-SRS-analysis.md), [plan v2](workflow-v2-plan.md),
[probe lưu trong repo](evidence/README.md), [kiến trúc hiện tại](adr/0001-architecture.md).

### Đính chính quan trọng khi dùng plan v2

Roadmap này là hướng dẫn thực thi mới hơn; không dùng những khẳng định quá mạnh
trong plan v2 làm điều kiện nghiệm thu:

- **0 UC** là kết quả `pdftotext → splitter` và input tổng hợp. Chưa đo
  `Syncfusion → app UI` nên không nói chắc app thật báo 0 trên OTES.
- **63 occurrence / 52 ID nguyên văn / 51 ID chuẩn hoá** là mốc inventory OTES,
  không phải 63 yêu cầu độc lập đã được nghiệp vụ xác nhận. Giữ cả ba số.
- OTES là tài liệu **2020**. Không áp ngược syllabus 2026 hoặc ngưỡng 20–25 UC
  để kết luận dự án này không đủ điều kiện bảo vệ. Profile syllabus phải có nguồn,
  phiên bản và được người dùng chọn; mặc định chỉ review chất lượng tài liệu.
- Trùng ID và heading rỗng có thể kiểm tất định. Mâu thuẫn ngữ nghĩa cần cặp
  bằng chứng + bước đánh giá, không hứa keyword tự phát hiện mọi mâu thuẫn.
  Hai evidence có thể cùng một trang; không bắt buộc nằm ở hai trang khác nhau.
- Finding thủ công OTES là **seed để annotation**, chưa phải gold set hoàn chỉnh.
  Không dùng chỉ tiêu mơ hồ “6/7 lỗi” khi chưa định danh và chốt bộ đánh giá.
- Có image/vector object không chứng minh đó là sơ đồ (có thể là logo/đường bảng).
  Chưa biết tổng số sơ đồ, nên không dùng mẫu số 63 UC để tuyên bố coverage ảnh.
- Probe pdfplumber chỉ đo cấu hình mặc định trên một số trang, không loại bỏ mọi
  parser khác. Comment trong code không thay thế việc kiểm API package hiện tại.
- Không hứa exactly-once model call: crash sau khi provider trả nhưng trước khi
  checkpoint được ghi vẫn có thể gây gọi lại. Chỉ cam kết không gửi lại kết quả
  **đã lưu thành công** và chưa đổi input/version.

## Requirements

- Functional: inventory không mất nội dung; review theo section/unit; kiểm nguồn;
  app tự đề xuất trang sơ đồ, có ngân sách và preview; checkpoint; export coverage.
- Reliability: không cắt ngầm file/unit; lỗi từng bước có trạng thái và retry;
  ngừng review nếu extraction không đủ tin cậy.
- Security: key ở server; tài liệu/OCR là dữ liệu không đáng tin, không phải lệnh;
  giới hạn bytes/page/giải nén; không log toàn bộ tài liệu hoặc secrets.
- Evaluation: tách chất lượng extraction, độ phủ review, chất lượng findings,
  token/latency; không dùng điểm rubric thay cho bốn chỉ số này.

## Assumptions

- Tiếp tục code hiện có, không viết lại. Ưu tiên desktop; Android cần gate riêng
  nếu dùng Python helper cục bộ (helper desktop không tự chạy được trên Android).
- App phải mở khi xử lý; đóng app thì dừng, mở lại resume phần đã checkpoint.
- Giữ weights rubric là đề xuất, chờ bảng chính thức từ khoa.
- App tự chọn trang có sơ đồ theo quyết định người dùng; vẫn cho xem/bỏ chọn
  trước khi gửi. Budget 12 trang chỉ là mặc định thử nghiệm, không phải mức đã đo.
- Lịch dưới là **ước lượng 3 sprint**, không bảo đảm xong trong 3 tuần nếu còn
  phải học Flutter/Python từ đầu hoặc đổi engine extraction.

## Cần tìm hiểu gì — học đến đâu là đủ để bắt tay làm

Không cần học hết một framework. Mỗi chủ đề phải tạo được một bài tập kiểm chứng.

| Thứ tự | Cần hiểu | Bài tập trên chính repo | Đủ để đi tiếp khi |
|---|---|---|---|
| L1 | SRS: scope, actor, UC, BR, NFR; requirement vs flow step | Annotate 3 UC nhiều trang + 2 NFR; đánh dấu heading/step/caption | Người thứ hai đối chiếu được từng nhãn với trang nguồn |
| L2 | Dart: null safety, collections, RegExp, JSON, async; state machine parsing | Viết fixture 2 UC cùng mã, main flow `1./2.`, caption xen giữa | Test thể hiện dữ liệu cần giữ, không chỉ kiểm số item |
| L3 | PDF layout vs text; DOCX XML; page/bbox/offset; OCR vs vision | Xuất output Syncfusion các trang OTES khó và so với text nguồn | Giải thích được lỗi extraction hay lỗi splitter; không sửa nguồn bằng LLM |
| L4 | Flutter MVVM + Riverpod; isolate; local/server state; cancel | Mock màn hình inventory → progress → lỗi → resume | UI không treo; cancel không đánh dấu item là đã review |
| L5 | FastAPI/Pydantic + Dio; schema version; HTTP 401/413/422/429/5xx | Gọi mock `/review`, tạo input thiếu field/quá lớn | Dart/Python cùng hiểu error/result; API key không ở app |
| L6 | Structured output, grounding, quote verification, prompt injection | Cho model/mock quote bịa và tài liệu chứa “ignore instructions” | Quote bịa bị loại; nội dung tài liệu không điều khiển tool hoặc lộ key |
| L7 | Local persistence, atomic write, fingerprint, retry, idempotency | Kill ứng dụng sau khi lưu vài unit, mở lại | Unit đã lưu không gọi lại; input/version đổi thì invalidate |
| L8 | Vision: render/crop, OCR labels, ảnh vector, token/byte budget | Thử sơ đồ nhỏ chữ; crop + resize rồi kiểm khả năng đọc | Không ép ảnh xuống một ngưỡng bytes làm mất nhãn; biết abstain |
| L9 | Serverless Vercel: duration, body size, ephemeral state, secrets | Deploy staging `/health` và 1 request bounded | URL thật chạy được; không dựa vào local RAM để lưu job/quota toàn cục |
| L10 | Test pyramid; precision/recall, false positives, coverage, CI | Chốt bộ annotated positives + negatives; chạy baseline vs bản mới | Có bảng kết quả tái chạy, không chỉ screenshot “all green” |

### Tài liệu nên đọc có chọn lọc

Đây là danh sách đọc, không phải bằng chứng rằng project đã đạt khả năng tương ứng:

- [Dart language](https://dart.dev/language), [Dart async](https://dart.dev/libraries/async/async-await).
- [Flutter architecture guide](https://docs.flutter.dev/app-architecture/guide),
  [Flutter testing](https://docs.flutter.dev/testing/overview), [Riverpod](https://riverpod.dev/docs/introduction/getting_started).
- [FastAPI tutorial](https://fastapi.tiangolo.com/tutorial/), [Pydantic](https://docs.pydantic.dev/latest/).
- [Docling document model](https://docling-project.github.io/docling/concepts/docling_document/)
  và [chunking](https://docling-project.github.io/docling/concepts/chunking/): học provenance;
  chunk không tự động là một requirement.
- [Gemini structured output](https://ai.google.dev/gemini-api/docs/structured-output),
  [image understanding](https://ai.google.dev/gemini-api/docs/image-understanding),
  [token counting](https://ai.google.dev/gemini-api/docs/tokens).
- [Vercel FastAPI](https://vercel.com/docs/frameworks/backend/fastapi),
  [function limits](https://vercel.com/docs/functions/limitations): kiểm lại theo plan/runtime lúc deploy.
- [NALABS](https://github.com/eduardenoiu/NALABS): tham khảo smell rules, không coi
  keyword hit là kết luận lỗi; giữ attribution nếu tái dùng code/danh sách.

## Plan — milestones có đầu ra và gate

### M0 · Baseline + bộ mẫu có nguồn (sprint 1, học L1–L3)

- Chạy baseline hiện tại, lưu command/version/kết quả. Capturing output thật
  `ParseService` trên desktop, không dùng pdftotext thay thế rồi gọi là E2E.
- OTES: chọn range SRS 23–155, giữ context ngoài SRS như scope trang 17 với nhãn
  “context”, không tính lẫn vào inventory UC.
- Ghi manifest: hash file, physical page (1-based), source ID nguyên văn,
  occurrence, đoạn text/bbox nếu có. DOCX không có physical page ổn định thì
  dùng paragraph/table/cell locator, không bịa số trang PDF.
- Gate: đối chiếu được 63/52/51 từ nguồn; annotate mẫu nhiều trang, trùng ID,
  heading rỗng, main flow đánh số. Full PDF giữ local; chỉ commit fixture được
  phép chia sẻ hoặc fixture tổng hợp, không mặc định đưa tài liệu bên thứ ba lên GitHub.

### Parallel gates với M0–M1

- **P0 · Rubric source:** xin template/marking sheet và điều kiện syllabus từ GVHD,
  ghi nguồn + phiên bản. Nếu chưa có, mọi ngưỡng F7/F8/F9 và weights chỉ mang nhãn
  **provisional**; không dùng chúng để kết luận đạt/trượt.
- **P1 · Vercel smoke:** deploy `/health` và một `/review` bounded sớm (tuần 1),
  đo request bytes, response bytes, duration và lỗi thật. 200 KB là **policy thử
  nghiệm**, chưa phải số đo; nếu vượt, giảm context/compress theo dữ liệu thật,
  không nâng nguyện vọng.

### M1 · Inventory không mất dữ liệu (sprint 1, học L2–L4)

- Mở rộng parser theo trạng thái section/UC/flow; không sửa chỉ bằng một regex
  khiến section tiếp theo bị nối vào UC đang mở.
- `sourceId` không là primary key. `unitKey` dùng document hash + locator ổn định
  trong cùng parser version; fingerprint nội dung và parser version lưu riêng.
- FR/NFR/BR, heading rỗng và unknown block là first-class; UI cho xem/chỉnh phân
  loại rồi lưu override. Không tự sửa UC0134 thành ID “đúng” theo suy đoán.
- Gate: synthetic regression giữ cả hai UC trùng mã và mọi bước; OTES đủ inventory;
  >40 units không bị cắt im lặng; file 27.37 MiB được nhận sau nâng cap có chủ đích.

### M2 · Review text có bằng chứng (sprint 2, học L5–L6, L10)

- Tái dùng `SyllabusChecks`; thêm duplicate IDs, empty section, reference checks.
  Profile chất lượng chung tách khỏi profile syllabus theo khoá học/năm.
- Local review: whole UC + section context gọn, không cắt flow khỏi BR.
  Global review: tạo candidate pairs bằng ID/entity/reference, rồi đánh giá
  mâu thuẫn trên source passages. Tách “candidate” khỏi “confirmed finding”.
- Schema result: source refs, evidence spans, severity, status và lý do abstain;
  page do parser cấp, không tin page model tự viết.
- Gate: kiểm quote trên source unit tương ứng; findings mâu thuẫn giữ cả hai
  evidence; bộ positive/negative đã annotation có precision/recall theo loại.
  **Coverage (bao nhiêu unit được duyệt) và quality (bao nhiêu finding đúng) là
  hai chỉ số riêng; không nhân coverage thành điểm.** Không hứa zero false
  positive ngoài tập kiểm thử.

### M3 · Vercel + resume ổn định (sprint 2, học L7/L9)

- FastAPI nhận review unit bounded, không upload PDF 27 MiB qua Function body.
  Default text payload 200 KB là policy thử nghiệm; ảnh có budget riêng.
- Cache fingerprint gồm toàn bộ input ảnh hưởng đáp án: text/context/source refs,
  image hash (bao gồm trường hợp **không có ảnh**), model, prompt, rubric, schema
  và options. Chỉ đổi ảnh phải cache miss.
- Regression bắt buộc: cùng unit, cùng text, một request có ảnh và một request
  không ảnh phải cho **hai cache key khác nhau**; kết quả có ảnh không được trả
  cho request không ảnh.
- Local checkpoint ghi atomically; timeout/429 có backoff giới hạn, 401 dừng với
  hướng dẫn; cancel có trạng thái riêng. RAM server chỉ là cache tăng tốc;
  checkpoint là nguồn bền cho resume. Gate “0 call lặp lại” đo từ log client,
  không suy ra từ cache server.
- Trước khi pin model, benchmark ít nhất 5 unit đại diện bằng key thật: text-only,
  flow dài, quote khó, bảng dính chữ và ảnh nhỏ; ghi usage/latency. Tên model trong
  tài liệu marketing không thay thế benchmark này.
- API public cần auth phù hợp + shared quota store hoặc platform controls;
  không gọi một token nhúng trong desktop và process-local counter là per-user security.
- Gate: staging URL `/health` và `/review` thật; 413/422/429/timeout test được;
  kill/reopen chỉ skip unit đã lưu có fingerprint khớp. Báo cửa sổ có thể gọi lại.

### M4 · App tự chọn sơ đồ, kiểm có ngân sách (sprint 3, học L3/L8)

- Spike renderer/crop trước: kiểm API và licence bản package đang dùng. Thử
  vector diagram lẫn raster image; image count không đủ nhận diện diagram.
- Auto-select từ layout/caption/labels; preview danh sách cho user sửa. Đo precision/
  recall của detector trên tập ảnh annotated, không giả định UC nào cũng có một hình.
- Chỉ gửi crop/page cần thiết + text liên quan. Cap số trang, tổng tokens dự kiến,
  bytes request **sau base64/JSON**; đo usage thật. Vượt budget thì hoãn, không
  downsample đến mức không còn đọc được nhãn.
- Gate: đổi ảnh đổi cache key; log không chứa base64; provider receipt không đủ
  gọi là “đã hiểu hình”: cần valid result hoặc trạng thái failed/uncertain.
  Coverage ghi candidate/extracted/reviewed/skipped/failed và lý do.
- Nếu cần Docling/Python helper: desktop-only spike, đánh giá cài đặt/RAM/licence;
  không mặc định nhét vào Vercel hoặc cho là hoạt động trên Android.

### M5 · Export + nghiệm thu (sprint 3, học L10)

- Export findings + source refs + text/image coverage + scope + rubric version +
  limitations. “Không thấy lỗi trong phần đã kiểm” khác “SRS hoàn toàn đúng”.
- CI: Flutter analyze/test, pytest, ruff check/format, contract tests, guardrails.
- E2E: nhập OTES → xác nhận inventory → chọn section → review text/ảnh → ngắt
  mạng → resume → export. Có offline mock để demo nhưng tách rõ khỏi kết quả live.
- Gate: test trên desktop đích, đối chiếu 10 citations, ghi token/latency thực tế;
  ít nhất một tài liệu khác chưa dùng tuning để tránh overfit OTES.
- Nếu rubric chính thức vẫn chưa có, export ghi rõ **provisional** và nguồn của
  mọi ngưỡng; không đổi weights để làm đẹp kết quả demo.

## Files / Modules Affected

Lần lập roadmap này chỉ đổi `docs/roadmap.md` và thêm notice vào plan v2.
Khi implement, ownership theo concern:

| Workstream | Modules chính | Phụ thuộc |
|---|---|---|
| Extraction/inventory | `parse_service.dart`, `requirement_splitter.dart`, `srs_document.dart`, fixtures | M0 trước M1 |
| UI/local orchestration | ViewModels, `review_repository.dart`, checkpoint service, export | Chốt model/schema M1 trước |
| API/LLM | `schemas.py`, `main.py`, `prompt.py`, cache/provider, contract fixtures | Có thể học/spike song song; tích hợp sau schema |
| QA/evaluation | tests, annotation manifest, CI, reproducible benchmark | Bắt đầu M0, chạy xuyên suốt |

Nếu một người làm: đi M0 → M1 → M2 → M3 → M4 → M5; không dựng framework agent/RAG.
Nếu nhóm nhiều người: phân theo bốn concern trên, không chia theo “mỗi người một màn
hình” khiến contract và parser không ai chịu trách nhiệm.

## Risks

- Extraction sai kéo theo mọi check sai → M0/M1 là blocker của semantic review.
- Gold set ít/thiên lệch → reviewer thứ hai kiểm annotation; giữ tài liệu holdout.
- Vision tốn tiền hoặc không đọc được chữ → preview, budget, usage, abstain.
- Helper local đổi phạm vi đóng gói → quyết định riêng sau spike, giữ kế hoạch desktop.
- Không đủ thời gian → giảm Q&A nâng cao/diff/theme trước; không bỏ integrity,
  citation, bảo mật và báo cáo phần chưa review để làm đẹp demo.

## Acceptance Criteria

- **ROADMAP-AC1:** mỗi M0–M5 có deliverable và gate, mỗi L1–L10 có bài tập thực hành.
- **ROADMAP-AC2:** phân biệt rõ đang có / dự kiến / chưa đo; không coi probe là E2E.
- **ROADMAP-AC3:** giữ đúng quyết định Flutter local, Vercel proxy, auto-select ảnh,
  rubric đề xuất; không tự triển khai hoặc đổi dependency trong lượt planning.
- **ROADMAP-AC4:** khi nghiệm thu app: inventory, source refs, resume, input validation,
  cache image/context, coverage và desktop E2E đều có test; số liệu model phải đo thật.

## Bắt đầu ngay khi được yêu cầu implement

1. Làm L1–L3 gắn với M0, xuất manifest và fixture nhỏ (không upload PDF lên repo).
2. Chốt schema locator/unit identity và viết test đỏ cho ba ca splitter.
3. Chỉ sau đó sửa M1; chưa mua dịch vụ, chưa thêm vector DB, chưa đổi engine theo cảm tính.
