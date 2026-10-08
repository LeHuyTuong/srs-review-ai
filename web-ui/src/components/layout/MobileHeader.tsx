import { Bell, Files } from "lucide-react"
import { Link } from "react-router-dom"
import Avatar from "@/components/ui/Avatar"
import Badge from "@/components/ui/Badge"
import { useSession } from "@/app/auth"
import { useStore } from "@/data/store"

export default function MobileHeader() {
  // ADR-0020: the avatar and the role come from the SERVER session. Reading
  // them from mockData would show the same fictional person to every account.
  const user = useSession()
  const role = user?.role ?? "teacher"
  const { notifications } = useStore()
  const initials = (user?.username ?? "?").slice(0, 2).toUpperCase()
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
          <Avatar initials={initials} />
        </Link>
      </div>
    </header>
  )
}
