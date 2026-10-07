import { Search } from "lucide-react"
import Input from "./Input"

export default function SearchInput({ placeholder }: { placeholder: string }) {
  return <Input type="search" placeholder={placeholder} aria-label={placeholder} icon={<Search size={19} strokeWidth={1.75} />} />
}
