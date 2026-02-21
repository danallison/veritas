import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { renderHook, waitFor, act } from '@testing-library/react'
import { useCeremony } from './useCeremony'
import type { CeremonyResponse } from '../api/types'

vi.mock('../api/client', () => ({
  api: {
    getCeremony: vi.fn(),
  },
}))

import { api } from '../api/client'

const mockGetCeremony = vi.mocked(api.getCeremony)

function makeCeremony(overrides: Partial<CeremonyResponse> = {}): CeremonyResponse {
  return {
    id: 'test-id',
    question: 'Who goes first?',
    ceremony_type: { tag: 'CoinFlip' },
    entropy_method: 'OfficiantVRF',
    required_parties: 2,
    commitment_mode: 'Immediate',
    commit_deadline: '2026-12-01T00:00:00Z',
    reveal_deadline: null,
    non_participation_policy: null,
    beacon_spec: null,
    phase: 'Pending',
    created_by: 'creator-id',
    created_at: '2026-01-01T00:00:00Z',
    commitment_count: 0,
    committed_participants: [],
    ...overrides,
  }
}

beforeEach(() => {
  vi.clearAllMocks()
})

afterEach(() => {
  vi.restoreAllMocks()
  vi.useRealTimers()
})

describe('useCeremony', () => {
  it('fetches on mount and sets loading to false', async () => {
    const ceremony = makeCeremony({ phase: 'Finalized' })
    mockGetCeremony.mockResolvedValue(ceremony)

    const { result } = renderHook(() => useCeremony('test-id'))

    expect(result.current.loading).toBe(true)

    await waitFor(() => {
      expect(result.current.loading).toBe(false)
      expect(result.current.ceremony).toEqual(ceremony)
      expect(result.current.error).toBeNull()
    })
  })

  it('sets error when fetch fails', async () => {
    mockGetCeremony.mockRejectedValue(new Error('Network failure'))

    const { result } = renderHook(() => useCeremony('test-id'))

    await waitFor(() => {
      expect(result.current.loading).toBe(false)
      expect(result.current.error).toBe('Network failure')
      expect(result.current.ceremony).toBeNull()
    })
  })

  it('does not fetch when id is undefined', async () => {
    const { result } = renderHook(() => useCeremony(undefined))

    // Give effect a chance to run
    await new Promise((r) => setTimeout(r, 50))

    expect(mockGetCeremony).not.toHaveBeenCalled()
    expect(result.current.loading).toBe(true)
  })

  it('stops polling on terminal phase (Finalized)', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true })
    mockGetCeremony.mockResolvedValue(makeCeremony({ phase: 'Finalized' }))

    renderHook(() => useCeremony('test-id', 1000))

    await waitFor(() => {
      expect(mockGetCeremony).toHaveBeenCalledTimes(1)
    })

    // Advance past several poll intervals
    await act(async () => {
      await vi.advanceTimersByTimeAsync(5000)
    })

    // Should still be just 1 call (no polling for terminal phase)
    expect(mockGetCeremony).toHaveBeenCalledTimes(1)
  })

  it('continues polling on non-terminal phase', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true })
    mockGetCeremony.mockResolvedValue(makeCeremony({ phase: 'Pending' }))

    renderHook(() => useCeremony('test-id', 1000))

    await waitFor(() => {
      expect(mockGetCeremony).toHaveBeenCalledTimes(1)
    })

    // Advance through poll intervals
    await act(async () => {
      await vi.advanceTimersByTimeAsync(3500)
    })

    // Should have polled multiple times
    expect(mockGetCeremony.mock.calls.length).toBeGreaterThan(1)
  })

  it('refetch() updates data', async () => {
    const ceremony1 = makeCeremony({ phase: 'Finalized', commitment_count: 1 })
    const ceremony2 = makeCeremony({ phase: 'Finalized', commitment_count: 3 })
    mockGetCeremony.mockResolvedValueOnce(ceremony1).mockResolvedValueOnce(ceremony2)

    const { result } = renderHook(() => useCeremony('test-id'))

    await waitFor(() => {
      expect(result.current.ceremony?.commitment_count).toBe(1)
    })

    await act(async () => {
      await result.current.refetch()
    })

    expect(result.current.ceremony?.commitment_count).toBe(3)
  })

  it('cleans up on unmount (no errors after unmount)', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true })
    mockGetCeremony.mockResolvedValue(makeCeremony({ phase: 'Pending' }))

    const { unmount } = renderHook(() => useCeremony('test-id', 1000))

    await waitFor(() => {
      expect(mockGetCeremony).toHaveBeenCalledTimes(1)
    })

    // Unmount should not throw
    unmount()

    // Advance timers — should not cause errors
    await act(async () => {
      await vi.advanceTimersByTimeAsync(5000)
    })
  })
})
