# Architecture patterns — kiến trúc khai báo quyết định hình dạng sequence và class diagram

**Thêm ở rulebook 1.1** (2026-09-15) sau khi Amy chỉ ra: sample SEQ-001 đúng cú pháp UML nhưng không nói theo kiến trúc nào, và rulebook không có luật bắt điều đó. Cùng một use case, ba kiến trúc cho ba sequence diagram khác nhau; reviewer không biết pattern thì không phân biệt được "đúng UML nhưng sai kiến trúc".

Nguyên tắc: **SDS §2.1 phải gọi tên style** (kèm ADR). Từ style suy ra: lifeline nào được phép xuất hiện, message được đi chiều nào, ranh giới nào phải ghi protocol, class diagram phải có package/tầng gì. Đây là **chain 7** trong `scoring.md` §5.

---

## 1. Nền chung — ECB của Jacobson (1992), dùng để đối chiếu mọi style

Ba vai (stereotype UML `«boundary»` `«control»` `«entity»`), gốc từ OOSE của Ivar Jacobson, sau đó vào Unified Process và ICONIX (robustness diagram):

| Vai | Là gì | Ví dụ |
|---|---|---|
| **Boundary** | Nơi actor (người hoặc hệ ngoài) chạm vào hệ thống | màn hình, REST controller, API client, adapter tới Jitsi |
| **Control** | Điều phối một use case, chứa logic nghiệp vụ không thuộc riêng entity nào | service, use-case interactor, view model |
| **Entity** | Thông tin sống lâu, thường persist | User, Schedule, Order |

**Luật robustness** — ai được gửi message cho ai. Đây là test cơ bản áp cho **mọi** sequence diagram bất kể style:

| Từ → tới | Actor | Boundary | Control | Entity |
|---|---|---|---|---|
| **Actor** | — | ✓ | ✗ | ✗ |
| **Boundary** | ✓ | chỉ trong cùng một boundary | ✓ | **✗** |
| **Control** | ✗ | ✓ | ✓ | ✓ |
| **Entity** | ✗ | ✗ | ✓ (hoặc publish event) | ✓ |

Hai vi phạm hay gặp nhất trong capstone: **boundary gọi thẳng entity** (màn hình gọi repository/DB, bỏ qua control) và **entity gọi boundary** (model tự gọi màn hình). Cả hai → red.

Lưu ý: **ECB-control ≠ MVC-controller.** ECB-control chứa logic use case; MVC-controller chỉ xử lý input người dùng (việc đó ở ECB là của boundary). Đừng nhầm khi map.

---

## 2. Catalogue — 5 style capstone FPT thực sự dùng

Mỗi style: vai → ECB · chiều gọi · dấu hiệu sequence đúng · dấu hiệu class diagram đúng · map C4 · lỗi hay gặp.

### A. Layered REST API — Controller → Service → Repository (Spring Boot, ASP.NET Web API, NestJS)

Style phổ biến nhất cho backend capstone. OTES khai báo biến thể này ("Domain Driven Design", Controller/Service/Repository).

| | |
|---|---|
| Vai → ECB | Controller = boundary · Service = control · Repository = boundary tới DB (adapter) · Entity/Model = entity · **DTO** = cấu trúc đi qua boundary, không phải entity |
| Chiều gọi | Client → Controller → Service → Repository → DB. **Chỉ đi xuống, không nhảy tầng.** Controller không gọi Repository. Service không biết HTTP. Repository không chứa logic nghiệp vụ |
| Sequence đúng | Lifeline theo đúng thứ tự trên; **ranh giới client↔API là container boundary, message qua đó ghi `HTTP verb + path`** (`POST /auth/login`); reply từ Controller là status code + body (`200 {token}`, `401`); Service trả domain object, Controller đổi sang DTO |
| Class diagram đúng | ≥ 3 package: `controller`/`api`, `service`/`application`, `repository`/`infrastructure` + `domain`/`entity`. Dependency chỉ đi xuống. **DTO và Entity là hai class khác nhau** (`LoginRequest`, `UserDto` vs `User`). Repository là interface, implementation ở infrastructure |
| C4 | L2: client container(s) + API container + DB container. L3 của API container = các package trên |
| Lỗi hay gặp | (1) class diagram **chỉ có entity**, không có controller/service/repository — sequence vẽ 4 tầng nhưng class chỉ có 1 tầng → chain 7e = 0 (**OTES**). (2) Controller gọi thẳng Repository. (3) Entity trả thẳng ra API (không DTO) → amber. (4) Ranh giới HTTP không ghi verb/path → 7d fail. (5) Mọi class chỉ có getter/setter → không phải service (**OTES**) |

