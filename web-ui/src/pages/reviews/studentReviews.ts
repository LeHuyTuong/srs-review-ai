import { currentStudent } from "@/data/mockData"
import type { useStore } from "@/data/store"

/** The reviews this student's group submitted, with the numbers a list row needs. */
export function studentReviews(store: ReturnType<typeof useStore>) {
  return store.reviews
    .filter((r) => r.submitter === currentStudent.name)
    .map((review) => ({
      review,
      openComments: store.comments.filter((c) => c.reviewId === review.id && !c.resolved).length,
      lastNote: [...store.events].reverse().find((e) => e.reviewId === review.id && e.by === "teacher")?.note,
    }))
}
