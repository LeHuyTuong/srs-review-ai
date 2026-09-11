# Architecture Review — SRS Review AI (Flutter app)

**Ngày:** 2026-09-11
**Phạm vi:** `srs-review-ai/app` (Flutter, Dart SDK ^3.12.2, package `srs_review_ai`)
**Góc nhìn:** sẵn sàng cho phát triển **mobile** (Android/iOS)
**Người review:** WorkBuddy AI — DesignMdArchitect

---

## 0. Kết luận nhanh (TL;DR)

Kiến trúc **đã chuẩn và tốt hơn mức trung bình của một dự án Flutter sinh viên** — thậm chí có
những thứ hiếm gặp ở dự án thương mại (guardrail phân tầng chạy trong CI, versioning contract
3 phía, 103 test). **Không cần đập đi làm lại.**

Vấn đề thật sự **không nằm ở kiến trúc**, mà ở cấu hình nền tảng: quyền `INTERNET` chỉ có ở
manifest `debug`, và HTTP cleartext bị Android chặn. **Cả hai đã được sửa — xem §7.**

> **Đính chính so với bản đầu.** Bản review đầu tiên của tôi nói app "đang tối ưu cho desktop,
> không phải mobile". Điều đó **sai**. `workspace_shell_test.dart` có test cho bề rộng 390px
> (`inventory row fits a 390px phone without overflow`, `narrow screens get a glass tab bar`,
> tap target 44–48px) và tất cả đều pass. Shell dùng `NavigationRail` khi rộng ≥1100px và
> `Drawer` + glass tab bar khi hẹp — đúng chuẩn adaptive. **Layout không phải vấn đề.**

Nói cách khác: **khung xương kiến trúc ổn — chỉ cần một lượt "mobile hardening" ở tầng cấu hình
nền tảng, không phải refactor kiến trúc.**

Điểm số tổng: **8/10 về kiến trúc**, **7/10 về mức sẵn sàng mobile** (sau khi vá §7).

---

## 1. Kiến trúc hiện tại

```
app/lib/
├── main.dart                      # ProviderScope + override SharedPreferences
├── core/                          # hạ tầng dùng chung, không phụ thuộc feature
│   ├── app_config.dart            # --dart-define, KHÔNG chứa secret
│   ├── providers.dart             # "composition root" — nơi duy nhất wiring DI
│   ├── router/app_router.dart     # go_router + StatefulShellRoute (3 branch)
│   ├── theme/                     # app_theme, app_tokens, glass_tokens, workspace_colors
│   └── widgets/                   # content_shell, glass_surface, chrome_insets
├── data/                          # data layer — KHÔNG import features/, KHÔNG import material
│   ├── models/                    # SrsDocument, ReviewResult, DeterministicFinding (immutable)
│   ├── parsing/                   # requirement_splitter
│   ├── checks/                    # rubric_config, syllabus_checks (F7/F8/F9)
│   ├── repositories/              # DocumentRepository, ReviewRepository
│   └── services/                  # ReviewApi (interface) + ApiService + MockReviewApi,
│                                  # SessionStore, FilePickerService, ParseService
└── features/                      # feature-first, mỗi feature = models / view_model / view
    ├── workspace/                 # feature chính (shell + 3 tab + modals)
    ├── document/                  # màn hình legacy
    └── review/                    # màn hình legacy
```

**Stack đang dùng**

| Thành phần | Lựa chọn | Đánh giá |
|---|---|---|
| State management | `flutter_riverpod` ^3.4.3 (`Notifier` / `NotifierProvider`) | ✅ Hiện đại, đúng |
| Routing | `go_router` ^17.5.0 + `StatefulShellRoute.indexedStack` | ✅ Chuẩn cho bottom-nav |
| HTTP | `dio` ^5.11.1 | ✅ |
| Local storage | `shared_preferences` ^2.5.5 | ⚠️ ổn cho history, xem §4.3 |
| PDF/DOCX | `syncfusion_flutter_pdf` + `archive` + `xml` | ✅ |
| Lint | `flutter_lints` + `analysis_options` siết chặt | ✅ Rất tốt |
| Code-gen | **Không dùng** (hand-written models — có ADR) | ⚠️ Chấp nhận được, xem §4.3 |

