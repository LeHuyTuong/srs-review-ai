import { reviewsOf, type useStore } from "@/data/store"

/** The reviews this student's group submitted, with the numbers a list row needs.
 *
 * The name filter that used to sit here is gone, and deleting it is the point.
 * It read `r.submitter === currentStudent.name` — a comparison against a
 * fixture name — to decide which rows were "mine". The server already answers
 * that question: `GET /submissions` is scoped by the session, so the only rows
 * that ever arrive are the caller's (ADR-0020 §4). Keeping the filter meant two
 * things that could disagree about who the student is, and the fixture was one
 * of them.
 */
export function studentReviews(store: ReturnType<typeof useStore>) {
  return reviewsOf(store).map((review) => ({
    review,
    openComments: store.comments.filter((c) => c.reviewId === review.id && !c.resolved).length,
    lastNote: [...store.events].reverse().find((e) => e.reviewId === review.id && e.by === "teacher")?.note,
  }))
}
