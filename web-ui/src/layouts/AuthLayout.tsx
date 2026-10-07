import { Navigate, Outlet } from "react-router-dom"
import { isAuthenticated } from "@/app/auth"

export default function AuthLayout() {
  if (isAuthenticated()) return <Navigate to="/dashboard" replace />
  return (
    <div className="mobile-app bg-white">
      <main className="mobile-content safe-top safe-bottom">
        <Outlet />
      </main>
    </div>
  )
}
