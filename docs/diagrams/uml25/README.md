# Bộ diagram UML 2.5 của SRS Review AI

Thư mục này chứa bộ diagram canonical cho SRS Review AI: 23 diagram, không dùng emoji hoặc icon Unicode trong nguồn. Nhãn người dùng dùng tiếng Việt; tên lớp, endpoint, enum và mã định danh giữ bằng tiếng Anh để đối chiếu với mã nguồn.

## Chỉ mục

| # | Diagram | Nguồn | SVG / PNG | draw.io |
|---:|---|---|---|---|
| 1 | Tổng quan kiến trúc | [01-architecture-overview.mmd](01-architecture-overview.mmd) | [SVG](rendered/01-architecture-overview.svg) / [PNG](rendered/01-architecture-overview.png) | [draw.io](drawio/01-architecture-overview.drawio) |
| 2 | Triển khai tổng quan | [02-deployment-view.mmd](02-deployment-view.mmd) | [SVG](rendered/02-deployment-view.svg) / [PNG](rendered/02-deployment-view.png) | [draw.io](drawio/02-deployment-view.drawio) |
| 3 | Thành phần tổng quan | [03-component-view.mmd](03-component-view.mmd) | [SVG](rendered/03-component-view.svg) / [PNG](rendered/03-component-view.png) | [draw.io](drawio/03-component-view.drawio) |
| 4 | Hoạt động chính theo làn | [04-activity-main-swimlanes.mmd](04-activity-main-swimlanes.mmd) | [SVG](rendered/04-activity-main-swimlanes.svg) / [PNG](rendered/04-activity-main-swimlanes.png) | [draw.io](drawio/04-activity-main-swimlanes.drawio) |
| 5 | Các lớp gói | [05-package-layers.mmd](05-package-layers.mmd) | [SVG](rendered/05-package-layers.svg) / [PNG](rendered/05-package-layers.png) | [draw.io](drawio/05-package-layers.drawio) |
| 6 | Quan điểm lưu trữ | [06-persistence-view.mmd](06-persistence-view.mmd) | [SVG](rendered/06-persistence-view.svg) / [PNG](rendered/06-persistence-view.png) | [draw.io](drawio/06-persistence-view.drawio) |
| 7 | Tổng quan tương tác | [07-interaction-overview.mmd](07-interaction-overview.mmd) | [SVG](rendered/07-interaction-overview.svg) / [PNG](rendered/07-interaction-overview.png) | [draw.io](drawio/07-interaction-overview.drawio) |
| 8 | Tuần tự nhập và phân tích | [08-sequence-import-parse.mmd](08-sequence-import-parse.mmd) | [SVG](rendered/08-sequence-import-parse.svg) / [PNG](rendered/08-sequence-import-parse.png) | [draw.io](drawio/08-sequence-import-parse.drawio) |
| 9 | Tuần tự review | [09-sequence-review.mmd](09-sequence-review.mmd) | [SVG](rendered/09-sequence-review.svg) / [PNG](rendered/09-sequence-review.png) | [draw.io](drawio/09-sequence-review.drawio) |
| 10 | Tuần tự audit sơ đồ | [10-sequence-diagram-audit.mmd](10-sequence-diagram-audit.mmd) | [SVG](rendered/10-sequence-diagram-audit.svg) / [PNG](rendered/10-sequence-diagram-audit.png) | [draw.io](drawio/10-sequence-diagram-audit.drawio) |
| 11 | Tuần tự hỏi tài liệu | [11-sequence-ask.mmd](11-sequence-ask.mmd) | [SVG](rendered/11-sequence-ask.svg) / [PNG](rendered/11-sequence-ask.png) | [draw.io](drawio/11-sequence-ask.drawio) |
| 12 | Tuần tự xuất và chia sẻ | [12-sequence-export-share.mmd](12-sequence-export-share.mmd) | [SVG](rendered/12-sequence-export-share.svg) / [PNG](rendered/12-sequence-export-share.png) | [draw.io](drawio/12-sequence-export-share.drawio) |
| 13 | Nền tảng tải lên | [13-sequence-upload-groundwork.mmd](13-sequence-upload-groundwork.mmd) | [SVG](rendered/13-sequence-upload-groundwork.svg) / [PNG](rendered/13-sequence-upload-groundwork.png) | [draw.io](drawio/13-sequence-upload-groundwork.drawio) |
| 14 | Lớp miền và ứng dụng | [14-class-domain-application.mmd](14-class-domain-application.mmd) | [SVG](rendered/14-class-domain-application.svg) / [PNG](rendered/14-class-domain-application.png) | [draw.io](drawio/14-class-domain-application.drawio) |
| 15 | Trạng thái lượt review | [15-state-review-run.mmd](15-state-review-run.mmd) | [SVG](rendered/15-state-review-run.svg) / [PNG](rendered/15-state-review-run.png) | [draw.io](drawio/15-state-review-run.drawio) |
| 16 | Vòng đời finding | [16-state-finding-lifecycle.mmd](16-state-finding-lifecycle.mmd) | [SVG](rendered/16-state-finding-lifecycle.svg) / [PNG](rendered/16-state-finding-lifecycle.png) | [drawio](drawio/16-state-finding-lifecycle.drawio) |
| 17 | Tổng quan use case | [17-use-case-overview.puml](17-use-case-overview.puml) | [SVG](rendered/17-use-case-overview.svg) / [PNG](rendered/17-use-case-overview.png) | [draw.io](drawio/17-use-case-overview.drawio) |
| 18 | Hoạt động chính theo làn, PlantUML | [18-activity-main-swimlanes.puml](18-activity-main-swimlanes.puml) | [SVG](rendered/18-activity-main-swimlanes.svg) / [PNG](rendered/18-activity-main-swimlanes.png) | [draw.io](drawio/18-activity-main-swimlanes.drawio) |
| 19 | Kiến trúc thành phần, PlantUML | [19-component-architecture.puml](19-component-architecture.puml) | [SVG](rendered/19-component-architecture.svg) / [PNG](rendered/19-component-architecture.png) | [draw.io](drawio/19-component-architecture.drawio) |
| 20 | Giao tiếp review, PlantUML | [20-communication-review.puml](20-communication-review.puml) | [SVG](rendered/20-communication-review.svg) / [PNG](rendered/20-communication-review.png) | [draw.io](drawio/20-communication-review.drawio) |
| 21 | Triển khai runtime, PlantUML | [21-deployment-runtime.puml](21-deployment-runtime.puml) | [SVG](rendered/21-deployment-runtime.svg) / [PNG](rendered/21-deployment-runtime.png) | [draw.io](drawio/21-deployment-runtime.drawio) |
| 22 | Giao tiếp review, Mermaid | [22-communication-review.mmd](22-communication-review.mmd) | [SVG](rendered/22-communication-review.svg) / [PNG](rendered/22-communication-review.png) | [draw.io](drawio/22-communication-review.drawio) |
| 23 | Mô hình dữ liệu ERD | [23-data-model-erd.mmd](23-data-model-erd.mmd) | [SVG](rendered/23-data-model-erd.svg) / [PNG](rendered/23-data-model-erd.png) | [draw.io](drawio/23-data-model-erd.drawio) |

