import { documentStatusMeta } from "@/data/mockData"
import type { DocumentStatus } from "@/types"
import Badge from "./Badge"

export default function StatusBadge({ status }: { status: DocumentStatus }) {
  const { label, tone } = documentStatusMeta[status]
  return <Badge tone={tone}>{label}</Badge>
}
