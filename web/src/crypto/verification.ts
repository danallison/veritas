/**
 * Independent verification of the Veritas outcome derivation pipeline.
 *
 * Implements the same algorithms as the Haskell backend:
 * 1. Entropy combination: sort by canonical key, concatenate raw bytes, SHA-256
 * 2. HKDF-SHA256 derivation: extract with "veritas-salt", expand with info label
 * 3. Type-specific outcome derivation from the uniform value
 *
 * All crypto uses the Web Crypto API (no dependencies).
 */

import { hexToBytes, bytesToHex } from './entropy'

const TWO_TO_256 = 2n ** 256n
const SALT = new TextEncoder().encode('veritas-salt')

// --- Low-level crypto ---

export async function sha256(data: Uint8Array): Promise<Uint8Array> {
  const hash = await crypto.subtle.digest('SHA-256', data)
  return new Uint8Array(hash)
}

export async function hkdfSha256(
  ikm: Uint8Array,
  info: Uint8Array,
): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    'raw', ikm, 'HKDF', false, ['deriveBits'],
  )
  const bits = await crypto.subtle.deriveBits(
    { name: 'HKDF', hash: 'SHA-256', salt: SALT, info },
    key,
    256, // 32 bytes
  )
  return new Uint8Array(bits)
}

export function bytesToBigInt(bytes: Uint8Array): bigint {
  let n = 0n
  for (const b of bytes) {
    n = n * 256n + BigInt(b)
  }
  return n
}

// --- Uniform derivation ---

const INFO_UNIFORM = new TextEncoder().encode('veritas-uniform')

/** Derive a uniform numerator n such that n / 2^256 is in [0, 1). */
export async function deriveUniformN(entropy: Uint8Array): Promise<bigint> {
  const okm = await hkdfSha256(entropy, INFO_UNIFORM)
  return bytesToBigInt(okm)
}

/** Derive the nth sub-value for Fisher-Yates shuffle. */
export async function deriveNthN(entropy: Uint8Array, i: number): Promise<bigint> {
  const info = new TextEncoder().encode(`veritas-shuffle-${i}`)
  const okm = await hkdfSha256(entropy, info)
  return bytesToBigInt(okm)
}

// --- Entropy combination ---

export interface EntropyInput {
  sourceType: 'ParticipantEntropy' | 'DefaultEntropy' | 'BeaconEntropy' | 'VRFEntropy'
  sourceId: string // participant UUID for Participant/Default, "beacon"/"vrf" for others
  valueHex: string
}

function sortKey(input: EntropyInput): [number, string] {
  switch (input.sourceType) {
    case 'ParticipantEntropy': return [0, input.sourceId]
    case 'DefaultEntropy':     return [1, input.sourceId]
    case 'BeaconEntropy':      return [2, 'beacon']
    case 'VRFEntropy':         return [3, 'vrf']
  }
}

function compareSortKeys(a: [number, string], b: [number, string]): number {
  if (a[0] !== b[0]) return a[0] - b[0]
  return a[1] < b[1] ? -1 : a[1] > b[1] ? 1 : 0
}

export async function combineEntropy(inputs: EntropyInput[]): Promise<string> {
  const sorted = [...inputs].sort((a, b) => compareSortKeys(sortKey(a), sortKey(b)))
  const parts = sorted.map((i) => hexToBytes(i.valueHex))
  const totalLen = parts.reduce((sum, p) => sum + p.length, 0)
  const concat = new Uint8Array(totalLen)
  let offset = 0
  for (const p of parts) {
    concat.set(p, offset)
    offset += p.length
  }
  const hash = await sha256(concat)
  return bytesToHex(hash)
}

// --- Outcome derivation ---

export async function deriveCoinFlip(entropyHex: string, labels: [string, string]): Promise<string> {
  const n = await deriveUniformN(hexToBytes(entropyHex))
  const isTrue = n * 2n >= TWO_TO_256 // equivalent to n/2^256 >= 0.5
  return isTrue ? labels[0] : labels[1]
}

export async function deriveChoice(entropyHex: string, choices: string[]): Promise<string> {
  const n = await deriveUniformN(hexToBytes(entropyHex))
  const numChoices = BigInt(choices.length)
  const idx = Number((n * numChoices) / TWO_TO_256)
  const safeIdx = Math.min(idx, choices.length - 1)
  return choices[safeIdx]
}

