# uc-review (vendored)

Công cụ kiểm **Use Case Diagram** dạng `.drawio`, chạy tất định (không gọi AI). Server gọi nó qua
subprocess ở `POST /diagram/drawio` (`app/infrastructure/drawio_review.py`).

- Nguồn: `~/.dsh/skill-repo/diagram/kickoff-uml/scripts/` (skill `kickoff-uml`), cùng công cụ mà
  `startup-srs/web/lib/kiem-tra.ts` dùng.
- Vendor ngày 10/11/2026. SHA-256:
  - `uc-review.mjs`         `333364fd0c6f1e107d5ae4e4a8fbfc7bead8a1e708be87578f1b16af57df87d3`
  - `usecase-overview.mjs`  `385d0c0b70723e9b1d240251b487daf88c129d85800daff4f80aeb6b9d767e91`
- Chỉ dùng Node stdlib. Server luôn gọi với `--no-png` nên không cần `rsvg-convert` / Playwright.
- Cần Node ≥ 22 (image Docker copy binary từ `node:22-bookworm-slim`).

Cập nhật: copy lại hai file từ nguồn, ghi SHA mới vào đây, chạy
`server/.venv/bin/python -m pytest tests/test_drawio_review.py`.
**Đừng sửa tay hai file `.mjs`** — sửa ở skill gốc rồi vendor lại, nếu không hai bản sẽ trôi.

Luật mà công cụ thi hành được ghi ở `review-rules/adapters/app-port-map.md` (mục Use Case `.drawio`).
