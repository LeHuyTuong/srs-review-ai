import { useRole } from "@/app/auth"
import StudentDashboard from "./StudentDashboard"
import TeacherDashboard from "./TeacherDashboard"

export default function DashboardPage() {
  return useRole() === "student" ? <StudentDashboard /> : <TeacherDashboard />
}
