import type {
  CreateCeremonyRequest,
  CeremonyResponse,
  CommitRequest,
  CommitResponse,
  RevealRequest,
  RevealResponse,
  OutcomeResponse,
  AuditLogResponse,
  VerifyResponse,
  RandomCoinResponse,
  RandomIntResponse,
  RandomUUIDResponse,
  HealthResponse,
  BeaconVerificationGuideResponse,
  JoinRequest,
  JoinResponse,
  AckRosterRequest,
  AckRosterResponse,
  RosterResponse,
} from './types'

const BASE = import.meta.env.VITE_API_BASE ?? '/api'

class ApiError extends Error {
  constructor(public status: number, public body: string) {
    super(`API ${status}: ${body}`)
  }
}

async function request<T>(method: string, path: string, body?: unknown): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: body ? { 'Content-Type': 'application/json' } : undefined,
    body: body ? JSON.stringify(body) : undefined,
  })
  const text = await res.text()
  if (!res.ok) throw new ApiError(res.status, text)
  return JSON.parse(text) as T
}

function get<T>(path: string) { return request<T>('GET', path) }
function post<T>(path: string, body: unknown) { return request<T>('POST', path, body) }

const api = {
  createCeremony: (req: CreateCeremonyRequest) =>
    post<CeremonyResponse>('/ceremonies', req),

  getCeremony: (id: string) =>
    get<CeremonyResponse>(`/ceremonies/${id}`),

  listCeremonies: (phase?: string) =>
    get<CeremonyResponse[]>(`/ceremonies${phase ? `?phase=${phase}` : ''}`),

  join: (id: string, req: JoinRequest) =>
    post<JoinResponse>(`/ceremonies/${id}/join`, req),

  ackRoster: (id: string, req: AckRosterRequest) =>
    post<AckRosterResponse>(`/ceremonies/${id}/ack-roster`, req),

  getRoster: (id: string) =>
    get<RosterResponse>(`/ceremonies/${id}/roster`),

  commit: (id: string, req: CommitRequest) =>
    post<CommitResponse>(`/ceremonies/${id}/commit`, req),

  reveal: (id: string, req: RevealRequest) =>
    post<RevealResponse>(`/ceremonies/${id}/reveal`, req),

  getOutcome: (id: string) =>
    get<OutcomeResponse>(`/ceremonies/${id}/outcome`),

  getAuditLog: (id: string) =>
    get<AuditLogResponse>(`/ceremonies/${id}/log`),

  verify: (id: string) =>
    get<VerifyResponse>(`/ceremonies/${id}/verify`),

  flipCoin: () =>
    get<RandomCoinResponse>('/random/coin'),

  randomInt: (min: number, max: number) =>
    get<RandomIntResponse>(`/random/integer?min=${min}&max=${max}`),

  randomUUID: () =>
    get<RandomUUIDResponse>('/random/uuid'),

  health: () =>
    get<HealthResponse>('/health'),

  getBeaconVerificationGuide: () =>
    get<BeaconVerificationGuideResponse>('/verify/beacon'),
}

export { api, ApiError }
