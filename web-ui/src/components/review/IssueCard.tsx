import Badge from "@/components/ui/Badge"
import type { AIIssue, IssueSeverity, Tone } from "@/types"

const severity: Record<IssueSeverity, { label: string; tone: Tone }> = {
  critical: { label: "Critical", tone: "danger" },
  major: { label: "Major", tone: "rust" },
  minor: { label: "Minor", tone: "amber" },
  suggestion: { label: "Gợi ý", tone: "olive" },
}

export default function IssueCard({ issue }: { issue: AIIssue }) {
  const meta = severity[issue.severity]
  return (
    <div className="flex flex-col gap-2 rounded-[8px] border border-line bg-white p-3">
      <div className="flex flex-wrap gap-2">
        <Badge tone={meta.tone}>{meta.label}</Badge>
        <Badge>{issue.category}</Badge>
      </div>
      <p className="text-[13px] leading-[1.45] text-ink">{issue.message}</p>
      <button type="button" className="self-start text-[12px] font-semibold text-brand">
        {issue.action}
      </button>
    </div>
  )
}
