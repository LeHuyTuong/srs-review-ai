import { useSyncExternalStore } from "react"
import type { Role } from "@/types"

const KEY = "project-review:session"

// Mock session: the stored value is the role. "1" is what the teacher-only
// version of this prototype wrote, so an old session still reads as a teacher.
const read = (): Role | null => {
  const v = localStorage.getItem(KEY)
  if (v === "student") return "student"
  if (v === "teacher" || v === "1") return "teacher"
  return null
}

const listeners = new Set<() => void>()
const emit = () => listeners.forEach((l) => l())

export const getRole = read
export const isAuthenticated = () => read() !== null
export const signIn = (role: Role) => {
  localStorage.setItem(KEY, role)
  emit()
}
export const signOut = () => {
  localStorage.removeItem(KEY)
  emit()
}

export const useRole = (): Role | null =>
  useSyncExternalStore(
    (cb) => {
      listeners.add(cb)
      return () => listeners.delete(cb)
    },
    read,
  )
