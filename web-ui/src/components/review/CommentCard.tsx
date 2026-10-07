import Avatar from "@/components/ui/Avatar"
import Badge from "@/components/ui/Badge"
import type { ReviewComment } from "@/types"

export default function CommentCard({ comment, onToggle }: { comment: ReviewComment; onToggle: () => void }) {
  return (
    <div className="flex flex-col gap-2.5 rounded-[8px] border border-line bg-white p-3">
      <div className="flex items-center gap-2.5">
        <Avatar initials="NA" size={32} />
        <div className="min-w-0 flex-1 leading-[1.45]">
          <p className="text-[13px] font-semibold text-ink">{comment.author}</p>
          <p className="text-[11px] text-muted">{comment.role} · {comment.createdAt}</p>
        </div>
        <Badge tone={comment.resolved ? "brand" : "amber"}>{comment.resolved ? "Đã xử lý" : "Đang mở"}</Badge>
      </div>
      <p className="text-[12px] text-muted">Phần tử: {comment.element}</p>
      <p className="text-[13px] leading-[1.45] text-ink">{comment.message}</p>
      <button type="button" onClick={onToggle} className="self-start text-[12px] font-semibold text-brand">
        {comment.resolved ? "Mở lại comment" : "Đánh dấu đã xử lý"}
      </button>
    </div>
  )
}
