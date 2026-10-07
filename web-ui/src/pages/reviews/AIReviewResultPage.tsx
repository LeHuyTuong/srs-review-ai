import { CircleCheck, ClipboardList } from "lucide-react"
import IssueCard from "@/components/review/IssueCard"
import ReviewContextCard from "@/components/review/ReviewContextCard"
import BackLink from "@/components/ui/BackLink"
import Badge, { toneClasses } from "@/components/ui/Badge"
import Button from "@/components/ui/Button"
import Card from "@/components/ui/Card"
import EmptyState from "@/components/ui/EmptyState"
import Notice from "@/components/ui/Notice"
import PageHeading from "@/components/ui/PageHeading"
import SectionHeader from "@/components/ui/SectionHeader"
import { aiChecks, aiIssues, aiSeverityCounts } from "@/data/mockData"
import useReviewFromParams from "./useReviewFromParams"

export default function AIReviewResultPage() {
  const { review } = useReviewFromParams()
  if (!review) return <EmptyState title="Không tìm thấy yêu cầu review" />

  return (
    <>
      <BackLink label="Không gian review" fallback={`/reviews/${review.id}`} />
      <PageHeading eyebrow="PHÂN TÍCH TÀI LIỆU" title="Kết quả AI Review" aside={<Badge tone="brand">Đã hoàn tất</Badge>} description="03/10/2026 · 08:17" />
      <ReviewContextCard context={`${review.classCode} · ${review.groupName}`} version={review.version} projectName={review.projectName} documentTitle={review.documentTitle} status={review.status} />

      <div className="grid grid-cols-2 gap-3">
        {aiSeverityCounts.map((s) => (
          <div key={s.label} className={`flex flex-col gap-1 rounded-[12px] p-4 ${toneClasses[s.tone]}`}>
            <span className="text-[28px] leading-none font-semibold">{s.value}</span>
            <span className="text-[12px]">{s.label}</span>
          </div>
        ))}
      </div>
      <Notice>AI Review chỉ mang tính hỗ trợ. Quyết định phê duyệt cuối cùng thuộc về giảng viên.</Notice>

      <section className="flex flex-col gap-3">
        <SectionHeader title="Kết quả kiểm tra" />
        <Card className="gap-0 py-1">
          <ul>
            {aiChecks.map((c) => (
              <li key={c.title} className="flex gap-3 border-b border-line py-3 last:border-b-0">
                <CircleCheck size={18} strokeWidth={1.75} className="mt-0.5 shrink-0 text-muted" />
                <div className="flex min-w-0 flex-1 flex-col items-start gap-1.5 leading-[1.45]">
                  <div className="flex w-full flex-wrap items-center justify-between gap-2">
                    <span className="text-[14px] font-semibold text-ink">{c.title}</span>
                    <Badge tone={c.tone}>{c.result}</Badge>
                  </div>
                  <p className="text-[12px] text-muted">{c.detail}</p>
                </div>
              </li>
            ))}
          </ul>
        </Card>
      </section>

      <section className="flex flex-col gap-3">
        <SectionHeader title="Các vấn đề cần xử lý" meta="6 phát hiện" />
        {aiIssues.map((i) => <IssueCard key={i.id} issue={i} />)}
      </section>

      <Card tinted>
        <p className="text-[14px] font-semibold text-ink">Đối chiếu lần nộp trước</p>
        <p className="text-[12px] leading-[1.45] text-muted">{review.version} · Nộp lại lần 1. Actor Student đã được bổ sung; còn 1 comment từ v1 cần giảng viên kiểm tra.</p>
      </Card>
      <Button to={`/reviews/${review.id}`} icon={<ClipboardList size={18} strokeWidth={1.75} />}>Bắt đầu review</Button>
    </>
  )
}
