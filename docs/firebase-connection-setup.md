# Nối backend Firestore cho Mobile (Lab 3) — 05/11/2026

Tài liệu này ghi lại việc **đã làm thật** để mobile lấy Firestore làm backend, và những bước còn
phải làm tay trên Console/thiết bị. Không dòng nào dưới đây được coi là "đã nghiệm thu" nếu chưa
có ảnh/log từ máy thật.

## 1. Hiện trạng hạ tầng (đo được)

| Mục | Giá trị |
|---|---|
| Firebase project | `srs-ai-prm` (khớp `mobile/.firebaserc` và `mobile/firebase.json`) |
| Firestore database | `projects/srs-ai-prm/databases/(default)`, edition STANDARD, FIRESTORE_NATIVE |
| Project `prm-srs-ai` | **Không dùng**: tài khoản `hienngunguoi1234@gmail.com` không có quyền (403). Đừng trỏ app sang đó. |
| Rules | Đã deploy `mobile/firestore.rules` lúc 05/11/2026, CLI báo `released rules ... compiled successfully` |
| Tài khoản deploy | `hienngunguoi1234@gmail.com` (Firebase CLI 15.34.2) |

## 2. Thay đổi trong code

| File | Vai trò |
|---|---|
| `mobile/lib/models/project.dart` | Model thuần Dart + `toCreateMap/toUpdateMap/fromMap`; không import Firebase |
| `mobile/lib/services/projects_firestore_service.dart` | **Nơi duy nhất** gọi Firestore SDK: `users/{uid}/projects`, `orderBy(updatedAt)`, `snapshots()` |
| `mobile/lib/repositories/projects_repository.dart` | Kiểm dữ liệu vào, dịch `FirebaseException` thành `ProjectsFailure` cho UI |
| `mobile/lib/core/di/projects_providers.dart` | Riverpod: `projectsProvider` (stream realtime) + `ProjectsViewModel` |
| `mobile/lib/features/projects_firestore/.../firestore_projects_screen.dart` | Màn CRUD + realtime đầu tiên chạy dữ liệu thật |
| `mobile/lib/app/app.dart` | Route `/firestore-projects` |
| `mobile/lib/features/account/presentation/views/account_screens.dart` | Mục "KẾT NỐI BACKEND" trong Profile |
| `mobile/lib/services/crashlytics_service.dart` | Bản mirror `crash_logs` nay có `ownerUid` (rules yêu cầu) |
| `mobile/firestore.rules` | Rules mới: owner-only, admin read, `crash_logs`, `reports` |
| `mobile/firestore.indexes.json` | Khung index (hiện rỗng, chưa cần composite) |
| `mobile/firebase.json` | Thêm khối `firestore` để `firebase deploy` biết file rules/index |

Luồng: **View → ViewModel → Repository → Service → Firestore SDK**. View không import
`cloud_firestore`, không tự ghép đường dẫn.

## 3. Mô hình dữ liệu đã nối

```
users/{uid}                       # hồ sơ Google do AuthService ghi
  └── projects/{projectId}        # ENTITY CHÍNH của Lab 3
        name, description, status(active|archived), ownerUid,
        schemaVersion=1, createdAt, updatedAt   (serverTimestamp)
crash_logs/{logId}                # mirror cho Admin Web đọc
reports/{reportId}                # metadata PDF sau khi upload Cloudinary
admins/{uid}                      # do Console tạo; quyết định ai là Admin
```

`createdAt/updatedAt` là `FieldValue.serverTimestamp()`; rules so `== request.time` nên client
không tự đặt giờ được.

## 4. Việc phải làm tay trên Console

1. **Tạo Admin** (để Admin Web đọc `users`, `crash_logs`, `reports`):
   - Đăng nhập app bằng tài khoản admin, mở **Tài khoản → Dự án trên Firestore**, đọc dòng `UID: ...`.
   - Firestore → collection `admins` → Add document → **Document ID = uid đó**, field bất kỳ
     (`note: "admin"`). Không có bước này, mọi truy vấn admin bị `permission-denied`.
2. **Authentication → Google**: bật provider, thêm **SHA-1 và SHA-256** của keystore dùng để chấm.
3. Kiểm tra đã có index mặc định cho `updatedAt` (tự động); chỉ cần composite index khi thêm
   query kết hợp `where` + `orderBy` khác field.

## 5. Chạy trên thiết bị thật

```powershell
# từ root repo, sinh google-services.json + dart-defines từ .env
python tools/flutter_env.py mobile run -d <device-id>

# hoặc build bản cài
python tools/flutter_env.py mobile build apk --debug
```

Kịch bản kiểm tra tối thiểu:

1. Đăng nhập Google → **Tài khoản → Dự án trên Firestore**.
2. Màn hình hiện `UID: <uid>` và đường dẫn `users/{uid}/projects`.
3. Bấm **Tạo dự án** → tên `Dự án Firestore 01` → Lưu.
4. Mở Firebase Console → Firestore → `users/{uid}/projects` → thấy document mới, có
   `ownerUid`, `createdAt`, `updatedAt`.
5. Sửa tên trên app → Console đổi theo (và ngược lại: sửa trên Console → app tự cập nhật vì
   đang dùng `snapshots()`).
6. Xóa trên app → document biến mất.
7. Tắt mạng → thao tác → app hiện thông báo lỗi thay vì treo.

## 6. Ma trận kiểm quyền (phải chạy, hiện CHƯA chạy)

| Trường hợp | Kỳ vọng |
|---|---|
| Chưa đăng nhập, đọc `users/{uid}/projects` | DENY |
| User A đọc/ghi `users/A/projects/*` | ALLOW |
| User A đọc `users/B/projects/*` | DENY |
| User A ghi `ownerUid = B` vào path của A | DENY (rules so path với field) |
| User A sửa `createdAt` | DENY |
| User A ghi `updatedAt` bằng giờ tự đặt | DENY (`!= request.time`) |
| Admin đọc `users/*`, `crash_logs` | ALLOW |
| Admin xóa/sửa `crash_logs` | DENY |
| Bất kỳ ai ghi `admins/*` từ client | DENY |

Cách chạy: emulator (`firebase emulators:start --only firestore`) với Rules Unit Testing, hoặc
hai tài khoản Google trên hai máy. **Chưa có log nào cho bảng này** — đừng ghi "đã test" vào báo cáo.

## 7. Deploy lại rules khi sửa

```powershell
cd mobile
firebase deploy --only firestore:rules --project srs-ai-prm
```

Rules là nguồn sự thật về quyền. Sửa quyền bằng cách sửa file này rồi deploy, **không** nới rule
trên Console bằng tay (sẽ bị lần deploy sau ghi đè).

## 8. Còn thiếu — không được tuyên bố là xong

- Chưa chạy màn này trên điện thoại thật (chưa có log/ảnh).
- Chưa chạy ma trận rules ở §6.
- Các màn học vụ khác (Course/Class/Group/Review) **vẫn đọc fixture**; đây mới là mô-đun đầu.
- Admin Web vẫn dùng `MockAdminAuthService`; chưa đọc `crash_logs` thật.
- Upload PDF vẫn chưa nối; `reports` mới có rules, chưa có writer.
- FCM, Remote Config, Analytics chưa làm (xem `docs/lab3-completion-checklist-2026-11-05.md`).
