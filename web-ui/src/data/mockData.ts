import type {
  AICheck,
  AIIssue,
  AttentionItem,
  ClassRoom,
  DocumentStatus,
  DocumentVersion,
  GroupHealth,
  Notification,
  Project,
  ProjectDocument,
  ReviewActivity,
  ReviewComment,
  ReviewEvent,
  ReviewRequest,
  StudentGroup,
  Tone,
} from "@/types"

export const currentUser = {
  name: "Nguyễn Văn An",
  initials: "NA",
  role: "Giảng viên / Supervisor",
  email: "an.nguyen@university.edu.vn",
  semester: "Fall 2026",
}

export const currentStudent = {
  name: "Nguyễn Minh Anh",
  initials: "MA",
  role: "Sinh viên · Trưởng nhóm",
  email: "anh.nm@student.university.edu.vn",
  semester: "Fall 2026",
  group: "SE1701 · Group 04",
}

export const documentStatusMeta: Record<DocumentStatus, { label: string; tone: Tone }> = {
  approved: { label: "Đã phê duyệt", tone: "brand" },
  pending: { label: "Chờ giảng viên review", tone: "amber" },
  resubmitted: { label: "Đã nộp lại", tone: "olive" },
  changes_requested: { label: "Cần chỉnh sửa", tone: "rust" },
  needsRevision: { label: "Cần chỉnh sửa", tone: "rust" },
  rejected: { label: "Không đạt", tone: "danger" },
  locked: { label: "Bị khóa", tone: "neutral" },
  notStarted: { label: "Chưa bắt đầu", tone: "neutral" },
  ready: { label: "Sẵn sàng nộp", tone: "olive" },
}

export const groupHealthMeta: Record<GroupHealth, { label: string; tone: Tone }> = {
  onTrack: { label: "Đúng tiến độ", tone: "brand" },
  attention: { label: "Cần chú ý", tone: "amber" },
  needsRevision: { label: "Cần chỉnh sửa", tone: "rust" },
  dueSoon: { label: "Sắp đến hạn", tone: "amber" },
  notSubmitted: { label: "Chưa nộp tài liệu", tone: "neutral" },
  overdue: { label: "Quá hạn", tone: "danger" },
  waitingLong: { label: "Chờ review lâu", tone: "rust" },
}

export const classes: ClassRoom[] = [
  { id: "se1701", code: "SE1701", subject: "Software Engineering Project", semester: "Fall 2026", lecturer: "Nguyễn Văn An", groupCount: 8, studentCount: 34, projectCount: 8, pendingReviews: 5 },
  { id: "se1702", code: "SE1702", subject: "Software Engineering Project", semester: "Fall 2026", lecturer: "Nguyễn Văn An", groupCount: 4, studentCount: 18, projectCount: 4, pendingReviews: 1 },
  { id: "swp391-01", code: "SWP391-01", subject: "Software Engineering Project", semester: "Fall 2026", lecturer: "Nguyễn Văn An", groupCount: 3, studentCount: 15, projectCount: 3, pendingReviews: 1 },
  { id: "swp391-02", code: "SWP391-02", subject: "Software Engineering Project", semester: "Fall 2026", lecturer: "Nguyễn Văn An", groupCount: 3, studentCount: 14, projectCount: 3, pendingReviews: 0 },
]

const group = (
  n: string,
  projectId: string,
  health: GroupHealth,
  memberCount: number,
  progress: number,
  pendingReviews: number,
  lastActivity: string,
): StudentGroup => ({ id: `se1701-group-${n}`, classId: "se1701", name: `Group ${n}`, projectId, health, memberCount, progress, pendingReviews, lastActivity })

export const studentGroups: StudentGroup[] = [
  group("01", "smart-campus-management", "onTrack", 4, 65, 2, "15 phút trước"),
  group("02", "hospital-management-system", "attention", 5, 54, 1, "3 giờ trước"),
  group("03", "student-services-portal", "needsRevision", 4, 48, 0, "1 ngày trước"),
  group("04", "smart-attendance-system", "onTrack", 4, 32, 1, "2 giờ trước"),
  group("05", "dormitory-management-platform", "dueSoon", 4, 40, 1, "5 giờ trước"),
  group("06", "ai-learning-assistant", "notSubmitted", 4, 12, 0, "2 ngày trước"),
  group("07", "event-management-system", "overdue", 4, 25, 0, "3 ngày trước"),
  group("08", "campus-service-portal", "waitingLong", 5, 46, 1, "45 phút trước"),
]

