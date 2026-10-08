import BackLink from "@/components/ui/BackLink"
import Card from "@/components/ui/Card"
import PageHeading from "@/components/ui/PageHeading"
import SectionHeader from "@/components/ui/SectionHeader"

/**
 * The teacher's classes.
 *
 * This page used to render `classes` from `mockData` under a heading reading
 * "3 lớp đang phụ trách", with a "Học kỳ: Fall 2026" badge and the footer
 * "18 project · 81 sinh viên trong học kỳ này" — four invented facts about the
 * teacher's own job, dressed as a dashboard.
 *
 * It cannot be wired up yet, and saying why is the honest version rather than
 * another mock. The server can read ONE class by id (`GET /classes/{id}`), and
 * on this branch that id IS the credential (ADR-0016): there is no route that
 * lists the classes a signed-in teacher owns, so there is nothing to render.
 * ADR-0022 adds `/roster` and a teacher-owned class scope; until that lands the
 * list has no source, and a page with no source must say so.
 */
export default function ClassListPage() {
  return (
    <>
      <BackLink label="Tổng quan" fallback="/dashboard" />
      <PageHeading
        eyebrow="QUẢN LÝ LỚP HỌC"
        title="Lớp của tôi"
        description="Danh sách lớp gắn với tài khoản giảng viên."
      />
      <section className="flex flex-col gap-3">
        <SectionHeader title="Chưa có nguồn dữ liệu" />
        <Card>
          <p className="text-[13px] leading-[1.45] text-ink">
            Máy chủ hiện chỉ đọc được <strong>một</strong> lớp khi biết mã lớp, và mã lớp
            chính là chìa khoá. Chưa có route liệt kê các lớp thuộc về tài khoản đang
            đăng nhập, nên trang này chưa có gì để hiển thị.
          </p>
          <p className="text-[12px] leading-[1.45] text-muted">
            Trước đây trang hiển thị ba lớp lấy từ dữ liệu mẫu cùng số liệu học kỳ được
            viết tay. Bỏ đi, vì một con số sai về lớp của chính mình thì tệ hơn một câu
            nói thật là chưa có.
          </p>
          <p className="text-[12px] leading-[1.45] text-muted">
            Bài nộp của lớp đã có thật và nằm ở trang Tổng quan, đọc theo phiên đăng nhập.
          </p>
        </Card>
      </section>
    </>
  )
}
