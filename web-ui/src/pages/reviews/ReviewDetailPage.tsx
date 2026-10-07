import { useRole } from "@/app/auth"
import ReviewWorkspacePage from "./ReviewWorkspacePage"
import StudentReviewPage from "./StudentReviewPage"

export default function ReviewDetailPage() {
  return useRole() === "student" ? <StudentReviewPage /> : <ReviewWorkspacePage />
}
