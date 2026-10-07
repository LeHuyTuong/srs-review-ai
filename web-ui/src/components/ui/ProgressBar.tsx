export default function ProgressBar({ value, label }: { value: number; label?: string }) {
  return (
    <div className="flex w-full flex-col gap-1.5">
      {label && (
        <div className="flex justify-between text-[12px] leading-[1.45]">
          <span className="text-muted">{label}</span>
          <span className="font-semibold text-ink">{value}%</span>
        </div>
      )}
      <div className="h-1.5 w-full overflow-hidden rounded-full bg-brand-soft" role="progressbar" aria-valuenow={value} aria-valuemin={0} aria-valuemax={100}>
        <div className="h-full rounded-full bg-brand" style={{ width: `${value}%` }} />
      </div>
    </div>
  )
}
