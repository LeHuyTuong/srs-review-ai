import type { ReactNode } from "react"
import { Navigate } from "react-router-dom"
import { useSession } from "@/app/auth"

/** Classes and projects are the teacher's view; a student has one group and no class list.
 *
 * `null` (server said signed out) redirects, and `undefined` (not asked yet)
 * also redirects — but that branch is unreachable in practice because
 * `MobileAppLayout` renders a loading surface until the session resolves, so a
 * child never mounts with an unknown role. Keeping the check explicit means a
 * future refactor that mounts this elsewhere fails closed rather than open. */
export default function TeacherOnly({ children }: { children: ReactNode }) {
  const user = useSession()
  return user?.role === "student" ? <Navigate to="/dashboard" replace /> : <>{children}</>
}
