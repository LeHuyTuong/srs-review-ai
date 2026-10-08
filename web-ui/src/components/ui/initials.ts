/**
 * Avatar initials for any display name.
 *
 * This used to import two hardcoded accounts from `mockData` and return their
 * stored initials — a function whose answer never depended on its argument for
 * the only two names the app could ever show. The derivation below was already
 * correct and already the fallback; the special cases were the mock, and with
 * real accounts (ADR-0020) there is no fixed pair left to special-case.
 */
export function initialsOf(name: string): string {
  return name
    .split(" ")
    .filter(Boolean)
    .map((w) => w[0])
    .slice(0, 2)
    .join("")
    .toUpperCase()
}
