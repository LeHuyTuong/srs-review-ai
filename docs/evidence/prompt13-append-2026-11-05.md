# Bổ sung prompt Plan 13, giữ nguyên phần trước

Ngày: 05/11/2026, Asia/Saigon. Người dùng yêu cầu giữ nguyên phần trước của
`promt.txt`, chỉ nối thêm mục `# Kế hoạch implement 13` ở cuối.

Đã đọc lại file thực tế, không phục hồi hoặc ghi đè bằng phiên bản prompt của
lượt trước. Ghi append-only, kiểm toàn bộ prefix bằng bytes ngay sau khi ghi.

- Prefix trước khi nối: 7.906 bytes.
- SHA-256 prefix: `67c2bcd15b2882cb28eb4ea2de02dae540e224c85fefe6a8df2fe2fd19c9fc7b`.
- Phần nối: 6.191 bytes; heading mới bắt đầu dòng 113.
- Prefix sau ghi khớp hoàn toàn; heading mới có đúng một lần.
- Bổ sung link plan/progress/handoff, lựa chọn đã chốt, test từng chặng,
  mẫu yêu cầu thao tác cụ thể và quy tắc dừng trước phí mới.

Không triển khai code, chạy cloud/device hoặc đổi trạng thái nghiệm thu WP.
