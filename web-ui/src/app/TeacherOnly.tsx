import type { ReactNode } from "react"
import { Navigate } from "react-router-dom"
import { useRole } from "@/app/auth"

/** Classes and projects are the teacher's view; a student has one group and no class list. */
export default function TeacherOnly({ children }: { children: ReactNode }) {
  return useRole() === "student" ? <Navigate to="/dashboard" replace /> : <>{children}</>
}
