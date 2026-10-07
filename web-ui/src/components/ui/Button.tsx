import type { ButtonHTMLAttributes, ReactNode } from "react"
import { Link } from "react-router-dom"

type Variant = "primary" | "secondary" | "danger"

const variants: Record<Variant, string> = {
  primary: "border-brand bg-brand text-white",
  secondary: "border-line bg-white text-ink",
  danger: "border-line bg-white text-danger",
}

const base =
  "inline-flex min-h-[44px] w-full items-center justify-center gap-2 rounded-[8px] border px-[14px] py-3 text-[14px] font-semibold leading-[1.45] transition active:scale-[0.985] active:brightness-95"

interface Props extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant
  icon?: ReactNode
  to?: string
}

export default function Button({ variant = "primary", icon, to, className = "", children, ...rest }: Props) {
  const classes = `${base} ${variants[variant]} ${className}`
  if (to) {
    return (
      <Link to={to} className={classes}>
        {icon}
        {children}
      </Link>
    )
  }
  return (
    <button type="button" className={classes} {...rest}>
      {icon}
      {children}
    </button>
  )
}
