import { useEffect, useRef } from "react"
import { Navigate, Outlet, useLocation } from "react-router-dom"
import BottomNavigation from "@/components/layout/BottomNavigation"
import MobileHeader from "@/components/layout/MobileHeader"
import SideNavigation from "@/components/layout/SideNavigation"
import { isAuthenticated } from "@/app/auth"

export default function MobileAppLayout() {
  const location = useLocation()
  const contentRef = useRef<HTMLElement>(null)

  // The document never scrolls, so reset the content pane on route change.
  useEffect(() => {
    contentRef.current?.scrollTo({ top: 0 })
  }, [location.pathname])

  if (!isAuthenticated()) {
    return <Navigate to="/login" replace state={{ from: location.pathname }} />
  }

  return (
    <div className="mobile-app lg:flex-row">
      <SideNavigation pathname={location.pathname} />
      <div className="flex min-h-0 min-w-0 flex-1 flex-col">
        <MobileHeader />
        <main ref={contentRef} className="mobile-content">
          <div className="mx-auto flex w-full max-w-[480px] flex-col gap-6 px-5 pt-5 pb-8 lg:max-w-[880px] lg:px-8 lg:pt-8">
            <Outlet />
          </div>
        </main>
        <BottomNavigation pathname={location.pathname} />
      </div>
    </div>
  )
}
