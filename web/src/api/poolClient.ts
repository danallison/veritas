// Typed fetch client for pool computing API endpoints

import type {
  CreatePoolRequest,
  PoolResponse,
  JoinPoolRequest,
  PoolMemberResponse,
  SubmitComputeRequest,
  ValidationRoundResponse,
  SubmitSealRequest,
  RoundStatusResponse,
  SubmitRevealRequest,
  RoundDetailResponse,
  SealDetailResponse,
  CacheEntryResponse,
} from './poolTypes'

const BASE = import.meta.env.VITE_API_BASE ?? '/api'

class PoolApiError extends Error {
  constructor(public status: number, public body: string) {
    super(`Pool API ${status}: ${body}`)
  }
}

async function request<T>(method: string, path: string, body?: unknown): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: body ? { 'Content-Type': 'application/json' } : undefined,
    body: body ? JSON.stringify(body) : undefined,
  })
  const text = await res.text()
  if (!res.ok) throw new PoolApiError(res.status, text)
  return JSON.parse(text) as T
}

export const poolApi = {
  createPool: (req: CreatePoolRequest) =>
    request<PoolResponse>('POST', '/pools', req),

  getPool: (id: string) =>
    request<PoolResponse>('GET', `/pools/${id}`),

  joinPool: (poolId: string, req: JoinPoolRequest) =>
    request<PoolMemberResponse>('POST', `/pools/${poolId}/join`, req),

  listMembers: (poolId: string) =>
    request<PoolMemberResponse[]>('GET', `/pools/${poolId}/members`),

  queryCache: async (poolId: string, fingerprint: string): Promise<CacheEntryResponse | null> => {
    try {
      return await request<CacheEntryResponse>('GET', `/pools/${poolId}/cache/${fingerprint}`)
    } catch (e) {
      if (e instanceof PoolApiError && e.status === 404) return null
      throw e
    }
  },

  listCacheEntries: (poolId: string) =>
    request<CacheEntryResponse[]>('GET', `/pools/${poolId}/cache`),

  submitCompute: (poolId: string, req: SubmitComputeRequest) =>
    request<ValidationRoundResponse>('POST', `/pools/${poolId}/compute`, req),

  listRounds: (poolId: string) =>
    request<ValidationRoundResponse[]>('GET', `/pools/${poolId}/rounds`),

  getRoundStatus: (poolId: string, roundId: string) =>
    request<RoundStatusResponse>('GET', `/pools/${poolId}/rounds/${roundId}`),

  getRoundDetail: (poolId: string, roundId: string) =>
    request<RoundDetailResponse>('GET', `/pools/${poolId}/rounds/${roundId}/detail`),

  listSeals: (poolId: string, roundId: string) =>
    request<SealDetailResponse[]>('GET', `/pools/${poolId}/rounds/${roundId}/seals`),

  submitSeal: (poolId: string, roundId: string, req: SubmitSealRequest) =>
    request<RoundStatusResponse>('POST', `/pools/${poolId}/rounds/${roundId}/seal`, req),

  submitReveal: (poolId: string, roundId: string, req: SubmitRevealRequest) =>
    request<RoundStatusResponse>('POST', `/pools/${poolId}/rounds/${roundId}/reveal`, req),
}

export { PoolApiError }