const smartCampusMembers = [
  { initials: "MA", name: "Nguyễn Minh Anh", role: "Trưởng nhóm · Use Case Diagram" },
  { initials: "HN", name: "Trần Hoàng Nam", role: "Activity Diagram · SDS" },
  { initials: "GH", name: "Lê Gia Huy", role: "State Diagram · Detailed Design" },
  { initials: "TM", name: "Phạm Thảo My", role: "SRS · Kiểm tra requirement" },
]

const projectNames: Record<string, string> = {
  "smart-campus-management": "Smart Campus Management",
  "hospital-management-system": "Hospital Management System",
  "student-services-portal": "Student Services Portal",
  "smart-attendance-system": "Smart Attendance System",
  "dormitory-management-platform": "Dormitory Management Platform",
  "ai-learning-assistant": "AI Learning Assistant",
  "event-management-system": "Event Management System",
  "campus-service-portal": "Campus Service Portal",
}

export const projects: Project[] = studentGroups.map((g) => ({
  id: g.projectId,
  name: projectNames[g.projectId],
  classId: g.classId,
  groupId: g.id,
  groupName: g.name,
  lecturer: "Nguyễn Văn An",
  startDate: "01/09/2026",
  deadline: "15/12/2026",
  progress: g.projectId === "smart-campus-management" ? 58 : g.progress,
  members: smartCampusMembers.slice(0, Math.min(4, g.memberCount)),
  ...(g.projectId === "smart-campus-management" && {
    nextStep: "Review Sequence Diagram v2 và theo dõi bản chỉnh sửa State Diagram trước khi mở SRS.",
    lastReturn: "Lần trả lại gần nhất: 02/10/2026 · 3 comment đang mở",
  }),
}))

export const documents: ProjectDocument[] = [
  { id: "use-case", projectId: "smart-campus-management", title: "Use Case Diagram", version: "v3", status: "approved", submitter: "Nguyễn Minh Anh", updatedAt: "14/09/2026", aiSummary: "AI Không còn lỗi", commentCount: 3, reviewId: "review-003" },
  { id: "activity", projectId: "smart-campus-management", title: "Activity Diagram", version: "v2", status: "approved", submitter: "Trần Hoàng Nam", updatedAt: "20/09/2026", aiSummary: "AI Không còn lỗi", commentCount: 2 },
  { id: "sequence", projectId: "smart-campus-management", title: "Sequence Diagram", version: "v2", status: "pending", submitter: "Trần Hoàng Nam", updatedAt: "2 giờ trước", aiSummary: "AI 2 lỗi · 3 cảnh báo", commentCount: 4, note: "Nộp lại lần 1 · Feedback v1: sửa thứ tự message.", reviewId: "review-003" },
  { id: "state", projectId: "smart-campus-management", title: "State Diagram", version: "v1", status: "needsRevision", submitter: "Lê Gia Huy", updatedAt: "02/10/2026", aiSummary: "AI 1 lỗi · 2 cảnh báo", commentCount: 3, note: "Feedback: bổ sung trạng thái sau khi bị từ chối." },
  { id: "srs", projectId: "smart-campus-management", title: "SRS", status: "locked", submitter: "Phạm Thảo My", updatedAt: "Chưa nộp", aiSummary: "AI Chưa thực hiện", commentCount: 0, note: "SRS chưa thể gửi review vì Sequence Diagram và State Diagram chưa được phê duyệt." },
  { id: "sds", projectId: "smart-campus-management", title: "SDS", status: "notStarted", note: "Chưa có version · Sinh viên chưa nộp tài liệu" },
  { id: "detailed-design", projectId: "smart-campus-management", title: "Detailed Design", status: "notStarted", note: "Chưa có version · Sinh viên chưa nộp tài liệu" },
  { id: "class-diagram", projectId: "smart-campus-management", title: "Class Diagram", status: "ready", submitter: "Lê Gia Huy", updatedAt: "01/10/2026" },
]

