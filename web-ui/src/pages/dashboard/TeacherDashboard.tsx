import { BadgeCheck, ChevronRight } from "lucide-react"
import { Link } from "react-router-dom"
import ReviewRequestCard from "@/components/review/ReviewRequestCard"
import Badge from "@/components/ui/Badge"
import Card from "@/components/ui/Card"
import PageHeading from "@/components/ui/PageHeading"
import SearchInput from "@/components/ui/SearchInput"
import SectionHeader from "@/components/ui/SectionHeader"
import StatCard from "@/components/ui/StatCard"
import { attentionItems, currentUser } from "@/data/mockData"
import { reviewsOf, useStore } from "@/data/store"

const staticStats = [
  { value: 4, label: "Lớp đang phụ trách" },
  { value: 18, label: "Project đang hoạt động" },
]

export default function TeacherDashboard() {
  const store = useStore()
  const { notifications } = store
  const reviews = reviewsOf(store)
  const reviewRequests = reviews.filter((r) => r.status === "pending" || r.status === "resubmitted")
  const teacherNotifications = notifications.filter((n) => n.audience === "teacher").slice(0, 4)
  return (
    <>
      <div className="flex items-center justify-between gap-3 leading-[1.45]">
        <div className="min-w-0">
          <p className="text-[13px] font-semibold text-ink">Xin chào, {currentUser.name}</p>
          <p className="text-[12px] text-muted">{currentUser.role}</p>
        </div>
        <Badge>{currentUser.semester}</Badge>
      </div>

      <PageHeading eyebrow="QUẢN LÝ PROJECT SINH VIÊN" title="Tổng quan" description="Theo dõi lớp, project và các tài liệu đang chờ review." />
      <SearchInput placeholder="Tìm lớp, nhóm, project hoặc tài liệu..." />

      <section className="flex flex-col gap-3">
        <div className="grid grid-cols-2 gap-3">
          {[...staticStats, { value: reviewRequests.length, label: "Chờ review" }, { value: 5 + reviews.filter((r) => r.status === "needsRevision" || r.status === "rejected").length, label: "Cần chỉnh sửa" }].map((s) => <StatCard key={s.label} {...s} />)}
        </div>
        <Card tinted className="flex-row items-center gap-2.5">
          <BadgeCheck size={20} strokeWidth={1.75} className="shrink-0 text-brand" />
          <span className="flex-1 text-[13px] text-ink">Đã phê duyệt tuần này</span>
          <span className="text-[24px] leading-none font-semibold text-brand">{12 + reviews.filter((r) => r.status === "approved").length}</span>
        </Card>
      </section>

      <section className="flex flex-col gap-3">
        <SectionHeader title="Tài liệu đang chờ review" description="Các tài liệu sinh viên đã gửi yêu cầu và đang chờ bạn xử lý." linkTo="/reviews" />
        {reviewRequests.slice(0, 2).map((r) => <ReviewRequestCard key={r.id} review={r} />)}
      </section>

      <section className="flex flex-col gap-3">
        <SectionHeader title="Project cần chú ý" meta={`${attentionItems.length} project`} />
        <Card className="gap-0 py-1">
          <ul>
            {attentionItems.map((item) => (
              <li key={item.title} className="border-b border-line last:border-b-0">
                <Link to={`/projects/${item.projectId}`} className="flex items-center gap-3 py-3">
                  <div className="flex min-w-0 flex-1 flex-col items-start gap-1.5 leading-[1.45]">
                    <Badge tone={item.tone}>{item.label}</Badge>
                    <p className="text-[14px] font-semibold text-ink">{item.title}</p>
                    <p className="text-[12px] text-muted">{item.detail}</p>
                  </div>
                  <ChevronRight size={18} strokeWidth={1.75} className="shrink-0 text-muted" />
                </Link>
              </li>
            ))}
          </ul>
        </Card>
      </section>

      <section className="flex flex-col gap-3">
        <SectionHeader title="Hoạt động gần đây" linkTo="/notifications" />
        <Card className="gap-0 py-1">
          <ul>
            {teacherNotifications.map((n) => (
              <li key={n.id} className="border-b border-line py-3 leading-[1.45] last:border-b-0">
                <p className="text-[13px] text-ink">{n.title}</p>
                <p className="text-[12px] text-muted">{n.meta}</p>
              </li>
            ))}
          </ul>
        </Card>
      </section>
    </>
  )
}