### Luồng dữ liệu (một chiều, đúng chuẩn MVVM)

```
View (ConsumerWidget)
   │ ref.watch(state) / gọi command
   ▼
ViewModel (Notifier<State>)          ← không import material, không BuildContext
   │ ref.read(provider)
   ▼
Repository (DocumentRepository / ReviewRepository)
   │
   ▼
Service (ReviewApi ⇄ ApiService | MockReviewApi, ParseService, SessionStore)
   │
   ▼
Proxy FastAPI (http)  /  shared_preferences  /  file_picker
```

---

## 2. Điểm mạnh — những thứ ĐÃ đúng best practices

Đây là phần đáng giữ nguyên, không được phá khi refactor:

1. **Phân tầng có "hàng rào" thực thi tự động.** `tools/check_guardrails.py` chạy trong CI và
   pre-commit, chặn cứng 6 nhóm luật: secrets, no-direct-LLM, **MVVM layering**, dependency pins,
   contract version, design tokens. Tôi đã kiểm chứng độc lập bằng ripgrep:
   - `data/` **không** import `package:flutter/material.dart` → sạch.
   - `features/*/view_model/` **không** import material và **không** import `/view/` → sạch.
   - View **không** import `data/services/` hay `package:dio/` → sạch.
   Đây là điểm mạnh nhất của repo. Rất ít dự án Flutter làm được điều này.

2. **Đảo mock/real bằng DI, không bằng `if` rải rác.** `ReviewApi` là `abstract interface class`;
   `MockReviewApi` và `ApiService` cùng implements; `reviewApiProvider` chọn một lần duy nhất
   (`core/providers.dart:72-75`). Đúng chuẩn Dependency Inversion.

3. **Composition root tập trung.** Toàn bộ wiring nằm ở `core/providers.dart` — một chỗ để đọc,
   một chỗ để override trong test.

4. **App không giữ credential nào.** `AppConfig` chỉ đọc `--dart-define`; không có SDK LLM, không
   có API key. Có guardrail chặn cả việc vô tình thêm URL provider. Rất tốt về mặt bảo mật.

5. **Routing đúng chuẩn mobile.** `StatefulShellRoute.indexedStack` + `StatefulShellBranch` cho 3
   tab, mỗi branch giữ state riêng (scroll/tab) — đây chính xác là pattern Flutter khuyến nghị cho
   bottom navigation. Không dùng `Navigator.push` thủ công.

6. **Immutable state + `copyWith` ở ViewModel.** `WorkspaceState`, `DocumentState`, `ReviewState`
   đều là class bất biến với `copyWith` — đúng chuẩn, dễ test, tránh bug "quên rebuild".

7. **Xử lý vòng đời đúng.** `ref.onDispose` huỷ `StreamSubscription` và `Timer`
   (`workspace_view_model.dart:183-187`); kiểm tra `ref.mounted` trước khi ghi state sau await
   (`:638`). Đây là những chi tiết người mới hay bỏ sót.

8. **Versioning contract 3 phía.** `kContractVersion = '1.0.0'` ở Dart, `CONTRACT_VERSION` ở Python,
   `x-contract-version` ở JSON schema — guardrail fail build nếu lệch. Parse **strict**: enum lạ thì
   throw chứ không âm thầm hạ cấp (`review_models.dart:32-35`).

9. **Test thật.** 103 test case / 10 file, gồm cả `contract_test.dart` (parse cùng fixture với Python),
   `workspace_view_model_test.dart` (test ViewModel không cần widget tree — thành quả của việc
   tách ViewModel khỏi material) và test responsive cho bề rộng 390px.

10. **Design tokens tập trung.** `Color(0x...)` và `BorderRadius.circular` bị cấm ngoài `core/theme/`,
    có guardrail. Tránh "theme fork" — lỗi rất phổ biến khi app lớn lên.

---

## 3. Trả lời trực tiếp 3 câu hỏi của bạn

### 3.1. Tổ chức thư mục — có cần điều chỉnh không?

