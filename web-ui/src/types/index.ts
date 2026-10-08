export type Tone = "brand" | "olive" | "amber" | "rust" | "danger" | "neutral"

/**
 * Every state a submission can actually be in.
 *
 * Three sources, and only three:
 *   - `submitted` — the server's value before anyone decides
 *     (`record.get("status", "submitted")`, submissions.py).
 *   - `approved` / `changes_requested` — the teacher's decision. A CLOSED set
 *     of two, `Literal["approved", "changes_requested"]` at submissions.py:98.
 *   - `reviewed` — the round has an AI review attached but no verdict yet
 *     (`payload["status"] = "reviewed"`, infrastructure/submissions.py:275).
 *   - `resubmitted` — the student's own verb after a change request.
 *
 * `reviewed` was missing from the first draft of this type and was found by
 * running the real server, not by reading it: create a submission, attach a
 * review, read it back, and `status` has moved from `submitted` to `reviewed`.
 * A type listing four of the five states would have made the AI-reviewed round
 * — the one a teacher is most likely to be looking at — unrenderable.
 *
 * The list this replaces also carried `pending`, `needsRevision`, `rejected`,
 * `locked`, `notStarted` and `ready`. None of them is a value the server ever
 * sends. `rejected` and `needsRevision` were the expensive ones: a tutor
 * reading "Không đạt" would reasonably file a grade, when the server cannot
 * express that verdict at all — its worst decision is "please change this".
 * That is not a missing label, it is a claim about a verdict that does not
 * exist, so the values are removed rather than renamed.
 *
 * `submitted` was the opposite bug and the more likely one to bite: it is the
 * status of every row a teacher has not decided yet, and it was MISSING, so
 * `StatusBadge` read `documentStatusMeta["submitted"]` → `undefined` → threw
 * on `.label`. The commonest row on the screen was the one that crashed.
 */
export type DocumentStatus =
  | "submitted"
  | "reviewed"
  | "approved"
  | "changes_requested"
  | "resubmitted"

export type GroupHealth =
  | "onTrack"
  | "attention"
  | "needsRevision"
  | "dueSoon"
  | "notSubmitted"
  | "overdue"
  | "waitingLong"

export interface ClassRoom {
  id: string
  code: string
  subject: string
  semester: string
  lecturer: string
  groupCount: number
  studentCount: number
  projectCount: number
  pendingReviews: number
}

export interface StudentMember {
  initials: string
  name: string
  role: string
}

export interface StudentGroup {
  id: string
  classId: string
  name: string
  projectId: string
  health: GroupHealth
  memberCount: number
  progress: number
  pendingReviews: number
  lastActivity: string
}

export interface Project {
  id: string
  name: string
  classId: string
  groupId: string
  groupName: string
  lecturer: string
  startDate: string
  deadline: string
  progress: number
  members: StudentMember[]
  nextStep?: string
  lastReturn?: string
}

export interface ProjectDocument {
  id: string
  projectId: string
  title: string
  version?: string
  status: DocumentStatus
  submitter?: string
  updatedAt?: string
  aiSummary?: string
  commentCount?: number
  note?: string
  reviewId?: string
}

export type IssueSeverity = "critical" | "major" | "minor" | "suggestion"

export interface AIIssue {
  id: string
  severity: IssueSeverity
  category: string
  message: string
  action: string
}

export interface AICheck {
  title: string
  result: string
  tone: Tone
  detail: string
}

export interface ReviewRequest {
  id: string
  projectId: string
  classCode: string
  groupName: string
  projectName: string
  documentTitle: string
  version: string
  submittedAgo: string
  submittedAt: string
  submitter: string
  aiSummary: string
  status: DocumentStatus
  resubmitNote?: string
}

export type Role = "teacher" | "student"

export interface CommentReply {
  id: string
  author: string
  role: Role
  createdAt: string
  message: string
}

export interface ReviewComment {
  id: string
  reviewId: string
  author: string
  role: string
  createdAt: string
  element: string
  message: string
  resolved: boolean
  replies?: CommentReply[]
}

/** One step of the teacher <-> student conversation on a review.
 *
 * ADR-0019: this is the server's closed decision set (`approved |
 * changes_requested`, ADR-0016/0017) plus the student's own verb
 * (`resubmitted`). `needsRevision` and `rejected` are NOT event kinds — they
 * are `DocumentStatus` values (the state a document is in), and mixing the two
 * is the drift this ADR removed. */
export type ReviewEventKind = "approved" | "changes_requested" | "resubmitted"

export interface ReviewEvent {
  id: string
  reviewId: string
  kind: ReviewEventKind
  by: Role
  author: string
  version: string
  note: string
  createdAt: string
}

export interface DocumentVersion {
  id: string
  reviewId: string
  version: string
  submittedAt: string
  status: DocumentStatus
  aiSummary: string
  lecturerNote: string
  detail: string
  feedback?: string
  isCurrent?: boolean
}

export interface ReviewActivity {
  id: string
  reviewId: string
  title: string
  time: string
  meta: string
  quote?: string
  tone: Tone
}

export interface Notification {
  id: string
  audience: Role
  title: string
  meta: string
  unread: boolean
  link?: string
}

export interface AttentionItem {
  label: string
  tone: Tone
  title: string
  detail: string
  projectId: string
}
