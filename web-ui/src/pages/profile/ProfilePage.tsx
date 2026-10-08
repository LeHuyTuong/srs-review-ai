import { LogOut } from "lucide-react"
import { useNavigate } from "react-router-dom"
import { signOut, useSession } from "@/app/auth"
import Avatar from "@/components/ui/Avatar"
import Badge from "@/components/ui/Badge"
import Button from "@/components/ui/Button"
import Card from "@/components/ui/Card"
import MetaGrid from "@/components/ui/MetaGrid"
import PageHeading from "@/components/ui/PageHeading"

export default function ProfilePage() {
  const navigate = useNavigate()
  const user = useSession()

  // ADR-0020: the identity comes from the SERVER session, not from mockData.
  // A page that showed `currentUser.name` would greet every teacher as the same
  // fictional person, and would keep doing it after the server said otherwise.
  const name = user?.username ?? "—"
  const isStudent = user?.role === "student"

  const handleSignOut = async () => {
    // Awaited: the cookie is cleared by the SERVER's logout, and navigating
    // before that lands on a login page the browser still arrives at signed in.
    await signOut()
    navigate("/login", { replace: true })
  }

  return (
    <>
      <PageHeading eyebrow="TÀI KHOẢN" title="Tài khoản" />
      <Card>
        <div className="flex items-center gap-3">
          <Avatar initials={name.slice(0, 2).toUpperCase()} size={52} />
          <div className="min-w-0 flex-1 leading-[1.45]">
            <p className="text-[17px] font-semibold text-ink">{name}</p>
            <p className="truncate text-[12px] text-muted">
              {isStudent ? "Tài khoản sinh viên" : "Tài khoản giảng viên"}
            </p>
          </div>
        </div>
        <div className="flex flex-wrap gap-2">
          <Badge tone="brand">{isStudent ? "Sinh viên" : "Giảng viên"}</Badge>
        </div>
        <MetaGrid
          items={
            isStudent
              ? [
                  { label: "Nhóm", value: user?.group ?? "Chưa gắn nhóm" },
                  { label: "Tên đăng nhập", value: name },
                ]
              : [
                  { label: "Lớp phụ trách", value: user?.classId ?? "Chưa gắn lớp" },
                  { label: "Tên đăng nhập", value: name },
                ]
          }
        />
      </Card>
      <Button variant="danger" onClick={handleSignOut} icon={<LogOut size={18} strokeWidth={1.75} />}>
        Đăng xuất
      </Button>
    </>
  )
}