**Không cần tái cấu trúc.** `core / data / features` (feature-first) là cách tổ chức được Flutter
official architecture guide khuyến nghị cho app vừa và lớn. Giữ nguyên.

Chỉ có **2 chỉnh nhỏ** (xem §4.2): tách vài enum domain ra khỏi file repository, và dọn 2 route/screen
legacy. Cả hai đều là "dọn dẹp", không phải "đổi kiến trúc".

Một lưu ý: `features/workspace/view/` đang có file tới **996 dòng** (`workspace_modals.dart`) và
**865 dòng** (`document_review_view.dart`). Về kiến trúc không sai (đây là tầng presentation, được
phép dài), nhưng nên tách theo widget khi còn thời gian — dễ review, dễ merge, ít conflict.

### 3.2. State management — có cần đổi không?

**Không đổi. Riverpod 3 + `Notifier` là lựa chọn đúng và hiện đại.** Bạn đã dùng đúng:
`NotifierProvider` (không phải `StateProvider` legacy), `ref.watch` trong build, `ref.read` trong
command, `select()` để giới hạn rebuild, `ref.listen` cho side-effect (SnackBar).

Ba gợi ý **bổ sung, không thay thế**:

- **Cân nhắc `AsyncNotifier`** cho các luồng async đang tự quản bằng cờ `loading` thủ công
  (`historyLoading`, `restoring`). `AsyncValue` (`loading/data/error`) giúp UI xử lý 3 trạng thái
  gọn và nhất quán hơn. Không bắt buộc — code hiện tại chạy đúng.
- **Cân nhắc `ProviderObserver`** để log thay đổi state khi debug trên thiết bị thật.
- **Tránh `ref.watch` bên trong method.** `ProxyUrlNotifier.build()` có `ref.watch` — đúng. Nhưng trong
  `set()` (dòng 56) cũng dùng `ref.watch`; ở ngoài `build()` nên dùng `ref.read` để không tạo
  dependency ngầm.

### 3.3. Pattern — có cần điều chỉnh không?

**MVVM + Repository + Service interface là đúng chuẩn.** Giữ nguyên. Hai điều chỉnh về *chi tiết
thực thi* (không phải về pattern):

- **Bỏ model mutable** (`WorkspaceUnit`) — xem §4.2.1. Đây là điểm dễ sinh bug tinh vi nhất.
- **Tách domain enum khỏi tầng repository** — xem §4.2.2.

---

## 4. Vấn đề phát hiện được & khuyến nghị

### 4.1. P0 — Chặn mobile (phải sửa trước khi build lên máy)

#### P0-1. Không có thư mục `ios/` → không build được cho iPhone — *đã quyết định: bỏ qua*

```
$ ls -d app/*/  →  android/ assets/ build/ lib/ macos/ test/ tool/ web/ windows/
```
**Không có `ios/`.** README ghi mục tiêu là *"Android + Windows"*, nên đây là quyết định có chủ đích.

**Trạng thái (2026-09-11):** chủ dự án xác nhận **chưa cần iOS** — mục tiêu kiểm thử là **Chrome +
APK Android**. Không hành động. Khi nào cần iOS thì:

```sh
cd app && flutter create --platforms=ios .
```
Sau đó thêm `NSAppTransportSecurity` cho phép HTTP cleartext ở môi trường dev (tương đương P0-3),
và khai báo `NSPhotoLibraryUsageDescription`/`UIFileSharingEnabled` nếu dùng file picker.

#### P0-2. Quyền `INTERNET` chỉ có ở manifest `debug` → bản release mất mạng — **ĐÃ SỬA**

`android/app/src/main/AndroidManifest.xml` **không có**
`<uses-permission android:name="android.permission.INTERNET"/>`. Quyền này chỉ nằm ở
`android/app/src/debug/AndroidManifest.xml:6` — Flutter thêm vào **chỉ để phục vụ hot reload**.

**Hệ quả:** APK release (và profile) **không có quyền mạng** → `dio` không gọi được proxy → app
"chết lặng" đúng lúc demo/nộp bài. Đây là bug thật, rất dễ mắc và rất khó đoán.

