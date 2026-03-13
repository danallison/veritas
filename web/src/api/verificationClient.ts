import type {
  VolunteerPool,
  PoolMember,
  CreatePoolRequest,
  JoinPoolRequest,
  Verification,
  SubmitVerificationRequest,
  RecordSubmissionRequest,
  CacheEntry,
  CacheStats,
} from './verificationTypes'
import { get, post, ApiError } from './fetch'

const verificationApi = {
  // Pool management
  createPool: (req: CreatePoolRequest) =>
    post<VolunteerPool>('/pools', req),

  getPool: (id: string) =>
    get<VolunteerPool>(`/pools/${id}`),

  listPools: () =>
    get<VolunteerPool[]>('/pools'),

  joinPool: (poolId: string, req: JoinPoolRequest) =>
    post<PoolMember>(`/pools/${poolId}/join`, req),

  getMembers: (poolId: string) =>
    get<PoolMember[]>(`/pools/${poolId}/members`),

  // Verification
  submitVerification: (req: SubmitVerificationRequest) =>
    post<Verification>('/verify', req),

  getVerification: (id: string) =>
    get<Verification>(`/verify/${id}`),

  listVerifications: () =>
    get<Verification[]>('/verify'),

  recordSubmission: (verificationId: string, req: RecordSubmissionRequest) =>
    post<Verification>(`/verify/${verificationId}/submit`, req),

  // Cache
  lookupCache: (fingerprint: string) =>
    get<CacheEntry>(`/cache/${encodeURIComponent(fingerprint)}`),

  getCacheStats: () =>
    get<CacheStats>('/cache/stats'),

  listCache: () =>
    get<CacheEntry[]>('/cache'),
}

export { verificationApi, ApiError }
