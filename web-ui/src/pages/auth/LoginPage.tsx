import { Files, LockKeyhole, Mail } from "lucide-react"
import { useState, type FormEvent } from "react"
import { useLocation, useNavigate } from "react-router-dom"
import { signIn } from "@/app/auth"
import Badge from "@/components/ui/Badge"
import Button from "@/components/ui/Button"
import Input from "@/components/ui/Input"
import Notice from "@/components/ui/Notice"
import { currentStudent, currentUser } from "@/data/mockData"
import type { Role } from "@/types"

const accounts: Record<Role, { label: string; email: string; eyebrow: string; blurb: string }> = {
  teacher: { label: "Giảng viên", email: currentUser.email, eyebrow: "DÀNH CHO GIẢNG VIÊN", blurb: "Theo dõi lớp, project và review tài liệu của sinh viên." },
  student: { label: "Sinh viên", email: currentStudent.email, eyebrow: "DÀNH CHO SINH VIÊN", blurb: "Nộp tài liệu, xem nhận xét của giảng viên và nộp lại bản sửa." },
}

export default function LoginPage() {
  const navigate = useNavigate()
  const location = useLocation()
  const [role, setRole] = useState<Role>("teacher")
  const [email, setEmail] = useState(accounts.teacher.email)
  const [password, setPassword] = useState("password")
  const [error, setError] = useState("")

  const pick = (next: Role) => {
    setRole(next)
    setEmail(accounts[next].email)
  }

  const handleSubmit = (event: FormEvent) => {
    event.preventDefault()
    if (!email || !password) {
      setError("Vui lòng nhập email và mật khẩu.")
      return
    }
    signIn(role)
    const from = (location.state as { from?: string } | null)?.from
    navigate(from && from !== "/login" ? from : "/dashboard", { replace: true })
  }

  return (
    <div className="mx-auto flex min-h-full w-full max-w-[480px] flex-col justify-center gap-8 px-5 py-10">
      <div className="flex items-center gap-2.5">
        <Files size={28} strokeWidth={1.75} className="text-brand" />
        <span className="text-[19px] font-semibold text-ink">Project Review</span>
        <Badge tone="olive">AI</Badge>
      </div>
      <div role="tablist" aria-label="Vai trò" className="grid grid-cols-2 gap-1 rounded-[8px] bg-subtle p-1">
        {(Object.keys(accounts) as Role[]).map((r) => (
          <button
            key={r}
            role="tab"
            type="button"
            aria-selected={r === role}
            onClick={() => pick(r)}
            className={`rounded-[6px] px-3 py-2 text-[13px] font-medium transition ${r === role ? "bg-white text-brand shadow-[0_1px_2px_rgba(36,51,45,0.08)]" : "text-muted"}`}
          >
            {accounts[r].label}
          </button>
        ))}
      </div>
      <div className="flex flex-col gap-2">
        <p className="text-[10px] font-semibold tracking-wide text-brand">{accounts[role].eyebrow}</p>
        <h1 className="text-[26px] leading-[1.18] font-semibold text-ink">Đăng nhập</h1>
        <p className="text-[14px] leading-[1.45] text-muted">{accounts[role].blurb}</p>
      </div>
      <form onSubmit={handleSubmit} className="flex flex-col gap-4">
        <Input id="email" type="email" label="Email" autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} icon={<Mail size={18} strokeWidth={1.75} />} />
        <Input id="password" type="password" label="Mật khẩu" autoComplete="current-password" value={password} onChange={(e) => setPassword(e.target.value)} icon={<LockKeyhole size={18} strokeWidth={1.75} />} />
        {error && <p className="text-[12px] text-danger">{error}</p>}
        <Button type="submit">Đăng nhập</Button>
      </form>
      <Notice>Tài khoản demo đã được điền sẵn. AI Review chỉ hỗ trợ — quyết định phê duyệt thuộc về giảng viên.</Notice>
    </div>
  )
}
