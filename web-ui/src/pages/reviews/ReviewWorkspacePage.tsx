import { Expand, Maximize, Sparkles, ZoomIn, ZoomOut } from "lucide-react"
import { useState } from "react"
import CommentThread from "@/components/review/CommentThread"
import ConversationTimeline from "@/components/review/ConversationTimeline"
import IssueCard from "@/components/review/IssueCard"
import ReviewContextCard from "@/components/review/ReviewContextCard"
import BackLink from "@/components/ui/BackLink"
import Badge from "@/components/ui/Badge"
import Button from "@/components/ui/Button"
import Card from "@/components/ui/Card"
import EmptyState from "@/components/ui/EmptyState"
import MetaGrid from "@/components/ui/MetaGrid"
import Notice from "@/components/ui/Notice"
import PageHeading from "@/components/ui/PageHeading"
import SectionHeader from "@/components/ui/SectionHeader"
import SegmentedTabs from "@/components/ui/SegmentedTabs"
import Textarea from "@/components/ui/Textarea"
import { actions, useStore } from "@/data/store"
import useReviewFromParams from "./useReviewFromParams"

const useCases = ["Login", "Manage Project", "Upload Document", "Request Review", "Submit Document", "Review Document", "Approve Document"]
const tools = [
  { label: "Phóng to", icon: ZoomIn },
  { label: "Thu nhỏ", icon: ZoomOut },
  { label: "Vừa màn hình", icon: Maximize },
  { label: "Toàn màn hình", icon: Expand },
]

