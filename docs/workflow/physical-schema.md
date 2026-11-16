# Physical Schema & Database Mapping (Slide 15: Database Logical/Physical)

Tài liệu này tổng hợp toàn bộ sơ đồ cấu trúc dữ liệu vật lý (Physical Schema) phục vụ cho hệ thống `srs-review-ai` (bao gồm FastAPI Server SQLite/Postgres target, Firestore Mobile Cloud Database, và SQLite Cục bộ Mobile Offline Store).


> **Ghi chú kiểm chứng (Claude, 2026-11-10):** số dòng `models.py` do Gemini ghi lệch 18–40 dòng so với code hiện tại, đã chỉnh lại theo `__tablename__`/`class`. `CheckConstraint` trong code viết qua helper `_in(column, TUPLE)` (`models.py:65-67`), tài liệu viết dạng SQL tương đương. **14 bảng ORM ở §1.2 là schema đích (Postgres) — chưa có route API nào dùng** (chỉ `server/alembic/versions/0001_*`, `0002_*`); runtime hiện chạy SQLite (§1.1) + Firestore. Trạng thái ở ORM (`submitted/reviewed/approved/changes_requested`, `models.py:50`) **khác** trạng thái app đang dùng trên Firestore (`waiting/inReview/approved/needsRevision/notAccepted`) — slide 15 phải nói rõ đây là hai tầng khác nhau.

---

## 1. SQLite & Postgres Models trên Server

### 1.1. Các bảng Runtime SQLite trên Server (Durable Cache, Sync, Criteria, Rubric)

#### Bảng `cache_entries` (Database: `cache.sqlite3`)
- **Vị trí định nghĩa:** `server/app/infrastructure/store.py:165-176`
- **Các cột:**
  - `namespace` | `TEXT` | `NOT NULL` | Part of PK
  - `key` | `TEXT` | `NOT NULL` | Part of PK
  - `payload` | `TEXT` | `NOT NULL`
  - `created_at` | `REAL` | `NOT NULL`
  - `accessed_at` | `REAL` | `NOT NULL`
- **Ràng buộc:** `PRIMARY KEY (namespace, key)` (`server/app/infrastructure/store.py:172`)
- **Index:** `CREATE INDEX IF NOT EXISTS cache_entries_lru ON cache_entries (namespace, accessed_at)` (`server/app/infrastructure/store.py:175-176`)

#### Bảng `cache_meta` (Database: `cache.sqlite3`)
- **Vị trí định nghĩa:** `server/app/infrastructure/store.py:178`
- **Các cột:**
  - `key` | `TEXT` | `PRIMARY KEY`
  - `value` | `TEXT` | `NOT NULL`
- **Ràng buộc:** `PRIMARY KEY (key)` (`server/app/infrastructure/store.py:178`)
- **Index:** Không thấy index bổ sung trong code.

#### Bảng `sync_records` (Database: `sync.sqlite3`)
- **Vị trí định nghĩa:** `server/app/infrastructure/sync_store.py:74-85`
- **Các cột:**
  - `uid` | `TEXT` | `NOT NULL` | Part of PK
  - `collection` | `TEXT` | `NOT NULL` | Part of PK
  - `record_id` | `TEXT` | `NOT NULL` | Part of PK
  - `deleted` | `INTEGER` | `NOT NULL DEFAULT 0`
  - `data` | `TEXT` | Nullable
  - `client_ts` | `INTEGER` | `NOT NULL`
  - `device_id` | `TEXT` | `NOT NULL`
  - `seq` | `INTEGER` | `NOT NULL`
- **Ràng buộc:** `PRIMARY KEY (uid, collection, record_id)` (`server/app/infrastructure/sync_store.py:83`)
- **Index:** `CREATE INDEX IF NOT EXISTS idx_sync_records_seq ON sync_records(uid, seq)` (`server/app/infrastructure/sync_store.py:85`)

#### Bảng `sync_ops` (Database: `sync.sqlite3`)
- **Vị trí định nghĩa:** `server/app/infrastructure/sync_store.py:86-93`
- **Các cột:**
  - `uid` | `TEXT` | `NOT NULL` | Part of PK
  - `op_id` | `TEXT` | `NOT NULL` | Part of PK
  - `collection` | `TEXT` | `NOT NULL`
  - `record_id` | `TEXT` | `NOT NULL`
  - `seen` | `INTEGER` | `NOT NULL`
- **Ràng buộc:** `PRIMARY KEY (uid, op_id)` (`server/app/infrastructure/sync_store.py:92`)
- **Index:** `CREATE INDEX IF NOT EXISTS idx_sync_ops_seen ON sync_ops(uid, seen)` (`server/app/infrastructure/sync_store.py:93`)

#### Bảng `sync_counter` (Database: `sync.sqlite3`)
- **Vị trí định nghĩa:** `server/app/infrastructure/sync_store.py:95-98`
- **Các cột:**
  - `id` | `INTEGER` | `PRIMARY KEY` | `CHECK (id = 1)`
  - `value` | `INTEGER` | `NOT NULL`