**Bằng chứng bug (manifest release cũ, đã merge):** chỉ có
`DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` — không một dòng `INTERNET` nào.

**Đã sửa:** thêm vào `main/AndroidManifest.xml` ngay dưới thẻ `<manifest>`:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
```
Xác minh trên APK release mới bằng `aapt2 dump xmltree`:
`uses-permission android:name="android.permission.INTERNET"` → có mặt.

#### P0-3. HTTP cleartext bị Android chặn → không kết nối được proxy — **ĐÃ SỬA**

`lib/core/app_config.dart:26-30` trả về `http://10.0.2.2:8000` (emulator) và `http://localhost:8000`.
Android 9+ (API 28+), với `targetSdk` hiện tại (`flutter.targetSdkVersion`), **mặc định chặn HTTP
không mã hoá** (`usesCleartextTraffic=false`). Trước khi sửa, manifest không có
`usesCleartextTraffic` lẫn `networkSecurityConfig`.

**Hệ quả:** trên emulator/thiết bị thật, request tới proxy qua `http://` bị chặn ở tầng OS — trước cả
khi tới `dio`.

**Đã sửa:** tạo `android/app/src/main/res/xml/network_security_config.xml` và tham chiếu từ
`main/AndroidManifest.xml` (`android:networkSecurityConfig="@xml/network_security_config"`).

Khác với khuyến nghị ban đầu (đặt trong `src/debug/`), cấu hình được đặt ở `main/` để **APK release
cũng chạy được** — vì mục tiêu kiểm thử là bản APK release. Đổi lại, cleartext **không** được mở
toàn cục mà chỉ mở cho đúng các host dev:

```xml
<base-config cleartextTrafficPermitted="false"/>          <!-- mọi host khác vẫn HTTPS-only -->
<domain-config cleartextTrafficPermitted="true">
    <domain>10.0.2.2</domain>   <!-- emulator nhìn thấy máy host -->
    <domain>localhost</domain>  <!-- adb reverse tcp:8000 tcp:8000 -->
    <domain>127.0.0.1</domain>
</domain-config>
```

Xác minh trên APK release mới bằng `aapt2 dump xmltree --file res/8G.xml`:
`base-config cleartextTrafficPermitted=false` + `domain-config` đúng 3 host trên. Resource bị AGP
đổi tên ngắn (`res/8G.xml`) nên tra theo tên file là không thấy — phải tra qua `aapt2 dump resources`.

Về lâu dài nên chuyển proxy sang HTTPS để bỏ hẳn ngoại lệ này.

---

### 4.2. P1 — Nên sửa để code mobile bền vững

#### 4.2.1. `WorkspaceUnit` là model **mutable** → mầm bug tinh vi

`lib/features/workspace/models/workspace_unit.dart:70-74`:
```dart
bool malformed;          // non-final
bool selected;           // non-final
UnitStatus status;       // non-final
UnitKind kind;           // non-final
```
ViewModel sửa tại chỗ rồi tạo list mới để "đánh thức" Riverpod
(`workspace_view_model.dart:300-308`):
```dart
void _mutateUnit(String key, void Function(WorkspaceUnit) mutate) {
  for (final unit in state.units) { if (unit.key == key) mutate(unit); }
  state = state.copyWith(units: [...state.units]);   // list mới, nhưng item vẫn là object cũ
}
```
**Tại sao nguy hiểm:** `WorkspaceState` bất biến, nhưng các phần tử bên trong thì không. Bất kỳ widget
nào giữ tham chiếu tới một `WorkspaceUnit` sẽ **thấy dữ liệu đổi mà không được rebuild** — vì
`==`/`hashCode` không được override nên Riverpod so sánh theo identity của *list*, không theo nội dung
item. Hiện tại chạy đúng nhờ thủ thuật tạo list mới, nhưng đây là loại bug "im lặng": nó không báo lỗi,
chỉ hiển thị sai trong vài tình huống.

