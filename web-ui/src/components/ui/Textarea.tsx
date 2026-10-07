import type { TextareaHTMLAttributes } from "react"

interface Props extends TextareaHTMLAttributes<HTMLTextAreaElement> {
  label?: string
}

export default function Textarea({ label, id, className = "", ...rest }: Props) {
  return (
    <label htmlFor={id} className={`flex w-full flex-col gap-1.5 ${className}`}>
      {label && <span className="text-[13px] font-semibold text-ink">{label}</span>}
      <textarea
        id={id}
        rows={3}
        className="w-full resize-none rounded-[8px] border border-line bg-white p-3 text-[13px] leading-[1.45] text-ink outline-none placeholder:text-muted focus:border-brand"
        {...rest}
      />
    </label>
  )
}
