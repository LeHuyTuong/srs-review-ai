import { History } from "lucide-react"
import ReviewContextCard from "@/components/review/ReviewContextCard"
import BackLink from "@/components/ui/BackLink"
import Badge from "@/components/ui/Badge"
import Button from "@/components/ui/Button"
import Card from "@/components/ui/Card"
import EmptyState from "@/components/ui/EmptyState"
import MetaGrid from "@/components/ui/MetaGrid"
import Notice from "@/components/ui/Notice"
import PageHeading from "@/components/ui/PageHeading"
import SectionHeader from "@/components/ui/SectionHeader"
import StatusBadge from "@/components/ui/StatusBadge"
import { stamp, useStore } from "@/data/store"
import type { DocumentStatus } from "@/types"
import useReviewFromParams from "./useReviewFromParams"

export default function VersionHistoryPage() {
  const { reviewId, review } = useReviewFromParams()
  const { submission } = useStore()
  if (!review) return <EmptyState title="Không tìm thấy yêu cầu review" />

  // One entry per REVISION, taken from the submission's own `history` — the
  // same rows the server writes and every other view reads. This page used to
  // render `mockData.documentVersions`, and three parts of it were hardcoded
  // around that:
  //
  //   * `Version cũ: v2` / `Version mới: v3` — literal strings, shown for any
  //     document, including one that has only been submitted once;
  //   * `2 bổ sung · 1 chỉnh sửa · 0 xóa` — invented counts;
  //   * a before/after diff built from `mockData.versionChanges`.
  //
  // The server keeps NO content diff between rounds: it stores the round's
  // status and note, not what changed on the page. So the diff section is
  // removed rather than faked, and what remains is what actually exists —
  // which round happened, when, why, and where it ended up.
  const mine = submission && submission.id === reviewId ? submission.history : []

  const byRevision = new Map<number, { revision: number; at: string; status: string; event: string; note: string }>()
  for (const entry of mine) {
    const revision = Number(entry.revision ?? 1)
    const existing = byRevision.get(revision)
    // Later entries for the same round win: a round's status moves from
    // `submitted` to `reviewed` to decided, and the page wants where it ENDED.
    byRevision.set(revision, {
      revision,
      at: String(entry.at ?? existing?.at ?? ""),
      status: String(entry.status ?? existing?.status ?? "submitted"),
      event: String(entry.event ?? existing?.event ?? ""),
      note: String(entry.note ?? existing?.note ?? ""),
    })
  }
  const rounds = [...byRevision.values()].sort((a, b) => a.revision - b.revision)
  const current = rounds.at(-1)

  return (
    <>
      <BackLink label="Tài liệu Project" fallback={`/projects/${review.projectId}/documents`} />
      <PageHeading title="Lịch sử version" description="Theo dõi từng lần nộp và nội dung đã chỉnh sửa." />
      <ReviewContextCard
        context={`${review.classCode} · ${review.groupName}`}
        version={current ? `v${current.revision}` : review.version}
        projectName={review.projectName}
        documentTitle={review.documentTitle}
        status={(current?.status ?? review.status) as DocumentStatus}
      >
        <MetaGrid
          items={[
            { label: "Người nộp", value: review.submitter },
            { label: "Ngày gửi", value: review.submittedAt },
          ]}
        />
      </ReviewContextCard>
      <Notice>Mỗi lần nộp lại tạo một version mới. Tất cả version và feedback trước đó được lưu giữ.</Notice>

      <section className="flex flex-col gap-3">
        <SectionHeader title="Các lần nộp" meta={`${rounds.length} version`} />
        {rounds.length === 0 ? (
          <EmptyState
            title="Chưa có version"
            description="Máy chủ chưa ghi vòng nộp nào cho bài này."
          />
        ) : (
          rounds.map((r, i) => (
            <Card key={r.revision} tinted={i === rounds.length - 1}>
              <div className="flex items-center justify-between gap-3">
                <span className="text-[17px] font-semibold text-ink">
                  v{r.revision}
                  {i === rounds.length - 1 && " · Version hiện tại"}
                </span>
                <StatusBadge status={r.status} />
              </div>
              <p className="text-[12px] text-muted">{stamp(r.at)}</p>
              {r.note ? (
                <p className="text-[13px] leading-[1.45] text-ink">{r.note}</p>
              ) : (
                <p className="text-[12px] text-muted">Vòng này không kèm ghi chú.</p>
              )}
            </Card>
          ))
        )}
      </section>

      <Card tinted>
        <p className="text-[14px] font-semibold text-ink">Không so sánh nội dung giữa các vòng</p>
        <p className="text-[12px] leading-[1.45] text-muted">
          Máy chủ lưu trạng thái và ghi chú của từng vòng, không lưu nội dung tài liệu, nên
          không có gì để đối chiếu từng dòng. Cần xem nội dung thì mở bài nộp của vòng đó.
        </p>
      </Card>

      <Button
        variant="secondary"
        to={`/reviews/${review.id}/history`}
        icon={<History size={18} strokeWidth={1.75} />}
      >
        Xem lịch sử review
      </Button>
    </>
  )
}
