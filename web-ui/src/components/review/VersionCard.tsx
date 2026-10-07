import Badge from "@/components/ui/Badge"
import Card from "@/components/ui/Card"
import StatusBadge from "@/components/ui/StatusBadge"
import type { DocumentVersion } from "@/types"

export default function VersionCard({ version }: { version: DocumentVersion }) {
  return (
    <Card tinted={version.isCurrent} className={version.isCurrent ? "border-brand/30" : ""}>
      <div className="flex items-center justify-between gap-3">
        <span className="text-[17px] font-semibold text-ink">{version.version}{version.isCurrent && " · Version hiện tại"}</span>
        <StatusBadge status={version.status} />
      </div>
      <p className="text-[12px] text-muted">{version.submittedAt}</p>
      <div className="flex flex-wrap gap-2">
        <Badge tone="olive">{version.aiSummary}</Badge>
      </div>
      <div className="flex flex-col gap-1 text-[12px] leading-[1.45]">
        <p className="text-ink">{version.lecturerNote}</p>
        <p className="text-muted">{version.detail}</p>
        {version.feedback && <p className="text-muted">{version.feedback}</p>}
      </div>
      <button type="button" className="self-start text-[12px] font-semibold text-brand">Xem version →</button>
    </Card>
  )
}
