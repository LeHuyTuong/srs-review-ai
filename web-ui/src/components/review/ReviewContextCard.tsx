import { FileText } from "lucide-react"
import type { ReactNode } from "react"
import Badge from "@/components/ui/Badge"
import Card from "@/components/ui/Card"
import StatusBadge from "@/components/ui/StatusBadge"
import type { DocumentStatus } from "@/types"

interface Props {
  context: string
  version: string
  projectName: string
  documentTitle: string
  status: DocumentStatus
  children?: ReactNode
}

export default function ReviewContextCard({ context, version, projectName, documentTitle, status, children }: Props) {
  return (
    <Card>
      <div className="flex items-center justify-between gap-3">
        <span className="text-[12px] text-muted">{context}</span>
        <Badge>{version}</Badge>
      </div>
      <p className="text-[17px] leading-[1.45] font-semibold text-ink">{projectName}</p>
      <div className="flex flex-wrap items-center gap-2">
        <FileText size={18} strokeWidth={1.75} className="shrink-0 text-muted" />
        <span className="min-w-0 flex-1 text-[14px] font-semibold text-ink">{documentTitle}</span>
        <StatusBadge status={status} />
      </div>
      {children}
    </Card>
  )
}
