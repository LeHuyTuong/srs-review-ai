interface Props {
  tabs: string[]
  active: string
  onChange: (tab: string) => void
}

export default function SegmentedTabs({ tabs, active, onChange }: Props) {
  return (
    <div className="-mx-5 overflow-x-auto px-5 [scrollbar-width:none]">
      <div role="tablist" className="flex w-max gap-1 rounded-[8px] bg-subtle p-1">
        {tabs.map((tab) => (
          <button
            key={tab}
            role="tab"
            type="button"
            aria-selected={tab === active}
            onClick={() => onChange(tab)}
            className={`whitespace-nowrap rounded-[6px] px-3 py-2 text-[13px] font-medium transition ${tab === active ? "bg-white text-brand shadow-[0_1px_2px_rgba(36,51,45,0.08)]" : "text-muted"}`}
          >
            {tab}
          </button>
        ))}
      </div>
    </div>
  )
}
