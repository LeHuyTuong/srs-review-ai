import { useEffect, useRef } from "react"
import { Navigate, Outlet, useLocation } from "react-router-dom"
import BottomNavigation from "@/components/layout/BottomNavigation"
import MobileHeader from "@/components/layout/MobileHeader"
import SideNavigation from "@/components/layout/SideNavigation"
import { loadSession, useSession } from "@/app/auth"
import { actions } from "@/data/store"

export default function MobileAppLayout() {
  const location = useLocation()
  const contentRef = useRef<HTMLElement>(null)
  const user = useSession()

  // The document never scrolls, so reset the content pane on route change.
  useEffect(() => {
    contentRef.current?.scrollTo({ top: 0 })
  }, [location.pathname])

  // ADR-0020: "am I signed in" is a question for the SERVER now. `undefined`
  // means the question has not been answered yet, and answering it by looking
  // at a local flag is exactly the mock behaviour this replaced — so the first
  // paint waits instead of deciding. Without this the app redirects to /login on
  // every refresh (the state starts empty) and the user is thrown out of a
  // session the server still considers live.
  useEffect(() => {
    if (user === undefined) {
      void loadSession().catch(() => {
        // A down proxy leaves the session unresolved; the branch below then
        // keeps showing the spinner rather than lying in either direction.
      })
    }
  }, [user])

  // The list is identity-scoped server-side, so it is fetched once the identity
  // is known — not per page, and never with a scope the client chooses.
  useEffect(() => {
    if (user) void actions.loadList().catch(() => undefined)
  }, [user])

  if (user === undefined) {
    return (
      <div className="flex min-h-screen items-center justify-center text-[13px] text-muted">Đang tải…</div>
    )
  }

  if (user === null) {
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
