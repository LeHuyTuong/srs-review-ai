import { FileText } from "lucide-react"
import { Link } from "react-router-dom"
import Badge from "@/components/ui/Badge"
import Button from "@/components/ui/Button"
import Card from "@/components/ui/Card"
import MetaGrid from "@/components/ui/MetaGrid"
import StatusBadge from "@/components/ui/StatusBadge"
import type { ProjectDocument } from "@/types"

export default function DocumentCard({ doc }: { doc: ProjectDocument }) {
  const hasVersion = Boolean(doc.version)
  return (
    <Card>
      <div className="flex items-center gap-2">
        <FileText size={18} strokeWidth={1.75} className="shrink-0 text-muted" />
        <span className="min-w-0 flex-1 text-[17px] font-semibold text-ink">{doc.title}</span>
        <Badge>{doc.version ?? "—"}</Badge>
      </div>
      <StatusBadge status={doc.status} />
      {doc.submitter && (
        <MetaGrid items={[{ label: "Người nộp", value: doc.submitter }, { label: "Cập nhật", value: doc.updatedAt ?? "—" }]} />
      )}
      {(doc.aiSummary || doc.commentCount !== undefined) && (
        <div className="flex flex-wrap gap-2">
          {doc.aiSummary && <Badge tone="olive">{doc.aiSummary}</Badge>}
          {doc.commentCount !== undefined && <Badge>{doc.commentCount} comment</Badge>}
        </div>
      )}
      {doc.note && <p className="text-[12px] leading-[1.45] text-muted">{doc.note}</p>}
      {hasVersion && (
        <div className="grid grid-cols-2 gap-2">
          <Button variant="secondary">Xem</Button>
          <Button variant={doc.status === "submitted" ? "primary" : "secondary"} to={doc.reviewId ? `/reviews/${doc.reviewId}` : undefined}>
            {doc.status === "submitted" ? "Review" : "Xem review"}
          </Button>
        </div>
      )}
      {doc.reviewId && (
        <Link to={`/reviews/${doc.reviewId}/versions`} className="self-start text-[12px] font-semibold text-brand">
          Lịch sử version →
        </Link>
      )}
    </Card>
  )
}
