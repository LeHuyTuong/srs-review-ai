import ClassCard from "@/components/project/ClassCard"
import BackLink from "@/components/ui/BackLink"
import Badge from "@/components/ui/Badge"
import PageHeading from "@/components/ui/PageHeading"
import SearchInput from "@/components/ui/SearchInput"
import SectionHeader from "@/components/ui/SectionHeader"
import { classes } from "@/data/mockData"

export default function ClassListPage() {
  return (
    <>
      <BackLink label="Tổng quan" fallback="/dashboard" />
      <PageHeading eyebrow="QUẢN LÝ LỚP HỌC" title="Lớp của tôi" description="Theo dõi các lớp và project mà bạn đang phụ trách." />
      <div className="flex flex-col gap-3">
        <SearchInput placeholder="Tìm lớp..." />
        <div className="flex flex-wrap gap-2">
          <Badge tone="brand">Học kỳ: Fall 2026</Badge>
          <Badge>Môn học</Badge>
          <Badge>Trạng thái</Badge>
        </div>
      </div>
      <section className="flex flex-col gap-3">
        <SectionHeader title={`${classes.length} lớp đang phụ trách`} />
        {classes.map((c) => <ClassCard key={c.id} classRoom={c} />)}
        <p className="text-center text-[12px] text-muted">18 project · 81 sinh viên trong học kỳ này</p>
      </section>
    </>
  )
}
