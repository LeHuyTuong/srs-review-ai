import { ChevronLeft } from "lucide-react"
import { useNavigate } from "react-router-dom"

export default function BackLink({ label, fallback }: { label: string; fallback: string }) {
  const navigate = useNavigate()
  const goBack = () => (window.history.state?.idx > 0 ? navigate(-1) : navigate(fallback))
  return (
    <button type="button" onClick={goBack} className="-ml-1 flex items-center gap-1 self-start text-[13px] font-medium text-muted">
      <ChevronLeft size={18} strokeWidth={1.75} />
      {label}
    </button>
  )
}
