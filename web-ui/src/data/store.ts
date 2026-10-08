/**
 * web-ui's data layer — a real API client over the server (ADR-0020).
 *
 * The original `store.ts` was the mock: it held `{reviews, comments, events,
 * notifications}` in `localStorage` and every action was a `set([...state])`.
 * It was also the *behavioural specification* the goal points at, so what this
 * file preserves is the SHAPE — `useStore()`, `actions.addComment`, `.reply`,
 * `.toggleResolved`, `.decide`, `.resubmit`, `.markNotificationsRead` — while
 * the bodies now call the FastAPI server the Flutter app and this UI share.
 *
 * A reader who wants the old mock has it in git history; a reader who wants to
 * know what the server accepts should read `server/app/api/submissions.py`.
 *
 * Four decisions that are not obvious from the code
 * =================================================
 *
 * 1. **The server has no `GET /submissions` list, and this file does not invent
 *    one.** ADR-0016 derived "membership lives on the submission", so a list is
 *    a scan a route does not expose. web-ui therefore reads ONE submission by id
 *    (a capability in the path) and the caller supplies that id. A list view is
 *    a server change with its own ADR, not something to fake here.
 *
 * 2. **`comments` come from the server, formatted for these components.** The
 *    components want `{element, message, resolved, replies[]}`; the wire says
 *    `{body, resolvedAt, replyTo, revision}`. The mapping lives in
 *    `toReviewComment` in ONE place, because a second copy of it is how the two
 *    sides drift apart.
 *
 * 3. **`markNotificationsRead` is a NO-OP on the server, and that is ADR-0016.**
 *    "Đã đọc" is a phone watermark stored on the device, never on the server —
 *    there is no reader identity for a server-side read state to key on. web-ui
 *    keeps its own browser-local read marks, which is the same posture.
 *
 * 4. **Errors are surfaced, not swallowed.** The mock's actions returned
 *    silently; a real write that fails must tell the user, so each action
 *    rejects with an `ApiError` and the calling component shows it. The store
 *    keeps a `lastError` so a component that does not await can still render.
 */

import { useSyncExternalStore } from "react"
import { getUser } from "@/app/auth"
import { API_BASE, ApiError, apiFetch } from "@/data/api"
import type { Decision, Notification, ReviewComment, ReviewEvent, ReviewEventKind, ReviewRequest, Role } from "@/types"

// ---------------------------------------------------------------- wire types

/** What `GET /submissions/{id}` returns. Mirrors the server's read view. */
export interface SubmissionWire {
  id: string
  group: string
  project: string
  revision: number
  status: string
  class_id: string
  note: string
  decidedAt: string | null
  decision_note: string
  previous_id: string | null
  createdAt: string | null
  updatedAt: string | null
  history: HistoryEntry[]
  comments: CommentWire[]
  /** The server's own count for this round, or `null` if never scored. Read
   *  rather than recomputed — the proxy is given a score and never derives one
   *  (AttachReviewRequest, submissions.py:72). */
  score?: number | null
  /** Does this round have an HTML report on the server? The report itself is
   *  served by `/submissions/{id}/report`, so this is the flag that decides
   *  whether offering that link makes sense. Present on the route
   *  (submissions.py:619) and missing from this interface until an AI-result
   *  page tried to read it — the same hand-listed-read-view trap AGENTS.md
   *  records for `createdAt`, `history`, `score` and `findings`. */
  has_report?: boolean
  /** `review.findings` — a DICT the server does not interpret ("opaque to the
   *  proxy", submissions.py:73). Its shape is the caller's, so the UI must
   *  render what is there and invent nothing. */
  findings?: Record<string, unknown>
}

export interface HistoryEntry {
  revision?: number
  at?: string
  status?: string
  event?: string
  note?: string
}

export interface CommentWire {
  id: string
  author: string
  body: string
  revision: number
  at: string
  resolvedAt?: string | null
  replyTo?: string | null
}

// ---------------------------------------------------------------- state

interface State {
  /** The one submission in view, keyed by the id the caller supplied. */
  submission: SubmissionWire | null
  /** The submissions this signed-in user may see (ADR-0020 §4). The server
   *  decides the filter from the session, so there is no parameter here. */
  list: SubmissionSummary[]
  comments: ReviewComment[]
  events: ReviewEvent[]
  notifications: Notification[]
  loading: boolean
  lastError: string | null
  /** The id the UI is currently showing, so actions know where to write. */
  submissionId: string | null
  /** The class write key, when the caller has one (teacher writes need it). */
  writeKey: string | null
}