export default function ReviewWorkspacePage() {
  const { reviewId, review } = useReviewFromParams()
  const [selected, setSelected] = useState("Submit Document")
  const [panel, setPanel] = useState("AI Review")
  const [draft, setDraft] = useState("")
  const [note, setNote] = useState("")
  const { comments: all, events, submission } = useStore()
  // `findings` lives on the open submission's WIRE, not on `ReviewRequest` —
  // the summary rows a list is built from do not carry it. Read from the
  // detail the store is holding, and only when it is the same submission the
  // URL names (a mismatch would show one review's findings under another's).
  const findingEntries: [string, unknown][] =
    submission && submission.id === reviewId && submission.findings
      ? Object.entries(submission.findings)
      : []
  const comments = all.filter((c) => c.reviewId === reviewId)
  const thread = events.filter((e) => e.reviewId === reviewId)

  if (!review) return <EmptyState title="Không tìm thấy yêu cầu review" />

  const decided = review.status === "approved" || review.status === "changes_requested"
  const decide = (kind: "approved" | "changes_requested") => {
    actions.decide(review.id, kind, note)
    setNote("")
  }
  const sendComment = () => {
    if (!draft.trim()) return
    actions.addComment(review.id, selected, draft)
    setDraft("")
  }

  return (
    <>
      <BackLink label="Yêu cầu review" fallback="/reviews" />
      <PageHeading title="Không gian review" />
      <ReviewContextCard context={`${review.classCode} · ${review.groupName}`} version={review.version} projectName={review.projectName} documentTitle={review.documentTitle} status={review.status}>
        <MetaGrid items={[{ label: "Người nộp", value: review.submitter }, { label: "Ngày gửi", value: review.submittedAt }]} />
      </ReviewContextCard>

      <Card className="gap-3 p-3">
        <div className="grid grid-cols-4 gap-1">
          {tools.map(({ label, icon: Icon }) => (
            <button key={label} type="button" aria-label={label} className="flex flex-col items-center gap-1 rounded-[8px] py-1.5 text-[10px] text-muted active:bg-subtle">
              <Icon size={18} strokeWidth={1.75} />
              <span className="truncate">{label}</span>
            </button>
          ))}
        </div>
        <div className="grid grid-cols-[64px_1fr] items-center gap-3 rounded-[8px] bg-subtle p-3">
          <div className="flex flex-col gap-6 text-center text-[11px] font-semibold text-ink">
            <span>Student</span>
            <span>Supervisor</span>
          </div>
          <div className="flex flex-col gap-1.5">
            {useCases.map((uc) => (
              <button
                key={uc}
                type="button"
                onClick={() => setSelected(uc)}
                className={`truncate rounded-full border px-3 py-1.5 text-[12px] transition ${uc === selected ? "border-brand bg-brand-soft font-semibold text-brand" : "border-line bg-white text-ink"}`}
              >
                {uc}
              </button>
            ))}
          </div>
        </div>
        <p className="text-[12px] text-muted">Đang chọn: <span className="font-semibold text-ink">{selected}</span></p>
      </Card>

      <SegmentedTabs tabs={["AI Review", `Comment (${comments.length})`, "Review của giảng viên"]} active={panel} onChange={setPanel} />

      {/* The three badges that stood here — "2 lỗi", "3 cảnh báo", "4 gợi ý" —
        * were literal numbers in the JSX, and the issue cards below them came
        * from `mockData`. Both described one particular fixture review; every
        * real review showed them.
        *
        * They are replaced by what the server actually sends. `findings` is an
        * OPAQUE dict (submissions.py:73, "opaque to the proxy, which never
        * recomputes a score it was given"), so there is no fixed schema to
        * render: the page shows the keys it was handed and says plainly when
        * there are none, rather than filling the gap with a plausible count. */}
      <section className="flex flex-col gap-3">
        <Notice>AI chỉ hỗ trợ phát hiện vấn đề. Giảng viên quyết định phê duyệt cuối cùng.</Notice>
        {findingEntries.length === 0 ? (
          <Card>
            <p className="text-[13px] leading-[1.45] text-muted">
              Kỳ review này chưa có findings nào được gắn. Máy chủ chỉ lưu những gì công cụ
              review gửi lên, nên không có nghĩa là “không có lỗi” — chỉ nghĩa là chưa có.
            </p>
          </Card>
        ) : (
          findingEntries.map(([key, value]) => (
            <Card key={key}>
              <p className="text-[13px] font-semibold text-ink">{key}</p>
              <p className="text-[12px] leading-[1.45] text-muted">
                {typeof value === "string" || typeof value === "number"
                  ? String(value)
                  : JSON.stringify(value)}
              </p>
            </Card>
          ))
        )}
        <Button variant="secondary" to={`/reviews/${review.id}/ai-result`} icon={<Sparkles size={18} strokeWidth={1.75} />}>
          Xem kết quả AI Review
        </Button>
      </section>

      <section className="flex flex-col gap-3">
        <SectionHeader title="Comment trên phần tử" />
        <div className="flex flex-col gap-2 rounded-[8px] border border-line bg-white p-3">
          <Textarea aria-label="Nội dung comment" placeholder={`Nhận xét về “${selected}”...`} value={draft} onChange={(e) => setDraft(e.target.value)} />
          <Button onClick={sendComment} disabled={!draft.trim()}>Gửi comment cho sinh viên</Button>
        </div>
        {comments.length ? comments.map((c) => <CommentThread key={c.id} comment={c} viewer="teacher" />) : <EmptyState title="Chưa có comment" />}
      </section>

      <section className="flex flex-col gap-3">
        <SectionHeader title="Trao đổi với sinh viên" meta={`${thread.length} lượt`} />
        {thread.length ? <ConversationTimeline events={thread} /> : <EmptyState title="Chưa có trao đổi" />}
      </section>

      <section className="flex flex-col gap-3">
        <SectionHeader title={`Quyết định của giảng viên · ${review.documentTitle} ${review.version}`} />
        {decided && <Notice>Đã có quyết định cho {review.version}. Sinh viên nộp lại thì mới có thể quyết định tiếp.</Notice>}
        <Textarea aria-label="Ghi chú cho sinh viên" placeholder="Ghi chú gửi sinh viên (hiện cùng quyết định)..." value={note} onChange={(e) => setNote(e.target.value)} disabled={decided} />
        <Button onClick={() => decide("approved")} disabled={decided}>Phê duyệt</Button>
        <div className="grid grid-cols-2 gap-2">
          <Button variant="secondary" onClick={() => decide("changes_requested")} disabled={decided || !note.trim()}>Yêu cầu chỉnh sửa</Button>
        </div>
        {!decided && !note.trim() && <p className="text-[12px] text-muted">Yêu cầu chỉnh sửa cần ghi chú để sinh viên biết phải sửa gì.</p>}
        <div className="grid grid-cols-2 gap-2">
          <Button variant="secondary" to={`/reviews/${review.id}/versions`}>Lịch sử version</Button>
          <Button variant="secondary" to={`/reviews/${review.id}/history`}>Xem lịch sử review</Button>
        </div>
      </section>
    </>
  )
}
