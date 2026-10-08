import { Link } from "react-router-dom"
import ReviewContextCard from "@/components/review/ReviewContextCard"
import TimelineItem from "@/components/review/TimelineItem"
import BackLink from "@/components/ui/BackLink"
import Card from "@/components/ui/Card"
import EmptyState from "@/components/ui/EmptyState"
import Notice from "@/components/ui/Notice"
import PageHeading from "@/components/ui/PageHeading"
import SectionHeader from "@/components/ui/SectionHeader"
import { useStore } from "@/data/store"
import type { ReviewActivity, ReviewEventKind, Tone } from "@/types"
import useReviewFromParams from "./useReviewFromParams"

const KIND_META: Record<ReviewEventKind, { title: string; tone: Tone }> = {
  submitted: { title: "Nhóm đã nộp", tone: "neutral" },
  reviewed: { title: "AI Review đã đọc", tone: "amber" },
  // `decided` covers both outcomes because that is genuinely what the server
  // records; WHICH way it went is the entry's `status`, carried as
  // `direction`. The title is chosen below from that, not from the kind.
  decided: { title: "Giảng viên đã quyết định", tone: "brand" },
  revised: { title: "Nhóm nộp lại", tone: "olive" },
  backfilled: { title: "Ghi bổ sung trạng thái cũ", tone: "neutral" },
  class_assigned: { title: "Bài được gắn vào lớp", tone: "neutral" },
}

export default function ReviewHistoryPage() {
  const { reviewId, review } = useReviewFromParams()
  const { events, submission } = useStore()
  if (!review) return <EmptyState title="Không tìm thấy yêu cầu review" />

  // The timeline is the submission's own `history`, translated by
  // `toEvents` — the same rows the store already holds for the thread. It used
  // to come from `mockData.reviewActivities`, one fixed script for every
  // review, and three parts of this page were hardcoded around it:
  //
  //   * a literal date `14/09/2026` printed above whatever activities rendered;
  //   * `status={activities.length ? "approved" : review.status}` — a document
  //     was shown as APPROVED purely because it had more than zero timeline
  //     rows, which is true of every document that has ever been submitted;
  //   * "quyết định được ghi nhận từ giảng viên Nguyễn Văn An" — a tutor's name
  //     in the copy, for a session that may belong to anyone.
  //
  // Only the rows whose submission matches the URL are used: the store holds
  // one open submission, and a mismatch would show one review's history under
  // another's title.
  const mine = submission && submission.id === reviewId ? events : []
  const activities: ReviewActivity[] = mine.map((e) => {
    const base = KIND_META[e.kind] ?? { title: String(e.kind), tone: "neutral" as Tone }
    // A decision reads as what it was. Without this every verdict — approve or
    // send-back — shows the same words, and the timeline stops being a record.
    const meta =
      e.kind === "decided"
        ? e.direction === "approved"
          ? { title: "Giảng viên phê duyệt", tone: "brand" as Tone }
          : e.direction === "changes_requested"
            ? { title: "Giảng viên yêu cầu chỉnh sửa", tone: "rust" as Tone }
            : base
        : base
    return {
      id: e.id,
      reviewId: e.reviewId,
      title: meta.title,
      time: e.createdAt,
      meta: `${e.author} · ${e.version}`,
      quote: e.note || undefined,
      tone: meta.tone,
    }
  })

  return (
    <>
      <BackLink label={review.projectName} fallback={`/projects/${review.projectId}`} />
      <PageHeading title="Lịch sử review" description="Nhật ký nộp tài liệu, AI Review và quyết định của giảng viên." />
      <ReviewContextCard
        context={`${review.classCode} · ${review.groupName}`}
        version={review.version}
        projectName={review.projectName}
        documentTitle={review.documentTitle}
        status={review.status}
      />

      <section className="flex flex-col gap-3">
        <SectionHeader title="Hoạt động" meta={`${activities.length} hoạt động`} />
        {activities.length ? (
          <Card>
            <ol>
              {activities.map((a, i) => (
                <TimelineItem key={a.id} activity={a} last={i === activities.length - 1} />
              ))}
            </ol>
          </Card>
        ) : (
          <EmptyState
            title="Chưa có hoạt động"
            description="Máy chủ chưa ghi mốc nào cho bài nộp này."
          />
        )}
        <Notice>
          AI Review không đưa ra quyết định phê duyệt. Quyết định do giảng viên phụ trách lớp đưa ra.
        </Notice>
      </section>

      <Card tinted>
        <p className="text-[14px] font-semibold text-ink">Lịch sử trước đó được giữ nguyên</p>
        <p className="text-[12px] leading-[1.45] text-muted">
          Mỗi vòng nộp giữ nguyên mốc cũ; không version nào bị xóa.
        </p>
        <Link to={`/reviews/${review.id}/versions`} className="self-start text-[12px] font-semibold text-brand">
          Xem lịch sử version →
        </Link>
      </Card>
    </>
  )
}
