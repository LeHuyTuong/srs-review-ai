import type { InputHTMLAttributes, ReactNode } from "react"

interface Props extends InputHTMLAttributes<HTMLInputElement> {
  icon?: ReactNode
  label?: string
}

export default function Input({ icon, label, id, className = "", ...rest }: Props) {
  return (
    <label htmlFor={id} className={`flex w-full flex-col gap-1.5 ${className}`}>
      {label && <span className="text-[13px] font-semibold text-ink">{label}</span>}
      <span className="flex min-h-12 w-full items-center gap-2.5 rounded-[8px] border border-line bg-white p-3 focus-within:border-brand">
        {icon && <span className="shrink-0 text-muted">{icon}</span>}
        <input id={id} className="min-w-0 flex-1 bg-transparent text-[13px] leading-[1.45] text-ink outline-none placeholder:text-muted" {...rest} />
      </span>
    </label>
  )
}