- **Ràng buộc:** `PRIMARY KEY (id)`, `CHECK (id = 1)` (`server/app/infrastructure/sync_store.py:96`)
- **Index:** Không thấy index bổ sung trong code.

#### Bảng `criteria` (Database: `criteria.sqlite3`)
- **Vị trí định nghĩa:** `server/app/config/criteria.py:48-59`
- **Các cột:**
  - `id` | `TEXT` | `PRIMARY KEY`
  - `title` | `TEXT` | `NOT NULL`
  - `what` | `TEXT` | `NOT NULL`
  - `source` | `TEXT` | `NOT NULL DEFAULT ''`
  - `scope` | `TEXT` | `NOT NULL DEFAULT 'unit'`
  - `severity` | `TEXT` | `NOT NULL DEFAULT 'medium'`
  - `enabled` | `INTEGER` | `NOT NULL DEFAULT 1`
  - `position` | `INTEGER` | `NOT NULL DEFAULT 100`
  - `updated_at` | `TEXT` | `NOT NULL`
- **Ràng buộc:** `PRIMARY KEY (id)` (`server/app/config/criteria.py:50`)
- **Index:** Không thấy index bổ sung trong code.

#### Bảng `rubric_overrides` (Database: `rubric.sqlite3`)
- **Vị trí định nghĩa:** `server/app/config/rubric_store.py:66-70`
- **Các cột:**
  - `leaf` | `TEXT` | `PRIMARY KEY`
  - `value` | `TEXT` | `NOT NULL`
  - `updated_at` | `TEXT` | `NOT NULL`
- **Ràng buộc:** `PRIMARY KEY (leaf)` (`server/app/config/rubric_store.py:67`)
- **Index:** Không thấy index bổ sung trong code.

---

### 1.2. Các thực thể Conceptual ORM Target (`server/app/infrastructure/db/models.py`)

#### Bảng `users`
- **Vị trí định nghĩa:** `server/app/infrastructure/db/models.py:83-98`
- **Các cột:**
  - `uid` | `String(128)` | `PRIMARY KEY`
  - `email` | `String(320)` | Nullable
  - `display_name` | `String(200)` | Nullable
  - `role` | `String(16)` | `NOT NULL`, `server_default="student"`
  - `created_at` | `DateTime(timezone=True)` | `NOT NULL`, `server_default=func.now()`
  - `updated_at` | `DateTime(timezone=True)` | `NOT NULL`, `server_default=func.now()`
- **Ràng buộc:** `CheckConstraint("role IN ('student', 'teacher', 'admin')", name="role")` (`server/app/infrastructure/db/models.py:84`)
- **Index:** Không thấy index bổ sung ngoài PK trong code.

#### Bảng `classes`
- **Vị trí định nghĩa:** `server/app/infrastructure/db/models.py:101-114`
- **Các cột:**
  - `id` | `String(64)` | `PRIMARY KEY`
  - `name` | `String(200)` | `NOT NULL`
  - `write_key_hash` | `String(64)` | `NOT NULL`
  - `created_at` | `DateTime(timezone=True)` | `NOT NULL`
  - `updated_at` | `DateTime(timezone=True)` | `NOT NULL`
- **Ràng buộc:** `PRIMARY KEY (id)` (`server/app/infrastructure/db/models.py:101-114`)
- **Index:** Không thấy index bổ sung trong code.

#### Bảng `projects`
- **Vị trí định nghĩa:** `server/app/infrastructure/db/models.py:117-129`
- **Các cột:**
  - `id` | `String(64)` | `PRIMARY KEY`
  - `owner_uid` | `String(128)` | `NOT NULL`, `FK(users.uid, ondelete="RESTRICT")`
  - `name` | `String(200)` | `NOT NULL`
  - `description` | `Text` | `NOT NULL`, `server_default=""`
  - `created_at` | `DateTime(timezone=True)` | `NOT NULL`
  - `updated_at` | `DateTime(timezone=True)` | `NOT NULL`
- **Ràng buộc:** `FK(users.uid, ondelete="RESTRICT")` (`server/app/infrastructure/db/models.py:124`)
- **Index:** `index=True` trên `owner_uid` (`server/app/infrastructure/db/models.py:123`)

#### Bảng `documents`
- **Vị trí định nghĩa:** `server/app/infrastructure/db/models.py:132-145`
- **Các cột:**
  - `id` | `String(64)` | `PRIMARY KEY`
  - `project_id` | `String(64)` | `NOT NULL`, `FK(projects.id, ondelete="CASCADE")`
  - `title` | `String(300)` | `NOT NULL`
  - `kind` | `String(16)` | `NOT NULL`, `server_default="srs"`
  - `created_at` | `DateTime(timezone=True)` | `NOT NULL`
  - `updated_at` | `DateTime(timezone=True)` | `NOT NULL`
