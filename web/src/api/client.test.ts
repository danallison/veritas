import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'

// Set VITE_API_BASE before importing the client module
const TEST_BASE = 'http://test-api.example.com'

beforeEach(() => {
  vi.stubEnv('VITE_API_BASE', TEST_BASE)
})

afterEach(() => {
  vi.unstubAllEnvs()
  vi.restoreAllMocks()
})

// Dynamic import so env var is picked up
async function loadClient() {
  // Reset module cache so BASE is re-evaluated
  vi.resetModules()
  const mod = await import('./client')
  return mod
}

function mockFetch(response: { ok: boolean; status: number; body: unknown }) {
  const fn = vi.fn().mockResolvedValue({
    ok: response.ok,
    status: response.status,
    text: () => Promise.resolve(
      typeof response.body === 'string' ? response.body : JSON.stringify(response.body)
    ),
  })
  vi.stubGlobal('fetch', fn)
  return fn
}

describe('API client request function', () => {
  it('GET sends correct URL and no body', async () => {
    const fetchMock = mockFetch({ ok: true, status: 200, body: { status: 'ok' } })
    const { api } = await loadClient()

    await api.health()

    expect(fetchMock).toHaveBeenCalledOnce()
    const [url, opts] = fetchMock.mock.calls[0]
    expect(url).toBe(`${TEST_BASE}/health`)
    expect(opts.method).toBe('GET')
    expect(opts.body).toBeUndefined()
  })

  it('GET does not send Content-Type header', async () => {
    const fetchMock = mockFetch({ ok: true, status: 200, body: { status: 'ok' } })
    const { api } = await loadClient()

    await api.health()

    const [, opts] = fetchMock.mock.calls[0]
    expect(opts.headers).toBeUndefined()
  })

  it('POST sends correct URL, Content-Type, and JSON body', async () => {
    const fetchMock = mockFetch({ ok: true, status: 200, body: { id: '123', phase: 'Pending' } })
    const { api } = await loadClient()

    const reqBody = {
      question: 'Who goes first?',
      ceremony_type: { tag: 'CoinFlip' as const, contents: ['Heads', 'Tails'] as [string, string] },
      entropy_method: 'ParticipantReveal' as const,
      required_parties: 2,
      commitment_mode: 'Immediate' as const,
      commit_deadline: '2026-03-01T00:00:00Z',
    }
    await api.createCeremony(reqBody)

    const [url, opts] = fetchMock.mock.calls[0]
    expect(url).toBe(`${TEST_BASE}/ceremonies`)
    expect(opts.method).toBe('POST')
    expect(opts.headers).toEqual({ 'Content-Type': 'application/json' })
    expect(JSON.parse(opts.body)).toEqual(reqBody)
  })

  it('successful response is parsed as JSON', async () => {
    const responseBody = { status: 'ok', version: '1.0.0' }
    mockFetch({ ok: true, status: 200, body: responseBody })
    const { api } = await loadClient()

    const result = await api.health()
    expect(result).toEqual(responseBody)
  })

  it('non-ok response throws ApiError with status and body', async () => {
    mockFetch({ ok: false, status: 404, body: 'Not Found' })
    const { api, ApiError } = await loadClient()

    const error = await api.getCeremony('nonexistent').catch((e) => e)
    expect(error).toBeInstanceOf(ApiError)
    expect(error.status).toBe(404)
    expect(error.body).toBe('Not Found')
  })

  it('VITE_API_BASE prefix is applied to all paths', async () => {
    const fetchMock = mockFetch({ ok: true, status: 200, body: [] })
    const { api } = await loadClient()

    await api.listCeremonies()

    const [url] = fetchMock.mock.calls[0]
    expect((url as string).startsWith(TEST_BASE)).toBe(true)
  })
})

describe('API method paths', () => {
  it('getCeremony constructs /ceremonies/{id}', async () => {
    const fetchMock = mockFetch({ ok: true, status: 200, body: {} })
    const { api } = await loadClient()

    await api.getCeremony('abc-123')

    const [url] = fetchMock.mock.calls[0]
    expect(url).toBe(`${TEST_BASE}/ceremonies/abc-123`)
  })

  it('commit constructs /ceremonies/{id}/commit', async () => {
    const fetchMock = mockFetch({ ok: true, status: 200, body: {} })
    const { api } = await loadClient()

    await api.commit('abc-123', { participant_id: 'p1' })

    const [url] = fetchMock.mock.calls[0]
    expect(url).toBe(`${TEST_BASE}/ceremonies/abc-123/commit`)
  })

  it('verify constructs /ceremonies/{id}/verify', async () => {
    const fetchMock = mockFetch({ ok: true, status: 200, body: {} })
    const { api } = await loadClient()

    await api.verify('abc-123')

    const [url] = fetchMock.mock.calls[0]
    expect(url).toBe(`${TEST_BASE}/ceremonies/abc-123/verify`)
  })

  it('listCeremonies with phase filter adds query param', async () => {
    const fetchMock = mockFetch({ ok: true, status: 200, body: [] })
    const { api } = await loadClient()

    await api.listCeremonies('Pending')

    const [url] = fetchMock.mock.calls[0]
    expect(url).toBe(`${TEST_BASE}/ceremonies?phase=Pending`)
  })

  it('randomInt includes min and max query params', async () => {
    const fetchMock = mockFetch({ ok: true, status: 200, body: { result: 5, min: 1, max: 10 } })
    const { api } = await loadClient()

    await api.randomInt(1, 10)

    const [url] = fetchMock.mock.calls[0]
    expect(url).toBe(`${TEST_BASE}/random/integer?min=1&max=10`)
  })
})
