import type { ReactNode } from "react"

interface Props {
  eyebrow?: string
  title: string
  description?: string
  aside?: ReactNode
}

export default function PageHeading({ eyebrow, title, description, aside }: Props) {
  return (
    <div className="flex w-full flex-col gap-2">
      {eyebrow && <p className="text-[10px] leading-[1.45] font-semibold tracking-wide text-brand">{eyebrow}</p>}
      <div className="flex items-start justify-between gap-3">
        <h1 className="min-w-0 text-[26px] leading-[1.18] font-semibold text-ink">{title}</h1>
        {aside}
      </div>
      {description && <p className="text-[14px] leading-[1.45] text-muted">{description}</p>}
    </div>
  )
}