- **Ràng buộc:** `FK(projects.id, ondelete="CASCADE")` (`server/app/infrastructure/db/models.py:139`)
- **Index:** `index=True` trên `project_id` (`server/app/infrastructure/db/models.py:138`)

#### Bảng `document_files`
- **Vị trí định nghĩa:** `server/app/infrastructure/db/models.py:148-169`
- **Các cột:**
  - `id` | `String(64)` | `PRIMARY KEY`
  - `document_id` | `String(64)` | `NOT NULL`, `FK(documents.id, ondelete="CASCADE")`
  - `version` | `Integer` | `NOT NULL`, `server_default="1"`
  - `storage` | `String(32)` | `NOT NULL`, `server_default="cloudinary"`
  - `public_id` | `String(500)` | `NOT NULL`
  - `url` | `Text` | `NOT NULL`
  - `filename` | `String(300)` | `NOT NULL`
  - `mime_type` | `String(100)` | Nullable
  - `size_bytes` | `BigInteger` | Nullable
  - `sha256` | `String(64)` | Nullable
  - `uploaded_at` | `DateTime(timezone=True)` | `NOT NULL`
- **Ràng buộc:**
  - `FK(documents.id, ondelete="CASCADE")` (`server/app/infrastructure/db/models.py:156`)
  - `UniqueConstraint("document_id", "version", name="uq_document_files_document_version")` (`server/app/infrastructure/db/models.py:152-155`)
- **Index:** `index=True` trên `document_id` (`server/app/infrastructure/db/models.py:152-155`)

#### Bảng `submissions`
- **Vị trí định nghĩa:** `server/app/infrastructure/db/models.py:172-200`
- **Các cột:**
  - `id` | `String(64)` | `PRIMARY KEY`
  - `document_id` | `String(64)` | `NOT NULL`, `FK(documents.id, ondelete="RESTRICT")`
  - `document_file_id` | `String(64)` | Nullable, `FK(document_files.id, ondelete="SET NULL")`
  - `class_id` | `String(64)` | Nullable, `FK(classes.id, ondelete="SET NULL")`
  - `previous_id` | `String(64)` | Nullable, `FK(submissions.id, ondelete="RESTRICT")`, `UNIQUE`
  - `revision` | `Integer` | `NOT NULL`, `server_default="1"`
  - `status` | `String(32)` | `NOT NULL`, `server_default="submitted"`
  - `group_name` | `String(200)` | `NOT NULL`, `server_default=""`
  - `note` | `Text` | `NOT NULL`, `server_default=""`
  - `upload_uri` | `Text` | Nullable
  - `created_at` | `DateTime(timezone=True)` | `NOT NULL`
  - `updated_at` | `DateTime(timezone=True)` | `NOT NULL`
- **Ràng buộc:**
  - `CheckConstraint("status IN ('submitted', 'reviewed', 'approved', 'changes_requested')", name="status")` (`server/app/infrastructure/db/models.py:179`)
  - `CheckConstraint("revision >= 1", name="revision_positive")` (`server/app/infrastructure/db/models.py:180`)
  - `FK(documents.id, ondelete="RESTRICT")` (`server/app/infrastructure/db/models.py:185`)
  - `FK(document_files.id, ondelete="SET NULL")` (`server/app/infrastructure/db/models.py:187-189`)
  - `FK(classes.id, ondelete="SET NULL")` (`server/app/infrastructure/db/models.py:187-189`)
  - `FK(submissions.id, ondelete="RESTRICT")`, `unique=True` (`server/app/infrastructure/db/models.py:185`)
- **Index:** `index=True` trên `document_id` (`models.py:184`), `index=True` trên `class_id` (`models.py:184`)

#### Bảng `submission_events`
- **Vị trí định nghĩa:** `server/app/infrastructure/db/models.py:203-221`
- **Các cột:**
  - `id` | `BigInteger` | `PRIMARY KEY`, `autoincrement=True`
  - `submission_id` | `String(64)` | `NOT NULL`, `FK(submissions.id, ondelete="CASCADE")`
  - `revision` | `Integer` | `NOT NULL`
  - `event` | `String(32)` | `NOT NULL`
  - `status` | `String(32)` | `NOT NULL`
  - `approximate` | `Boolean` | `NOT NULL`, `server_default="false"`
  - `at` | `DateTime(timezone=True)` | `NOT NULL`
- **Ràng buộc:**
  - `CheckConstraint("event IN ('submitted', 'reviewed', 'revised', 'class_assigned', 'class_unassigned', 'decided', 'backfilled')", name="event")` (`server/app/infrastructure/db/models.py:206`)
  - `CheckConstraint("status IN ('submitted', 'reviewed', 'approved', 'changes_requested')", name="status")` (`server/app/infrastructure/db/models.py:209`)
  - `FK(submissions.id, ondelete="CASCADE")` (`server/app/infrastructure/db/models.py:214`)
