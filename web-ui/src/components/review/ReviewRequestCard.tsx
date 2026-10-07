import { FilePenLine, FileText } from "lucide-react"
import Badge from "@/components/ui/Badge"
import Button from "@/components/ui/Button"
import Card from "@/components/ui/Card"
import StatusBadge from "@/components/ui/StatusBadge"
import type { ReviewRequest } from "@/types"

export default function ReviewRequestCard({ review }: { review: ReviewRequest }) {
  return (
    <Card>
      <div className="flex justify-between gap-3 text-[12px] leading-[1.45] text-muted">
        <span className="min-w-0">{review.classCode} · {review.groupName}</span>
        <span className="shrink-0">{review.submittedAgo}</span>
      </div>
      <p className="text-[17px] leading-[1.45] font-semibold text-ink">{review.projectName}</p>
      <div className="flex items-center gap-2">
        <FileText size={18} strokeWidth={1.75} className="shrink-0 text-muted" />
        <span className="min-w-0 flex-1 text-[14px] font-semibold text-ink">{review.documentTitle}</span>
        <Badge>{review.version}</Badge>
      </div>
      <div className="flex flex-wrap gap-2">
        <Badge tone="olive">{review.aiSummary}</Badge>
        <StatusBadge status={review.status} />
      </div>
      {review.resubmitNote && <p className="text-[12px] leading-[1.45] text-muted">{review.resubmitNote}</p>}
      <Button to={`/reviews/${review.id}`} icon={<FilePenLine size={18} strokeWidth={1.75} />}>
        Review ngay
      </Button>
    </Card>
  )
}
