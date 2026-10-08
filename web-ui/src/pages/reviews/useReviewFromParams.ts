import { useParams } from "react-router-dom"
import { reviewsOf, useStore } from "@/data/store"

export default function useReviewFromParams() {
  const { reviewId } = useParams()
  const store = useStore()
  // The list is the source when it has been loaded; a direct open (deep link)
  // falls back to the detail the store is already holding. Neither path invents
  // a row the server did not send.
  const reviews = reviewsOf(store)
  return { reviewId, review: reviews.find((r) => r.id === reviewId) }
}