- **Index:** `index=True` trên `submission_id` (`server/app/infrastructure/db/models.py:213`)

#### Bảng `teacher_decisions`
- **Vị trí định nghĩa:** `server/app/infrastructure/db/models.py:224-240`
- **Các cột:**
  - `id` | `BigInteger` | `PRIMARY KEY`, `autoincrement=True`
  - `submission_id` | `String(64)` | `NOT NULL`, `FK(submissions.id, ondelete="CASCADE")`, `UNIQUE`
  - `decision` | `String(32)` | `NOT NULL`
  - `note` | `Text` | `NOT NULL`, `server_default=""`
  - `decided_by_uid` | `String(128)` | Nullable, `FK(users.uid, ondelete="SET NULL")`
  - `decided_at` | `DateTime(timezone=True)` | `NOT NULL`
- **Ràng buộc:**
  - `CheckConstraint("decision IN ('approved', 'changes_requested')", name="decision")` (`server/app/infrastructure/db/models.py:225`)
  - `FK(submissions.id, ondelete="CASCADE")`, `unique=True` (`server/app/infrastructure/db/models.py:232`)
  - `FK(users.uid, ondelete="SET NULL")` (`server/app/infrastructure/db/models.py:236`)
- **Index:** `unique=True` trên `submission_id` (`server/app/infrastructure/db/models.py:231`)

#### Bảng `rubrics`
- **Vị trí định nghĩa:** `server/app/infrastructure/db/models.py:243-254`
- **Các cột:**
  - `id` | `String(32)` | `PRIMARY KEY`
  - `syllabus` | `String(300)` | `NOT NULL`, `server_default=""`
  - `scope` | `String(300)` | `NOT NULL`, `server_default=""`
  - `body` | `JSONB` | `NOT NULL`
  - `is_active` | `Boolean` | `NOT NULL`, `server_default="false"`
  - `created_at` | `DateTime(timezone=True)` | `NOT NULL`
- **Ràng buộc:** `PRIMARY KEY (id)` (`server/app/infrastructure/db/models.py:243-254`)
- **Index:** Không thấy index bổ sung trong code.

#### Bảng `evaluation_criteria`
- **Vị trí định nghĩa:** `server/app/infrastructure/db/models.py:257-275`
- **Các cột:**
  - `id` | `String(64)` | `PRIMARY KEY`
  - `title` | `String(200)` | `NOT NULL`
  - `what` | `Text` | `NOT NULL`
  - `source` | `String(300)` | `NOT NULL`, `server_default=""`
  - `scope` | `String(16)` | `NOT NULL`, `server_default="unit"`
  - `severity` | `String(16)` | `NOT NULL`, `server_default="medium"`
  - `enabled` | `Boolean` | `NOT NULL`, `server_default="true"`
  - `sort_order` | `Integer` | `NOT NULL`, `server_default="100"`
  - `created_at` | `DateTime(timezone=True)` | `NOT NULL`
  - `updated_at` | `DateTime(timezone=True)` | `NOT NULL`
- **Ràng buộc:**
  - `CheckConstraint("scope IN ('unit', 'document')", name="scope")` (`server/app/infrastructure/db/models.py:262`)
  - `CheckConstraint("severity IN ('low', 'medium', 'high')", name="severity")` (`server/app/infrastructure/db/models.py:263`)
- **Index:** Không thấy index bổ sung trong code.

#### Bảng `review_reports`
- **Vị trí định nghĩa:** `server/app/infrastructure/db/models.py:278-296`
- **Các cột:**
  - `id` | `String(64)` | `PRIMARY KEY`
  - `submission_id` | `String(64)` | `NOT NULL`, `FK(submissions.id, ondelete="CASCADE")`, `UNIQUE`
  - `contract_version` | `String(32)` | `NOT NULL`
  - `prompt_version` | `String(32)` | `NOT NULL`
  - `model` | `String(100)` | `NOT NULL`
  - `overall_score` | `Float` | Nullable
  - `units_total` | `Integer` | `NOT NULL`, `server_default="0"`
  - `units_reviewed` | `Integer` | `NOT NULL`, `server_default="0"`
  - `prompt_tokens` | `Integer` | Nullable
  - `completion_tokens` | `Integer` | Nullable
  - `total_tokens` | `Integer` | Nullable
  - `created_at` | `DateTime(timezone=True)` | `NOT NULL`
- **Ràng buộc:** `FK(submissions.id, ondelete="CASCADE")`, `unique=True` (`server/app/infrastructure/db/models.py:285`)
- **Index:** `unique=True` trên `submission_id` (`server/app/infrastructure/db/models.py:284`)