**Khuyến nghị:** chuyển sang immutable + `copyWith` (giống `WorkspaceState` đang làm):
```dart
final bool selected;
final UnitStatus status;
final UnitKind kind;
WorkspaceUnit copyWith({UnitKind? kind, bool? selected, UnitStatus? status}) => ...;
```
rồi trong VM: `units: [for (final u in state.units) u.key == key ? u.copyWith(...) : u]`.

#### 4.2.2. Domain enum nằm trong file Repository → View phải import Repository

`ReviewStage`, `ReviewProgress`, `ReviewRun` định nghĩa trong
`lib/data/repositories/review_repository.dart:23-112`. Vì thế view buộc phải:
```dart
// lib/features/workspace/view/workspace_modals.dart:18
import '../../../data/repositories/review_repository.dart' show ReviewStage;
```
Guardrail hiện **không chặn** `data/repositories/` trong view (chỉ chặn `data/services/` + `dio`), nên
qua được — nhưng về mặt thiết kế, một widget đang phụ thuộc vào tầng repository chỉ để lấy một enum
là **coupling không cần thiết**.

**Khuyến nghị:** chuyển 3 type này sang `lib/data/models/review_progress.dart`. View import model
(giá trị thuần) thay vì repository. Đây cũng là điều kiện để siết guardrail: thêm luật
`view-no-repositories`.

#### 4.2.3. Parse PDF/DOCX chạy **trên main isolate** → giật lag trên điện thoại

`lib/data/services/parse_service.dart:99-111` giải nén text **đồng bộ** trong vòng lặp:
```dart
for (var page = 0; page < pageCount; page++) {
  if (onStatus != null && pageCount >= 8) {
    onStatus('Extracting text (page ${page + 1}/$pageCount)…');
    await Future<void>.delayed(Duration.zero);   // chỉ nhả event loop GIỮA các trang
  }
  pageTexts.add(extractor.extractText(startPageIndex: page, endPageIndex: page));
}
```
`await Future.delayed(Duration.zero)` **không** đẩy việc nặng sang isolate — nó chỉ cho event loop một
nhịp giữa hai trang. Một trang PDF nặng vẫn block UI thread. Trên desktop ít lộ; trên điện thoại, file
SRS 28,7 MB / hàng trăm trang sẽ **đứng hình vài giây**, có thể bị OS kill.

**Khuyến nghị:** chạy parse trong isolate. Vì `PdfDocument` của Syncfusion khó truyền qua isolate, cách
thực dụng là bọc cả `parse()` trong `Isolate.run` với `Uint8List` đầu vào, trả về `SrsDocument` (cần
`SrsDocument` ở dạng có thể gửi qua isolate — dùng `Map`/list thuần hoặc `TransferableTypedData`).
Tối thiểu: dùng `compute()` cho `DocxParser.extractText` (đã là `static`, thuần, dễ tách).

#### 4.2.4. Repository giữ state mutable, trùng lặp với ViewModel

`DocumentRepository` có field `LoadedDocument? _current` (`document_repository.dart:53`) và cả
`updateRubric()` sửa nó tại chỗ (`:59-69`). Trong khi đó `WorkspaceViewModel` cũng giữ `_document`
riêng. **Hai nguồn sự thật cho cùng một khái niệm** — dễ lệch trạng thái.

Vì `documentRepositoryProvider` là `Provider` (singleton toàn app), state này sống vĩnh viễn và chia
sẻ giữa các màn hình.

**Khuyến nghị:** chọn một trong hai —
(a) Repository **stateless** (bỏ `_current`, chỉ `pickAndParse()` trả về `LoadedDocument`), để
ViewModel là nguồn sự thật duy nhất; hoặc
(b) giữ state trong repository nhưng chuyển thành `Notifier` để vòng đời rõ ràng.
Hiện tại đang là nửa nọ nửa kia.

---

### 4.3. P2 — Cải thiện về lâu dài (không gấp)

