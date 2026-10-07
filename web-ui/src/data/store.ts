import { useSyncExternalStore } from "react"
import { currentStudent, currentUser, notifications as seedNotifications, reviewComments, reviewEvents, reviewRequests } from "@/data/mockData"
import type { Notification, ReviewComment, ReviewEvent, ReviewEventKind, ReviewRequest, Role } from "@/types"

// The one place the teacher and the student meet. Both roles read and write the
// same state, so what one does shows up on the other side after a role switch.
// Persisted to localStorage only because this is a mock with no server.

interface State {
  reviews: ReviewRequest[]
  comments: ReviewComment[]
  events: ReviewEvent[]
  notifications: Notification[]
}

const KEY = "project-review:state:v1"

const seed = (): State => ({
  reviews: reviewRequests,
  comments: reviewComments,
  events: reviewEvents,
  notifications: seedNotifications,
})

const load = (): State => {
  try {
    const raw = localStorage.getItem(KEY)
    if (raw) return JSON.parse(raw) as State
  } catch {
    // A corrupt blob must not brick the prototype: fall back to the seed.
  }
  return seed()
}

let state = load()
const listeners = new Set<() => void>()

const set = (next: State) => {
  state = next
  localStorage.setItem(KEY, JSON.stringify(state))
  listeners.forEach((l) => l())
}

export const useStore = (): State =>
  useSyncExternalStore(
    (cb) => {
      listeners.add(cb)
      return () => listeners.delete(cb)
    },
    () => state,
  )

const pad = (n: number) => String(n).padStart(2, "0")
const stamp = () => {
  const d = new Date()
  return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()} · ${pad(d.getHours())}:${pad(d.getMinutes())}`
}
let counter = 0
const uid = (p: string) => `${p}${Date.now().toString(36)}${counter++}`

const authorOf = (role: Role) => (role === "teacher" ? currentUser.name : currentStudent.name)

const notify = (audience: Role, title: string, meta: string, link: string): Notification => ({
  id: uid("n"),
  audience,
  title,
  meta,
  unread: true,
  link,
})

const bumpVersion = (v: string) => `v${(parseInt(v.replace(/\D/g, ""), 10) || 1) + 1}`

export const actions = {
  addComment(reviewId: string, element: string, message: string) {
    const review = state.reviews.find((r) => r.id === reviewId)
    if (!review || !message.trim()) return
    const c: ReviewComment = {
      id: uid("c"),
      reviewId,
      author: currentUser.name,
      role: "Giảng viên",
      createdAt: stamp(),
      element,
      message: message.trim(),
      resolved: false,
      replies: [],
    }
    set({
      ...state,
      comments: [c, ...state.comments],
      notifications: [notify("student", `Giảng viên nhận xét ${review.documentTitle} ${review.version}`, `${review.classCode} · ${review.groupName} · Vừa xong`, `/reviews/${reviewId}`), ...state.notifications],
    })
  },

  toggleResolved(commentId: string) {
    set({ ...state, comments: state.comments.map((c) => (c.id === commentId ? { ...c, resolved: !c.resolved } : c)) })
  },

  reply(commentId: string, role: Role, message: string) {
    const comment = state.comments.find((c) => c.id === commentId)
    const review = comment && state.reviews.find((r) => r.id === comment.reviewId)
    if (!comment || !review || !message.trim()) return
    const reply = { id: uid("r"), author: authorOf(role), role, createdAt: stamp(), message: message.trim() }
    const to: Role = role === "teacher" ? "student" : "teacher"
    const who = role === "teacher" ? "Giảng viên" : currentStudent.name
    set({
      ...state,
      comments: state.comments.map((c) => (c.id === commentId ? { ...c, replies: [...(c.replies ?? []), reply] } : c)),
      notifications: [notify(to, `${who} trả lời comment về “${comment.element}”`, `${review.documentTitle} ${review.version} · Vừa xong`, `/reviews/${review.id}`), ...state.notifications],
    })
  },

  /** Teacher decision. Appends an event; never rewrites an earlier one.
   *
   * ADR-0019: the two decision values are the server's closed set
   * (`approved | changes_requested`), and the document status written back is
   * the SAME value — but `rejected` is no longer reachable, so the mock can no
   * longer render a state the server refuses to record. */
  decide(reviewId: string, kind: Exclude<ReviewEventKind, "resubmitted">, note: string) {
    const review = state.reviews.find((r) => r.id === reviewId)
    if (!review) return
    const event: ReviewEvent = { id: uid("e"), reviewId, kind, by: "teacher", author: currentUser.name, version: review.version, note: note.trim(), createdAt: stamp() }
    const verb = { approved: "phê duyệt", changes_requested: "yêu cầu chỉnh sửa" }[kind]
    set({
      ...state,
      reviews: state.reviews.map((r) => (r.id === reviewId ? { ...r, status: kind, resubmitNote: undefined } : r)),
      events: [...state.events, event],
      notifications: [notify("student", `Giảng viên ${verb} ${review.documentTitle} ${review.version}`, `${review.classCode} · ${review.groupName} · Vừa xong`, `/reviews/${reviewId}`), ...state.notifications],
    })
  },

  /** Student sends a new version back to the teacher. */
  resubmit(reviewId: string, note: string) {
    const review = state.reviews.find((r) => r.id === reviewId)
    if (!review) return
    const version = bumpVersion(review.version)
    const event: ReviewEvent = { id: uid("e"), reviewId, kind: "resubmitted", by: "student", author: currentStudent.name, version, note: note.trim(), createdAt: stamp() }
    const rounds = state.events.filter((e) => e.reviewId === reviewId && e.kind === "resubmitted").length + 1
    set({
      ...state,
      reviews: state.reviews.map((r) =>
        r.id === reviewId ? { ...r, version, status: "resubmitted", submittedAgo: "Vừa xong", submittedAt: stamp(), resubmitNote: `Nộp lại lần ${rounds}${note.trim() ? ` · ${note.trim()}` : ""}` } : r,
      ),
      events: [...state.events, event],
      notifications: [notify("teacher", `${review.groupName} vừa nộp lại ${review.documentTitle} ${version}`, `${review.classCode} · Vừa xong`, `/reviews/${reviewId}`), ...state.notifications],
    })
  },

  markNotificationsRead(role: Role) {
    if (!state.notifications.some((n) => n.audience === role && n.unread)) return
    set({ ...state, notifications: state.notifications.map((n) => (n.audience === role ? { ...n, unread: false } : n)) })
  },

  reset() {
    set(seed())
  },
}
