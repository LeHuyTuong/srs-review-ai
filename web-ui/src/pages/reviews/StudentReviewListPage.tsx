import { ChevronRight, FileText } from "lucide-react"
import { Link } from "react-router-dom"
import Badge from "@/components/ui/Badge"
import Card from "@/components/ui/Card"
import EmptyState from "@/components/ui/EmptyState"
import PageHeading from "@/components/ui/PageHeading"
import SectionHeader from "@/components/ui/SectionHeader"
import StatusBadge from "@/components/ui/StatusBadge"
import { useStore } from "@/data/store"
import { useSession } from "@/app/auth"
import { studentReviews } from "./studentReviews"

export default function StudentReviewListPage() {
  const store = useStore()
  const session = useSession()
  const items = studentReviews(store)
  const waiting = items.filter((r) => r.review.status === "changes_requested")

  return (
    <>
      <PageHeading eyebrow={(session?.group ?? "").toUpperCase()} title="Phản hồi" description="Nhận xét và quyết định của giảng viên cho các tài liệu nhóm đã nộp." />
      <section className="flex flex-col gap-3">
        <SectionHeader title="Tài liệu của nhóm" meta={waiting.length ? `${waiting.length} cần sửa` : undefined} />
        {items.length ? (
          <Card className="gap-0 py-1">
            <ul>
              {items.map(({ review, openComments, lastNote }) => (
                <li key={review.id} className="border-b border-line last:border-b-0">
                  <Link to={`/reviews/${review.id}`} className="flex items-center gap-3 py-3">
                    <FileText size={18} strokeWidth={1.75} className="shrink-0 text-muted" />
                    <span className="flex min-w-0 flex-1 flex-col items-start gap-1.5 leading-[1.45]">
                      <span className="text-[14px] font-semibold text-ink">{review.documentTitle} <span className="font-normal text-muted">{review.version}</span></span>
                      <span className="text-[12px] text-muted">{review.projectName}</span>
                      <span className="flex flex-wrap gap-2">
                        <StatusBadge status={review.status} />
                        {openComments > 0 && <Badge tone="amber">{openComments} comment đang mở</Badge>}
                      </span>
                      {lastNote && <span className="line-clamp-2 text-[12px] text-muted">“{lastNote}”</span>}
                    </span>
                    <ChevronRight size={18} strokeWidth={1.75} className="shrink-0 text-muted" />
                  </Link>
                </li>
              ))}
            </ul>
          </Card>
        ) : (
          <EmptyState title="Chưa có tài liệu" description="Nhóm chưa nộp tài liệu nào." />
        )}
      </section>
    </>
  )
}
