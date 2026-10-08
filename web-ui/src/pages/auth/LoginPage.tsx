import { Files, LockKeyhole, User } from "lucide-react"
import { useState, type FormEvent } from "react"
import { useLocation, useNavigate } from "react-router-dom"
import { signIn, signUp } from "@/app/auth"
import Badge from "@/components/ui/Badge"
import Button from "@/components/ui/Button"
import Input from "@/components/ui/Input"
import Notice from "@/components/ui/Notice"
import { ApiError } from "@/data/api"
import type { Role } from "@/types"

const roles: Record<Role, { label: string; eyebrow: string; blurb: string }> = {
  teacher: {
    label: "Giảng viên",
    eyebrow: "DÀNH CHO GIẢNG VIÊN",
    blurb: "Theo dõi lớp, project và review tài liệu của sinh viên.",
  },
  student: {
    label: "Sinh viên",
    eyebrow: "DÀNH CHO SINH VIÊN",
    blurb: "Nộp tài liệu, xem nhận xét của giảng viên và nộp lại bản sửa.",
  },
}

export default function LoginPage() {
  const navigate = useNavigate()
  const location = useLocation()
  const [role, setRole] = useState<Role>("teacher")
  const [username, setUsername] = useState("")
  const [password, setPassword] = useState("")
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState("")

  // ADR-0020: this is a REAL login. The account must exist on the server, so
  // the flow registers then signs in — there is no demo account to pre-fill and
  // no role flag to toggle the client's way into a teacher view.
  const handleSubmit = async (event: FormEvent) => {
    event.preventDefault()
    setError("")
    if (!username.trim() || !password) {
      setError("Vui lòng nhập tên đăng nhập và mật khẩu.")
      return
    }
    setBusy(true)
    try {
      try {
        await signIn(username.trim(), password)
      } catch (err) {
        // Only an unknown account is worth a registration attempt. A wrong
        // password on an EXISTING account must not silently create a second
        // account or mask the real error.
        if (err instanceof ApiError && err.status === 401) {
          await signUp(username.trim(), password, role)
        } else {
          throw err
        }
      }
      const from = (location.state as { from?: string } | null)?.from
      navigate(from && from !== "/login" ? from : "/dashboard", { replace: true })
    } catch (err) {
      setError(err instanceof ApiError ? err.detail : String(err))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="mx-auto flex min-h-full w-full max-w-[480px] flex-col justify-center gap-8 px-5 py-10">
      <div className="flex items-center gap-2.5">
        <Files size={28} strokeWidth={1.75} className="text-brand" />
        <span className="text-[19px] font-semibold text-ink">Project Review</span>
        <Badge tone="olive">AI</Badge>
      </div>
      <div role="tablist" aria-label="Vai trò" className="grid grid-cols-2 gap-1 rounded-[8px] bg-subtle p-1">
        {(Object.keys(roles) as Role[]).map((r) => (
          <button
            key={r}
            role="tab"
            type="button"
            aria-selected={r === role}
            onClick={() => setRole(r)}
            className={`rounded-[6px] px-3 py-2 text-[13px] font-medium transition ${r === role ? "bg-white text-brand shadow-[0_1px_2px_rgba(36,51,45,0.08)]" : "text-muted"}`}
          >
            {roles[r].label}
          </button>
        ))}
      </div>
      <div className="flex flex-col gap-2">
        <p className="text-[10px] font-semibold tracking-wide text-brand">{roles[role].eyebrow}</p>
        <h1 className="text-[26px] leading-[1.18] font-semibold text-ink">Đăng nhập</h1>
        <p className="text-[14px] leading-[1.45] text-muted">{roles[role].blurb}</p>
      </div>
      <form onSubmit={handleSubmit} className="flex flex-col gap-4">
        <Input
          id="username"
          type="text"
          label="Tên đăng nhập"
          autoComplete="username"
          value={username}
          onChange={(e) => setUsername(e.target.value)}
          icon={<User size={18} strokeWidth={1.75} />}
        />
        <Input
          id="password"
          type="password"
          label="Mật khẩu"
          autoComplete="current-password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          icon={<LockKeyhole size={18} strokeWidth={1.75} />}
        />
        {error && <p className="text-[12px] text-danger">{error}</p>}
        <Button type="submit" disabled={busy}>
          {busy ? "Đang đăng nhập…" : "Đăng nhập"}
        </Button>
      </form>
      <Notice>
        Tài khoản chưa tồn tại sẽ được tạo với vai trò đang chọn. AI Review chỉ hỗ trợ — quyết định phê duyệt thuộc về giảng viên.
      </Notice>
    </div>
  )
}
