import { useState } from "react"
import { useParams } from "react-router-dom"
import ProjectCard from "@/components/project/ProjectCard"
import BackLink from "@/components/ui/BackLink"
import Badge from "@/components/ui/Badge"
import EmptyState from "@/components/ui/EmptyState"
import Notice from "@/components/ui/Notice"
import PageHeading from "@/components/ui/PageHeading"
import SearchInput from "@/components/ui/SearchInput"
import SectionHeader from "@/components/ui/SectionHeader"
import SegmentedTabs from "@/components/ui/SegmentedTabs"
import StatCard from "@/components/ui/StatCard"
import { classes, studentGroups } from "@/data/mockData"

export default function ClassDetailPage() {
  const { classId } = useParams()
  const [tab, setTab] = useState("Nhóm")
  const classRoom = classes.find((c) => c.id === classId)

  if (!classRoom) return <EmptyState title="Không tìm thấy lớp" description={`Mã lớp “${classId}” không tồn tại.`} />

  const groups = studentGroups.filter((g) => g.classId === classRoom.id)

  return (
    <>
      <BackLink label="Lớp của tôi" fallback="/classes" />
      <PageHeading
        eyebrow="CHI TIẾT LỚP"
        title={classRoom.code}
        description={`${classRoom.subject} · ${classRoom.semester}`}
        aside={<Badge tone="brand">Đang giảng dạy</Badge>}
      />
      <SegmentedTabs tabs={["Tổng quan", "Nhóm", "Project", "Yêu cầu review"]} active={tab} onChange={setTab} />
      <div className="grid grid-cols-3 gap-3">
        <StatCard value={classRoom.groupCount} label="Số nhóm" />
        <StatCard value={classRoom.studentCount} label="Sinh viên" />
        <StatCard value={classRoom.pendingReviews} label="Đang chờ review" />
      </div>
      <section className="flex flex-col gap-3">
        <SectionHeader title="Nhóm sinh viên" meta={`${classRoom.groupCount} nhóm`} />
        <SearchInput placeholder="Tìm nhóm hoặc project..." />
        {groups.length ? groups.map((g) => <ProjectCard key={g.id} group={g} />) : <EmptyState title="Chưa có nhóm nào" />}
        <Notice>Tiến độ nhóm gồm tài liệu, mốc nộp và công việc. Tiến độ tài liệu của project được theo dõi riêng.</Notice>
      </section>
    </>
  )
}
