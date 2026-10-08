import { beforeEach, describe, expect, it, vi } from "vitest"
import { ApiError, apiFetch } from "@/data/api"

/**
 * `apiFetch` is the only place web-ui talks to the server, so every branch in
 * it is a decision that shows up on screen. These tests pin the branches that
 * were each written in response to something that had gone wrong.
 */

function respond(body: string, init: ResponseInit = {}) {
  return new Response(body, {
    status: 200,
    headers: { "Content-Type": "application/json" },
    ...init,
  })
}

/** The options the fetch under test was called with. */
function lastCall(mock: ReturnType<typeof vi.fn>): [string, RequestInit] {
  return mock.mock.calls.at(-1) as [string, RequestInit]
}

describe("apiFetch", () => {
  let fetchMock: ReturnType<typeof vi.fn>

  beforeEach(() => {
    fetchMock = vi.fn()
    vi.stubGlobal("fetch", fetchMock)
  })

  it("always sends credentials, because the session is an HttpOnly cookie", async () => {
    // Without `credentials: "include"` the browser sends an ANONYMOUS request
    // and every route looks like it is rejecting a valid session — a bug that
    // reads as a server permission problem.
    fetchMock.mockResolvedValue(respond('{"ok":true}'))
    await apiFetch("/submissions")
    expect(lastCall(fetchMock)[1].credentials).toBe("include")
  })

  it("sends a JSON content-type only when there IS a body", async () => {
    // A Response body can be read ONCE, so each call needs its own.
    fetchMock.mockImplementation(async () => respond("{}"))
    await apiFetch("/submissions")
    // A GET with `Content-Type: application/json` and no body is a lie the
    // server may act on.
    expect(lastCall(fetchMock)[1].headers).not.toHaveProperty("Content-Type")

    await apiFetch("/submissions", { method: "POST", body: { group: "Nhom 1" } })
    expect(lastCall(fetchMock)[1].headers).toHaveProperty("Content-Type", "application/json")
    expect(lastCall(fetchMock)[1].body).toBe('{"group":"Nhom 1"}')
  })

  it("sends the class write key as X-Class-Key", async () => {
    fetchMock.mockResolvedValue(respond("{}"))
    await apiFetch("/submissions/1/decision", { method: "POST", body: {}, writeKey: "k-123" })
    expect(lastCall(fetchMock)[1].headers).toHaveProperty("X-Class-Key", "k-123")
  })

  it("passes the abort signal through to fetch", async () => {
    // This parameter was invented before its signature was read. A screen that
    // fetches on a URL id needs it: without it, navigating class A -> B leaves
    // whichever request answers LAST on screen, so A's rows can render under
    // B's title.
    fetchMock.mockResolvedValue(respond("{}"))
    const controller = new AbortController()
    await apiFetch("/classes/1", { signal: controller.signal })
    expect(lastCall(fetchMock)[1].signal).toBe(controller.signal)
  })

  it("rethrows an abort AS an abort, not as a server failure", async () => {
    // Wrapping this in ApiError(0) shows "Không kết nối được máy chủ" on a
    // screen the user just navigated away from — an error about a request
    // nobody is waiting for any more.
    const abort = new DOMException("The operation was aborted.", "AbortError")
    fetchMock.mockRejectedValue(abort)
    await expect(apiFetch("/classes/1")).rejects.toBe(abort)
  })

  it("reports a network failure as status 0, NOT as 401", async () => {
    // Telling the user to log in again when the proxy is down sends them to a
    // login form that cannot work either.
    fetchMock.mockRejectedValue(new TypeError("Failed to fetch"))
    const err = await apiFetch("/submissions").catch((e: unknown) => e)
    expect(err).toBeInstanceOf(ApiError)
    expect((err as ApiError).status).toBe(0)
    expect((err as ApiError).isUnauthorized).toBe(false)
  })

  it("returns undefined for a 204 instead of throwing on empty JSON", async () => {
    fetchMock.mockResolvedValue(new Response(null, { status: 204 }))
    await expect(apiFetch("/submit")).resolves.toBeUndefined()
  })

  it("carries the server's string detail into ApiError.detail", async () => {
    fetchMock.mockResolvedValue(respond('{"detail":"class_missing"}', { status: 409 }))
    const err = await apiFetch("/submissions").catch((e: unknown) => e)
    expect((err as ApiError).status).toBe(409)
    expect((err as ApiError).detail).toBe("class_missing")
  })

  it("flattens FastAPI's per-field validation array, not '[object Object]'", async () => {
    // FastAPI answers our own HTTPExceptions with a STRING and pydantic
    // failures with an ARRAY of objects. Rendering the array raw shows
    // "[object Object]" to a user.
    fetchMock.mockResolvedValue(
      respond(
        JSON.stringify({
          detail: [
            { loc: ["body", "name"], msg: "Field required", type: "missing" },
            { loc: ["body", "score"], msg: "Input should be <= 10", type: "less_than_equal" },
          ],
        }),
        { status: 422 },
      ),
    )
    const err = await apiFetch("/submissions", { method: "POST", body: {} }).catch(
      (e: unknown) => e,
    )
    expect((err as ApiError).status).toBe(422)
    expect((err as ApiError).detail).toBe("Field required; Input should be <= 10")
  })

  it("turns an HTML error page into a message, not a SyntaxError", async () => {
    // A reverse proxy answering 502 with HTML is the common case. Letting
    // JSON.parse throw here replaces a useful status with a parse error.
    fetchMock.mockResolvedValue(
      new Response("<html><body>502 Bad Gateway</body></html>", {
        status: 502,
        headers: { "Content-Type": "text/html" },
      }),
    )
    const err = await apiFetch("/submissions").catch((e: unknown) => e)
    expect(err).toBeInstanceOf(ApiError)
    expect((err as ApiError).status).toBe(502)
    expect((err as ApiError).detail).toContain("502 Bad Gateway")
  })

  it("marks a 401 as a normal branch, not a failure", async () => {
    fetchMock.mockResolvedValue(respond('{"detail":"Not authenticated"}', { status: 401 }))
    const err = await apiFetch("/me").catch((e: unknown) => e)
    expect((err as ApiError).isUnauthorized).toBe(true)
  })

  it("falls back to a status message when the body has no detail", async () => {
    fetchMock.mockResolvedValue(respond("{}", { status: 500 }))
    const err = await apiFetch("/submissions").catch((e: unknown) => e)
    expect((err as ApiError).detail).toBe("Yêu cầu thất bại (HTTP 500)")
  })
})
