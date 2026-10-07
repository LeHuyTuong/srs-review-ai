import Avatar from "@/components/ui/Avatar"
import type { StudentMember } from "@/types"

export default function MemberRow({ member }: { member: StudentMember }) {
  return (
    <li className="flex items-center gap-3 py-2.5">
      <Avatar initials={member.initials} />
      <div className="min-w-0 leading-[1.45]">
        <p className="text-[14px] font-semibold text-ink">{member.name}</p>
        <p className="text-[12px] text-muted">{member.role}</p>
      </div>
    </li>
  )
}
