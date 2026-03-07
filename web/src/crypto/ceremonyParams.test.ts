// @vitest-environment node
import { describe, it, expect } from 'vitest'
import { buildCeremonyParamsBytes, computeParamsHash, verifyParamsHash } from './ceremonyParams'
import { bytesToHex } from './entropy'
import type { CeremonyResponse } from '../api/types'

function makeCeremony(overrides: Partial<CeremonyResponse> = {}): CeremonyResponse {
  return {
    id: '00000000-0000-0000-0000-000000000000',
    question: 'Who goes first?',
    ceremony_type: { tag: 'CoinFlip', contents: ['Heads', 'Tails'] },
    entropy_method: 'OfficiantVRF',
    required_parties: 2,
    commitment_mode: 'Immediate',
    commit_deadline: '2026-06-01T12:00:00Z',
    reveal_deadline: null,
    non_participation_policy: null,
    beacon_spec: null,
    identity_mode: 'SelfCertified',
    phase: 'Pending',
    created_by: '00000000-0000-0000-0000-000000000000',
    created_at: '2026-01-01T00:00:00Z',
    commitment_count: 0,
    committed_participants: [],
    roster: null,
    params_hash: '',
    ...overrides,
  }
}

describe('ceremonyParams', () => {
  describe('buildCeremonyParamsBytes', () => {
    it('starts with the version prefix', () => {
      const bytes = buildCeremonyParamsBytes(makeCeremony())
      const prefix = new TextDecoder().decode(bytes.slice(0, 18))
      expect(prefix).toBe('veritas-params-v1:')
    })

    it('is deterministic (same inputs -> same bytes)', () => {
      const c = makeCeremony()
      const b1 = buildCeremonyParamsBytes(c)
      const b2 = buildCeremonyParamsBytes(c)
      expect(bytesToHex(b1)).toBe(bytesToHex(b2))
    })

    it('different questions -> different bytes', () => {
      const b1 = buildCeremonyParamsBytes(makeCeremony({ question: 'Question A' }))
      const b2 = buildCeremonyParamsBytes(makeCeremony({ question: 'Question B' }))
      expect(bytesToHex(b1)).not.toBe(bytesToHex(b2))
    })

    it('different ceremony types -> different bytes', () => {
      const b1 = buildCeremonyParamsBytes(makeCeremony({ ceremony_type: { tag: 'CoinFlip', contents: ['Heads', 'Tails'] } }))
      const b2 = buildCeremonyParamsBytes(makeCeremony({ ceremony_type: { tag: 'UniformChoice', contents: ['A', 'B', 'C'] } }))
      expect(bytesToHex(b1)).not.toBe(bytesToHex(b2))
    })

    it('different coin flip labels -> different bytes', () => {
      const b1 = buildCeremonyParamsBytes(makeCeremony({ ceremony_type: { tag: 'CoinFlip', contents: ['Heads', 'Tails'] } }))
      const b2 = buildCeremonyParamsBytes(makeCeremony({ ceremony_type: { tag: 'CoinFlip', contents: ['Alice wins', 'Bob wins'] } }))
      expect(bytesToHex(b1)).not.toBe(bytesToHex(b2))
    })

    it('different entropy methods -> different bytes', () => {
      const b1 = buildCeremonyParamsBytes(makeCeremony({ entropy_method: 'OfficiantVRF' }))
      const b2 = buildCeremonyParamsBytes(makeCeremony({ entropy_method: 'ExternalBeacon', beacon_spec: { beaconNetwork: 'default', beaconRound: null, beaconFallback: { tag: 'CancelCeremony' } } }))
      expect(bytesToHex(b1)).not.toBe(bytesToHex(b2))
    })

    it('different required parties -> different bytes', () => {
      const b1 = buildCeremonyParamsBytes(makeCeremony({ required_parties: 2 }))
      const b2 = buildCeremonyParamsBytes(makeCeremony({ required_parties: 3 }))
      expect(bytesToHex(b1)).not.toBe(bytesToHex(b2))
    })

    it('does not depend on mutable fields (phase, id, created_by, created_at)', () => {
      const b1 = buildCeremonyParamsBytes(makeCeremony())
      const b2 = buildCeremonyParamsBytes(makeCeremony({
        id: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        phase: 'Finalized',
        created_by: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        created_at: '2026-06-15T00:00:00Z',
      }))
      expect(bytesToHex(b1)).toBe(bytesToHex(b2))
    })

    it('encodes beacon spec when present', () => {
      const b1 = buildCeremonyParamsBytes(makeCeremony({ beacon_spec: null }))
      const b2 = buildCeremonyParamsBytes(makeCeremony({
        beacon_spec: { beaconNetwork: 'drand-quicknet', beaconRound: null, beaconFallback: { tag: 'CancelCeremony' } },
      }))
      expect(bytesToHex(b1)).not.toBe(bytesToHex(b2))
    })
  })

  describe('computeParamsHash', () => {
    it('returns a 64-character hex string', async () => {
      const hash = await computeParamsHash(makeCeremony())
      expect(hash).toMatch(/^[0-9a-f]{64}$/)
    })

    it('is deterministic', async () => {
      const c = makeCeremony()
      const h1 = await computeParamsHash(c)
      const h2 = await computeParamsHash(c)
      expect(h1).toBe(h2)
    })

    it('different params -> different hash', async () => {
      const h1 = await computeParamsHash(makeCeremony({ question: 'A' }))
      const h2 = await computeParamsHash(makeCeremony({ question: 'B' }))
      expect(h1).not.toBe(h2)
    })

    // Cross-language golden test: this hash must match the Haskell implementation
    // in test/Veritas/Crypto/CeremonyParamsSpec.hs (baseCeremony)
    it('matches Haskell golden hash for base ceremony', async () => {
      const hash = await computeParamsHash(makeCeremony())
      expect(hash).toBe('cf082b4901fa9040b8be96fc45586d3b0a7eaecca8c9400b30958a0238a63f78')
    })
  })

  describe('verifyParamsHash', () => {
    it('returns true when hash matches', async () => {
      const c = makeCeremony()
      c.params_hash = await computeParamsHash(c)
      expect(await verifyParamsHash(c)).toBe(true)
    })

    it('returns false when hash does not match', async () => {
      const c = makeCeremony({ params_hash: 'ab'.repeat(32) })
      expect(await verifyParamsHash(c)).toBe(false)
    })
  })
})
