# web-ui

Bản mock giao diện (React + Vite + Tailwind v4) cho giảng viên, xuất từ Figma Make. Chỉ là UI/UX: dữ liệu giả trong `src/data/mockData.ts`, đăng nhập giả bằng cờ localStorage, **không gọi server** và không dùng chung build với `app/` hay `server/`.

```sh
cd web-ui && pnpm install && pnpm dev   # http://127.0.0.1:5173
pnpm build                              # kiểm tra build
```

Hai vai, một cuộc trao đổi (`src/data/store.ts`, lưu localStorage, đổi vai ở màn đăng nhập):
- **Giảng viên:** comment lên từng phần tử, trả lời comment, Phê duyệt / Yêu cầu chỉnh sửa / Không đạt kèm ghi chú (chỉnh sửa và không đạt bắt buộc có ghi chú).
- **Sinh viên:** xem quyết định và comment, trả lời, đánh dấu đã sửa, nộp bản mới (chỉ khi giảng viên đã trả lại) kèm ghi chú.
- Mỗi hành động tạo thông báo cho phía bên kia. "Đặt lại dữ liệu demo" ở Tài khoản.
- Không có admin.

Responsive: dưới 1024px là layout mobile (tab dưới); từ 1024px là sidebar trái + cột nội dung 880px (`src/layouts/MobileAppLayout.tsx`).

Đã bỏ khỏi bản export: `.figma/`, plugin Figma trong `vite.config.ts`, `.gitattributes` (rule Git LFS cho ảnh) và `AGENTS.md`/`CLAUDE.md` của Figma.