#### Bảng `shared_reports`
- **Vị trí định nghĩa:** `server/app/infrastructure/db/models.py:299-310`
- **Các cột:**
  - `id` | `String(64)` | `PRIMARY KEY`
  - `review_report_id` | `String(64)` | `NOT NULL`, `FK(review_reports.id, ondelete="CASCADE")`, `UNIQUE`
  - `expires_at` | `DateTime(timezone=True)` | Nullable
  - `created_at` | `DateTime(timezone=True)` | `NOT NULL`
- **Ràng buộc:** `FK(review_reports.id, ondelete="CASCADE")`, `unique=True` (`server/app/infrastructure/db/models.py:307`)
- **Index:** `unique=True` trên `review_report_id` (`server/app/infrastructure/db/models.py:306`)

#### Bảng `requirement_reviews`
- **Vị trí định nghĩa:** `server/app/infrastructure/db/models.py:313-343`
- **Các cột:**
  - `id` | `BigInteger` | `PRIMARY KEY`, `autoincrement=True`
  - `review_report_id` | `String(64)` | `NOT NULL`, `FK(review_reports.id, ondelete="CASCADE")`
  - `rubric_id` | `String(32)` | `NOT NULL`, `FK(rubrics.id, ondelete="RESTRICT")`
  - `requirement_id` | `String(100)` | `NOT NULL`
  - `section` | `String(300)` | Nullable
  - `page_index` | `Integer` | Nullable
  - `text` | `Text` | `NOT NULL`
  - `score` | `Integer` | `NOT NULL`
  - `context_note` | `Text` | Nullable
  - `dropped_issue_count` | `Integer` | `NOT NULL`, `server_default="0"`
  - `model` | `String(100)` | `NOT NULL`
  - `mock` | `Boolean` | `NOT NULL`, `server_default="false"`
  - `prompt_tokens` | `Integer` | Nullable
  - `completion_tokens` | `Integer` | Nullable
  - `total_tokens` | `Integer` | Nullable
  - `created_at` | `DateTime(timezone=True)` | `NOT NULL`
- **Ràng buộc:**
  - `CheckConstraint("score BETWEEN 0 AND 10", name="score_range")` (`server/app/infrastructure/db/models.py:322`)
  - `FK(review_reports.id, ondelete="CASCADE")` (`server/app/infrastructure/db/models.py:326`)
  - `FK(rubrics.id, ondelete="RESTRICT")` (`server/app/infrastructure/db/models.py:329`)
- **Index:** `index=True` trên `review_report_id` (`models.py:325`), `index=True` trên `rubric_id` (`models.py:325`)

#### Bảng `review_issues`
- **Vị trí định nghĩa:** `server/app/infrastructure/db/models.py:346-366`
- **Các cột:**
  - `id` | `BigInteger` | `PRIMARY KEY`, `autoincrement=True`
  - `requirement_review_id` | `BigInteger` | `NOT NULL`, `FK(requirement_reviews.id, ondelete="CASCADE")`
  - `criterion_id` | `String(64)` | Nullable, `FK(evaluation_criteria.id, ondelete="SET NULL")`
  - `type` | `String(64)` | `NOT NULL`
  - `severity` | `String(16)` | `NOT NULL`
  - `quote` | `Text` | `NOT NULL`
  - `suggestion` | `Text` | `NOT NULL`
  - `verification` | `String(32)` | `NOT NULL`
  - `similarity` | `Float` | Nullable
  - `coverage` | `Float` | Nullable
  - `created_at` | `DateTime(timezone=True)` | `NOT NULL`
- **Ràng buộc:**
  - `CheckConstraint("severity IN ('low', 'medium', 'high')", name="severity")` (`server/app/infrastructure/db/models.py:350`)
  - `FK(requirement_reviews.id, ondelete="CASCADE")` (`server/app/infrastructure/db/models.py:354`)
  - `FK(evaluation_criteria.id, ondelete="SET NULL")` (`server/app/infrastructure/db/models.py:357`)
- **Index:** `index=True` trên `requirement_review_id` (`models.py:353`), `index=True` trên `criterion_id` (`models.py:353`)

---

## 2. Firestore Mobile Database (`mobile/lib`)

#### Collection: `users/{uid}`
- **Đường dẫn:** `users/{uid}`
- **Field chính:** `uid` (string), `email` (string), `displayName` (string), `photoUrl` (string), `lastSignInAt` (timestamp), `role` (string, e.g. 'teacher'), `fcmTokens` (array of string), `fcmTokenUpdatedAt` (timestamp)
- **Đọc / Ghi trong code:**
  - Ghi FCM tokens: `mobile/lib/core/services/fcm_service.dart:60, 64, 70` (`_doc(uid).set(...)`)
  - Ghi User profile: `mobile/lib/services/auth_service.dart:125, 131` (`_syncUserProfile`)
  - Đọc Profile: `mobile/lib/features/account/data/repositories/current_user_repository.dart:94-100` (`_db.collection('users').doc(user.uid).snapshots()`)