/** One row from `GET /submissions` — the server's whitelist, mirrored. */
export interface SubmissionSummary {
  id: string
  group: string
  project: string
  revision: number
  status: string
  class_id: string
  note: string
  decidedAt: string | null
  decision_note: string
  previous_id: string | null
  createdAt: string | null
  updatedAt: string | null
  commentCount: number
  openCommentCount: number
}

const EMPTY: State = {
  submission: null,
  list: [],
  comments: [],
  events: [],
  notifications: [],
  loading: false,
  lastError: null,
  submissionId: null,
  writeKey: null,
}

// Read marks stay browser-local on purpose — see decision 3.
const READ_KEY = "project-review:read:v1"
const READ_MARK = (id: string) => `${READ_KEY}:${id}`

let state: State = EMPTY
const listeners = new Set<() => void>()

const set = (patch: Partial<State>) => {
  state = { ...state, ...patch }
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

// ---------------------------------------------------------------- mapping

let counter = 0
const uid = (p: string) => `${p}${Date.now().toString(36)}${counter++}`

const pad = (n: number) => String(n).padStart(2, "0")

/** The components render a pre-formatted local stamp, not an ISO string. */
export const stamp = (iso?: string | null): string => {
  if (!iso) return "Vừa xong"
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return "Vừa xong"
  return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()} · ${pad(d.getHours())}:${pad(d.getMinutes())}`
}

const roleLabel = (role: Role): string => (role === "teacher" ? "Giảng viên" : "Sinh viên")

/**
 * A wire comment (and its replies) as the `ReviewComment` the UI renders.
 *
 * `element` has no home on the wire: the server stores a `body` and a
 * `revision`, not a named artifact part. The round is the closest honest
 * mapping — a comment on round 2 is a comment about the round-2 document — and
 * doing it HERE rather than in the server keeps the wire vocabulary closed.
 */
function toReviewComment(reviewId: string, wire: CommentWire, replies: CommentWire[]): ReviewComment {
  return {
    id: wire.id,
    reviewId,
    author: wire.author,
    role: roleLabel(wire.author === "teacher" ? "teacher" : "student"),
    createdAt: stamp(wire.at),
    element: `Vòng ${wire.revision}`,
    message: wire.body,
    resolved: Boolean(wire.resolvedAt),
    replies: replies.map((r) => ({
      id: r.id,
      author: r.author,
      role: (r.author === "teacher" ? "teacher" : "student") as Role,
      createdAt: stamp(r.at),
      message: r.body,
    })),
  }
}

/** Group flat wire comments into top-level comments + their replies. */
function groupComments(reviewId: string, wire: CommentWire[]): ReviewComment[] {
  const byParent = new Map<string, CommentWire[]>()
  const roots: CommentWire[] = []
  for (const c of wire) {
    if (c.replyTo) {
      const list = byParent.get(c.replyTo) ?? []
      list.push(c)
      byParent.set(c.replyTo, list)
    } else {
      roots.push(c)
    }
  }
  // Newest first, matching the mock's `[c, ...state.comments]` ordering.
  return roots.reverse().map((root) => toReviewComment(reviewId, root, byParent.get(root.id) ?? []))
}

/** Wire history entries as the conversation events the timeline renders. */
const EVENT_KINDS: ReviewEventKind[] = [
  "submitted",
  "reviewed",
  "decided",
  "revised",
  "backfilled",
  "class_assigned",
]

function toEvents(reviewId: string, wire: SubmissionWire): ReviewEvent[] {
  const events: ReviewEvent[] = []
  for (const entry of wire.history) {
    // Read `event`, the field that says WHAT HAPPENED. The previous version
    // read `entry.status ?? entry.event`, which for a decision reads
    // `status` ("changes_requested") and lands on the student's vocabulary
    // instead of the server's — an accident that happened to look right.
    const kind = String(entry.event ?? "")
    if (!EVENT_KINDS.includes(kind as ReviewEventKind)) continue
    // A decision's DIRECTION lives in `status`, because `event` is `decided`
    // for both outcomes. Collapsing that here means a timeline can never say
    // which way a round went, and "decided" alone tells a student nothing.
    const direction = kind === "decided" ? String(entry.status ?? "") : ""
    events.push({
      id: uid("e"),
      reviewId,
      kind: kind as ReviewEventKind,
      direction,
      by: kind === "submitted" || kind === "revised" ? "student" : "teacher",
      // Only a decision or a revision is a person's act. `reviewed` is the
      // server reading the document, and `backfilled`/`class_assigned` are
      // bookkeeping — attributing any of them to a teacher names a decision
      // nobody made.
      author:
        kind === "submitted" || kind === "revised"
          ? wire.group
          : kind === "reviewed"
            ? "Hệ thống"
            : kind === "decided"
              ? "Giảng viên"
              : "",
      version: `v${entry.revision ?? wire.revision}`,
      note: entry.note ?? "",
      createdAt: stamp(entry.at),
    })
  }
  return events
}

// ---------------------------------------------------------------- actions

const currentActor = (): string => getUser()?.username ?? "anonymous"

const notify = (audience: Role, title: string, meta: string, link: string): Notification => ({
  id: uid("n"),
  audience,
  title,
  meta,
  unread: true,
  link,
})

/** Re-read the submission so what is rendered is what the SERVER holds. */
async function refresh(): Promise<void> {
  await actions.load(state.submissionId ?? "")
}

function requireId(): string {
  const id = state.submissionId
  if (!id) throw new ApiError(0, "Chưa chọn bài nộp nào.")
  return id
}

export const actions = {
  /** Read the submissions this signed-in user may see.
   *
   * ONE call, and the server decides the scope — a teacher gets their class, a
   * student their group. The client never says whose list it wants, so there is
   * nothing here to tamper with.
   */
  async loadList(): Promise<void> {
    set({ loading: true, lastError: null })
    try {
      const body = await apiFetch<{ submissions: SubmissionSummary[] }>("/submissions")
      set({
        list: body.submissions ?? [],
        // The summary is not the detail. Keeping the previous `submission` here
        // would leave a stale thread on screen next to a fresh list.
        loading: false,
      })
    } catch (error) {
      set({
        loading: false,
        list: [],
        lastError: error instanceof ApiError ? error.detail : String(error),
      })
      throw error
    }
  },

  /** Point the store at one submission and read it from the server. */
  async load(submissionId: string, writeKey?: string): Promise<void> {
    if (!submissionId) {
      set({ ...EMPTY })
      return
    }
    set({ submissionId, loading: true, lastError: null, ...(writeKey ? { writeKey } : {}) })
    try {
      const wire = await apiFetch<SubmissionWire>(`/submissions/${encodeURIComponent(submissionId)}`)
      set({
        submission: wire,
        comments: groupComments(wire.id, wire.comments ?? []),
        events: toEvents(wire.id, wire),
        loading: false,
      })
    } catch (error) {
      const detail = error instanceof ApiError ? error.detail : String(error)
      set({ loading: false, lastError: detail, submission: null, comments: [], events: [] })
      throw error
    }
  },

  async addComment(reviewId: string, element: string, message: string): Promise<void> {
    if (!message.trim()) return
    // The write key is attached when the caller has one; the server decides
    // whether the route needs it (teacher remarks do, student replies do not).
    await apiFetch(`/submissions/${encodeURIComponent(reviewId)}/comments`, {
      method: "POST",
      body: { body: message.trim(), author: getUser()?.role ?? "teacher" },
      writeKey: state.writeKey ?? undefined,
    })
    set({
      notifications: [
        notify("student", `Giảng viên nhận xét ${element || "bài nộp"}`, "Vừa xong", `/reviews/${reviewId}`),
        ...state.notifications,
      ],
    })
    await refresh()
  },

  async toggleResolved(commentId: string): Promise<void> {
    const id = requireId()
    const comment = state.comments.find((c) => c.id === commentId)
    if (!comment) return
    await apiFetch(`/submissions/${encodeURIComponent(id)}/comments/${encodeURIComponent(commentId)}`, {
      method: "PATCH",
      body: { resolved: !comment.resolved },
      writeKey: state.writeKey ?? undefined,
    })
    await refresh()
  },

  async reply(commentId: string, role: Role, message: string): Promise<void> {
    if (!message.trim()) return
    const id = requireId()
    const comment = state.comments.find((c) => c.id === commentId)
    await apiFetch(`/submissions/${encodeURIComponent(id)}/comments/${encodeURIComponent(commentId)}/replies`, {
      method: "POST",
      body: { body: message.trim(), author: role },
      writeKey: state.writeKey ?? undefined,
    })
    set({
      notifications: [
        notify(role === "teacher" ? "student" : "teacher", `${currentActor()} trả lời một nhận xét`, "Vừa xong", `/reviews/${id}`),
        ...state.notifications,
      ],
    })
    await refresh()
    void comment
  },

  /** Teacher decision. The server APPENDS a round; it never rewrites one. */
  /** The teacher's verdict. NOT a `ReviewEventKind`: a decision is a verb the
   *  route accepts, and `decided` is the event it later writes. Tying this
   *  parameter to the event vocabulary made `decide("decided")` type-check and
   *  `decide("approved")` depend on the enum happening to overlap. */
  async decide(reviewId: string, kind: Decision, note: string): Promise<void> {
    // A class key is the server's gate on this route (a group must not approve
    // its own work), so a decision without one is refused BEFORE the request
    // rather than as an opaque 409 after it.
    if (!state.writeKey) {
      throw new ApiError(0, "Cần mã lớp (X-Class-Key) để ra quyết định.")
    }
    await apiFetch(`/submissions/${encodeURIComponent(reviewId)}/decision`, {
      method: "POST",
      body: { status: kind, note: note.trim() },
      writeKey: state.writeKey,
    })
    set({
      notifications: [
        notify("student", `Giảng viên ${kind === "approved" ? "phê duyệt" : "yêu cầu chỉnh sửa"} bài nộp`, "Vừa xong", `/reviews/${reviewId}`),
        ...state.notifications,
      ],
    })
    await refresh()
  },

  /** Student sends a new version back — the server opens revision + 1. */
  async resubmit(reviewId: string, note: string): Promise<void> {
    await apiFetch(`/submissions/${encodeURIComponent(reviewId)}/revise`, {
      method: "POST",
      body: { note: note.trim() },
    })
    set({
      notifications: [
        notify("teacher", "Nhóm vừa nộp lại bài", "Vừa xong", `/reviews/${reviewId}`),
        ...state.notifications,
      ],
    })
    await refresh()
  },

  /** Read marks are BROWSER-LOCAL — the server has no reader identity to key on
   *  (ADR-0016 §2). This never calls the server, on purpose. */
  markNotificationsRead(role: Role): void {
    if (!state.notifications.some((n) => n.audience === role && n.unread)) return
    try {
      localStorage.setItem(READ_MARK(role), String(Date.now()))
    } catch {
      // A private-mode browser with storage off still gets an in-memory mark.
    }
    set({ notifications: state.notifications.map((n) => (n.audience === role ? { ...n, unread: false } : n)) })
  },

  /** Drop the local view. Nothing is cleared on the server: the round history
   *  is the record, and a "reset demo data" button must not delete it. */
  reset(): void {
    set({ ...EMPTY })
  },

  clearError(): void {
    set({ lastError: null })
  },
}

/** Convenience for the report link, matching the mock's shape. */
export const reportUri = (submissionId: string) => `${API_BASE}/submissions/${encodeURIComponent(submissionId)}/report`

/** The list as the pages' `ReviewRequest` rows. `useStore()` does not expose
 *  `reviews` (the server has no such field), so callers that need rows for the
 *  existing list components derive them here — one adapter, not eight. */
export const reviewsOf = (store: { list: SubmissionSummary[]; submission: SubmissionWire | null }): ReviewRequest[] => {
  const rows = store.list.length ? store.list : store.submission ? [summaryFrom(store.submission)] : []
  return rows.map(toReviewRequestFromSummary)
}

function summaryFrom(wire: SubmissionWire): SubmissionSummary {
  return {
    id: wire.id,
    group: wire.group,
    project: wire.project,
    revision: wire.revision,
    status: wire.status,
    class_id: wire.class_id,
    note: wire.note,
    decidedAt: wire.decidedAt,
    decision_note: wire.decision_note,
    previous_id: wire.previous_id,
    createdAt: wire.createdAt,
    updatedAt: wire.updatedAt,
    commentCount: wire.comments?.length ?? 0,
    openCommentCount: (wire.comments ?? []).filter((c) => !c.resolvedAt).length,
  }
}

export const selectRequests = (): ReviewRequest[] =>
  state.list.length ? state.list.map(toReviewRequestFromSummary) : state.submission ? [toReviewRequest(state.submission)] : []

function toReviewRequestFromSummary(wire: SubmissionSummary): ReviewRequest {
  return {
    id: wire.id,
    projectId: wire.class_id || "unfiled",
    classCode: wire.class_id || "—",
    groupName: wire.group,
    projectName: wire.project,
    documentTitle: wire.project || "Bài nộp",
    version: `v${wire.revision}`,
    submittedAgo: stamp(wire.createdAt),
    submittedAt: stamp(wire.createdAt),
    submitter: wire.group,
    aiSummary: "",
    status: (wire.status as ReviewRequest["status"]) ?? "pending",
    resubmitNote: wire.decision_note || undefined,
  }
}

function toReviewRequest(wire: SubmissionWire): ReviewRequest {
  return {
    id: wire.id,
    projectId: wire.class_id || "unfiled",
    classCode: wire.class_id || "—",
    groupName: wire.group,
    projectName: wire.project,
    documentTitle: wire.project || "Bài nộp",
    version: `v${wire.revision}`,
    submittedAgo: stamp(wire.createdAt),
    submittedAt: stamp(wire.createdAt),
    submitter: wire.group,
    aiSummary: "",
    status: (wire.status as ReviewRequest["status"]) ?? "pending",
    resubmitNote: wire.decision_note || undefined,
  }
}
