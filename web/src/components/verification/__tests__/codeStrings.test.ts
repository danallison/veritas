// @vitest-environment node
import { describe, it, expect } from 'vitest'
import {
  UTILITY_CODE,
  UTILITY_NAMES,
  UTILITY_SELF_TEST,
  fetchDataCode,
  verifyBeaconCode,
  verifyEntropyCode,
  verifyOutcomeCode,
  verifyCommitRevealCode,
  verifyIdentityCode,
  verifyParamsHashCode,
} from '../codeStrings'
import vectors from '../../../crypto/test-vectors.json'

// eslint-disable-next-line @typescript-eslint/no-unsafe-function-type
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor as new (
  ...args: string[]
) => (...args: unknown[]) => Promise<unknown>

/**
 * Compile utility functions from the UTILITY_CODE string,
 * then build an async runner for a step code string.
 * This is the EXACT same mechanism used at runtime.
 */
// eslint-disable-next-line @typescript-eslint/no-unsafe-function-type
function getUtilities(): Record<string, Function> {
  const fn = new Function(
    UTILITY_CODE + '\nreturn { ' + UTILITY_NAMES.join(', ') + ' };',
  // eslint-disable-next-line @typescript-eslint/no-unsafe-function-type
  ) as () => Record<string, Function>
  return fn()
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function makeRunner(code: string): () => Promise<any> {
  const utils = getUtilities()
  const names = Object.keys(utils)
  const values = Object.values(utils)
  return async () => {
    const fn = new AsyncFunction(...names, code)
    return fn(...values)
  }
}

describe('UTILITY_CODE', () => {
  it('defines all required helper functions', () => {
    const utils = getUtilities()
    expect(typeof utils.hexToBytes).toBe('function')
    expect(typeof utils.bytesToHex).toBe('function')
    expect(typeof utils.sha256).toBe('function')
    expect(typeof utils.hkdfSha256).toBe('function')
    expect(typeof utils.bytesToBigInt).toBe('function')
  })

  it('self-test passes', async () => {
    const run = makeRunner(UTILITY_SELF_TEST)
    const result = await run()
    expect(result.status).toBe('pass')
  })

  it('hexToBytes/bytesToHex roundtrip', () => {
    const utils = getUtilities()
    const hex = 'f96b3e2b2894159a6f1d84fe5ee9fb63'
    const bytes = utils.hexToBytes(hex)
    expect(utils.bytesToHex(bytes)).toBe(hex)
  })

  it('bytesToBigInt matches expected', () => {
    const utils = getUtilities()
    const bytes = new Uint8Array([0x01, 0x00])
    expect(utils.bytesToBigInt(bytes)).toBe(256n)
  })
})

describe('verifyEntropyCode', () => {
  it('passes with fullPipeline test vector', async () => {
    const inputs = vectors.fullPipeline.contributions.map((c) => ({
      sourceType: c.source as 'ParticipantEntropy',
      sourceId: c.participant_id!,
      valueHex: c.value,
    }))
    const code = verifyEntropyCode(inputs, vectors.fullPipeline.combined_entropy)
    const run = makeRunner(code)
    const result = await run()
    expect(result.status).toBe('pass')
  })

  it('passes with mixedSources test vector (reverse order)', async () => {
    const inputs = vectors.mixedSources.contributions.map((c) => ({
      sourceType: c.source as 'ParticipantEntropy' | 'DefaultEntropy' | 'BeaconEntropy' | 'VRFEntropy',
      sourceId: c.source_id ?? c.participant_id ?? c.source,
      valueHex: c.value,
    }))
    const code = verifyEntropyCode(inputs, vectors.mixedSources.combined_entropy)
    const run = makeRunner(code)
    const result = await run()
    expect(result.status).toBe('pass')
  })

  it('fails with wrong expected hash', async () => {
    const inputs = vectors.fullPipeline.contributions.map((c) => ({
      sourceType: c.source as 'ParticipantEntropy',
      sourceId: c.participant_id!,
      valueHex: c.value,
    }))
    const wrongHash = '00'.repeat(32)
    const code = verifyEntropyCode(inputs, wrongHash)
    const run = makeRunner(code)
    const result = await run()
    expect(result.status).toBe('fail')
  })
})

describe('verifyOutcomeCode', () => {
  it('passes for coinFlip test vector', async () => {
    const code = verifyOutcomeCode(
      { tag: 'CoinFlip', contents: ['Heads', 'Tails'] },
      vectors.coinFlip.entropy,
      vectors.coinFlip.result ? 'Heads' : 'Tails',
    )
    const run = makeRunner(code)
    const result = await run()
    expect(result.status).toBe('pass')
  })

  it('passes for uniformChoice test vector', async () => {
    const code = verifyOutcomeCode(
      { tag: 'UniformChoice', contents: vectors.uniformChoice.choices },
      vectors.uniformChoice.entropy,
      vectors.uniformChoice.result,
    )
    const run = makeRunner(code)
    const result = await run()
    expect(result.status).toBe('pass')
  })

  it('passes for intRange test vector', async () => {
    const code = verifyOutcomeCode(
      { tag: 'IntRange', contents: [vectors.intRange.lo, vectors.intRange.hi] },
      vectors.intRange.entropy,
      vectors.intRange.result,
    )
    const run = makeRunner(code)
    const result = await run()
    expect(result.status).toBe('pass')
  })

  it('passes for weightedChoice test vector', async () => {
    const choices = vectors.weightedChoice.choices.map((c) =>
      [c.label, { numerator: c.weight, denominator: 1 }])
    const code = verifyOutcomeCode(
      { tag: 'WeightedChoice', contents: choices },
      vectors.weightedChoice.entropy,
      vectors.weightedChoice.result,
    )
    const run = makeRunner(code)
    const result = await run()
    expect(result.status).toBe('pass')
  })

  it('passes for shuffle test vector', async () => {
    const code = verifyOutcomeCode(
      { tag: 'Shuffle', contents: vectors.shuffle.items },
      vectors.shuffle.entropy,
      vectors.shuffle.result,
    )
    const run = makeRunner(code)
    const result = await run()
    expect(result.status).toBe('pass')
  })

  it('fails with wrong expected outcome', async () => {
    const code = verifyOutcomeCode(
      { tag: 'CoinFlip', contents: ['Heads', 'Tails'] },
      vectors.coinFlip.entropy,
      vectors.coinFlip.result ? 'Tails' : 'Heads', // wrong on purpose
    )
    const run = makeRunner(code)
    const result = await run()
    expect(result.status).toBe('fail')
  })
})

describe('verifyCommitRevealCode', () => {
  it('passes with matching seal', async () => {
    // Compute a seal manually using the same UTILITY_CODE helpers
    const utils = getUtilities()
    const ceremonyId = '550e8400-e29b-41d4-a716-446655440000'
    const participantId = '660e8400-e29b-41d4-a716-446655440000'
    const entropyHex = 'f96b3e2b2894159a6f1d84fe5ee9fb63bd5f36fc7328e8b7c1b75f58f896a057'

    // Compute seal: SHA-256(ceremonyId_ascii || participantId_ascii || entropy_bytes)
    const encoder = new TextEncoder()
    const cidBytes = encoder.encode(ceremonyId)
    const pidBytes = encoder.encode(participantId)
    const entropyBytes = utils.hexToBytes(entropyHex)
    const input = new Uint8Array(cidBytes.length + pidBytes.length + entropyBytes.length)
    input.set(cidBytes, 0)
    input.set(pidBytes, cidBytes.length)
    input.set(entropyBytes, cidBytes.length + pidBytes.length)
    const sealHash = utils.bytesToHex(await utils.sha256(input))

    const code = verifyCommitRevealCode(ceremonyId, [
      { participantId, sealHash, entropy: entropyHex },
    ])
    const run = makeRunner(code)
    const result = await run()
    expect(result.status).toBe('pass')
  })

  it('fails with wrong seal', async () => {
    const code = verifyCommitRevealCode('550e8400-e29b-41d4-a716-446655440000', [
      { participantId: '660e8400-e29b-41d4-a716-446655440000', sealHash: '00'.repeat(32), entropy: '01'.repeat(32) },
    ])
    const run = makeRunner(code)
    const result = await run()
    expect(result.status).toBe('fail')
  })
})

describe('verifyParamsHashCode', () => {
  it('passes with golden hash test vector', async () => {
    // Must match makeCeremony() in ceremonyParams.test.ts exactly
    const ceremony = {
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
      identity_mode: 'Anonymous',
      params_hash: 'c22d9d86ddcbd47e28a8071cfbf796757b2b5e3c80665843a42f61f6a0949a46',
      phase: 'Pending',
      created_by: '00000000-0000-0000-0000-000000000000',
      created_at: '2026-01-01T00:00:00Z',
      commitment_count: 0,
      committed_participants: [],
      roster: null,
    }
    const code = verifyParamsHashCode(ceremony)
    const run = makeRunner(code)
    const result = await run()
    expect(result.status).toBe('pass')
  })

  it('fails with wrong params_hash', async () => {
    const ceremony = {
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
      identity_mode: 'Anonymous',
      params_hash: '00'.repeat(32),
      phase: 'Pending',
      created_by: '00000000-0000-0000-0000-000000000000',
      created_at: '2026-01-01T00:00:00Z',
      commitment_count: 0,
      committed_participants: [],
      roster: null,
    }
    const code = verifyParamsHashCode(ceremony)
    const run = makeRunner(code)
    const result = await run()
    expect(result.status).toBe('fail')
  })
})

describe('input validation (defense-in-depth)', () => {
  it('fetchDataCode rejects non-UUID ceremonyId', () => {
    expect(() => fetchDataCode("'; alert('xss'); '", 'http://localhost:3000')).toThrow('not a valid UUID')
  })

  it('fetchDataCode rejects invalid baseUrl', () => {
    expect(() => fetchDataCode('550e8400-e29b-41d4-a716-446655440000', "'; alert(1); '")).toThrow('not a valid URL')
  })

  it('verifyBeaconCode rejects non-hex network', () => {
    expect(() => verifyBeaconCode("not-hex!", 1, 'aa', 'bb')).toThrow('not valid hex')
  })

  it('verifyBeaconCode rejects non-integer round', () => {
    expect(() => verifyBeaconCode('aabb', 1.5, 'aa', 'bb')).toThrow('not a safe integer')
  })

  it('verifyCommitRevealCode rejects non-UUID ceremonyId', () => {
    expect(() => verifyCommitRevealCode('bad-id', [])).toThrow('not a valid UUID')
  })

  it('verifyCommitRevealCode rejects non-hex sealHash', () => {
    expect(() => verifyCommitRevealCode('550e8400-e29b-41d4-a716-446655440000', [
      { participantId: '660e8400-e29b-41d4-a716-446655440000', sealHash: 'not-hex!', entropy: 'aa' },
    ])).toThrow('not valid hex')
  })

  it('verifyIdentityCode rejects non-UUID ceremonyId', () => {
    expect(() => verifyIdentityCode('bad', 'aabb', [], {}, [])).toThrow('not a valid UUID')
  })

  it('verifyIdentityCode rejects non-hex paramsHash', () => {
    expect(() => verifyIdentityCode('550e8400-e29b-41d4-a716-446655440000', 'not-hex!', [], {}, [])).toThrow('not valid hex')
  })

  it('verifyEntropyCode rejects non-hex entropy value', () => {
    expect(() => verifyEntropyCode(
      [{ sourceType: 'VRFEntropy', sourceId: 'vrf', valueHex: 'not-hex!' }],
      'aa',
    )).toThrow('not valid hex')
  })

  it('verifyParamsHashCode rejects non-hex params_hash', () => {
    expect(() => verifyParamsHashCode({
      id: '550e8400-e29b-41d4-a716-446655440000',
      params_hash: 'not-hex!',
    })).toThrow('not valid hex')
  })

  it('verifyParamsHashCode rejects non-UUID ceremony id', () => {
    expect(() => verifyParamsHashCode({
      id: 'bad-id',
      params_hash: 'aabb',
    })).toThrow('not a valid UUID')
  })
})

describe('verifyIdentityCode', () => {
  it('generates well-formed code that parses without error', () => {
    const code = verifyIdentityCode(
      '550e8400-e29b-41d4-a716-446655440000',
      'aabb'.repeat(16),
      [{ participantId: '660e8400-e29b-41d4-a716-446655440000', publicKey: 'cc'.repeat(32) }],
      { '660e8400-e29b-41d4-a716-446655440000': 'dd'.repeat(64) },
      [{ participantId: '660e8400-e29b-41d4-a716-446655440000', signature: 'ee'.repeat(64), sealHash: null }],
    )
    // Verify the code string is valid JavaScript by constructing an AsyncFunction
    // (this throws SyntaxError if the code is malformed)
    const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor
    expect(() => new AsyncFunction(...UTILITY_NAMES, code)).not.toThrow()
  })
})