- **Rule tương ứng (`mobile/firestore.rules:43-54`):**
  - Read: `isSelf(uid) || isAdmin()`
  - Create: `isSelf(uid) && request.resource.data.get('role', 'teacher') == 'teacher'`
  - Update: `isSelf(uid) && (role không đổi || đổi từ '' sang 'teacher')`
  - Delete: `false`

#### Collection: `users/{uid}/inbox/{id}`
- **Đường dẫn:** `users/{uid}/inbox/{id}`
- **Field chính:** `title` (string), `body` (string), `source` (string, e.g. 'device'), `read` (boolean), `receivedAt` (timestamp)
- **Đọc / Ghi trong code:**
  - Đọc watch stream: `mobile/lib/features/account/data/push_inbox_repository.dart:73, 76-84`
  - Ghi record: `mobile/lib/features/account/data/push_inbox_repository.dart:88-91`
  - Cập nhật markRead: `mobile/lib/features/account/data/push_inbox_repository.dart:95`
- **Rule tương ứng (`mobile/firestore.rules:57-67`):**
  - Read, Delete: `isSelf(uid)`
  - Create: `isSelf(uid) && request.resource.data.source == 'device' && request.resource.data.title is string`
  - Update: `isSelf(uid) && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['read', 'receivedAt'])`

#### Collection: `admins/{uid}`
- **Đường dẫn:** `admins/{uid}`
- **Field chính:** Chứa document ID khớp `uid` của Admin để phân quyền hệ thống.
- **Đọc / Ghi trong code:** không thấy trong code Dart của app Mobile SDK (document tạo qua Firebase Console / Admin SDK).
- **Rule tương ứng (`mobile/firestore.rules:38-41`):**
  - Read: `isSelf(uid)`
  - Write: `false`

#### Collections Học vụ Dùng chung (`courses`, `classes`, `groups`, `projects`, `registrations`, `semesters`, `offerings`, `ruleSets`, `students`, `documents`)
- **Đường dẫn:** `courses/{id}`, `classes/{id}`, `groups/{id}`, `projects/{id}`, `registrations/{id}`, `semesters/{id}`, `offerings/{id}`, `ruleSets/{id}`, `students/{id}` (KHÔNG có `documents/{id}` — tài liệu nằm trong `_meta/snapshot`, xem `rtm.md` §8.2)
- **Field chính:** Dữ liệu học vụ JSON snapshot (e.g., `code`, `name`, `teacherId`, `semesterId`, `studentIds`...)
- **Đọc / Ghi trong code:**
  - Đọc watch snapshots: `mobile/lib/features/academic/data/services/firestore_academic_service.dart:136-146`
  - Ghi upsert batch: `mobile/lib/features/academic/data/services/firestore_academic_service.dart:323-328`
  - Xoá batch: `mobile/lib/features/academic/data/services/firestore_academic_service.dart:424-426`
- **Rule tương ứng (`mobile/firestore.rules:70-79`):**
  - Read, Write: `signedIn()`

#### Collection: `_meta`
- **Đường dẫn:** `_meta/snapshot`
- **Field chính:** `updatedAt` / snapshot sync metadata.
- **Đọc / Ghi trong code:**
  - Đọc: `mobile/lib/features/academic/data/services/firestore_academic_service.dart:150`
  - Ghi: `mobile/lib/features/academic/data/services/firestore_academic_service.dart:284, 330`
- **Rule tương ứng (`mobile/firestore.rules:78`):**
  - Read, Write: `signedIn()`

#### Collection: `submissions`
- **Đường dẫn:** `submissions/{id}`
- **Field chính:** `file_url` (string), `file_name` (string), `uploaded_at` (timestamp), `student_id` (string), `student_name` (string), `class_id` (string, optional), `project_id` (string, optional), `storage_provider` (string)
- **Đọc / Ghi trong code:**
  - Đọc stream: `mobile/lib/features/academic/data/student_submissions_repository.dart:72-81`
  - Ghi create: `mobile/lib/features/student/presentation/viewmodels/student_upload_view_model.dart:159, 166-176`
- **Rule tương ứng (`mobile/firestore.rules:82-89`):**
  - Create: `signedIn() && request.resource.data.student_id == request.auth.uid && request.resource.data.file_url is string && request.resource.data.file_name is string`
  - Read: `signedIn()`
  - Update, Delete: `false`

#### Collection: `srs_reports`
- **Đường dẫn:** `srs_reports/{id}`
- **Field chính:** `uid` (string), `fileName` (string), `fileSize` (number), `fileExtension` (string), `storagePath` (string), `downloadUrl` (string), `uploadedBy` (string), `uploadedByEmail` (string), `uploadedAt` (timestamp), `classId` (string, optional), `projectId` (string, optional)
- **Đọc / Ghi trong code:**
  - Ghi create (Student upload sync): `mobile/lib/features/student/presentation/viewmodels/student_upload_view_model.dart:179-189`
  - Ghi create (Direct SRS upload service): `mobile/lib/services/srs_service.dart:100-111`
