import { useEffect, useState } from "react"
import { useParams } from "react-router-dom"
import BackLink from "@/components/ui/BackLink"
import Badge from "@/components/ui/Badge"
import Card from "@/components/ui/Card"
import EmptyState from "@/components/ui/EmptyState"
import Notice from "@/components/ui/Notice"
import PageHeading from "@/components/ui/PageHeading"
import SectionHeader from "@/components/ui/SectionHeader"
import SegmentedTabs from "@/components/ui/SegmentedTabs"
import StatCard from "@/components/ui/StatCard"
import StatusBadge from "@/components/ui/StatusBadge"
import { ApiError, apiFetch } from "@/data/api"

/** Exactly what `GET /classes/{id}` returns. `submissions` is the server's
 *  member list, sorted `createdAt` DESC. */
interface ClassWire {
  id: string
  name: string
  submissions: {
    id: string
    group: string
    project: string
    revision: number
    status: string
    has_report: boolean
    score: number | null
  }[]
}

export default function ClassDetailPage() {
  const { classId } = useParams()
  const [tab, setTab] = useState("Tổng quan")
  const [data, setData] = useState<ClassWire | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  // Abort on unmount / id change: without this, switching class quickly can
  // land an older response last and show class A's rows under class B's title.
  useEffect(() => {
    if (!classId) return
    const ctl = new AbortController()
    setLoading(true)
    setError(null)
    apiFetch<ClassWire>(`/classes/${encodeURIComponent(classId)}`, { signal: ctl.signal })
      .then((wire) => {
        if (!ctl.signal.aborted) setData(wire)
      })
      .catch((e) => {
        if (!ctl.signal.aborted) setError(e instanceof ApiError ? e.detail : String(e))
      })
      .finally(() => {
        if (!ctl.signal.aborted) setLoading(false)
      })
    return () => ctl.abort()
  }, [classId])

  if (loading) {
    return (
      <>
        <BackLink label="Lớp của tôi" fallback="/classes" />
        <EmptyState title="Đang tải lớp" description="Đang đọc lớp từ máy chủ." />
      </>
    )
  }

  // The server answers 404 for both "no such class" and "not yours", on purpose
  // (ADR-0021): one answer for both means the route cannot be used to test
  // whether an id exists. The page must not invent a distinction.
  if (error || !data) {
    return (
      <>
        <BackLink label="Lớp của tôi" fallback="/classes" />
        <EmptyState
          title="Không mở được lớp"
          description={error ?? `Không tìm thấy lớp “${classId}”.`}
        />
      </>
    )
  }

  const rows = data.submissions ?? []
  // Counted, not stored. The header used to print `classRoom.groupCount`,
  // `studentCount` and `pendingReviews` straight off a fixture — three numbers
  // about a real class that no request ever returned.
  const groupCount = new Set(rows.map((r) => r.group).filter(Boolean)).size
  const waiting = rows.filter((r) => r.status === "submitted" || r.status === "resubmitted").length
  const returned = rows.filter((r) => r.status === "changes_requested").length

  return (
    <>
      <BackLink label="Lớp của tôi" fallback="/classes" />
      <PageHeading
        eyebrow="CHI TIẾT LỚP"
        title={data.name || data.id}
        description={`Mã lớp ${data.id}`}
      />
      <SegmentedTabs tabs={["Tổng quan", "Bài nộp"]} active={tab} onChange={setTab} />

      {tab === "Tổng quan" ? (
        <div className="grid grid-cols-3 gap-3">
          <StatCard value={groupCount} label="Số nhóm" />
          <StatCard value={rows.length} label="Bài nộp" />
          <StatCard value={waiting} label="Đang chờ review" />
        </div>
      ) : (
        <section className="flex flex-col gap-3">
          <SectionHeader
            title="Bài nộp của lớp"
            meta={`${rows.length} bài`}
            description="Mới nhất trước, theo máy chủ sắp xếp."
          />
          {rows.length === 0 ? (
            <EmptyState title="Chưa có bài nộp" description="Lớp này chưa có bài nào." />
          ) : (
            <Card className="gap-0 py-1">
              <ul>
                {rows.map((row) => (
                  <li key={row.id} className="flex items-center gap-3 border-b border-line py-3 last:border-b-0">
                    <span className="flex min-w-0 flex-1 flex-col items-start gap-1 leading-[1.45]">
                      <span className="text-[14px] font-semibold text-ink">{row.project}</span>
                      <span className="text-[12px] text-muted">
                        {row.group} · vòng {row.revision}
                      </span>
                    </span>
                    {returned > 0 && row.status === "changes_requested" ? (
                      <Badge tone="rust">Cần sửa</Badge>
                    ) : null}
                    <StatusBadge status={row.status} />
                  </li>
                ))}
              </ul>
            </Card>
          )}
        </section>
      )}

      <Notice>
        Điểm và báo cáo AI của từng bài nằm trong bài nộp đó; trang này chỉ liệt kê.
      </Notice>
    </>
  )
}
