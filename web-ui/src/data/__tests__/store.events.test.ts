import { beforeEach, describe, expect, it, vi } from "vitest"
import { actions, snapshot } from "@/data/store"

/**
 * The timeline is built from a submission's `history`, and every test here
 * exists because that mapping was WRONG in a way nothing caught.
 *
 * The server writes BOTH `status` (the document's state) and `event` (what
 * happened) into each entry:
 *
 *     {"revision":1,"at":"…","status":"changes_requested","event":"decided"}
 *
 * The first version of `ReviewEventKind` listed three values of `status` and
 * `toEvents` read `entry.status ?? entry.event`. That reads correctly for a
 * decision BY ACCIDENT, and can never see `decided`, `revised`, `reviewed`,
 * `backfilled` or `class_assigned` as themselves — so every timeline silently
 * lost "the group submitted" and "the AI finished", and a dropped event looks
 * exactly like an event that never happened.
 *
 * These tests pin the field, not the spelling: they assert on `event` values
 * taken from a running server.
 */

/** The wire shape `GET /submissions/{id}` returns, narrowed to `history`. */
const wire = (history: Record<string, unknown>[]) => ({
  id: "sub-1",
  group: "Nhom 1",
  project: "P1",
  revision: 1,
  status: "changes_requested",
  class_id: "cls-A",
  note: "",
  decidedAt: null,
  decision_note: "",
  previous_id: null,
  createdAt: "2026-10-08T04:16:49Z",
  updatedAt: "2026-10-08T04:25:26Z",
  history,
  comments: [],
})

/** Drive the store through its real path — `load` fetches, nothing is injected. */
async function loadHistory(history: Record<string, unknown>[]) {
  vi.stubGlobal(
    "fetch",
    vi.fn(async () =>
      new Response(JSON.stringify(wire(history)), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    ),
  )
  await actions.load("sub-1")
}

describe("history -> events", () => {
  beforeEach(() => {
    vi.unstubAllGlobals()
  })

  it("keeps the round's first entry, not just its verdict", async () => {
    // Measured from a running server: create a submission, read it back, and
    // `history` is `[{event:"submitted"}]`.
    await loadHistory([
      { revision: 1, at: "2026-10-08T04:16:49Z", status: "submitted", event: "submitted" },
    ])
    const events = snapshot().events
    expect(events).toHaveLength(1)
    expect(events[0].kind).toBe("submitted")
    // The group sent it; no teacher acted, so nothing is attributed to one.
    expect(events[0].by).toBe("student")
    expect(events[0].author).toBe("Nhom 1")
  })

  it("keeps the AI step, which is the server's own act", async () => {
    // Attaching a review writes `{"status":"reviewed","event":"reviewed"}`.
    await loadHistory([
      { revision: 1, at: "2026-10-08T04:16:49Z", status: "submitted", event: "submitted" },
      { revision: 1, at: "2026-10-08T04:25:11Z", status: "reviewed", event: "reviewed" },
    ])
    const kinds = snapshot().events.map((e) => e.kind)
    expect(kinds).toEqual(["submitted", "reviewed"])
    // `"Giảng viên"` here would name a decision nobody made.
    expect(snapshot().events[1].author).toBe("Hệ thống")
  })

  it("reads `event` for a decision, and carries the direction from `status`", async () => {
    // This is the entry the old code got right by accident: it read `status`
    // ("changes_requested") and landed on a value the enum happened to hold.
    // The point of this test is that the kind is `decided` — the server's word
    // — while the WAY it went is carried separately.
    await loadHistory([
      {
        revision: 1,
        at: "2026-10-08T04:25:26Z",
        status: "changes_requested",
        event: "decided",
      },
    ])
    const events = snapshot().events
    expect(events).toHaveLength(1)
    expect(events[0].kind).toBe("decided")
    expect(events[0].direction).toBe("changes_requested")
  })

  it("carries an approval as its own direction, not as a different event", async () => {
    await loadHistory([
      { revision: 1, at: "2026-10-08T05:00:00Z", status: "approved", event: "decided" },
    ])
    expect(snapshot().events[0].kind).toBe("decided")
    expect(snapshot().events[0].direction).toBe("approved")
  })

  it("keeps `revised` and drops the events it cannot name", async () => {
    // `revised` is the student's resubmit. `backfilled`/`class_assigned` are
    // bookkeeping and are in the vocabulary, but an unknown string must be
    // dropped rather than crash — the server may add one before this does.
    await loadHistory([
      { revision: 1, at: "2026-10-08T04:00:00Z", status: "submitted", event: "submitted" },
      { revision: 2, at: "2026-10-08T06:00:00Z", status: "submitted", event: "revised" },
      { revision: 2, at: "2026-10-08T07:00:00Z", status: "submitted", event: "something_new" },
    ])
    expect(snapshot().events.map((e) => e.kind)).toEqual(["submitted", "revised"])
  })

  it("does not invent events when history is empty", async () => {
    await loadHistory([])
    expect(snapshot().events).toEqual([])
  })
})