- **Rule tương ứng (`mobile/firestore.rules:91-99`):**
  - Create: `signedIn() && (request.resource.data.get('uid', '') == request.auth.uid || request.resource.data.get('uploadedBy', '') == request.auth.uid)`
  - Read: `isAdmin() || (signedIn() && (resource.data.get('uid', '') == request.auth.uid || resource.data.get('uploadedBy', '') == request.auth.uid))`
  - Update, Delete: `false`

#### Collection: `crash_logs`
- **Đường dẫn:** `crash_logs/{id}`
- **Field chính:** `logId` (string), `type` ('non-fatal' | 'fatal'), `message` (string), `userId` (string), `timestamp` (timestamp), `stackTrace` (string), `deviceInfo` (string), `reason` (string), `customKeys` (map)
- **Đọc / Ghi trong code:**
  - Ghi non-fatal log: `mobile/lib/services/crashlytics_service.dart:84, 95-108`
  - Ghi fatal test log: `mobile/lib/services/crashlytics_service.dart:130, 133-140`
- **Rule tương ứng (`mobile/firestore.rules:101-105`):**
  - Create: `ownsMonitoringRecord() && request.resource.data.type in ['non-fatal', 'fatal']`
  - Read: `isAdmin()`
  - Update, Delete: `false`

#### Collection: `analytics_events`
- **Đường dẫn:** `analytics_events/{id}`
- **Field chính:** `name` (string), `params` (map), `userId` (string), `platform` (string), `timestamp` (timestamp)
- **Đọc / Ghi trong code:**
  - Ghi mirror analytics event: `mobile/lib/services/analytics_service.dart:192, 194-200`
- **Rule tương ứng (`mobile/firestore.rules:107-111`):**
  - Create: `ownsMonitoringRecord() && request.resource.data.name is string`
  - Read: `isAdmin()`
  - Update, Delete: `false`

#### Firebase Storage Path: `/reports/{userId}/{allPaths=**}`
- **Đường dẫn:** `/reports/{userId}/{allPaths=**}`
- **Rule tương ứng (`mobile/storage.rules:8-10`):**
  - Read, Write: `request.auth != null && request.auth.uid == userId`

---

## 3. SQLite Cục bộ Mobile (Outbox/Offline Academic Store)

- **File định nghĩa:** `mobile/lib/core/sync/offline_academic_store.dart`
- **Phiên bản Schema:** `schemaVersion = 1` (`mobile/lib/core/sync/offline_academic_store.dart:47`)
- **Tên file SQLite:** `srs_academic.db` (`mobile/lib/core/sync/offline_academic_store.dart:48`)

#### Bảng `academic_snapshot`
- **Vị trí định nghĩa:** `mobile/lib/core/sync/offline_academic_store.dart:76-80`
- **Các cột:**
  - `id` | `INTEGER` | `PRIMARY KEY` | `CHECK (id = 1)`
  - `json` | `TEXT` | `NOT NULL`
  - `updated_at` | `INTEGER` | `NOT NULL`
- **Ràng buộc:** `PRIMARY KEY (id)`, `CHECK (id = 1)` (`mobile/lib/core/sync/offline_academic_store.dart:77`)
- **Index:** Không thấy index bổ sung trong code.

#### Bảng `outbox`
- **Vị trí định nghĩa:** `mobile/lib/core/sync/offline_academic_store.dart:82-95`
- **Các cột:**
  - `op_id` | `TEXT` | `PRIMARY KEY`
  - `collection` | `TEXT` | `NOT NULL`
  - `record_id` | `TEXT` | `NOT NULL`
  - `deleted` | `INTEGER` | `NOT NULL DEFAULT 0`
  - `data` | `TEXT` | Nullable
  - `client_ts` | `INTEGER` | `NOT NULL`
  - `attempts` | `INTEGER` | `NOT NULL DEFAULT 0`
  - `last_error` | `TEXT` | Nullable
- **Ràng buộc:** `PRIMARY KEY (op_id)` (`mobile/lib/core/sync/offline_academic_store.dart:83`)
- **Index:**
  - `CREATE INDEX idx_outbox_ts ON outbox(client_ts)` (`mobile/lib/core/sync/offline_academic_store.dart:92`)
  - `CREATE INDEX idx_outbox_record ON outbox(collection, record_id)` (`mobile/lib/core/sync/offline_academic_store.dart:93-94`)

#### Bảng `sync_meta`
- **Vị trí định nghĩa:** `mobile/lib/core/sync/offline_academic_store.dart:97`
- **Các cột:**
  - `key` | `TEXT` | `PRIMARY KEY`
  - `value` | `TEXT` | `NOT NULL`
- **Ràng buộc:** `PRIMARY KEY (key)` (`mobile/lib/core/sync/offline_academic_store.dart:97`)
- **Index:** Không thấy index bổ sung trong code.

---

## 4. Ràng buộc chưa có (Observed Facts in Code)

