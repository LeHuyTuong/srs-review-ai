export default function Avatar({ initials, size = 36 }: { initials: string; size?: number }) {
  return (
    <span className="flex shrink-0 items-center justify-center rounded-full bg-brand-soft text-[12px] font-semibold text-brand" style={{ width: size, height: size }}>
      {initials}
    </span>
  )
}