export const reviewRequests: ReviewRequest[] = [
  { id: "review-001", projectId: "smart-attendance-system", classCode: "SE1701", groupName: "Group 04", projectName: "Smart Attendance System", documentTitle: "Use Case Diagram", version: "v2", submittedAgo: "2 giờ trước", submittedAt: "03/10/2026 · 08:15", submitter: "Nguyễn Minh Anh", aiSummary: "AI 2 lỗi · 3 cảnh báo", status: "pending", resubmitNote: "Nộp lại lần 1 · 1 comment cũ chưa xử lý" },
  { id: "review-002", projectId: "hospital-management-system", classCode: "SE1701", groupName: "Group 02", projectName: "Hospital Management System", documentTitle: "Sequence Diagram", version: "v3", submittedAgo: "3 giờ trước", submittedAt: "03/10/2026 · 07:10", submitter: "Đỗ Khánh Linh", aiSummary: "AI Đã hoàn tất", status: "resubmitted", resubmitNote: "Nộp lại lần 2 · 2 comment đã xử lý" },
  { id: "review-003", projectId: "smart-campus-management", classCode: "SE1701", groupName: "Group 01", projectName: "Smart Campus Management", documentTitle: "Use Case Diagram", version: "v3", submittedAgo: "3 giờ trước", submittedAt: "14/09/2026 · 10:32", submitter: "Nguyễn Minh Anh", aiSummary: "AI 2 lỗi · 3 cảnh báo", status: "pending", resubmitNote: "Nộp lại lần 1 · 4 comment cần kiểm tra" },
  { id: "review-004", projectId: "campus-service-portal", classCode: "SE1701", groupName: "Group 08", projectName: "Campus Service Portal", documentTitle: "Sequence Diagram", version: "v2", submittedAgo: "4 ngày trước", submittedAt: "29/09/2026 · 16:40", submitter: "Võ Quốc Bảo", aiSummary: "AI 1 lỗi · 1 cảnh báo", status: "pending", resubmitNote: "Nộp lại lần 1 · Chờ xử lý hơn 72 giờ" },
  { id: "review-005", projectId: "dormitory-management-platform", classCode: "SE1701", groupName: "Group 05", projectName: "Dormitory Management Platform", documentTitle: "Activity Diagram", version: "v1", submittedAgo: "1 ngày trước", submittedAt: "02/10/2026 · 09:00", submitter: "Hoàng Thu Trang", aiSummary: "AI Không phát hiện lỗi", status: "pending" },
  { id: "review-006", projectId: "smart-campus-management", classCode: "SE1702", groupName: "Group 03", projectName: "Smart Campus Management", documentTitle: "SRS", version: "v2", submittedAgo: "20 phút trước", submittedAt: "03/10/2026 · 09:55", submitter: "Phạm Thảo My", aiSummary: "AI 1 lỗi · 2 cảnh báo", status: "resubmitted", resubmitNote: "Nộp lại lần 1 · UML phụ thuộc đã phê duyệt" },
  { id: "review-007", projectId: "ai-learning-assistant", classCode: "SWP391-01", groupName: "Group 02", projectName: "AI Learning Assistant", documentTitle: "Use Case Diagram", version: "v1", submittedAgo: "2 giờ trước", submittedAt: "03/10/2026 · 08:05", submitter: "Bùi Gia Bảo", aiSummary: "AI Đã hoàn tất", status: "pending" },
]

export const aiSeverityCounts = [
  { value: 1, label: "Lỗi nghiêm trọng", tone: "danger" as Tone },
  { value: 2, label: "Lỗi", tone: "rust" as Tone },
  { value: 3, label: "Cảnh báo", tone: "amber" as Tone },
  { value: 4, label: "Gợi ý", tone: "olive" as Tone },
]

export const aiChecks: AICheck[] = [
  { title: "Kiểm tra Mermaid", result: "Hợp lệ", tone: "brand", detail: "Cú pháp được phân tích thành công." },
  { title: "Cấu trúc diagram", result: "1 lỗi nghiêm trọng", tone: "danger", detail: "Actor Admin được tham chiếu nhưng chưa khai báo." },
  { title: "Tính nhất quán tên", result: "1 cảnh báo", tone: "amber", detail: "Manage User và Manage Project cần tên cụ thể hơn." },
  { title: "Phần tử bị thiếu", result: "1 lỗi", tone: "rust", detail: "Login chưa có Association với Actor." },
  { title: "Kiểm tra relationship", result: "1 lỗi", tone: "rust", detail: "Submit Document thiếu Association với Student." },
  { title: "Tính nhất quán với requirement", result: "3 gợi ý", tone: "olive", detail: "Đối chiếu FR-03, FR-05 và Business Rule BR-02." },
]

