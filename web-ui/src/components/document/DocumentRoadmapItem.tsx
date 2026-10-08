import { CircleCheck, Lock } from "lucide-react"
import { Link } from "react-router-dom"
import Badge from "@/components/ui/Badge"
import StatusBadge from "@/components/ui/StatusBadge"
import type { ProjectDocument } from "@/types"

export default function DocumentRoadmapItem({ doc }: { doc: ProjectDocument }) {
  // `locked` was never a server state. A document the student cannot submit
  // yet is exactly one with no submission behind it, which `version` already
  // says — so the roadmap reads that instead of a status the API cannot send.
  const Icon = doc.version ? CircleCheck : Lock
  const body = (
    <>
      <Icon size={18} strokeWidth={1.75} className={`mt-0.5 shrink-0 ${doc.status === "approved" ? "text-brand" : "text-muted"}`} />
      <div className="flex min-w-0 flex-1 flex-col gap-1.5">
        <div className="flex flex-wrap items-center gap-2">
          <span className="text-[14px] font-semibold text-ink">{doc.title}</span>
          {doc.version && <Badge>{doc.version}</Badge>}
        </div>
        <StatusBadge status={doc.status} />
        {doc.note && <p className="text-[12px] leading-[1.45] text-muted">{doc.note}</p>}
      </div>
    </>
  )
  return (
    <li className="border-b border-line last:border-b-0">
      {doc.reviewId ? (
        <Link to={`/reviews/${doc.reviewId}`} className="flex gap-3 py-3">{body}</Link>
      ) : (
        <div className="flex gap-3 py-3">{body}</div>
      )}
    </li>
  )
}