| # | Vấn đề | Vị trí | Khuyến nghị |
|---|---|---|---|
| P2-1 | Route + screen **legacy** còn sống | `core/router/app_router.dart:22-24, 61-67`; `features/document/view/document_screen.dart` (367 dòng), `features/review/view/review_screen.dart` (271 dòng) | Xoá nếu workspace đã thay thế hoàn toàn; hoặc cô lập vào thư mục `legacy/` để không ai vô tình import |
| P2-2 | `WorkspaceDestination.route` **chết và sai** | `workspace_shell.dart:22` (`this.route`), giá trị `'/workspace'` ở `:30` — nhưng `AppRoutes.workspace = '/'` (`app_router.dart:18`). Field **không được đọc ở đâu** (điều hướng theo `currentIndex` qua `goBranch`) | Xoá field `route`, hoặc dùng nó và sửa `'/workspace'` → `'/'`. Đang là dữ liệu gây hiểu nhầm |
| P2-3 | Snapshot lưu vào `shared_preferences` | `workspace_view_model.dart:612-630` | `shared_preferences` không dành cho blob lớn. Snapshot units + result JSON có thể phình. Trên mobile nên chuyển sang `path_provider` + file JSON (hoặc `sqflite`/`drift` nếu history lớn dần) |
| P2-4 | Không có cơ chế **retry** dù đã có cờ `isRetryable` | `data/services/api_service.dart:19`, `:133`, `:138` | `isRetryable` được set nhưng **không nơi nào đọc** để retry. Thêm interceptor `dio` retry (backoff) cho lỗi mạng/timeout — quan trọng hơn trên mobile vì mạng chập chờn |
| P2-5 | Release ký bằng **debug key** | `android/app/build.gradle.kts:29-33` | Chấp nhận được cho đồ án, nhưng phải sửa trước khi phát hành thật. Có `TODO` sẵn |
| P2-6 | Không dùng **code-gen** | `data/models/*.dart`, `workspace/models/*.dart` | ADR 0002 ghi rõ đây là quyết định có chủ đích cho sprint 3 tuần — **hợp lý**. Nhưng: model không có `==`/`hashCode`, và `fromJson` viết tay dễ lệch khi schema đổi. Khi model vượt ~10 class, cân nhắc `freezed` + `json_serializable`. Đổi lại: thêm `build_runner` vào vòng lặp dev |
| P2-7 | `WorkspaceState` có **18 field** | `workspace_view_model.dart:38-58` | Chưa cần tách, nhưng khi thêm tính năng, cân nhắc nhóm lại (ví dụ `ImportState`, `RunState`) để `copyWith` không phình thành "tham số thứ 19" |
| P2-8 | `ref.watch` ngoài `build()` | `core/providers.dart:56` (`ProxyUrlNotifier.set`) | Đổi sang `ref.read` để tránh dependency ngầm ngoài vòng build |

---

## 5. Lộ trình hành động đề xuất

**Giai đoạn 1 — Mobile unblock (làm ngay, ~nửa ngày)**
1. Thêm `<uses-permission android:name="android.permission.INTERNET"/>` vào `main/AndroidManifest.xml`.
2. Thêm `network_security_config.xml` (chỉ cho `debug`) để cho phép HTTP tới `10.0.2.2`/`localhost`.
3. Quyết định có cần iOS không → nếu có, `flutter create --platforms=ios .` + cấu hình ATS.
4. **Kiểm chứng:** `flutter build apk --release` rồi chạy trên máy thật, xác nhận gọi được proxy.

**Giai đoạn 2 — Làm cứng kiến trúc (1–2 ngày)**
5. Chuyển `WorkspaceUnit` sang immutable + `copyWith` (§4.2.1).
6. Tách `ReviewStage`/`ReviewProgress`/`ReviewRun` sang `data/models/`, thêm guardrail
   `view-no-repositories` (§4.2.2).
7. Đưa parse PDF/DOCX vào isolate (§4.2.3) — đo thời gian parse file 28 MB trước/sau.
8. Bỏ state trùng lặp ở `DocumentRepository` (§4.2.4).

**Giai đoạn 3 — Dọn dẹp & mở rộng (khi rảnh)**
9. Xoá route/screen legacy + field `WorkspaceDestination.route` chết (P2-1, P2-2).
10. Thêm retry interceptor cho `dio` (P2-4).
11. Chuyển snapshot sang file-based storage (P2-3).
12. Tách `workspace_modals.dart` (996 dòng) theo widget.

