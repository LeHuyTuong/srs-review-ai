import { ArrowRight, CalendarClock } from "lucide-react"
import { useState } from "react"
import { useParams } from "react-router-dom"
import DocumentRoadmapItem from "@/components/document/DocumentRoadmapItem"
import MemberRow from "@/components/project/MemberRow"
import BackLink from "@/components/ui/BackLink"
import Badge from "@/components/ui/Badge"
import Button from "@/components/ui/Button"
import Card from "@/components/ui/Card"
import EmptyState from "@/components/ui/EmptyState"
import MetaGrid from "@/components/ui/MetaGrid"
import Notice from "@/components/ui/Notice"
import PageHeading from "@/components/ui/PageHeading"
import ProgressBar from "@/components/ui/ProgressBar"
import SectionHeader from "@/components/ui/SectionHeader"
import SegmentedTabs from "@/components/ui/SegmentedTabs"
import { classes, documents, projects } from "@/data/mockData"

export default function ProjectDetailPage() {
  const { projectId } = useParams()
  const [tab, setTab] = useState("Tổng quan")
  const project = projects.find((p) => p.id === projectId)

  if (!project) return <EmptyState title="Không tìm thấy project" description={`“${projectId}” không tồn tại.`} />

  const classCode = classes.find((c) => c.id === project.classId)?.code ?? ""
  const docs = documents.filter((d) => d.projectId === project.id)

  return (
    <>
      <BackLink label={`${classCode} / ${project.groupName}`} fallback={`/classes/${project.classId}`} />
      <PageHeading eyebrow="CHI TIẾT PROJECT" title={project.name} description={`${classCode} · ${project.groupName}`} />
      <Card>
        <div className="flex items-center justify-between">
          <Badge tone="brand">Đang thực hiện</Badge>
          <CalendarClock size={18} strokeWidth={1.75} className="text-muted" />
        </div>
        <MetaGrid items={[{ label: "Giảng viên", value: project.lecturer }, { label: "Bắt đầu", value: project.startDate }, { label: "Deadline", value: project.deadline }]} />
        <ProgressBar value={project.progress} label="Tiến độ tài liệu" />
      </Card>
      <SegmentedTabs tabs={["Tổng quan", "Tài liệu", "Thành viên", "Lịch sử review"]} active={tab} onChange={setTab} />

      <section className="flex flex-col gap-3">
        <SectionHeader title="Lộ trình tài liệu" description="Tài liệu sau chỉ mở khi các tài liệu phụ thuộc đã được giảng viên phê duyệt." />
        {docs.length ? (
          <>
            <Card className="gap-0 py-1">
              <ul>{docs.filter((d) => d.id !== "class-diagram").map((d) => <DocumentRoadmapItem key={d.id} doc={d} />)}</ul>
            </Card>
            <Notice>SRS chưa thể gửi review vì Sequence Diagram và State Diagram chưa được phê duyệt.</Notice>
            <Button variant="secondary" to={`/projects/${project.id}/documents`} icon={<ArrowRight size={18} strokeWidth={1.75} />} className="flex-row-reverse">
              Xem tất cả tài liệu
            </Button>
          </>
        ) : (
          <EmptyState title="Chưa có tài liệu" description="Nhóm chưa nộp tài liệu nào." />
        )}
      </section>

      <section className="flex flex-col gap-3">
        <SectionHeader title="Thành viên" meta={`${project.members.length} sinh viên`} />
        <Card className="gap-0 py-1">
          <ul className="divide-y divide-line">{project.members.map((m) => <MemberRow key={m.name} member={m} />)}</ul>
        </Card>
      </section>

      {project.nextStep && (
        <Card tinted>
          <p className="text-[14px] font-semibold text-ink">Bước tiếp theo</p>
          <p className="text-[13px] leading-[1.45] text-ink">{project.nextStep}</p>
          <p className="text-[12px] text-muted">{project.lastReturn}</p>
        </Card>
      )}
    </>
  )
}
