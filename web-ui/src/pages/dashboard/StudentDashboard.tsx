import { ChevronRight } from "lucide-react"
import { Link } from "react-router-dom"
import Badge from "@/components/ui/Badge"
import Card from "@/components/ui/Card"
import PageHeading from "@/components/ui/PageHeading"
import SectionHeader from "@/components/ui/SectionHeader"
import StatCard from "@/components/ui/StatCard"
import StatusBadge from "@/components/ui/StatusBadge"
import { useStore } from "@/data/store"
import { useSession } from "@/app/auth"
import { studentReviews } from "@/pages/reviews/studentReviews"

export default function StudentDashboard() {
  const store = useStore()
  const items = studentReviews(store)
  const count = (...s: string[]) => items.filter((i) => s.includes(i.review.status)).length
  const needsWork = items.filter((i) => i.review.status === "changes_requested")
  const mine = store.notifications.filter((n) => n.audience === "student").slice(0, 4)
  // The account on the SERVER, not a name in a fixture. `useSession` is
  // `undefined` while the session is still being asked about and `null` when
  // there is none, so both are rendered as an empty greeting rather than
  // flashed as "Xin chào, undefined" — the header is not worth a skeleton, but
  // it is worth not lying for one frame.
  const session = useSession()

  return (
    <>
      <div className="flex items-center justify-between gap-3 leading-[1.45]">
        <div className="min-w-0">
          <p className="text-[13px] font-semibold text-ink">Xin chào, {session?.username ?? ""}</p>
          <p className="text-[12px] text-muted">Sinh viên</p>
        </div>
      </div>

      <PageHeading eyebrow={(session?.group ?? "").toUpperCase()} title="Tổng quan" description="Xem giảng viên đã nhận xét gì và còn việc gì nhóm cần sửa." />

      <div className="grid grid-cols-2 gap-3">
        <StatCard value={needsWork.length} label="Cần chỉnh sửa" />
        <StatCard value={count("pending", "resubmitted")} label="Chờ giảng viên" />
        <StatCard value={count("approved")} label="Đã phê duyệt" />
        <StatCard value={items.reduce((n, i) => n + i.openComments, 0)} label="Comment đang mở" />
      </div>

      <section className="flex flex-col gap-3">
        <SectionHeader title="Giảng viên đang chờ bạn" description="Các tài liệu bị trả lại và cần nộp bản mới." linkTo="/reviews" />
        {needsWork.length ? (
          needsWork.map(({ review, lastNote }) => (
            <Card key={review.id}>
              <div className="flex items-center justify-between gap-2">
                <span className="text-[14px] font-semibold text-ink">{review.documentTitle} {review.version}</span>
                <StatusBadge status={review.status} />
              </div>
              {lastNote && <p className="text-[12px] leading-[1.45] text-muted">“{lastNote}”</p>}
              <Link to={`/reviews/${review.id}`} className="text-[13px] font-semibold text-brand">Xem phản hồi và nộp lại →</Link>
            </Card>
          ))
        ) : (
          <Card tinted><p className="text-[13px] text-ink">Không có tài liệu nào đang chờ nhóm sửa.</p></Card>
        )}
      </section>

      <section className="flex flex-col gap-3">
        <SectionHeader title="Cập nhật từ giảng viên" linkTo="/notifications" />
        <Card className="gap-0 py-1">
          <ul>
            {mine.map((n) => (
              <li key={n.id} className="border-b border-line last:border-b-0">
                <Link to={n.link ?? "/dashboard"} className="flex items-center gap-3 py-3 leading-[1.45]">
                  <span className="min-w-0 flex-1">
                    <span className={`block text-[13px] text-ink ${n.unread ? "font-semibold" : ""}`}>{n.title}</span>
                    <span className="block text-[12px] text-muted">{n.meta}</span>
                  </span>
                  <ChevronRight size={18} strokeWidth={1.75} className="shrink-0 text-muted" />
                </Link>
              </li>
            ))}
          </ul>
        </Card>
      </section>
    </>
  )
}