**Việc KHÔNG nên làm:** đổi Riverpod sang BLoC/Provider, đổi go_router, hay tái cấu trúc lại
`core/data/features`. Cả ba đang đúng chuẩn — đổi chỉ tốn thời gian mà không tăng chất lượng.

---

## 6. Bảng điểm chi tiết

| Tiêu chí | Điểm | Ghi chú |
|---|---|---|
| Phân tầng (layering) | 10/10 | Có guardrail CI thực thi, đã kiểm chứng độc lập |
| Tổ chức thư mục | 9/10 | Feature-first chuẩn; chỉ còn route legacy |
| State management | 9/10 | Riverpod 3 `Notifier` hiện đại, dùng đúng API |
| Pattern (MVVM/Repository) | 8/10 | Đúng, trừ model mutable + enum đặt sai chỗ |
| Dependency Injection | 10/10 | Interface + provider override, composition root sạch |
| Routing | 10/10 | `StatefulShellRoute` — đúng chuẩn bottom-nav |
| Test | 8/10 | 103 case, có contract test + test responsive 390px; thiếu golden test |
| Bảo mật | 10/10 | App không giữ secret, có guardrail chặn |
| Quản lý tài nguyên | 8/10 | `onDispose`/`ref.mounted` đúng; parse còn trên main isolate |
| **Sẵn sàng mobile** | **7/10** | Đã vá quyền INTERNET + cleartext (§7); còn thiếu iOS (đã quyết định bỏ qua) và isolate cho parse |

---

## 7. Nhật ký thay đổi (2026-09-11)

Mục tiêu: **test được trên Chrome và build được APK Android**. Bỏ qua iOS theo yêu cầu.

### 7.1 Mobile unblock — cấu hình nền tảng Android

Không sửa một dòng Dart nào cho phần này.

| File | Thay đổi |
|---|---|
| `app/android/app/src/main/AndroidManifest.xml` | Thêm `<uses-permission android:name="android.permission.INTERNET"/>`; thêm `android:networkSecurityConfig="@xml/network_security_config"` vào `<application>` |
| `app/android/app/src/main/res/xml/network_security_config.xml` | **Mới.** `base-config` chặn cleartext; `domain-config` cho phép cleartext với `10.0.2.2`, `localhost`, `127.0.0.1` |

**Trước khi sửa:** manifest release đã merge chỉ chứa `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`,
không có `INTERNET` → APK release không thể gọi mạng. Đây là bằng chứng bug, không phải suy đoán.

### 7.2 Làm cứng kiến trúc — 4 mục P1 (§4.2)

| Mục | Thay đổi |
|---|---|
| **P1.1** Tách domain enum | `ReviewStage` / `ReviewProgress` / `ReviewRun` rời `review_repository.dart` sang `data/models/review_progress.dart`; `LoadedDocument` rời `document_repository.dart` sang `data/models/loaded_document.dart`. Không còn view nào phải import một repository chỉ để lấy một enum. Thêm luật guardrail **`view-no-repositories`** để không tái diễn |
| **P1.2** `WorkspaceUnit` bất biến | 4 field `non-final` → `final`; thêm `copyWith`; `classify()` (sửa tại chỗ) → `classified()` (trả về bản mới). `_mutateUnit` nhận mapper trả về unit mới thay vì sửa tại chỗ |
| **P1.3** Parse trong isolate | `ParseService` dùng `compute()` → parse chạy ở background isolate, hết đứng hình UI với file 28 MB. `compute` chạy inline trên web nên Chrome không đổi hành vi |
| **P1.4** Bỏ state trùng | `DocumentRepository` thành **stateless**: bỏ `_current`, `current`, `updateRubric` (dead code), `clear`. ViewModel là nguồn sự thật duy nhất; màn hình legacy đọc document từ `documentViewModelProvider` |

File chạm: `data/models/review_progress.dart` + `data/models/loaded_document.dart` (mới),
`data/repositories/{review,document}_repository.dart`, `data/services/parse_service.dart`,
`features/workspace/models/workspace_unit.dart`, `features/workspace/view_model/workspace_view_model.dart`,
`features/{document,review}/**`, `tools/check_guardrails.py`, `test/parse_service_test.dart` (mới).

