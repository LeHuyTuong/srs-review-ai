import { Bell, FileCheck2, Folder, LayoutDashboard, UserRound } from "lucide-react"
import type { Role } from "@/types"

const home = { to: "/dashboard", label: "Tổng quan", icon: LayoutDashboard, extra: [] as string[] }
const notifications = { to: "/notifications", label: "Thông báo", icon: Bell, extra: [] as string[] }
const profile = { to: "/profile", label: "Tài khoản", icon: UserRound, extra: [] as string[] }

export const navItemsByRole = {
  teacher: [
    home,
    { to: "/projects", label: "Project", icon: Folder, extra: ["/classes"] },
    { to: "/reviews", label: "Review", icon: FileCheck2, extra: [] as string[] },
    notifications,
    profile,
  ],
  // A student has no classes or projects to browse: one group, its reviews, and the conversation.
  student: [home, { to: "/reviews", label: "Phản hồi", icon: FileCheck2, extra: [] as string[] }, notifications, profile],
} satisfies Record<Role, (typeof home)[]>
