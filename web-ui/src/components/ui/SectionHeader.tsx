import { Link } from "react-router-dom"

interface Props {
  title: string
  description?: string
  meta?: string
  linkTo?: string
  linkLabel?: string
}

export default function SectionHeader({ title, description, meta, linkTo, linkLabel = "Xem tất cả" }: Props) {
  return (
    <div className="flex w-full flex-col gap-1.5 leading-[1.45]">
      <div className="flex items-center justify-between gap-3">
        <h2 className="min-w-0 text-[18px] font-semibold text-ink">{title}</h2>
        {meta && <span className="shrink-0 text-[12px] text-muted">{meta}</span>}
        {linkTo && (
          <Link to={linkTo} className="shrink-0 text-[12px] font-semibold text-brand">
            {linkLabel}
          </Link>
        )}
      </div>
      {description && <p className="text-[14px] text-muted">{description}</p>}
    </div>
  )
}
