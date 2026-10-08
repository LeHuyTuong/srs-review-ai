import { useState } from "react"
import { useParams } from "react-router-dom"
import DocumentCard from "@/components/document/DocumentCard"
import BackLink from "@/components/ui/BackLink"
import Badge from "@/components/ui/Badge"
import Card from "@/components/ui/Card"
import EmptyState from "@/components/ui/EmptyState"
import Notice from "@/components/ui/Notice"
import PageHeading from "@/components/ui/PageHeading"
import ProgressBar from "@/components/ui/ProgressBar"
import SegmentedTabs from "@/components/ui/SegmentedTabs"
import { classes, documents, projects } from "@/data/mockData"
import type { DocumentStatus } from "@/types"

const filters: { label: (n: number) => string; match?: DocumentStatus }[] = [
  { label: (n) => `Tất cả (${n})` },
  { label: (n) => `Chờ review (${n})`, match: "submitted" },
  { label: (n) => `Cần sửa (${n})`, match: "changes_requested" },
]

export default function ProjectDocumentsPage() {
  const { projectId } = useParams()
  const project = projects.find((p) => p.id === projectId)
  const docs = documents.filter((d) => d.projectId === projectId)
  const tabs = filters.map((f) => f.label(f.match ? docs.filter((d) => d.status === f.match).length : docs.length))
  const [active, setActive] = useState(tabs[0])

  if (!project) return <EmptyState title="Không tìm thấy project" />

  const match = filters[tabs.indexOf(active)]?.match
  const visible = match ? docs.filter((d) => d.status === match) : docs
  const classCode = classes.find((c) => c.id === project.classId)?.code

  return (
    <>
      <BackLink label={project.name} fallback={`/projects/${project.id}`} />
      <PageHeading title="Tài liệu Project" description="Theo dõi trạng thái, version và kết quả review của từng tài liệu." />
      <Card>
        <p className="text-[12px] text-muted">{classCode} · {project.groupName} · Fall 2026</p>
        <p className="text-[13px] text-ink">Giảng viên: {project.lecturer}</p>
        <div className="flex items-center justify-between gap-2">
          <Badge tone="brand">Đang thực hiện</Badge>
          <span className="text-[12px] text-muted">{docs.length} loại tài liệu</span>
        </div>
        <ProgressBar value={project.progress} />
      </Card>
      <SegmentedTabs tabs={tabs} active={active} onChange={setActive} />
      <Notice>Sinh viên nộp version trước, sau đó gửi yêu cầu review. Mỗi lần nộp lại tạo version mới; version cũ luôn được giữ lại.</Notice>
      <section className="flex flex-col gap-3">
        {visible.length ? visible.map((d) => <DocumentCard key={d.id} doc={d} />) : <EmptyState title="Không có tài liệu" />}
      </section>
    </>
  )
}
