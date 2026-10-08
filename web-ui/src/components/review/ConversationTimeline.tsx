import Avatar from "@/components/ui/Avatar"
import { initialsOf } from "@/components/ui/initials"
import Badge from "@/components/ui/Badge"
import type { ReviewEvent, ReviewEventKind, Tone } from "@/types"

// ADR-0019: the keys are exactly `ReviewEventKind` — the server's closed
// decision set plus the student's verb. `needsRevision`/`rejected` are
// document states, not conversation events, so they are gone from here.
const kindMeta: Record<ReviewEventKind, { label: string; tone: Tone }> = {
  submitted: { label: "Đã nộp", tone: "neutral" },
  reviewed: { label: "AI đã đọc", tone: "amber" },
  decided: { label: "Giảng viên đã quyết định", tone: "brand" },
  revised: { label: "Nộp lại", tone: "olive" },
  backfilled: { label: "Ghi bổ sung", tone: "neutral" },
  class_assigned: { label: "Gắn vào lớp", tone: "neutral" },
}

/** Teacher decisions and student resubmissions in one chronological thread. */
export default function ConversationTimeline({ events }: { events: ReviewEvent[] }) {
  return (
    <ol className="flex flex-col gap-3">
      {events.map((e) => {
        // `kindMeta` is exhaustive over `ReviewEventKind`, so a missing key can
        // only mean a value the server added since. Falling back to the raw
        // kind keeps the entry visible; throwing would blank the whole thread
        // for one unknown row.
        const { label, tone } = kindMeta[e.kind] ?? {
          label: String(e.kind),
          tone: "neutral" as Tone,
        }
        return (
          <li key={e.id} className={`flex gap-2.5 ${e.by === "student" ? "flex-row-reverse" : ""}`}>
            <Avatar initials={initialsOf(e.author)} size={32} />
            <div className={`flex min-w-0 max-w-[85%] flex-col gap-1.5 rounded-[12px] border p-3 ${e.by === "student" ? "border-line bg-white" : "border-line bg-brand-tint"}`}>
              <div className="flex flex-wrap items-center gap-2">
                <Badge tone={tone}>{label}</Badge>
                <Badge>{e.version}</Badge>
              </div>
              {e.note && <p className="text-[13px] leading-[1.45] text-ink">{e.note}</p>}
              <p className="text-[11px] text-muted">{e.author} · {e.by === "teacher" ? "Giảng viên" : "Sinh viên"} · {e.createdAt}</p>
            </div>
          </li>
        )
      })}
    </ol>
  )
}
