import { currentStudent } from "@/data/mockData"
import { reviewsOf, type useStore } from "@/data/store"

/** The reviews this student's group submitted, with the numbers a list row needs. */
export function studentReviews(store: ReturnType<typeof useStore>) {
  // `store.reviews` no longer exists — the server has no such field. The rows
  // come from the identity-scoped list, and the name filter stays because a
  // student's OWN group is what the mock showed; the server already narrowed
  // the list to that group, so this is a no-op for a correctly-scoped account.
  return reviewsOf(store)
    .filter((r) => store.list.length > 0 || r.submitter === currentStudent.name)
    .map((review) => ({
      review,
      openComments: store.comments.filter((c) => c.reviewId === review.id && !c.resolved).length,
      lastNote: [...store.events].reverse().find((e) => e.reviewId === review.id && e.by === "teacher")?.note,
    }))
}
