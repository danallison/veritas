import { describe, it, expect, beforeEach } from 'vitest'
import { renderHook, act } from '@testing-library/react'
import { useCeremonySecrets } from './useCeremonySecrets'

beforeEach(() => {
  sessionStorage.clear()
})

describe('useCeremonySecrets', () => {
  const ceremonyId = 'test-ceremony-001'

  it('getSecrets returns null when nothing is stored', () => {
    const { result } = renderHook(() => useCeremonySecrets(ceremonyId))
    expect(result.current.getSecrets()).toBeNull()
  })

  it('saveSecrets + getSecrets round-trips correctly (with entropy)', () => {
    const { result } = renderHook(() => useCeremonySecrets(ceremonyId))
    const secrets = { entropy: 'aabb', seal: 'ccdd', committed: true }

    act(() => {
      result.current.saveSecrets(secrets)
    })

    expect(result.current.getSecrets()).toEqual(secrets)
  })

  it('saveSecrets + getSecrets round-trips correctly (without entropy)', () => {
    const { result } = renderHook(() => useCeremonySecrets(ceremonyId))
    const secrets = { committed: true }

    act(() => {
      result.current.saveSecrets(secrets)
    })

    expect(result.current.getSecrets()).toEqual(secrets)
  })

  it('storage key includes ceremony ID (veritas_secret_{id})', () => {
    const { result } = renderHook(() => useCeremonySecrets(ceremonyId))
    const secrets = { entropy: '1234', seal: '5678', committed: true }

    act(() => {
      result.current.saveSecrets(secrets)
    })

    const raw = sessionStorage.getItem(`veritas_secret_${ceremonyId}`)
    expect(raw).not.toBeNull()
    expect(JSON.parse(raw!)).toEqual(secrets)
  })

  it('clearSecrets removes the stored value', () => {
    const { result } = renderHook(() => useCeremonySecrets(ceremonyId))
    const secrets = { entropy: 'aabb', seal: 'ccdd', committed: true }

    act(() => {
      result.current.saveSecrets(secrets)
    })
    expect(result.current.getSecrets()).not.toBeNull()

    act(() => {
      result.current.clearSecrets()
    })
    expect(result.current.getSecrets()).toBeNull()
  })

  it('different ceremony IDs are isolated', () => {
    const { result: hookA } = renderHook(() => useCeremonySecrets('ceremony-a'))
    const { result: hookB } = renderHook(() => useCeremonySecrets('ceremony-b'))

    const secretsA = { entropy: 'aaaa', seal: 'bbbb', committed: true }
    const secretsB = { entropy: 'cccc', seal: 'dddd', committed: true }

    act(() => {
      hookA.current.saveSecrets(secretsA)
      hookB.current.saveSecrets(secretsB)
    })

    expect(hookA.current.getSecrets()).toEqual(secretsA)
    expect(hookB.current.getSecrets()).toEqual(secretsB)
  })
})
