import { Link } from "react-router-dom"
import ReviewContextCard from "@/components/review/ReviewContextCard"
import TimelineItem from "@/components/review/TimelineItem"
import BackLink from "@/components/ui/BackLink"
import Card from "@/components/ui/Card"
import EmptyState from "@/components/ui/EmptyState"
import Notice from "@/components/ui/Notice"
import PageHeading from "@/components/ui/PageHeading"
import SectionHeader from "@/components/ui/SectionHeader"
import { reviewActivities } from "@/data/mockData"
import useReviewFromParams from "./useReviewFromParams"

export default function ReviewHistoryPage() {
  const { reviewId, review } = useReviewFromParams()
  if (!review) return <EmptyState title="Không tìm thấy yêu cầu review" />
  const activities = reviewActivities.filter((a) => a.reviewId === reviewId)

  return (
    <>
      <BackLink label={review.projectName} fallback={`/projects/${review.projectId}`} />
      <PageHeading title="Lịch sử review" description="Nhật ký nộp tài liệu, AI Review và quyết định của giảng viên." />
      <ReviewContextCard context={`${review.classCode} · ${review.groupName}`} version={review.version} projectName={review.projectName} documentTitle={review.documentTitle} status={activities.length ? "approved" : review.status} />

      <section className="flex flex-col gap-3">
        <SectionHeader title="Hoạt động" meta={`${activities.length} hoạt động`} />
        {activities.length ? (
          <Card>
            <p className="text-[12px] font-semibold text-muted">14/09/2026</p>
            <ol>{activities.map((a, i) => <TimelineItem key={a.id} activity={a} last={i === activities.length - 1} />)}</ol>
          </Card>
        ) : (
          <EmptyState title="Chưa có hoạt động" />
        )}
        <Notice>AI Review không đưa ra quyết định phê duyệt. Quyết định được ghi nhận từ giảng viên Nguyễn Văn An.</Notice>
      </section>

      <Card tinted>
        <p className="text-[14px] font-semibold text-ink">Lịch sử trước đó được giữ nguyên</p>
        <ul className="flex flex-col gap-1 text-[12px] leading-[1.45] text-muted">
          <li>v1: 3 comment · Cần chỉnh sửa</li>
          <li>v2: AI 1 lỗi · Cần chỉnh sửa</li>
          <li>2 lần nộp lại · Không có version bị xóa</li>
        </ul>
        <Link to={`/reviews/${review.id}/versions`} className="self-start text-[12px] font-semibold text-brand">Xem lịch sử version →</Link>
      </Card>
    </>
  )
}
