import { describe, expect, it } from "vitest"
import { documentStatusMeta } from "@/components/ui/statusMeta"
import type { DocumentStatus } from "@/types"

/**
 * The five states the server can put a document in, taken from a running
 * server rather than from the client's own type.
 *
 *   submitted         created                          submissions.py:249
 *   reviewed          an AI report was attached        :285
 *   approved          a teacher approved               :474 (decision)
 *   changes_requested a teacher sent it back           :474 (decision)
 *   resubmitted       the student sent a new round     :325 (revised)
 *
 * The client type used to list NINE values. Four were invented, and one real
 * value was MISSING: `submitted` — the state of EVERY row a teacher has not
 * decided yet. `documentStatusMeta["submitted"]` was therefore `undefined`, and
 * the busiest rows on the screen crashed on `.label`. The list below is the
 * server's, and the test fails if the two ever drift apart again.
 */
const SERVER_STATUSES = [
  "submitted",
  "reviewed",
  "approved",
  "changes_requested",
  "resubmitted",
] as const satisfies readonly DocumentStatus[]

/** Values with no word on the server. See the `rejected` test below. */
const STATUSES_WITHOUT_A_SERVER_WORD = ["rejected", "pending", "needsRevision", "locked"]

describe("documentStatusMeta", () => {
  it("has a label for every status the server can send", () => {
    for (const status of SERVER_STATUSES) {
      const meta = documentStatusMeta[status]
      expect(meta, `missing label for "${status}"`).toBeDefined()
      expect(meta.label.length).toBeGreaterThan(0)
    }
  })

  it("covers exactly the server's statuses and nothing more", () => {
    expect(Object.keys(documentStatusMeta).sort()).toEqual([...SERVER_STATUSES].sort())
  })

  it("does not claim a verdict the server cannot express", () => {
    // `rejected` is the important one: it asserts a FAILING verdict, and this
    // API has no way to record one — a decision is only `approved` or
    // `changes_requested` (a closed two-value Literal). A label for it would
    // put a decision on screen that the server never made.
    for (const status of STATUSES_WITHOUT_A_SERVER_WORD) {
      expect(documentStatusMeta).not.toHaveProperty(status)
    }
  })

  it("gives every status a non-empty tone", () => {
    for (const status of SERVER_STATUSES) {
      expect(documentStatusMeta[status].tone.length).toBeGreaterThan(0)
    }
  })
})
