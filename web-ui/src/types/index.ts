export type Tone = "brand" | "olive" | "amber" | "rust" | "danger" | "neutral"

export type DocumentStatus =
  | "approved"
  | "pending"
  | "resubmitted"
  | "changes_requested"
  | "needsRevision"
  | "rejected"
  | "locked"
  | "notStarted"
  | "ready"

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
