import { useState } from "react"
import Avatar from "@/components/ui/Avatar"
import { initialsOf } from "@/components/ui/initials"
import Badge from "@/components/ui/Badge"
import Button from "@/components/ui/Button"
import Textarea from "@/components/ui/Textarea"
import { actions } from "@/data/store"
import type { ReviewComment, Role } from "@/types"

/** A teacher comment on a diagram element, with the replies under it. Either role can reply or toggle resolved. */
export default function CommentThread({ comment, viewer }: { comment: ReviewComment; viewer: Role }) {
  const [open, setOpen] = useState(false)
  const [draft, setDraft] = useState("")
  const replies = comment.replies ?? []

  const send = () => {
    if (!draft.trim()) return
    actions.reply(comment.id, viewer, draft)
    setDraft("")
    setOpen(false)
  }

  return (
    <div className="flex flex-col gap-2.5 rounded-[8px] border border-line bg-white p-3">
      <div className="flex items-center gap-2.5">
        <Avatar initials={initialsOf(comment.author)} size={32} />
        <div className="min-w-0 flex-1 leading-[1.45]">
          <p className="text-[13px] font-semibold text-ink">{comment.author}</p>
          <p className="text-[11px] text-muted">{comment.role} · {comment.createdAt}</p>
        </div>
        <Badge tone={comment.resolved ? "brand" : "amber"}>{comment.resolved ? "Đã xử lý" : "Đang mở"}</Badge>
      </div>
      <p className="text-[12px] text-muted">Phần tử: {comment.element}</p>
      <p className="text-[13px] leading-[1.45] text-ink">{comment.message}</p>

      {replies.length > 0 && (
        <ul className="flex flex-col gap-2 border-l-2 border-line pl-3">
          {replies.map((r) => (
            <li key={r.id} className="leading-[1.45]">
              <p className="text-[11px] text-muted">{r.author} · {r.role === "teacher" ? "Giảng viên" : "Sinh viên"} · {r.createdAt}</p>
              <p className="text-[13px] text-ink">{r.message}</p>
            </li>
          ))}
        </ul>
      )}

      {open && (
        <div className="flex flex-col gap-2">
          <Textarea aria-label="Nội dung trả lời" placeholder="Viết trả lời..." value={draft} onChange={(e) => setDraft(e.target.value)} autoFocus />
          <div className="grid grid-cols-2 gap-2">
            <Button variant="secondary" onClick={() => setOpen(false)}>Hủy</Button>
            <Button onClick={send} disabled={!draft.trim()}>Gửi</Button>
          </div>
        </div>
      )}

      <div className="flex gap-4">
        {!open && <button type="button" onClick={() => setOpen(true)} className="text-[12px] font-semibold text-brand">Trả lời</button>}
        <button type="button" onClick={() => actions.toggleResolved(comment.id)} className="text-[12px] font-semibold text-brand">
          {comment.resolved ? "Mở lại comment" : viewer === "student" ? "Đánh dấu đã sửa" : "Đánh dấu đã xử lý"}
        </button>
      </div>
    </div>
  )
}