**Đánh đổi của P1.3 cần biết:** `onStatus` không truyền được qua ranh giới isolate, nên thông báo tiến
độ khi import giờ là "Parsing <tên file>…" thay vì đếm từng trang. UI vẫn có spinner động + đồng hồ
thời gian, nên file lớn vẫn trông là "đang chạy" chứ không "treo". Muốn lấy lại tiến độ theo trang thì
phải dùng `Isolate.spawn` + `SendPort` thay cho `compute` — thêm ~40 dòng và một nhánh `kIsWeb`.

### Bằng chứng kiểm chứng

| Kiểm tra | Kết quả |
|---|---|
| `flutter analyze` | `No issues found!` |
| `flutter test` | **107/107 pass** (103 cũ + 4 mới cho `ParseService`) |
| `tools/check_guardrails.py` | `All guardrails passed across 156 files` — gồm luật `view-no-repositories` mới |
| `flutter build apk --release` | `✓ Built build/app/outputs/flutter-apk/app-release.apk` |
| `flutter build web --release --no-web-resources-cdn` | `✓ Built build/web` |
| `aapt2 dump xmltree` — manifest release | `uses-permission android:name="android.permission.INTERNET"` ✓ |
| `aapt2 dump xmltree --file res/8G.xml` | `base-config cleartextTrafficPermitted=false` + 3 domain dev ✓ |
| test "failure raised inside the isolate still arrives typed" | **Pass** — `ParseException` giữ nguyên type qua ranh giới isolate |

`test/parse_service_test.dart` là test **đầu tiên** chạm vào `ParseService` (trước đó không có test
nào), và nó tồn tại chính vì P1.3 đưa vào một giả định mới: exception phải sống sót qua isolate.

### Ghi chú vận hành (bẫy môi trường)

- **`flutter test` hỏng giả khi có biến proxy.** Máy này có `HTTP_PROXY=http://127.0.0.1:53589`;
  `flutter_tester` đẩy WebSocket loopback qua proxy nên bị từ chối:
  `WebSocketException: Invalid WebSocket upgrade request`, và **cả 10 file test fail ở bước load**
  (trông như "test hỏng" nhưng không phải). Chạy:
  ```sh
  env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy flutter test
  ```
- **`grep` BSD mặc định trên macOS không hỗ trợ alternation `\|`.** Các lệnh dạng
  `grep "a\|b"` trả về rỗng **sai**. Dùng `grep -E "a|b"` hoặc ripgrep. Bẫy này đã gây kết luận
  sai hai lần trong quá trình review (tưởng thiếu CORS, tưởng phân tầng bẩn) — thực tế cả hai đều ổn.
- **Comment XML không được chứa `--`.** Build fail với
  `The string "--" is not permitted within comments` khi tôi viết `--dart-define` trong comment của
  `network_security_config.xml`.
- **CORS proxy đã đúng sẵn:** `server/app/config.py:62` `cors_origins: str = "*"`, và `.env` không
  override → Chrome gọi được proxy thật. Lần test Chrome trước (2026-09-10) chỉ chạy **mock mode**,
  nên CORS chưa bao giờ được kiểm chứng — nay xác nhận đã ổn.
- **Resource bị AGP đổi tên trong APK release:** `network_security_config.xml` → `res/8G.xml`.
  Tra theo tên file sẽ không thấy; phải dùng `aapt2 dump resources`.
- **`dart:typed_data` thừa khi đã import `flutter/foundation.dart`** — `unnecessary_import` là lint
  bật sẵn, và `flutter analyze` fail cả với mức `info`.

### Còn lại (chưa làm)

Các mục **P2** (§4.3) vẫn nguyên trạng: route/screen legacy (`/legacy/*`, ~640 dòng), field
`WorkspaceDestination.route` chết và sai, snapshot trong `shared_preferences`, không có retry dù đã
có `isRetryable`, release ký debug key. Không mục nào chặn build/test.

---

*§1–§6 là kết quả review. §7 ghi lại các thay đổi đã thực hiện và bằng chứng kiểm chứng.*
