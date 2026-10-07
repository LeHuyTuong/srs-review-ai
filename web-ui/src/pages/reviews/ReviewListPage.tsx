import { useRole } from "@/app/auth"
import ReviewRequestsPage from "./ReviewRequestsPage"
import StudentReviewListPage from "./StudentReviewListPage"

export default function ReviewListPage() {
  return useRole() === "student" ? <StudentReviewListPage /> : <ReviewRequestsPage />
}
