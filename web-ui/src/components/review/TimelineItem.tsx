import { toneClasses } from "@/components/ui/Badge"
import type { ReviewActivity } from "@/types"

export default function TimelineItem({ activity, last }: { activity: ReviewActivity; last?: boolean }) {
  return (
    <li className="relative flex gap-3 pb-5 last:pb-0">
      {!last && <span className="absolute top-4 bottom-0 left-[7px] w-px bg-line" />}
      <span className={`relative mt-1 size-[15px] shrink-0 rounded-full border-[3px] border-white ring-1 ring-line ${toneClasses[activity.tone]} !bg-current`} />
      <div className="min-w-0 flex-1 leading-[1.45]">
        <p className="text-[14px] font-semibold text-ink">{activity.title}</p>
        <p className="text-[12px] text-muted">{activity.time}</p>
        <p className="text-[12px] text-muted">{activity.meta}</p>
        {activity.quote && <p className="mt-2 rounded-[8px] bg-subtle p-2.5 text-[13px] text-ink italic">{activity.quote}</p>}
      </div>
    </li>
  )
}