### B. MVC — server-rendered web (ASP.NET MVC, Django, Rails, Spring MVC + Thymeleaf)

Theo Fowler (*GUI Architectures*), MVC cổ điển: Controller nhận input, cập nhật Model, View đọc Model để render. Trong web MVC hiện đại, View là template server render.

| | |
|---|---|
| Vai → ECB | View = boundary · Controller = boundary (xử lý input) **+ một phần control** · Model = entity (+ service nếu tách) |
| Chiều gọi | Browser → Controller (route) → Model/Service → Controller chọn View → View render Model → Browser. **View không gọi Controller ngược lại**, View không gọi DB |
| Sequence đúng | Lifeline: `:Browser` (actor), `:XxxController`, `:XxxService` hoặc `:Model`, `:XxxView`. Reply cuối là HTML. Nếu có "View gọi Model" thì phải là **đọc** (getter), không ghi |
| Class diagram đúng | Package `controllers`, `models`, `views` (hoặc templates). Controller phụ thuộc Model; View phụ thuộc Model; **Model không phụ thuộc ai** |
| C4 | Một web container + DB; L3 = 3 package |
| Lỗi hay gặp | Controller béo chứa toàn bộ nghiệp vụ (không có Service) → amber, hỏi ADR; View gọi thẳng DB → red; nhầm với REST API (không có View, trả JSON) — hai style khác nhau, phải chọn một |

### C. MVVM — Flutter recommended architecture (Riverpod/Provider/Bloc), Android Jetpack, WPF

Theo *Flutter — Guide to app architecture*: **UI layer** (View + ViewModel) và **Data layer** (Repository + Service), có thể thêm **Domain layer** (use-case) ở giữa. Data chảy **một chiều**: Repository là single source of truth, ViewModel giữ UI state, View chỉ render state và gửi event. Chính app `srs-review-ai` dùng style này.

| | |
|---|---|
| Vai → ECB | View (Widget/Screen) = boundary · ViewModel = control · Repository = control-ish (điều phối nguồn dữ liệu) · Service (API client, local DB wrapper) = boundary tới hệ ngoài · Model = entity |
| Chiều gọi | View → ViewModel (event/command) → Repository → Service → (network/DB). Dữ liệu về theo chiều ngược **qua state**, không phải qua return trực tiếp tới View. **View không gọi Repository. ViewModel không biết Widget** |
| Sequence đúng | Lifeline: `:Lecturer`, `:LoginScreen`, `:LoginViewModel`, `:AuthRepository`, `:AuthApiClient`. Message cuối về View là **state changed / notifyListeners / stream emit**, vẽ là message thường (không phải reply) từ ViewModel tới View. Reply đồng bộ thường dừng ở ViewModel |
| Class diagram đúng | Package `ui/<feature>/view`, `ui/<feature>/view_model`, `data/repositories`, `data/services`, `domain/models`. ViewModel phụ thuộc Repository (interface), không phụ thuộc Widget. Model **không** có annotation UI |
| C4 | L2: mobile/desktop app container + backend API container. L3 của app = UI / Domain / Data |
| Lỗi hay gặp | Widget gọi thẳng API client → red (boundary→boundary ngoài, nhảy tầng); ViewModel import Flutter widget → amber; Repository trả DTO thô của API lên ViewModel (không map sang Model) → amber; không có state object nào trong class diagram → nghi không phải MVVM thật |

### D. Clean Architecture / Onion — Entities → Use cases → Interface adapters → Frameworks

Theo Robert C. Martin (2012): **Dependency Rule** — source code dependency chỉ trỏ **vào trong**. Vòng trong không biết gì về vòng ngoài. Vượt ranh giới ngược chiều bằng **interface (port)** ở vòng trong, implementation ở vòng ngoài.

