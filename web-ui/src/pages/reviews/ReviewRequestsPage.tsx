import { useState } from "react"
import ReviewRequestCard from "@/components/review/ReviewRequestCard"
import Badge from "@/components/ui/Badge"
import EmptyState from "@/components/ui/EmptyState"
import Notice from "@/components/ui/Notice"
import PageHeading from "@/components/ui/PageHeading"
import SearchInput from "@/components/ui/SearchInput"
import SectionHeader from "@/components/ui/SectionHeader"
import SegmentedTabs from "@/components/ui/SegmentedTabs"
import { reviewsOf, useStore } from "@/data/store"
import type { DocumentStatus } from "@/types"

const waiting: DocumentStatus[] = ["submitted", "resubmitted"]
// `rejected` was never a server decision. Its worst verdict is
// `changes_requested` — "please change this" — and there is no way to express
// "failed", so a filter that claimed to find rejected work was offering a
// result set that cannot be non-empty.
const returned: DocumentStatus[] = ["changes_requested"]
const done: DocumentStatus[] = ["approved"]
const filterChips = ["Lớp", "Nhóm", "Project", "Loại tài liệu", "Trạng thái", "Kết quả AI Review", "Ngày gửi"]

export default function ReviewRequestsPage() {
  const reviews = reviewsOf(useStore())
  const count = (list: DocumentStatus[]) => reviews.filter((r) => list.includes(r.status)).length
  const tabs = [`Đang chờ (${count(waiting)})`, `Cần chỉnh sửa (${count(returned)})`, `Đã hoàn tất (${count(done)})`]
  const [index, setIndex] = useState(0)
  const active = [waiting, returned, done][index]
  const items = reviews.filter((r) => active.includes(r.status))

  return (
    <>
      <PageHeading eyebrow="KHÔNG GIAN REVIEW" title="Yêu cầu review" description="Quản lý các tài liệu sinh viên đang chờ giảng viên review." />
      <SegmentedTabs tabs={tabs} active={tabs[index]} onChange={(t) => setIndex(tabs.indexOf(t))} />
      <div className="flex flex-col gap-3">
        <SearchInput placeholder="Tìm project hoặc tài liệu..." />
        <div className="flex flex-wrap gap-2">
          {filterChips.map((c) => <Badge key={c}>{c}</Badge>)}
        </div>
      </div>
      <section className="flex flex-col gap-3">
        <SectionHeader title={`${items.length} yêu cầu`} meta="Mới nhất" />
        <Notice>Chỉ hiển thị tài liệu đã nộp và đã gửi yêu cầu review. AI không tự phê duyệt tài liệu.</Notice>
        {items.length ? items.map((r) => <ReviewRequestCard key={r.id} review={r} />) : <EmptyState title="Không có yêu cầu" description="Chưa có tài liệu nào ở trạng thái này." />}
      </section>
    </>
  )
}
