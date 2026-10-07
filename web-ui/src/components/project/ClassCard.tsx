import { ChevronRight } from "lucide-react"
import Badge from "@/components/ui/Badge"
import Button from "@/components/ui/Button"
import Card from "@/components/ui/Card"
import type { ClassRoom } from "@/types"

export default function ClassCard({ classRoom }: { classRoom: ClassRoom }) {
  return (
    <Card>
      <div className="flex items-center justify-between gap-3">
        <span className="text-[17px] font-semibold text-ink">{classRoom.code}</span>
        <Badge tone="brand">Đang giảng dạy</Badge>
      </div>
      <div className="leading-[1.45]">
        <p className="text-[14px] font-semibold text-ink">{classRoom.subject}</p>
        <p className="text-[12px] text-muted">{classRoom.semester} · Giảng viên {classRoom.lecturer}</p>
      </div>
      <div className="grid grid-cols-3 gap-2 text-[12px] text-muted">
        <span>{classRoom.groupCount} nhóm</span>
        <span>{classRoom.studentCount} sinh viên</span>
        <span>{classRoom.projectCount} project</span>
      </div>
      <Badge tone={classRoom.pendingReviews > 0 ? "amber" : "neutral"}>{classRoom.pendingReviews} tài liệu đang chờ review</Badge>
      <Button variant="secondary" to={`/classes/${classRoom.id}`} className="flex-row-reverse">
        <ChevronRight size={18} strokeWidth={1.75} />
        Xem lớp
      </Button>
    </Card>
  )
}
