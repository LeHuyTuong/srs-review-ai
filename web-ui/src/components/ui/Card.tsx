import type { ReactNode } from "react"

interface Props {
  children: ReactNode
  className?: string
  tinted?: boolean
}

export default function Card({ children, className = "", tinted }: Props) {
  return (
    <div className={`flex w-full min-w-0 flex-col gap-3 rounded-[12px] border border-line p-4 ${tinted ? "bg-brand-tint" : "bg-white"} ${className}`}>
      {children}
    </div>
  )
}