## Cách tái tạo

Từ thư mục gốc `srs-review-ai/`:

```sh
bash docs/diagrams/uml25/render.sh
python3 docs/diagrams/uml25/make_drawio.py
```

`render.sh` render Mermaid bằng `mmdc` và PlantUML bằng `java -jar ... -pipe`, ghi SVG/PNG vào `rendered/`. Cách dùng `-pipe` tránh thư mục lồng do PlantUML `-o` tạo ra. Nếu muốn render riêng:

```sh
mmdc -i docs/diagrams/uml25/01-architecture-overview.mmd \
  -o docs/diagrams/uml25/rendered/01-architecture-overview.svg -b white

java -jar "$HOME/.local/share/plantuml/plantuml.jar" \
  -charset UTF-8 -Playout=smetana -tsvg -pipe \
  < docs/diagrams/uml25/17-use-case-overview.puml \
  > docs/diagrams/uml25/rendered/17-use-case-overview.svg
```

Các file draw.io là XML tự chứa: mỗi file có một cell ảnh SVG dạng `data:image/svg+xml;base64,...`, kèm `sourcePath`, `sourceFormat`, `sourceHash`, `description` và một cell nguồn ẩn. Mở trực tiếp bằng diagrams.net/draw.io; không cần tải ảnh rời.

## Quy ước nhãn và nguồn

- Nguồn canonical chỉ chứa tiếng Việt ở nhãn người dùng; tên mã như `WorkspaceViewModel`, `POST /review`, `ReviewCache` được giữ nguyên để đối chiếu với code.
- Không dùng emoji hoặc icon Unicode trong nguồn diagram.
- PlantUML dùng include tuyệt đối tới `diagrams-agent/style.iuml`; nếu chuyển repo, cập nhật đường dẫn include trước khi render.
- `workflow.mmd` và `erd.mmd` ở thư mục cha là bản tương thích legacy đã được làm sạch, không phải diagram canonical. Các PNG legacy cũ đã được xóa.

## Giới hạn runtime cần ghi nhớ

- Cap hiện tại của app là **60 requirement/lượt** (`app/lib/core/app_config.dart:46`).
- Proxy giới hạn **50 request/ngày/người** (`server/app/config.py:56`). Vì vậy lượt đầu tiên với 60 requirement hoàn toàn mới có thể gặp 429 sau request thứ 50; app ghi nhận kết quả từng unit và không giả vờ rằng các unit chưa chạy đã được review.
- Quyết định hiện tại được ghi trong [ADR 0005](../../docs/adr/0005-run-cap-vs-quota.md). Một số tài liệu cũ còn nói cap 40; đó là quyết định cũ, không phải hành vi hiện tại của working tree.