Các điểm thực tế quan sát được trực tiếp từ mã nguồn (không suy đoán hay đề xuất):

1. **Server ORM & SQLite Models (`server/app/infrastructure/db/models.py` & store files):**
   - Cột `User.email` trong `models.py:94` không có ràng buộc `UNIQUE` hoặc format check ở cấp database model (chỉ khai báo `String(320)` nullable).
   - Cột `Document.kind` trong `models.py:142` (`server_default="srs"`) không có `CheckConstraint` để giới hạn các giá trị hợp lệ (`srs`, `sds`), khác với cột `status`, `event`, `decision` vốn có `CheckConstraint`.
   - Cột `RequirementReview.score` có `CheckConstraint("score BETWEEN 0 AND 10")` (`models.py:322`), nhưng cột `ReviewReport.overall_score` (`models.py:290`) là `Float` không có ràng buộc khoảng giá trị (min/max constraint) ở cấp model.
   - Các bảng trong `sync.sqlite3` (`sync_records`, `sync_ops` tại `server/app/infrastructure/sync_store.py:74-93`) không có ràng buộc khóa ngoại (Foreign Key) tới bảng người dùng hay bảng hệ thống nào.
   - Bảng `cache_entries` (`server/app/infrastructure/store.py:165-176`) không có chỉ mục (index) hay ràng buộc trên cột `created_at`.
   - Bảng `criteria` (`server/app/config/criteria.py:48-59`) không có chỉ mục (index) riêng cho cột `enabled` hay `scope`.

2. **Mobile Firestore Rules (`mobile/firestore.rules`):**
   - 10 Collections Học vụ dùng chung (`courses`, `classes`, `groups`, `projects`, `registrations`, `semesters`, `offerings`, `ruleSets`, `students`, `documents`, `_meta`) dùng chung rule duy nhất `allow read, write: if signedIn();` (`mobile/firestore.rules:70-79`), không có kiểm tra kiểu dữ liệu (data type validation), cấu trúc trường (schema field validation) hay quyền sở hữu từng dòng record ở cấp Firestore Security Rules.
   - Collection `submissions` (`mobile/firestore.rules:82-89`) chỉ kiểm tra `student_id == request.auth.uid`, `file_url is string`, `file_name is string`; không kiểm tra sự tồn tại hoặc kiểu dữ liệu của các trường `student_name`, `class_id`, `project_id`, `storage_provider`.
   - Collection `srs_reports` (`mobile/firestore.rules:91-99`) không kiểm tra kiểu dữ liệu của `fileName`, `fileSize`, `fileExtension`, `storagePath`, `downloadUrl`.
   - Collection `users/{uid}` (`mobile/firestore.rules:43-54`) cho phép `update` nếu `isSelf(uid)`, ngoại trừ khóa `role` bị chặn không cho tự đổi, các trường khác (`displayName`, `photoUrl`, `fcmTokens`, `fcmTokenUpdatedAt`) không có ràng buộc kiểu hay độ dài chuỗi ở cấp Firestore Rules.

3. **Mobile Local SQLite Store (`mobile/lib/core/sync/offline_academic_store.dart`):**
   - Bảng `outbox`: cột `deleted` được định nghĩa `INTEGER NOT NULL DEFAULT 0` (`L86`) nhưng không có ràng buộc `CHECK (deleted IN (0, 1))`.
   - Bảng `outbox`: cột `op_id` là `PRIMARY KEY`, nhưng cặp `(collection, record_id)` không có ràng buộc khóa ngoại tới bảng `academic_snapshot`.
   - Bảng `sync_meta`: chỉ khai báo `(key TEXT PRIMARY KEY, value TEXT NOT NULL)` (`L97`), không có ràng buộc Check enum cho danh sách các `key` hợp lệ.

---

## 5. Danh sách File đã Đọc

1. `AGENTS.md`
2. `server/app/infrastructure/db/models.py`
3. `server/app/infrastructure/sync_store.py`
4. `server/app/store.py`
5. `server/app/infrastructure/store.py`
6. `server/app/config/criteria.py`
7. `server/app/config/rubric_store.py`
8. `mobile/firestore.rules`
9. `mobile/storage.rules`
10. `mobile/lib/core/services/fcm_service.dart`
11. `mobile/lib/features/account/data/push_inbox_repository.dart`
12. `mobile/lib/features/account/data/repositories/current_user_repository.dart`
13. `mobile/lib/services/auth_service.dart`
14. `mobile/lib/features/academic/data/services/firestore_academic_service.dart`
15. `mobile/lib/features/academic/data/student_submissions_repository.dart`
16. `mobile/lib/features/student/presentation/viewmodels/student_upload_view_model.dart`
17. `mobile/lib/services/analytics_service.dart`
18. `mobile/lib/services/crashlytics_service.dart`
19. `mobile/lib/services/srs_service.dart`
20. `mobile/lib/core/sync/offline_academic_store.dart`
