import { BadgeCheck, ChevronRight } from "lucide-react"
import { Link } from "react-router-dom"
import ReviewRequestCard from "@/components/review/ReviewRequestCard"
import Badge from "@/components/ui/Badge"
import Card from "@/components/ui/Card"
import PageHeading from "@/components/ui/PageHeading"
import SectionHeader from "@/components/ui/SectionHeader"
import StatCard from "@/components/ui/StatCard"
import { useSession } from "@/app/auth"
import { useStore } from "@/data/store"


export default function TeacherDashboard() {
  const store = useStore()
  const { notifications } = store
  // Counted from the SERVER's list for this session, not from fixtures.
  //
  // The lines this replaces read `{ value: 4, label: "Lớp đang phụ trách" }` and
  // `{ value: 18, label: "Project đang hoạt động" }` — two numbers a teacher
  // would read as facts about their own teaching, invented. A dashboard that
  // guesses is worse than one that says zero, because zero is at least
  // checkable. These count the rows the server actually returned for the
  // session (`store.list`, filled by `actions.loadList()`).
  const session = useSession()
  const submissions = store.list
  const waiting = submissions.filter(
    (s) => s.status === "submitted" || s.status === "changes_requested",
  ).length
  const needsWork = submissions.filter((s) => s.status === "changes_requested").length
  const approved = submissions.filter((s) => s.status === "approved").length
  const staticStats = [
    { value: submissions.length, label: "Bài nộp của lớp tôi" },
    { value: needsWork, label: "Cần chỉnh sửa" },
  ]
  const waitingRows = submissions.filter(
    (s) => s.status === "submitted" || s.status === "changes_requested",
  )
  const teacherNotifications = notifications.filter((n) => n.audience === "teacher").slice(0, 4)
  return (
    <>
      <div className="flex items-center justify-between gap-3 leading-[1.45]">
        <div className="min-w-0">
          <p className="text-[13px] font-semibold text-ink">Xin chào, {session?.username ?? ""}</p>
          <p className="text-[12px] text-muted">Giảng viên</p>
        </div>
      </div>

      {/* The search box that stood here is gone, not hidden. It filtered
        * fixture arrays in the browser and the server has no search route, so
        * keeping it would mean either a field that does nothing or one that
        * pretends to search a list the page already holds in full. A dead
        * control is a worse dashboard than a smaller one. */}
      <PageHeading eyebrow="QUẢN LÝ LỚP" title="Tổng quan" description="Bài nộp của lớp bạn phụ trách, đọc theo phiên đăng nhập." />

      <section className="flex flex-col gap-3">
        <div className="grid grid-cols-2 gap-3">
          {[...staticStats, { value: waiting, label: "Chờ review" }].map((s) => <StatCard key={s.label} {...s} />)}
        </div>
        <Card tinted className="flex-row items-center gap-2.5">
          <BadgeCheck size={20} strokeWidth={1.75} className="shrink-0 text-brand" />
          <span className="flex-1 text-[13px] text-ink">Đã phê duyệt tuần này</span>
          <span className="text-[24px] leading-none font-semibold text-brand">{approved}</span>
        </Card>
      </section>

      <section className="flex flex-col gap-3">
        <SectionHeader title="Bài nộp đang chờ bạn" description="Bài đã nộp hoặc đã bị yêu cầu sửa, theo thứ tự mới nhất trước." linkTo="/reviews" />
        {waitingRows.length === 0 ? (
          <Card>
            <p className="text-[13px] text-muted">
              Chưa có bài nào đang chờ. Danh sách này đọc thẳng từ máy chủ theo lớp của bạn.
            </p>
          </Card>
        ) : (
          waitingRows.map((row) => (
            <Card key={row.id}>
              <div className="flex justify-between gap-3 text-[12px] leading-[1.45] text-muted">
                <span className="min-w-0">{row.class_id}</span>
                <span className="shrink-0">vòng {row.revision}</span>
              </div>
              <p className="text-[17px] leading-[1.45] font-semibold text-ink">{row.project}</p>
              <div className="flex flex-wrap items-center gap-2">
                <Badge>{row.group}</Badge>
                <Badge tone={row.status === "submitted" ? "olive" : "amber"}>{row.status}</Badge>
                {row.openCommentCount > 0 ? (
                  <Badge tone="rust">{row.openCommentCount} nhận xét đang mở</Badge>
                ) : null}
              </div>
              <Link to={`/reviews/${row.id}`} className="text-[13px] font-semibold text-brand">
                Mở bài nộp
              </Link>
            </Card>
          ))
        )}
      </section>

      <section className="flex flex-col gap-3">
        <SectionHeader title="Hoạt động gần đây" linkTo="/notifications" />
        <Card className="gap-0 py-1">
          {teacherNotifications.length === 0 ? (
            <p className="py-3 text-[13px] text-muted">Chưa có hoạt động nào.</p>
          ) : (
            <ul>
              {teacherNotifications.map((n) => (
                <li key={n.id} className="border-b border-line py-3 leading-[1.45] last:border-b-0">
                  <p className="text-[13px] text-ink">{n.title}</p>
                  <p className="text-[12px] text-muted">{n.meta}</p>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </section>
    </>
  )
}
