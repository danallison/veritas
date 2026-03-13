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
import { get, post, ApiError } from './fetch'

const api = {
  createCeremony: (req: CreateCeremonyRequest) =>
    post<CeremonyResponse>('/ceremonies', req),

  getCeremony: (id: string) =>
    get<CeremonyResponse>(`/ceremonies/${id}`),

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