| | |
|---|---|
| Vai → ECB | Entity = entity · Use case / Interactor = control · Controller, Presenter, Gateway = boundary (interface adapters) · Framework/DB/Web = ngoài cùng |
| Chiều gọi | Controller → Use case (qua **input port** interface) → Entity; Use case → **output port** (interface) ← Presenter implement. Use case gọi Gateway interface ← Repository implement. **Không có mũi tên nào từ vòng trong trỏ ra class cụ thể của vòng ngoài** |
| Sequence đúng | Lifeline có cả interface và implementation, hoặc ghi rõ `:IUserGateway` / `:UserGatewayImpl`; use case nhận **request model**, trả **response model** (không phải HTTP, không phải entity thô); Presenter đổi response model sang view model |
| Class diagram đúng | 4 vòng = 4 package; **mọi dependency đi vào trong**; interface (port) nằm ở vòng use case, implementation ở vòng ngoài, realization dashed hollow triangle chỉ **vào trong** |
| C4 | Giống A về container; L3 = 4 vòng |
| Lỗi hay gặp | Gọi là "Clean" nhưng use case import ORM/framework → red (vi phạm Dependency Rule); không có interface nào ở vòng trong → không phải Clean, chỉ là Layered (A) đổi tên → amber, sửa ADR; **DDD ≠ Clean** — nói DDD (như OTES) phải có aggregate/bounded context, không thì chỉ là Layered |

### E. Client–server + hệ ngoài realtime (OTES: desktop app + REST API + Jitsi + Quiznow)

Không phải một style riêng — là **ghép**: client theo C (hoặc B), backend theo A (hoặc D), cộng ≥ 1 hệ ngoài. Luật ghép:

| | |
|---|---|
| Lifeline hệ ngoài | Vẽ là lifeline `:Jitsi` / `:QuiznowServer` với stereotype `«external system»`; hoặc tách thành actor hệ thống ở mép phải. **Không** vẽ là actor người |
| Ranh giới | Mỗi lần qua container khác → message ghi **protocol** (`HTTPS POST /…`, `BOSH`, `WebSocket`, `gRPC`). Vẽ đường chấm dọc hoặc `ref` để thấy ranh giới |
| Lỗi | Client gọi thẳng hệ ngoài **và** backend cũng gọi hệ ngoài mà không giải thích ai là owner → amber, hỏi ADR; message qua ranh giới không có protocol → 7d fail (**OTES: 0/5 ranh giới có protocol**) |

*(Microservices: mỗi service một container, gọi nhau qua HTTP/message queue, có saga/eventual consistency — capstone hiếm dùng thật; nếu khai báo, áp E cho từng cặp service và đòi ADR cho việc tách.)*

---

## 3. Chain 7 — sequence ↔ kiến trúc khai báo (`scoring.md` §5)

Năm tỉ lệ, trung bình cộng bằng nhau. **Điều kiện tiên quyết**: SDS §2.1 gọi tên style. Không gọi tên → 7a = 0, và 7b–7e đo theo style **suy luận** từ tài liệu (mục 4) nhưng ledger ghi `info: style not declared` — không được coi suy luận là sự thật.

| # | Đo gì | Phân số | Nguồn |
|---|---|---|---|
| 7a | Style được khai báo + có ADR | 1 nếu §2.1 nêu tên style **và** có ADR chọn nó; 0.5 nếu nêu tên không ADR; 0 nếu không nêu | §2.1, §6 |
| 7b | Lifeline thuộc vai của style | số lifeline map được vào một vai của style (hoặc `«external system»`) / tổng lifeline toàn bộ sequence diagram | mục 2, cột "Vai" |
| 7c | Message đi đúng chiều | số message tuân luật robustness (mục 1) **và** luật chiều gọi của style (mục 2) / tổng message. Nhảy tầng, boundary→entity, entity→boundary, vòng trong→vòng ngoài (Clean) = vi phạm | mục 1 + 2 |
| 7d | Ranh giới container có protocol | số message vượt ranh giới container (client↔API, API↔hệ ngoài, API↔DB nếu vẽ) **có ghi protocol/verb/path** / tổng message vượt ranh giới | mục 2E |
| 7e | Class diagram phản ánh style | 1 nếu class diagram có đủ package/tầng của style và dependency đúng chiều; 0.5 nếu có tầng nhưng thiếu ≥1 hoặc dependency sai chiều; 0 nếu class diagram chỉ có entity trong khi sequence vẽ nhiều tầng | mục 2, cột "Class diagram đúng" |

