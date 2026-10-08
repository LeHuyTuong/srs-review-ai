import Badge from "./Badge"
import { documentStatusMeta } from "./statusMeta"
import type { DocumentStatus, Tone } from "@/types"

/**
 * A status pill that cannot throw.
 *
 * The lookup `documentStatusMeta[status]` was unguarded, so any value the
 * server sent that the map did not list crashed the whole page on `.label`.
 * That is not hypothetical: `submitted` (every undecided row) and `reviewed`
 * (an AI-reviewed round) were both missing when this was wired up, and both
 * were found only by running the real server.
 *
 * The status type is closed, but it is closed on the CLIENT — the value arrives
 * as a string off the wire, so a server that adds a sixth state must degrade to
 * showing that state's raw name, not blank the screen.
 */
export default function StatusBadge({ status }: { status: DocumentStatus | string }) {
  const known = documentStatusMeta[status as DocumentStatus]
  if (!known) {
    return (
      <Badge tone={"neutral" as Tone}>
        {status}
      </Badge>
    )
  }
  return <Badge tone={known.tone}>{known.label}</Badge>
}
