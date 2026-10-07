import { Bell, Files } from "lucide-react"
import { Link } from "react-router-dom"
import Avatar from "@/components/ui/Avatar"
import Badge from "@/components/ui/Badge"
import { useRole } from "@/app/auth"
import { currentStudent, currentUser } from "@/data/mockData"
import { useStore } from "@/data/store"

export default function MobileHeader() {
  const role = useRole() ?? "teacher"
  const { notifications } = useStore()
  const me = role === "student" ? currentStudent : currentUser
  const hasUnread = notifications.some((n) => n.audience === role && n.unread)
  return (
    <header className="mobile-header w-full border-b border-line">
      <div className="mobile-header-inner gap-2.5 px-5">
        <Link to="/dashboard" className="flex min-w-0 items-center gap-2.5 lg:hidden">
          <Files size={24} strokeWidth={1.75} className="shrink-0 text-brand" />
          <span className="truncate text-[17px] font-semibold text-ink">Project Review</span>
          <Badge tone="olive">AI</Badge>
        </Link>
        <div className="flex-1" />
        <Link to="/notifications" aria-label="Thông báo" className="relative flex size-10 items-center justify-center text-ink">
          <Bell size={20} strokeWidth={1.75} />
          {hasUnread && <span className="absolute top-2 right-2.5 size-2 rounded-full border-2 border-white bg-rust" />}
        </Link>
        <Link to="/profile" aria-label="Tài khoản">
          <Avatar initials={me.initials} />
        </Link>
      </div>
    </header>
  )
}