export async function deriveIntRange(entropyHex: string, lo: number, hi: number): Promise<number> {
  if (lo > hi) return deriveIntRange(entropyHex, hi, lo)
  if (lo === hi) return lo
  const n = await deriveUniformN(hexToBytes(entropyHex))
  const range = BigInt(hi - lo + 1)
  const offset = Number((n * range) / TWO_TO_256)
  return lo + Math.min(offset, hi - lo)
}

export async function deriveWeightedChoice(
  entropyHex: string,
  choices: [string, number][],
): Promise<string> {
  const n = await deriveUniformN(hexToBytes(entropyHex))
  // Use integer arithmetic: scale weights to avoid floating point.
  // Find a common scale factor to make all weights integers.
  // For integer weights, scaleFactor = 1.
  const scaleFactor = findScaleFactor(choices.map(([, w]) => w))
  const scaledWeights = choices.map(([label, w]) => [label, BigInt(Math.round(w * scaleFactor))] as [string, bigint])
  const totalScaled = scaledWeights.reduce((sum, [, w]) => sum + w, 0n)

  // target = n * totalScaled / 2^256 (but we compare without dividing)
  // target < weight iff n * totalScaled < weight * 2^256
  const targetN = n * totalScaled
  let remaining = targetN
  for (let i = 0; i < scaledWeights.length; i++) {
    const [label, weight] = scaledWeights[i]
    if (i === scaledWeights.length - 1) return label
    const threshold = weight * TWO_TO_256
    if (remaining < threshold) return label
    remaining -= threshold
  }
  return choices[choices.length - 1][0] // fallback (shouldn't reach)
}

function findScaleFactor(weights: number[]): number {
  // Find the smallest integer multiplier that makes all weights integers
  let factor = 1
  for (const w of weights) {
    const decimals = (w.toString().split('.')[1] ?? '').length
    factor = Math.max(factor, 10 ** decimals)
  }
  return factor
}

export async function deriveShuffle(entropyHex: string, items: string[]): Promise<string[]> {
  const entropy = hexToBytes(entropyHex)
  const result = [...items]
  const n = result.length
  for (let i = n - 1; i >= 1; i--) {
    const subN = await deriveNthN(entropy, i)
    const range = BigInt(i + 1)
    const j = Number((subN * range) / TWO_TO_256)
    const safeJ = Math.min(j, i)
    // swap
    const tmp = result[i]
    result[i] = result[safeJ]
    result[safeJ] = tmp
  }
  return result
}

// --- Full verification ---

export interface VerificationResult {
  combinedEntropyMatch: boolean
  outcomeMatch: boolean
  computedCombinedEntropy: string
  computedOutcome: unknown
}

export async function verifyOutcome(
  ceremonyType: { tag: string; contents?: unknown },
  entropyInputs: EntropyInput[],
  expectedCombinedEntropy: string,
  expectedOutcome: unknown,
): Promise<VerificationResult> {
  const computedCombinedEntropy = await combineEntropy(entropyInputs)
  const combinedEntropyMatch = computedCombinedEntropy === expectedCombinedEntropy

  let computedOutcome: unknown
  switch (ceremonyType.tag) {
    case 'CoinFlip':
      computedOutcome = await deriveCoinFlip(
        computedCombinedEntropy,
        ceremonyType.contents as [string, string],
      )
      break
    case 'UniformChoice':
      computedOutcome = await deriveChoice(
        computedCombinedEntropy,
        ceremonyType.contents as string[],
      )
      break
    case 'IntRange': {
      const [lo, hi] = ceremonyType.contents as [number, number]
      computedOutcome = await deriveIntRange(computedCombinedEntropy, lo, hi)
      break
    }
    case 'WeightedChoice':
      computedOutcome = await deriveWeightedChoice(
        computedCombinedEntropy,
        ceremonyType.contents as [string, number][],
      )
      break
    case 'Shuffle':
      computedOutcome = await deriveShuffle(
        computedCombinedEntropy,
        ceremonyType.contents as string[],
      )
      break
    default:
      throw new Error(`Unknown ceremony type: ${ceremonyType.tag}`)
  }

  const outcomeMatch = JSON.stringify(computedOutcome) === JSON.stringify(expectedOutcome)

  return {
    combinedEntropyMatch,
    outcomeMatch,
    computedCombinedEntropy,
    computedOutcome,
  }
}
