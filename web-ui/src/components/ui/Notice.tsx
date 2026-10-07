import { Info } from "lucide-react"
import type { ReactNode } from "react"

export default function Notice({ children }: { children: ReactNode }) {
  return (
    <div className="flex w-full gap-2.5 rounded-[8px] bg-subtle p-3 text-[12px] leading-[1.45] text-muted">
      <Info size={16} strokeWidth={1.75} className="mt-px shrink-0 text-brand" />
      <p className="min-w-0">{children}</p>
    </div>
  )
}
