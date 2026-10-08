/**
 * Session state for web-ui — a real server session, not a localStorage flag.
 *
 * What changed and why it is not cosmetic (ADR-0020)
 * ==================================================
 * The mock stored the ROLE in `localStorage` under `project-review:session`
 * (with `"1"` reading as teacher, for a teacher-only build that predates this
 * file). That value was the entire authorisation story: editing it in devtools
 * made anyone a teacher. Here the role comes from `/auth/me`, the session is an
 * `HttpOnly` cookie JavaScript cannot forge, and the server is the thing that
 * decides what a teacher may do.
 *
 * The store keeps ONE piece of state — the resolved user, or null while unknown
 * — because that is exactly what the UI needs to render. `undefined` and `null`
 * are deliberately different: `undefined` is "we have not asked yet" (show a
 * spinner) and `null` is "we asked, and nobody is signed in" (show the login
 * page). Collapsing them makes the login page flash on every refresh.
 */

import { useSyncExternalStore } from "react"
import { ApiError, apiFetch } from "@/data/api"
import type { Role } from "@/types"

export interface SessionUser {
  id: string
  username: string
  role: Role
  /** The teacher's class, or the student's group. `null` until an account is
   *  attached to one — which is why it is nullable rather than absent: "not in
   *  a class yet" is a real state the UI must render, not a missing field. */
  classId: string | null
  group: string | null
}

/** `undefined` = not asked yet; `null` = asked, signed out; a user = signed in. */
type SessionState = SessionUser | null | undefined

let state: SessionState = undefined
let inflight: Promise<SessionUser | null> | null = null

const listeners = new Set<() => void>()
const emit = () => listeners.forEach((l) => l())

const setState = (next: SessionState) => {
  state = next
  emit()
}

export const getRole = (): Role | null => state?.role ?? null
export const getUser = (): SessionUser | null => state ?? null
export const isAuthenticated = (): boolean => state != null
export const isResolved = (): boolean => state !== undefined

/**
 * Ask the server who we are, once.
 *
 * Deduplicated through `inflight`: boot calls this, and so does the login page's
 * guard, and two concurrent `/auth/me` requests on first paint are two round
 * trips for one fact. A 401 is NOT an error here — it is the answer "signed
 * out", which is why it resolves to null instead of throwing.
 */
export async function loadSession(): Promise<SessionUser | null> {
  if (inflight) return inflight
  inflight = (async () => {
    try {
      const user = await apiFetch<SessionUser>("/auth/me")
      setState(user)
      return user
    } catch (error) {
      if (error instanceof ApiError && error.isUnauthorized) {
        setState(null)
        return null
      }
      // A down proxy is not "signed out" — leave the state unresolved so the UI
      // reports a connection problem instead of redirecting to a login form
      // that would fail the same way.
      throw error
    } finally {
      inflight = null
    }
  })()
  return inflight
}

export async function signIn(username: string, password: string): Promise<SessionUser> {
  const user = await apiFetch<SessionUser>("/auth/login", {
    method: "POST",
    body: { username, password },
  })
  setState(user)
  return user
}

export async function signUp(username: string, password: string, role: Role): Promise<SessionUser> {
  // Registration on this server does NOT log in (ADR-0020: two separate acts),
  // so this deliberately follows with a sign-in — the caller asked to "create
  // and use an account", and doing only half would strand them on a login page
  // they just came from.
  await apiFetch("/auth/register", { method: "POST", body: { username, password, role } })
  return signIn(username, password)
}

export async function signOut(): Promise<void> {
  try {
    await apiFetch<{ signedOut: boolean }>("/auth/logout", { method: "POST" })
  } catch {
    // A failed logout must still clear the client, or the UI shows a signed-in
    // shell over a session the server may already have dropped.
  }
  setState(null)
}

/** Test seam and "reset for demo" hook. */
export const resetSession = () => setState(undefined)

export const useSession = (): SessionState =>
  useSyncExternalStore(
    (cb) => {
      listeners.add(cb)
      return () => listeners.delete(cb)
    },
    () => state,
  )

export const useRole = (): Role | null => useSession()?.role ?? null
