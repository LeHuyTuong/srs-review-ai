import { Files } from "lucide-react"
import { Link, NavLink } from "react-router-dom"
import Badge from "@/components/ui/Badge"
import { useRole } from "@/app/auth"
import { navItemsByRole } from "@/components/layout/navItems"

export default function SideNavigation({ pathname }: { pathname: string }) {
  const role = useRole() ?? "teacher"
  return (
    <aside className="hidden w-60 shrink-0 flex-col border-r border-line bg-white lg:flex">
      <Link to="/dashboard" className="flex h-16 items-center gap-2.5 border-b border-line px-5">
        <Files size={24} strokeWidth={1.75} className="shrink-0 text-brand" />
        <span className="truncate text-[17px] font-semibold text-ink">Project Review</span>
        <Badge tone="olive">AI</Badge>
      </Link>
      <nav aria-label="Điều hướng chính" className="flex flex-col gap-1 p-3">
        {navItemsByRole[role].map(({ to, label, icon: Icon, extra }) => {
          const alsoActive = extra.some((p) => pathname.startsWith(p))
          return (
            <NavLink
              key={to}
              to={to}
              className={({ isActive }) =>
                `flex items-center gap-3 rounded-[8px] px-3 py-2.5 text-[14px] font-semibold transition-colors ${isActive || alsoActive ? "bg-brand-soft text-brand" : "text-muted hover:bg-canvas"}`
              }
            >
              <Icon size={20} strokeWidth={1.75} />
              <span className="truncate">{label}</span>
            </NavLink>
          )
        })}
      </nav>
    </aside>
  )
}
