import { currentStudent, currentUser } from "@/data/mockData"

/** Avatar initials: the two known accounts keep the ones their profile shows. */
export function initialsOf(name: string): string {
  if (name === currentUser.name) return currentUser.initials
  if (name === currentStudent.name) return currentStudent.initials
  return name.split(" ").map((w) => w[0]).slice(0, 2).join("").toUpperCase()
}
