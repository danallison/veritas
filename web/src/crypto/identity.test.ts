// @vitest-environment node
import { describe, it, expect, beforeEach } from 'vitest'
import {
  isValidPublicKeyHex,
  storePublicKey,
  loadPublicKey,
  buildRosterPayload,
  buildCommitPayload,
  describeRosterPayload,
  describeCommitPayload,
} from './identity'

// Minimal localStorage shim for Node tests
const storage = new Map<string, string>()
Object.defineProperty(globalThis, 'localStorage', {
  value: {
    getItem: (key: string) => storage.get(key) ?? null,
    setItem: (key: string, value: string) => storage.set(key, value),
    removeItem: (key: string) => storage.delete(key),
    clear: () => storage.clear(),
  },
  writable: true,
})

const testParamsHash = 'ab'.repeat(32)
const differentParamsHash = 'cd'.repeat(32)

describe('identity', () => {
  beforeEach(() => {
    storage.clear()
  })

  describe('isValidPublicKeyHex', () => {
    it('accepts a valid 64-char lowercase hex string', () => {
      expect(isValidPublicKeyHex('ab'.repeat(32))).toBe(true)
    })

    it('accepts uppercase hex', () => {
      expect(isValidPublicKeyHex('AB'.repeat(32))).toBe(true)
    })

    it('accepts mixed-case hex', () => {
      expect(isValidPublicKeyHex('aBcDeF'.repeat(10) + 'aBcD')).toBe(true)
    })

    it('rejects too-short strings', () => {
      expect(isValidPublicKeyHex('ab'.repeat(31))).toBe(false)
    })

    it('rejects too-long strings', () => {
      expect(isValidPublicKeyHex('ab'.repeat(33))).toBe(false)
    })

    it('rejects non-hex characters', () => {
      expect(isValidPublicKeyHex('zz'.repeat(32))).toBe(false)
    })

    it('rejects empty string', () => {
      expect(isValidPublicKeyHex('')).toBe(false)
    })
  })

  describe('storePublicKey / loadPublicKey', () => {
    it('round-trips a public key', () => {
      const pid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      const pk = 'ab'.repeat(32)
      storePublicKey(pid, pk)
      expect(loadPublicKey(pid)).toBe(pk)
    })

    it('returns null for unknown participant', () => {
      expect(loadPublicKey('unknown-id')).toBeNull()
    })

    it('overwrites previous value', () => {
      const pid = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
      storePublicKey(pid, 'ab'.repeat(32))
      storePublicKey(pid, 'cd'.repeat(32))
      expect(loadPublicKey(pid)).toBe('cd'.repeat(32))
    })
  })

  describe('buildRosterPayload', () => {
    it('is deterministic for the same inputs', () => {
      const roster = [
        { participantId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', publicKey: 'ab'.repeat(32) },
        { participantId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', publicKey: 'cd'.repeat(32) },
      ]
      const p1 = buildRosterPayload('cccccccc-cccc-cccc-cccc-cccccccccccc', testParamsHash, roster)
      const p2 = buildRosterPayload('cccccccc-cccc-cccc-cccc-cccccccccccc', testParamsHash, roster)
      expect(p1).toEqual(p2)
    })

    it('sorts by participantId regardless of input order', () => {
      const a = { participantId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', publicKey: 'ab'.repeat(32) }
      const b = { participantId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', publicKey: 'cd'.repeat(32) }
      const p1 = buildRosterPayload('cccccccc-cccc-cccc-cccc-cccccccccccc', testParamsHash, [a, b])
      const p2 = buildRosterPayload('cccccccc-cccc-cccc-cccc-cccccccccccc', testParamsHash, [b, a])
      expect(p1).toEqual(p2)
    })

    it('changes when participants differ', () => {
      const roster1 = [
        { participantId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', publicKey: 'ab'.repeat(32) },
      ]
      const roster2 = [
        { participantId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', publicKey: 'cd'.repeat(32) },
      ]
      const p1 = buildRosterPayload('cccccccc-cccc-cccc-cccc-cccccccccccc', testParamsHash, roster1)
      const p2 = buildRosterPayload('cccccccc-cccc-cccc-cccc-cccccccccccc', testParamsHash, roster2)
      expect(p1).not.toEqual(p2)
    })

    it('starts with the v2 prefix', () => {
      const roster = [
        { participantId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', publicKey: 'ab'.repeat(32) },
      ]
      const payload = buildRosterPayload('cccccccc-cccc-cccc-cccc-cccccccccccc', testParamsHash, roster)
      const text = new TextDecoder().decode(payload.slice(0, 18))
      expect(text).toBe('veritas-roster-v2:')
    })

    it('different paramsHash -> different payload', () => {
      const roster = [
        { participantId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', publicKey: 'ab'.repeat(32) },
      ]
      const p1 = buildRosterPayload('cccccccc-cccc-cccc-cccc-cccccccccccc', testParamsHash, roster)
      const p2 = buildRosterPayload('cccccccc-cccc-cccc-cccc-cccccccccccc', differentParamsHash, roster)
      expect(p1).not.toEqual(p2)
    })
  })

  describe('buildCommitPayload', () => {
    it('starts with the v2 prefix', () => {
      const payload = buildCommitPayload(
        'cccccccc-cccc-cccc-cccc-cccccccccccc',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        testParamsHash,
      )
      const text = new TextDecoder().decode(payload.slice(0, 18))
      expect(text).toBe('veritas-commit-v2:')
    })

    it('changes with different seal', () => {
      const p1 = buildCommitPayload('cccccccc-cccc-cccc-cccc-cccccccccccc', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', testParamsHash)
      const p2 = buildCommitPayload('cccccccc-cccc-cccc-cccc-cccccccccccc', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', testParamsHash, 'ab'.repeat(32))
      expect(p1.length).not.toBe(p2.length)
    })

    it('different paramsHash -> different payload', () => {
      const p1 = buildCommitPayload('cccccccc-cccc-cccc-cccc-cccccccccccc', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', testParamsHash)
      const p2 = buildCommitPayload('cccccccc-cccc-cccc-cccc-cccccccccccc', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', differentParamsHash)
      expect(p1).not.toEqual(p2)
    })
  })

  describe('describeRosterPayload', () => {
    it('includes ceremony ID and params_hash in the description', () => {
      const cid = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
      const roster = [
        { participantId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', publicKey: 'ab'.repeat(32) },
      ]
      const desc = describeRosterPayload(cid, testParamsHash, roster)
      expect(desc).toContain(cid)
      expect(desc).toContain(testParamsHash)
      expect(desc).toContain('veritas-roster-v2:')
    })

    it('includes all participant IDs', () => {
      const pid1 = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      const pid2 = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
      const roster = [
        { participantId: pid1, publicKey: 'ab'.repeat(32) },
        { participantId: pid2, publicKey: 'cd'.repeat(32) },
      ]
      const desc = describeRosterPayload('cccccccc-cccc-cccc-cccc-cccccccccccc', testParamsHash, roster)
      expect(desc).toContain(pid1)
      expect(desc).toContain(pid2)
    })

    it('includes ceremony parameters when provided', () => {
      const roster = [
        { participantId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', publicKey: 'ab'.repeat(32) },
      ]
      const ceremony = {
        id: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
        question: 'Who goes first?',
        ceremony_type: { tag: 'CoinFlip' as const, contents: ['Alice wins', 'Bob wins'] as [string, string] },
        entropy_method: 'OfficiantVRF' as const,
        required_parties: 2,
        commitment_mode: 'Immediate' as const,
        commit_deadline: '2026-12-01T00:00:00Z',
        reveal_deadline: null,
        non_participation_policy: null,
        beacon_spec: null,
        identity_mode: 'SelfCertified' as const,
        phase: 'AwaitingRosterAcks' as const,
        created_by: 'creator-id',
        created_at: '2026-01-01T00:00:00Z',
        commitment_count: 0,
        committed_participants: [],
        roster: null,
        params_hash: testParamsHash,
      }
      const desc = describeRosterPayload('cccccccc-cccc-cccc-cccc-cccccccccccc', testParamsHash, roster, ceremony)
      expect(desc).toContain('Who goes first?')
      expect(desc).toContain('Coin Flip: "Alice wins" vs "Bob wins"')
      expect(desc).toContain('OfficiantVRF')
      expect(desc).toContain('SelfCertified')
    })
  })

  describe('describeCommitPayload', () => {
    it('includes the v2 prefix and params_hash', () => {
      const desc = describeCommitPayload(
        'cccccccc-cccc-cccc-cccc-cccccccccccc',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        testParamsHash,
      )
      expect(desc).toContain('veritas-commit-v2:')
      expect(desc).toContain(testParamsHash)
    })

    it('includes ceremony ID and participant ID', () => {
      const cid = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
      const pid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      const desc = describeCommitPayload(cid, pid, testParamsHash)
      expect(desc).toContain(cid)
      expect(desc).toContain(pid)
    })

    it('includes seal when provided', () => {
      const seal = 'ab'.repeat(32)
      const desc = describeCommitPayload(
        'cccccccc-cccc-cccc-cccc-cccccccccccc',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        testParamsHash,
        seal,
      )
      expect(desc).toContain(seal)
    })
  })
})
