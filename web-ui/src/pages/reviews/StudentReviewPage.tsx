import { Send } from "lucide-react"
import { useState } from "react"
import CommentThread from "@/components/review/CommentThread"
import ConversationTimeline from "@/components/review/ConversationTimeline"
import ReviewContextCard from "@/components/review/ReviewContextCard"
import BackLink from "@/components/ui/BackLink"
import Button from "@/components/ui/Button"
import EmptyState from "@/components/ui/EmptyState"
import MetaGrid from "@/components/ui/MetaGrid"
import Notice from "@/components/ui/Notice"
import PageHeading from "@/components/ui/PageHeading"
import SectionHeader from "@/components/ui/SectionHeader"
import Textarea from "@/components/ui/Textarea"
import { actions, useStore } from "@/data/store"
import useReviewFromParams from "./useReviewFromParams"

/** The student's side of one review: what the teacher said, and the way back. */
export default function StudentReviewPage() {
  const { reviewId, review } = useReviewFromParams()
  const { comments: all, events } = useStore()
  const [note, setNote] = useState("")

  if (!review) return <EmptyState title="Không tìm thấy tài liệu" />

  const comments = all.filter((c) => c.reviewId === reviewId)
  const thread = events.filter((e) => e.reviewId === reviewId)
  const open = comments.filter((c) => !c.resolved).length
  const canResubmit = review.status === "needsRevision" || review.status === "rejected"

  const resubmit = () => {
    actions.resubmit(review.id, note)
    setNote("")
  }

  return (
    <>
      <BackLink label="Phản hồi" fallback="/reviews" />
      <PageHeading eyebrow="PHẢN HỒI TỪ GIẢNG VIÊN" title={review.documentTitle} />
      <ReviewContextCard context={`${review.classCode} · ${review.groupName}`} version={review.version} projectName={review.projectName} documentTitle={review.documentTitle} status={review.status}>
        <MetaGrid items={[{ label: "Lần nộp gần nhất", value: review.submittedAt }, { label: "Comment đang mở", value: String(open) }]} />
      </ReviewContextCard>

      {review.status === "approved" && <Notice>Giảng viên đã phê duyệt tài liệu này. Không cần nộp lại.</Notice>}
      {(review.status === "pending" || review.status === "resubmitted") && <Notice>Giảng viên đang xem bản {review.version}. Bạn sẽ nhận thông báo khi có quyết định.</Notice>}

      <section className="flex flex-col gap-3">
        <SectionHeader title="Trao đổi với giảng viên" meta={`${thread.length} lượt`} />
        {thread.length ? <ConversationTimeline events={thread} /> : <EmptyState title="Chưa có trao đổi" description="Giảng viên chưa phản hồi tài liệu này." />}
      </section>

      <section className="flex flex-col gap-3">
        <SectionHeader title="Comment trên phần tử" meta={`${comments.length} comment`} />
        {comments.length ? comments.map((c) => <CommentThread key={c.id} comment={c} viewer="student" />) : <EmptyState title="Chưa có comment" />}
      </section>

      <section className="flex flex-col gap-3">
        <SectionHeader title="Nộp bản chỉnh sửa" />
        {canResubmit ? (
          <>
            {open > 0 && <Notice>Còn {open} comment đang mở. Bạn vẫn có thể nộp, nhưng giảng viên sẽ thấy chúng chưa được xử lý.</Notice>}
            <Textarea aria-label="Ghi chú khi nộp lại" placeholder="Nhóm đã sửa những gì? (giảng viên sẽ đọc dòng này)" value={note} onChange={(e) => setNote(e.target.value)} />
            <Button onClick={resubmit} disabled={!note.trim()} icon={<Send size={18} strokeWidth={1.75} />}>Nộp {`v${(parseInt(review.version.replace(/\D/g, ""), 10) || 1) + 1}`} cho giảng viên</Button>
          </>
        ) : (
          <Notice>Chỉ nộp lại được sau khi giảng viên yêu cầu chỉnh sửa.</Notice>
        )}
      </section>
    </>
  )
}
