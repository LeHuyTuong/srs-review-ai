# P1 — Chain 1 đọc tiếng Việt: từ "0 finding" giả tới số thật (2026-09-26)

**Giả định sai bị phát hiện:** `docs/evidence/r13_otes_deterministic_ceiling.md:29`
ghi `crossArtifactName` = **0** trên OTES. Đọc theo nghĩa thường thì đó là "tài
liệu này sạch". Thực tế là **"check này không đọc nổi tiếng Việt"** — regex
`[A-Z][a-z]+` ASCII-only, còn OTES viết tiếng Việt. Đây là false *negative* do
giới hạn code, không phải kết luận về tài liệu.

**Sửa:** `contradiction_pass.dart` nay dùng `[A-ZÀ-Ỹ][a-zà-ỹ]+`, và `_stem`
**không còn là bản sao** — nó gọi `CrossArtifactChecker.stemOf`, đúng hàm mà
chain 2 dùng. Trước đó có hai bản sao của cùng một hàm chuẩn hoá; chỉ một bản
được sửa thì hai bên hiểu "cùng một tên" khác nhau, và mọi khớp thật đều hỏng
mà không ai thấy.

## Số đo trước khi viết test (đo trước, khẳng định sau)

| Chuỗi | `original` đọc được | `stem` |
|---|---|---|
| `Customer registers` | `Customer` | `customer` |
| `Customers book` | `Customers` | `customer` ← **bắn** |
| `Sinhvien` | `Sinhvien` | `sinhvien` |
| `Sinhviens` | `Sinhviens` | `sinhvien` ← **bắn** |
| `Lớp` / `Lớps` | — | `lớp` / `lớp` ← số nhiều VN cũng gộp |
| `Sinh viên xem điểm` | `Sinh` | `sinh` — **bị cắt** |
| `Khách hàng đăng ký` | `Khách` | `khách` |

## Kết quả

`app/test/contradiction_pass_vietnamese_test.dart` — **5/5 xanh**, mỗi ca có
kỳ vọng viết ra từ bảng trên:

1. Khái niệm tiếng Việt viết hai cách **được báo** (trước đây `[]`).
2. Tiếng Anh **không hồi quy** (`Customer`/`Customers` vẫn bắn).
3. Tài liệu tiếng Việt sạch **im lặng** — bảo vệ chống báo động giả.
4. Dòng vẫn là `PENDING-VISION`: text không đủ bằng chứng để bảo "sửa tên này".
5. Ba giới hạn được **ghim lại bằng test** thay vì để ai phát hiện trong báo cáo.

## Ba giới hạn, đã ghim, không giấu

- **Không bỏ dấu tiếng Việt.** `Khách` ≠ `Khach` với `stemOf`. Muốn bỏ dấu là
  một quyết định khác (và sẽ đụng mọi chain), chưa làm.
- **Chữ hoa bên trong cắt tên.** `SinhVien` đọc thành `Sinh` — regex chỉ nhận
  một từ viết hoa liên tiếp.
- **Chỉ nhìn phần đầu.** `Sinhvien đăng ký` → `Sinhvien đăng` (hai từ), còn
  `Sinh viên xem` → `Sinh` (một từ). Hai chuỗi đó **không** gộp.

Giới hạn thứ ba là lý do test dùng `Sinhvien` / `Sinhviens` làm cặp bắn: đó là
hình dạng mà cơ chế thật sự xử lý được, chứ không phải hình dạng mình tưởng.

## Chưa làm gì

- **Chưa đo lại trên OTES thật.** AC4 của plan yêu cầu bảng so sánh trước/sau
  trên tài liệu thật; việc này cần một lượt parse + check đầy đủ, chưa chạy
  trong phiên này. Các test ở trên chứng minh *cơ chế* đã đúng, không thay
  thế số liệu trên tài liệu thật.
- **Chưa tính vào điểm.** Không có gold set (roadmap M2 vẫn **MỞ**).
