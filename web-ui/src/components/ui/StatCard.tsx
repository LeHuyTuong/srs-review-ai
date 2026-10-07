export default function StatCard({ value, label }: { value: string | number; label: string }) {
  return (
    <div className="flex min-w-0 flex-col gap-2 rounded-[12px] border border-line bg-white p-4">
      <span className="text-[28px] leading-none font-semibold text-brand">{value}</span>
      <span className="text-[12px] leading-[1.45] text-muted">{label}</span>
    </div>
  )
}
