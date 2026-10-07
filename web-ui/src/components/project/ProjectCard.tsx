import Badge from "@/components/ui/Badge"
import Button from "@/components/ui/Button"
import Card from "@/components/ui/Card"
import MetaGrid from "@/components/ui/MetaGrid"
import ProgressBar from "@/components/ui/ProgressBar"
import { groupHealthMeta, projects } from "@/data/mockData"
import type { StudentGroup } from "@/types"

export default function ProjectCard({ group }: { group: StudentGroup }) {
  const health = groupHealthMeta[group.health]
  const project = projects.find((p) => p.id === group.projectId)
  return (
    <Card>
      <div className="flex items-center justify-between gap-3">
        <span className="text-[12px] text-muted">{group.name}</span>
        <Badge tone={health.tone}>{health.label}</Badge>
      </div>
      <p className="text-[17px] leading-[1.45] font-semibold text-ink">{project?.name}</p>
      <ProgressBar value={group.progress} label="Tiến độ tài liệu" />
      <MetaGrid
        items={[
          { label: "Thành viên", value: `${group.memberCount} sinh viên` },
          { label: "Chờ review", value: `${group.pendingReviews} tài liệu` },
          { label: "Hoạt động mới", value: group.lastActivity },
        ]}
      />
      <Button variant="secondary" to={`/projects/${group.projectId}`}>Xem project</Button>
    </Card>
  )
}
