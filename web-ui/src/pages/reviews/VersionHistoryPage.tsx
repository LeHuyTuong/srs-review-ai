import { History } from "lucide-react"
import ReviewContextCard from "@/components/review/ReviewContextCard"
import VersionCard from "@/components/review/VersionCard"
import BackLink from "@/components/ui/BackLink"
import Badge from "@/components/ui/Badge"
import Button from "@/components/ui/Button"
import Card from "@/components/ui/Card"
import EmptyState from "@/components/ui/EmptyState"
import MetaGrid from "@/components/ui/MetaGrid"
import Notice from "@/components/ui/Notice"
import PageHeading from "@/components/ui/PageHeading"
import SectionHeader from "@/components/ui/SectionHeader"
import { documentVersions, versionChanges } from "@/data/mockData"
import useReviewFromParams from "./useReviewFromParams"

export default function VersionHistoryPage() {
  const { reviewId, review } = useReviewFromParams()
  if (!review) return <EmptyState title="Không tìm thấy yêu cầu review" />
  const versions = documentVersions.filter((v) => v.reviewId === reviewId)

  return (
    <>
      <BackLink label="Tài liệu Project" fallback={`/projects/${review.projectId}/documents`} />
      <PageHeading title="Lịch sử version" description="Theo dõi từng lần nộp và nội dung đã chỉnh sửa." />
      <ReviewContextCard context={`${review.classCode} · ${review.groupName}`} version={review.version} projectName={review.projectName} documentTitle={review.documentTitle} status={versions.at(-1)?.status ?? review.status}>
        <MetaGrid items={[{ label: "Người nộp", value: review.submitter }, { label: "Ngày gửi", value: review.submittedAt }]} />
      </ReviewContextCard>
      <Notice>Mỗi lần nộp lại tạo một version mới. Tất cả version và feedback trước đó được lưu giữ.</Notice>

      <section className="flex flex-col gap-3">
        <SectionHeader title="Các lần nộp" meta={`${versions.length} version`} />
        {versions.length ? versions.map((v) => <VersionCard key={v.id} version={v} />) : <EmptyState title="Chưa có version trước" description="Đây là lần nộp đầu tiên của tài liệu." />}
      </section>

      {versions.length > 1 && (
        <section className="flex flex-col gap-3">
          <SectionHeader title="So sánh version" />
          <Card>
            <div className="flex flex-wrap gap-2">
              <Badge>Version cũ: v2</Badge>
              <Badge tone="brand">Version mới: v3</Badge>
            </div>
            <p className="text-[14px] font-semibold text-ink">So sánh v2 với v3</p>
            <div className="flex flex-wrap gap-2">
              <Badge tone="brand">2 bổ sung</Badge>
              <Badge tone="amber">1 chỉnh sửa</Badge>
              <Badge>0 xóa</Badge>
            </div>
            <p className="text-[12px] text-muted">{review.documentTitle} · {review.submitter}</p>
            {versionChanges.map((c) => (
              <div key={c.title} className="flex flex-col gap-2 border-t border-line pt-3">
                <p className="text-[13px] font-semibold text-ink">{c.title}</p>
                {c.before && (
                  <div className="rounded-[8px] bg-danger-soft p-2.5 text-[12px] leading-[1.45]">
                    <p className="text-[10px] font-semibold text-danger">TRƯỚC · v2</p>
                    <p className="text-ink">{c.before}</p>
                  </div>
                )}
                <div className="rounded-[8px] bg-brand-soft p-2.5 text-[12px] leading-[1.45]">
                  <p className="text-[10px] font-semibold text-brand">SAU · v3</p>
                  <p className="text-ink">{c.after}</p>
                </div>
                <p className="text-[12px] text-muted">{c.note}</p>
              </div>
            ))}
          </Card>
        </section>
      )}
      <Button variant="secondary" to={`/reviews/${review.id}/history`} icon={<History size={18} strokeWidth={1.75} />}>Xem lịch sử review</Button>
    </>
  )
}