export const aiIssues: AIIssue[] = [
  { id: "i1", severity: "critical", category: "Missing Element", message: "Actor “Admin” được tham chiếu nhưng không tồn tại trong diagram.", action: "Xem trong mã Mermaid →" },
  { id: "i2", severity: "major", category: "Incorrect Relationship", message: "Use Case “Login” chưa được kết nối với Actor nào.", action: "Thêm comment →" },
  { id: "i3", severity: "major", category: "Missing Element", message: "Use Case “Submit Document” chưa được liên kết với Actor “Student”.", action: "Thêm comment →" },
  { id: "i4", severity: "minor", category: "Naming Issue", message: "Use Case “Manage User” có phạm vi quá rộng.", action: "Thêm comment →" },
  { id: "i5", severity: "suggestion", category: "Logic Issue", message: "Tách Manage Project thành Create Project, Update Project và Archive Project.", action: "Xem 4 gợi ý →" },
]

export const reviewComments: ReviewComment[] = [
  { id: "c1", reviewId: "review-001", author: "Nguyễn Văn An", role: "Giảng viên", createdAt: "03/10/2026, 09:10", element: "Submit Document", message: "Relationship giữa Student và Submit Document chưa đúng.", resolved: false },
  { id: "c2", reviewId: "review-001", author: "Nguyễn Văn An", role: "Giảng viên", createdAt: "03/10/2026, 09:14", element: "Manage Project", message: "Comment #2 · Phạm vi Manage Project", resolved: true },
  { id: "c3", reviewId: "review-001", author: "Nguyễn Văn An", role: "Giảng viên", createdAt: "30/09/2026, 15:20", element: "Student", message: "Bổ sung Actor Student cho luồng nộp tài liệu.", resolved: true },
]

export const documentVersions: DocumentVersion[] = [
  { id: "v1", reviewId: "review-003", version: "v1", submittedAt: "10/09/2026 · 09:20", status: "needsRevision", aiSummary: "AI 3 lỗi", lecturerNote: "Giảng viên: Cần chỉnh sửa · 3 comment", detail: "Lần nộp đầu tiên", feedback: "Feedback: thiếu Actor Student, Association của Login và điều kiện gửi review." },
  { id: "v2", reviewId: "review-003", version: "v2", submittedAt: "12/09/2026 · 14:05", status: "resubmitted", aiSummary: "AI 1 lỗi", lecturerNote: "Giảng viên: Cần chỉnh sửa", detail: "Nộp lại lần 1 · 2/3 comment đã xử lý", feedback: "Feedback: Login vẫn chưa liên kết với Supervisor." },
  { id: "v3", reviewId: "review-003", version: "v3", submittedAt: "14/09/2026 · 10:32", status: "approved", aiSummary: "AI không còn lỗi", lecturerNote: "Giảng viên Nguyễn Văn An phê duyệt lúc 11:20.", detail: "Nộp lại lần 2 · 3 comment đã xử lý", isCurrent: true },
]

export const versionChanges = [
  { title: "Association của Login", before: "Login chỉ liên kết với Student.", after: "Bổ sung Association Supervisor — Login.", note: "Comment #3 đã xử lý" },
  { title: "Điều kiện gửi review", after: "Đã bổ sung Business Rule: chỉ cho phép Request Review sau khi Upload Document thành công.", note: "Feedback v2 được giữ lại trong lịch sử." },
]

export const reviewActivities: ReviewActivity[] = [
  { id: "a1", reviewId: "review-003", title: "Nguyễn Minh Anh đã nộp version v3", time: "14/09/2026 · 10:32", meta: "Sinh viên · Nộp lại lần 2", tone: "neutral" },
  { id: "a2", reviewId: "review-003", title: "AI Review bắt đầu", time: "14/09/2026 · 10:33", meta: "Hệ thống · Kiểm tra Mermaid và UML", tone: "olive" },
  { id: "a3", reviewId: "review-003", title: "AI Review hoàn tất", time: "14/09/2026 · 10:34", meta: "Hệ thống · Không phát hiện lỗi còn mở", tone: "olive" },
  { id: "a4", reviewId: "review-003", title: "Giảng viên mở tài liệu", time: "14/09/2026 · 11:05", meta: "Nguyễn Văn An · Use Case Diagram v3", tone: "neutral" },
  { id: "a5", reviewId: "review-003", title: "Giảng viên thêm comment", time: "14/09/2026 · 11:12", meta: "Nguyễn Văn An · Xác nhận Association đã sửa", quote: "“Association giữa Supervisor và Login đã chính xác.”", tone: "amber" },
  { id: "a6", reviewId: "review-003", title: "Tài liệu được phê duyệt", time: "14/09/2026 · 11:20", meta: "Nguyễn Văn An · Quyết định cuối cùng", tone: "brand" },
]

