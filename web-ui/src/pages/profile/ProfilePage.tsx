import { LogOut } from "lucide-react"
import { useNavigate } from "react-router-dom"
import { signOut } from "@/app/auth"
import Avatar from "@/components/ui/Avatar"
import Badge from "@/components/ui/Badge"
import Button from "@/components/ui/Button"
import Card from "@/components/ui/Card"
import MetaGrid from "@/components/ui/MetaGrid"
import PageHeading from "@/components/ui/PageHeading"
import { useRole } from "@/app/auth"
import { classes, currentStudent, currentUser } from "@/data/mockData"
import { actions } from "@/data/store"

export default function ProfilePage() {
  const navigate = useNavigate()
  const role = useRole() ?? "teacher"
  const me = role === "student" ? currentStudent : currentUser
  const handleSignOut = () => {
    signOut()
    navigate("/login", { replace: true })
  }

  return (
    <>
      <PageHeading eyebrow="TÀI KHOẢN" title="Tài khoản" />
      <Card>
        <div className="flex items-center gap-3">
          <Avatar initials={me.initials} size={52} />
          <div className="min-w-0 flex-1 leading-[1.45]">
            <p className="text-[17px] font-semibold text-ink">{me.name}</p>
            <p className="truncate text-[12px] text-muted">{me.email}</p>
          </div>
        </div>
        <div className="flex flex-wrap gap-2">
          <Badge tone="brand">{me.role}</Badge>
          <Badge>{me.semester}</Badge>
        </div>
        <MetaGrid items={role === "student" ? [{ label: "Nhóm", value: currentStudent.group }, { label: "Giảng viên", value: currentUser.name }] : [{ label: "Lớp phụ trách", value: `${classes.length} lớp` }, { label: "Sinh viên", value: "81 sinh viên" }]} />
      </Card>
      <Button variant="secondary" onClick={() => actions.reset()}>Đặt lại dữ liệu demo</Button>
      <Button variant="danger" onClick={handleSignOut} icon={<LogOut size={18} strokeWidth={1.75} />}>Đăng xuất</Button>
    </>
  )
}
