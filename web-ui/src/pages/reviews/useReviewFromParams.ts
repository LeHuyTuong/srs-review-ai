import { useParams } from "react-router-dom"
import { useStore } from "@/data/store"

export default function useReviewFromParams() {
  const { reviewId } = useParams()
  const { reviews } = useStore()
  return { reviewId, review: reviews.find((r) => r.id === reviewId) }
}
