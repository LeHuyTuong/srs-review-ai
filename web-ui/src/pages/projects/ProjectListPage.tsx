import { ChevronRight } from "lucide-react"
import { Link } from "react-router-dom"
import ProjectCard from "@/components/project/ProjectCard"
import PageHeading from "@/components/ui/PageHeading"
import SearchInput from "@/components/ui/SearchInput"
import SectionHeader from "@/components/ui/SectionHeader"
import { classes, studentGroups } from "@/data/mockData"

export default function ProjectListPage() {
  return (
    <>
      <PageHeading eyebrow="QUẢN LÝ PROJECT" title="Project" description="Tất cả project sinh viên trong các lớp bạn phụ trách." />
      <SearchInput placeholder="Tìm nhóm hoặc project..." />
      <Link to="/classes" className="flex items-center justify-between rounded-[12px] border border-line bg-brand-tint p-4">
        <span className="leading-[1.45]">
          <span className="block text-[14px] font-semibold text-ink">Lớp của tôi</span>
          <span className="block text-[12px] text-muted">{classes.length} lớp đang phụ trách</span>
        </span>
        <ChevronRight size={18} strokeWidth={1.75} className="text-brand" />
      </Link>
      <section className="flex flex-col gap-3">
        <SectionHeader title="SE1701" meta={`${studentGroups.length} project`} />
        {studentGroups.map((g) => <ProjectCard key={g.id} group={g} />)}
      </section>
    </>
  )
}
