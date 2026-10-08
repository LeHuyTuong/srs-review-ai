import { CircleCheck, ClipboardList, Minus } from "lucide-react"
import ReviewContextCard from "@/components/review/ReviewContextCard"
import BackLink from "@/components/ui/BackLink"
import Badge from "@/components/ui/Badge"
import Button from "@/components/ui/Button"
import Card from "@/components/ui/Card"
import EmptyState from "@/components/ui/EmptyState"
import Notice from "@/components/ui/Notice"
import PageHeading from "@/components/ui/PageHeading"
import SectionHeader from "@/components/ui/SectionHeader"
import { stamp, useStore } from "@/data/store"
import { reportUri } from "@/data/store"
import useReviewFromParams from "./useReviewFromParams"

/** Render one opaque `findings` value without pretending to know its shape. */
function render(value: unknown): string {
  if (value === null) return "—"
  if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") {
    return String(value)
  }
  return JSON.stringify(value, null, 2)
}

export default function AIReviewResultPage() {
  const { reviewId, review } = useReviewFromParams()
  const { submission } = useStore()
  if (!review) return <EmptyState title="Không tìm thấy yêu cầu review" />

  // What this page used to show, and why none of it survives:
  //
  //   * the timestamp was the literal `03/10/2026 · 08:17` — a fixed moment
  //     printed for every document;
  //   * the severity tiles and "6 phát hiện" came from `mockData`;
  //   * the closing card asserted "Actor Student đã được bổ sung; còn 1 comment
  //     từ v1" — prose describing ONE particular fixture's contents, shown on
  //     every AI result page.
  //
  // What the server actually stores for a round is `score` (a number) and
  // `findings` (a dict it does not interpret — "opaque to the proxy",
  // submissions.py:73). So this renders exactly those two, and reports absence
  // as absence.
  const mine = submission && submission.id === reviewId ? submission : null
  const findings = mine?.findings ?? {}
  const entries = Object.entries(findings)
  const hasReview = Boolean(mine?.has_report)

  return (
    <>
      <BackLink label="Không gian review" fallback={`/reviews/${review.id}`} />
      <PageHeading
        eyebrow="PHÂN TÍCH TÀI LIỆU"
        title="Kết quả AI Review"
        aside={hasReview ? <Badge tone="brand">Đã có báo cáo</Badge> : <Badge>Chưa có</Badge>}
        description={
          hasReview
            ? `Cập nhật ${stamp(mine?.updatedAt ?? null)} · vòng ${mine?.revision ?? review.version}`
            : "Vòng này chưa có kết quả AI Review."
        }
      />
      <ReviewContextCard
        context={`${review.classCode} · ${review.groupName}`}
        version={review.version}
        projectName={review.projectName}
        documentTitle={review.documentTitle}
        status={review.status}
      />

      <div className="grid grid-cols-2 gap-3">
        <Card>
          <span className="text-[28px] leading-none font-semibold text-ink">
            {mine?.score ?? "—"}
          </span>
          <span className="text-[12px] text-muted">Điểm máy chủ ghi nhận (thang 10)</span>
        </Card>
        <Card>
          <span className="text-[28px] leading-none font-semibold text-ink">{entries.length}</span>
          <span className="text-[12px] text-muted">Mục trong findings</span>
        </Card>
      </div>
      <Notice>AI Review chỉ mang tính hỗ trợ. Quyết định phê duyệt cuối cùng thuộc về giảng viên.</Notice>

      <section className="flex flex-col gap-3">
        <SectionHeader title="Findings" meta={entries.length ? `${entries.length} mục` : undefined} />
        {entries.length === 0 ? (
          <EmptyState
            title="Chưa có findings"
            description="Máy chủ chỉ lưu những gì công cụ review gửi lên. Không có không có nghĩa là không có lỗi."
          />
        ) : (
          <Card className="gap-0 py-1">
            <ul>
              {entries.map(([key, value]) => (
                <li key={key} className="flex gap-3 border-b border-line py-3 last:border-b-0">
                  <CircleCheck size={18} strokeWidth={1.75} className="mt-0.5 shrink-0 text-muted" />
                  <div className="flex min-w-0 flex-1 flex-col items-start gap-1 leading-[1.45]">
                    <span className="text-[14px] font-semibold text-ink">{key}</span>
                    <pre className="w-full overflow-x-auto text-[12px] whitespace-pre-wrap text-muted">
                      {render(value)}
                    </pre>
                  </div>
                </li>
              ))}
            </ul>
          </Card>
        )}
      </section>

      <section className="flex flex-col gap-3">
        <SectionHeader title="Báo cáo đầy đủ" />
        {hasReview ? (
          <Card>
            <p className="text-[13px] leading-[1.45] text-ink">
              Bản báo cáo HTML của vòng này có trên máy chủ.
            </p>
            <a
              className="self-start text-[13px] font-semibold text-brand"
              href={reportUri(review.id)}
              target="_blank"
              rel="noreferrer"
            >
              Mở báo cáo →
            </a>
          </Card>
        ) : (
          <Card>
            <p className="flex items-center gap-2 text-[13px] text-muted">
              <Minus size={16} strokeWidth={1.75} /> Vòng này chưa gắn báo cáo nào.
            </p>
          </Card>
        )}
      </section>

      <Button to={`/reviews/${review.id}`} icon={<ClipboardList size={18} strokeWidth={1.75} />}>
        Bắt đầu review
      </Button>
    </>
  )
}
