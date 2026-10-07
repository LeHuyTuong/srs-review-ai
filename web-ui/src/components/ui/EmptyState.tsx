export default function EmptyState({ title, description }: { title: string; description?: string }) {
  return (
    <div className="flex w-full flex-col items-center gap-1 rounded-[12px] border border-dashed border-line bg-white px-4 py-8 text-center">
      <p className="text-[14px] font-semibold text-ink">{title}</p>
      {description && <p className="text-[12px] text-muted">{description}</p>}
    </div>
  )
}
