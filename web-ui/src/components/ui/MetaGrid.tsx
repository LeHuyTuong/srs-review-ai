export default function MetaGrid({ items }: { items: { label: string; value: string }[] }) {
  return (
    <dl className="grid grid-cols-2 gap-3 text-[12px] leading-[1.45]">
      {items.map((item) => (
        <div key={item.label} className="min-w-0">
          <dt className="text-muted">{item.label}</dt>
          <dd className="font-semibold text-ink">{item.value}</dd>
        </div>
      ))}
    </dl>
  )
}
