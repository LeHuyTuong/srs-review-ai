import { NavLink } from "react-router-dom"
import { useRole } from "@/app/auth"
import { navItemsByRole } from "@/components/layout/navItems"

export default function BottomNavigation({ pathname }: { pathname: string }) {
  const role = useRole() ?? "teacher"
  return (
    <nav aria-label="Điều hướng chính" className="safe-bottom w-full shrink-0 border-t border-line bg-white lg:hidden">
      <ul className="flex gap-0.5 px-2.5 pt-2 pb-2.5">
        {navItemsByRole[role].map(({ to, label, icon: Icon, extra }) => {
          const alsoActive = extra.some((p) => pathname.startsWith(p))
          return (
            <li key={to} className="min-w-0 flex-1">
              <NavLink
                to={to}
                className={({ isActive }) =>
                  `flex flex-col items-center gap-[5px] rounded-[8px] px-px py-2 text-[10px] leading-[1.45] font-semibold transition-colors ${isActive || alsoActive ? "bg-brand-soft text-brand" : "text-muted"}`
                }
              >
                <Icon size={20} strokeWidth={1.75} />
                <span className="truncate">{label}</span>
              </NavLink>
            </li>
          )
        })}
      </ul>
    </nav>
  )
}