export const attentionItems: AttentionItem[] = [
  { label: "Quá hạn", tone: "danger", title: "Group 07 · Event Management System", detail: "Quá hạn nộp Activity Diagram 2 ngày", projectId: "event-management-system" },
  { label: "Sắp đến hạn", tone: "amber", title: "Group 05 · Dormitory Management Platform", detail: "Deadline 08/10 · còn 4 ngày", projectId: "dormitory-management-platform" },
  { label: "Chưa nộp", tone: "neutral", title: "Group 06 · AI Learning Assistant", detail: "Chưa nộp Use Case Diagram đầu tiên", projectId: "ai-learning-assistant" },
  { label: "Cần chú ý", tone: "rust", title: "Group 03 · Hospital Management System", detail: "State Diagram bị trả lại 3 lần", projectId: "student-services-portal" },
  { label: "Chờ lâu", tone: "rust", title: "Group 08 · Campus Service Portal", detail: "Sequence Diagram chờ review 4 ngày", projectId: "campus-service-portal" },
]

export const notifications: Notification[] = [
  { id: "n1", audience: "teacher", title: "Group 03 vừa nộp SRS v2", meta: "SE1702 · 20 phút trước", unread: true, link: "/reviews/review-006" },
  { id: "n2", audience: "teacher", title: "Group 08 vừa nộp lại Sequence Diagram", meta: "SE1701 · 45 phút trước", unread: true, link: "/reviews/review-004" },
  { id: "n3", audience: "teacher", title: "Bạn đã phê duyệt Use Case Diagram của Group 01", meta: "SE1701 · 1 giờ trước", unread: false, link: "/reviews/review-003/history" },
  { id: "n4", audience: "teacher", title: "AI Review đã hoàn tất cho Activity Diagram", meta: "SWP391-01 · Group 02 · 2 giờ trước", unread: false, link: "/reviews/review-007/ai-result" },
  { id: "n5", audience: "student", title: "Giảng viên đã nhận xét Use Case Diagram v2", meta: "SE1701 · Group 04 · 2 giờ trước", unread: true, link: "/reviews/review-001" },
  { id: "n6", audience: "student", title: "Giảng viên đã phê duyệt Use Case Diagram v3", meta: "SE1701 · Group 01 · 14/09/2026", unread: false, link: "/reviews/review-003" },
]

export const reviewEvents: ReviewEvent[] = [
  { id: "e1", reviewId: "review-001", kind: "changes_requested", by: "teacher", author: "Nguyễn Văn An", version: "v1", note: "Bổ sung Actor Student, kiểm tra Association với luồng nộp tài liệu.", createdAt: "30/09/2026 · 15:20" },
  { id: "e2", reviewId: "review-001", kind: "resubmitted", by: "student", author: "Nguyễn Minh Anh", version: "v2", note: "Nhóm đã bổ sung Actor Student và nối Login với Supervisor.", createdAt: "03/10/2026 · 08:15" },
  { id: "e3", reviewId: "review-003", kind: "changes_requested", by: "teacher", author: "Nguyễn Văn An", version: "v1", note: "Thiếu Actor Student, Association của Login và điều kiện gửi review.", createdAt: "10/09/2026 · 16:00" },
  { id: "e4", reviewId: "review-003", kind: "resubmitted", by: "student", author: "Nguyễn Minh Anh", version: "v2", note: "Đã thêm Actor Student và Association của Login.", createdAt: "12/09/2026 · 14:05" },
  { id: "e5", reviewId: "review-003", kind: "approved", by: "teacher", author: "Nguyễn Văn An", version: "v3", note: "Association giữa Supervisor và Login đã chính xác.", createdAt: "14/09/2026 · 11:20" },
]

