import type { DocumentStatus, Tone } from "@/types"

/**
 * Labels for `DocumentStatus`.
 *
 * Lives here rather than in `mockData` because it is not mock data: these are
 * the display names of the five states the server sends, and a component that
 * needs one of them should not have to import a file full of invented rows to
 * get it. Keeping them next to `StatusBadge` also makes the pair easy to check
 * against the server in one read, which is the check that caught `submitted`
 * and `reviewed` going missing.
 */
export const documentStatusMeta: Record<DocumentStatus, { label: string; tone: Tone }> = {
  submitted: { label: "Chờ giảng viên review", tone: "amber" },
  reviewed: { label: "Đã có kết quả AI", tone: "olive" },
  approved: { label: "Đã phê duyệt", tone: "brand" },
  changes_requested: { label: "Cần chỉnh sửa", tone: "rust" },
  resubmitted: { label: "Đã nộp lại", tone: "olive" },
}
