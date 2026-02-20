import { describe, it, expect } from 'vitest'
import { generateEntropy, computeSeal } from './entropy'

describe('generateEntropy', () => {
  it('returns a 64-character hex string (32 bytes)', () => {
    const entropy = generateEntropy()
    expect(entropy).toMatch(/^[0-9a-f]{64}$/)
  })

  it('returns different values on successive calls', () => {
    const a = generateEntropy()
    const b = generateEntropy()
    expect(a).not.toBe(b)
  })
})

describe('computeSeal', () => {
  const ceremonyId = '550e8400-e29b-41d4-a716-446655440000'
  const participantId = '660e8400-e29b-41d4-a716-446655440000'
  const zeroEntropy = '0'.repeat(64) // 32 zero bytes

  it('is deterministic — same inputs produce same output', async () => {
    const seal1 = await computeSeal(ceremonyId, participantId, zeroEntropy)
    const seal2 = await computeSeal(ceremonyId, participantId, zeroEntropy)
    expect(seal1).toBe(seal2)
  })

  it('matches the Haskell backend test vector', async () => {
    // SHA-256(toASCIIBytes("550e8400-...") || toASCIIBytes("660e8400-...") || 32 zero bytes)
    // Computed independently via: hashlib.sha256(cid + pid + b"\\x00"*32).hexdigest()
    const expected = 'f8e7de3b98b97e3e5e8de3ea4d4bb557a1f4ef9e378f12f8fdcd5773b400b326'
    const seal = await computeSeal(ceremonyId, participantId, zeroEntropy)
    expect(seal).toBe(expected)
  })

  it('different ceremony IDs produce different seals', async () => {
    const otherCeremonyId = '770e8400-e29b-41d4-a716-446655440000'
    const seal1 = await computeSeal(ceremonyId, participantId, zeroEntropy)
    const seal2 = await computeSeal(otherCeremonyId, participantId, zeroEntropy)
    expect(seal1).not.toBe(seal2)
  })

  it('different participant IDs produce different seals', async () => {
    const otherParticipantId = '880e8400-e29b-41d4-a716-446655440000'
    const seal1 = await computeSeal(ceremonyId, participantId, zeroEntropy)
    const seal2 = await computeSeal(ceremonyId, otherParticipantId, zeroEntropy)
    expect(seal1).not.toBe(seal2)
  })

  it('different entropy values produce different seals', async () => {
    const otherEntropy = 'ff'.repeat(32)
    const seal1 = await computeSeal(ceremonyId, participantId, zeroEntropy)
    const seal2 = await computeSeal(ceremonyId, participantId, otherEntropy)
    expect(seal1).not.toBe(seal2)
  })

  it('returns a 64-character hex string', async () => {
    const seal = await computeSeal(ceremonyId, participantId, zeroEntropy)
    expect(seal).toMatch(/^[0-9a-f]{64}$/)
  })
})