**Không đếm trùng với chain 3.** Chain 3 hỏi "lifeline này **có trong class diagram** không" (tồn tại). Chain 7b hỏi "lifeline này **là vai gì trong kiến trúc**" (đúng vai). Một lifeline có thể có class nhưng sai vai (View gọi thẳng Repository — cả hai đều là class, nhưng chiều sai → 7c bắt). Chain 7e hỏi class diagram **có cấu trúc tầng** không; chain 3 không hỏi.

**Ví dụ áp OTES** (sequence F76, F77, F80; class F75): 7a = 0.5 (nói "Domain Driven Design", không ADR, và thật ra là Layered A). 7b = 24/26 ≈ 0.92 — `Room Page`, `: Schedule Controller`, `:schedule service`, `:schedule repository`, `schedule`, `database`, `Jitsi`, `Quiznow server` đều map vào vai của A (Jitsi/Quiznow là external); chỉ `:Lecturer` actor không tính, và "database" là mơ hồ. 7c ≈ 0.9 — thứ tự Page→Controller→Service→Repository đúng; F77 `Room Page → Jitsi` là boundary→external, hợp lệ; F80 bỏ Repository là **thiếu**, không phải sai chiều. 7d = **0/5** — ba lần Page→Controller không ghi HTTP, hai lần gọi Jitsi/Quiznow không ghi protocol. 7e = **0** — class diagram chỉ có 10 entity, không một controller/service/repository nào, dù sequence vẽ đủ 4 tầng. Chain 7 = (0.5+0.92+0.9+0+0)/5 = **0.46**. Kết luận đúng bản chất: **sequence của OTES theo kiến trúc, class diagram thì không** — hai artefact tả hai hệ thống khác nhau.

---

## 4. Suy luận style khi §2.1 im lặng — chỉ để chấm 7b–7e, luôn kèm `info`

| Thấy trong tài liệu | Ứng viên | Không phải |
|---|---|---|
| `Controller`, `Service`, `Repository`, trả JSON, `POST /…` | **A Layered REST** | MVC (không có View render) |
| `Controller` + `View`/template + trả HTML | **B MVC** | REST |
| `ViewModel`, `Provider`, `Bloc`, `Riverpod`, `StateNotifier`, `notifyListeners`, Flutter/Android | **C MVVM** | MVC |
| `UseCase`, `Interactor`, `Port`, `Presenter`, `Gateway`, "dependency rule" | **D Clean** | Layered đổi tên — kiểm interface ở vòng trong |
| "DDD", "Domain Driven Design" | **D nếu có aggregate/bounded context**, còn không → **A** | — |
| Desktop/mobile app + server + Jitsi/Firebase/Zoom/Quiznow | **E ghép** | — |

Ghi vào ledger: `info: §2.1 không khai báo style; chain 7 chấm theo style suy luận <X> từ <bằng chứng>`.

---

## 5. Nguồn

- Ivar Jacobson, *Object-Oriented Software Engineering: A Use Case Driven Approach* (1992), tr. 130–133 — gốc của ECB; tóm ở [Entity–control–boundary, Wikipedia](https://en.wikipedia.org/wiki/Entity%E2%80%93control%E2%80%93boundary) và [Visual Paradigm — Robustness analysis tutorial](https://www.visual-paradigm.com/guide/uml-unified-modeling-language/robustness-analysis-tutorial/)
- Martin Fowler, [*GUI Architectures*](https://martinfowler.com/eaaDev/uiArchs.html) (2006) — MVC, Presentation Model (tiền thân MVVM), Passive View, Supervising Controller
- Robert C. Martin, [*The Clean Architecture*](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html) (2012) — Dependency Rule, 4 vòng, ports
- Flutter team, [*Guide to app architecture*](https://docs.flutter.dev/app-architecture/guide) — UI/Data/Domain layer, MVVM, unidirectional data flow
- Steve Smith (Ardalis), [*Should Controllers Reference Repositories or Services*](https://ardalis.com/should-controllers-reference-repositories-services/) — vì sao Controller không gọi Repository
