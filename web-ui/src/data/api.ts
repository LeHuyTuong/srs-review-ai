/**
 * The one place web-ui talks to the server.
 *
 * ADR-0020 turned this from a mock into a client: web-ui used to keep sessions
 * in `localStorage` (`src/app/auth.ts`, mock) and every piece of state in
 * `src/data/store.ts`. Both now read from the FastAPI server the app and the
 * teacher's tool share.
 *
 * Two decisions worth stating, because both are easy to "fix" wrongly later:
 *
 * 1. **`credentials: "include"` on every request.** The session is an
 *    `HttpOnly` cookie. JavaScript cannot read it, which is the point — so it
 *    must be the BROWSER that attaches it, and a `fetch` without this option
 *    silently sends an anonymous request. In development the API lives on a
 *    different port, so `vite.config.ts` proxies `/api` (see `API_BASE`).
 *
 * 2. **Errors are typed, not stringly.** A caller that has to `catch` and then
 *    test `err.message.includes("401")` is a caller that will get it wrong. The
 *    server's `detail` is carried through as `ApiError.detail`, and the status
 *    as `ApiError.status`.
 */

/** Empty in production (same origin); `/api` in dev, proxied by Vite to the server. */
export const API_BASE = import.meta.env.VITE_API_BASE ?? "/api"

export class ApiError extends Error {
  readonly status: number
  readonly detail: string

  constructor(status: number, detail: string) {
    super(detail)
    this.name = "ApiError"
    this.status = status
    this.detail = detail
  }

  /** 401 means "no live session" — a normal branch, not a failure. */
  get isUnauthorized(): boolean {
    return this.status === 401
  }
}

type RequestOptions = {
  method?: "GET" | "POST" | "PATCH" | "DELETE"
  body?: unknown
  /** A class write key, for the routes that take one instead of a session. */
  writeKey?: string
}

/**
 * One request, one place that knows about cookies, JSON and errors.
 *
 * Returns `undefined` for a 204 and parses the body otherwise: a caller that
 * expects a body from an empty response would otherwise get a confusing
 * `SyntaxError` from `JSON.parse("")`.
 */
export async function apiFetch<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const { method = "GET", body, writeKey } = options

  const headers: Record<string, string> = {}
  if (body !== undefined) headers["Content-Type"] = "application/json"
  if (writeKey) headers["X-Class-Key"] = writeKey

  let response: Response
  try {
    response = await fetch(`${API_BASE}${path}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
      // See decision 1 above. Without this the cookie is never sent and every
      // route looks like it is rejecting a valid session.
      credentials: "include",
    })
  } catch (cause) {
    // A network failure is NOT a 401: telling the user to log in again when the
    // proxy is simply down sends them to a login form that cannot work either.
    throw new ApiError(0, `Không kết nối được máy chủ. ${(cause as Error).message}`)
  }

  if (response.status === 204) return undefined as T

  const text = await response.text()
  let payload: unknown = null
  if (text) {
    try {
      payload = JSON.parse(text)
    } catch {
      // A non-JSON body from a reverse proxy (an HTML error page is the usual
      // one) must not become a confusing SyntaxError.
      payload = { detail: text.slice(0, 200) }
    }
  }

  if (!response.ok) {
    const detail = extractDetail(payload, response.status)
    throw new ApiError(response.status, detail)
  }
  return payload as T
}

function extractDetail(payload: unknown, status: number): string {
  if (payload && typeof payload === "object" && "detail" in payload) {
    const detail = (payload as { detail: unknown }).detail
    // FastAPI returns a STRING for our own HTTPExceptions and an ARRAY of
    // per-field objects for pydantic validation failures. Both happen on this
    // API, and showing "[object Object]" to a user is the failure to avoid.
    if (typeof detail === "string") return detail
    if (Array.isArray(detail)) {
      return detail
        .map((d) => (typeof d === "object" && d && "msg" in d ? String((d as { msg: unknown }).msg) : String(d)))
        .join("; ")
    }
  }
  return `Yêu cầu thất bại (HTTP ${status})`
}
