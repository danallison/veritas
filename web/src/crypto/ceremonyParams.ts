/**
 * Client-side canonical serialization of ceremony parameters.
 *
 * This must produce the exact same bytes as the Haskell
 * `Veritas.Crypto.CeremonyParams.buildCeremonyParamsBytes` function.
 * The frontend independently computes the params hash to verify that
 * the server's `params_hash` matches the visible ceremony parameters.
 */

import type { CeremonyResponse, CeremonyType, BeaconSpec, BeaconFallback } from '../api/types'
import { bytesToHex } from './entropy'

const encoder = new TextEncoder()

// --- Binary encoding helpers (matching Haskell) ---

/** Big-endian 32-bit unsigned integer */
function u32be(n: number): Uint8Array {
  return new Uint8Array([
    (n >>> 24) & 0xff,
    (n >>> 16) & 0xff,
    (n >>> 8) & 0xff,
    n & 0xff,
  ])
}

/** Length-prefixed UTF-8 string: u32be(byteLength) ++ utf8Bytes */
function lpString(s: string): Uint8Array {
  const bytes = encoder.encode(s)
  return concat([u32be(bytes.length), bytes])
}

/** Optional encoding: Nothing → 0x00, Just x → 0x01 ++ x */
function optional(value: Uint8Array | null): Uint8Array {
  if (value === null) {
    return new Uint8Array([0x00])
  }
  return concat([new Uint8Array([0x01]), value])
}

function concat(parts: Uint8Array[]): Uint8Array {
  const totalLen = parts.reduce((sum, p) => sum + p.length, 0)
  const result = new Uint8Array(totalLen)
  let offset = 0
  for (const p of parts) {
    result.set(p, offset)
    offset += p.length
  }
  return result
}

// --- Type-specific serialization ---

function ceremonyTypeBytes(ct: CeremonyType): Uint8Array {
  switch (ct.tag) {
    case 'CoinFlip':
      return concat([lpString('CoinFlip'), lpString(ct.contents[0]), lpString(ct.contents[1])])
    case 'UniformChoice':
      return concat([lpString('UniformChoice'), u32be(ct.contents.length), ...ct.contents.map(lpString)])
    case 'Shuffle':
      return concat([lpString('Shuffle'), u32be(ct.contents.length), ...ct.contents.map(lpString)])
    case 'IntRange':
      return concat([lpString('IntRange'), u32be(ct.contents[0]), u32be(ct.contents[1])])
    case 'WeightedChoice':
      return concat([
        lpString('WeightedChoice'),
        u32be(ct.contents.length),
        ...ct.contents.flatMap(([label, weight]) => [lpString(label), lpString(numberToRationalShow(weight))]),
      ])
  }
}

function beaconSpecBytes(spec: BeaconSpec): Uint8Array {
  return concat([
    lpString(spec.beaconNetwork),
    optional(spec.beaconRound !== null ? u32be(spec.beaconRound) : null),
    beaconFallbackBytes(spec.beaconFallback),
  ])
}

function beaconFallbackBytes(fb: BeaconFallback): Uint8Array {
  switch (fb.tag) {
    case 'ExtendDeadline':
      // Haskell: show NominalDiffTime appends "s" suffix
      return concat([new Uint8Array([0x01]), lpString(String(fb.contents) + 's')])
    case 'AlternateSource':
      return concat([new Uint8Array([0x02]), beaconSpecBytes(fb.contents)])
    case 'CancelCeremony':
      return new Uint8Array([0x03])
  }
}

/**
 * Convert a JS number to Haskell's `show` format for Rational ("n % d").
 *
 * Haskell's `show (3 % 2 :: Rational)` produces `"3 % 2"`.
 * Aeson encodes Rational as a JSON number, so we convert back.
 */
function numberToRationalShow(n: number): string {
  if (Number.isInteger(n)) {
    return `${n} % 1`
  }
  const str = String(n)
  const dotIndex = str.indexOf('.')
  if (dotIndex === -1) {
    return `${n} % 1`
  }
  const fracPart = str.slice(dotIndex + 1)
  const denominator = 10 ** fracPart.length
  const numerator = parseInt(str.replace('.', ''), 10)
  const g = gcd(Math.abs(numerator), denominator)
  return `${numerator / g} % ${denominator / g}`
}

function gcd(a: number, b: number): number {
  while (b !== 0) {
    ;[a, b] = [b, a % b]
  }
  return a
}

// --- Main serialization ---

/**
 * Build the canonical byte representation of ceremony parameters.
 * Must match Haskell's `buildCeremonyParamsBytes` exactly.
 */
export function buildCeremonyParamsBytes(ceremony: CeremonyResponse): Uint8Array {
  return concat([
    encoder.encode('veritas-params-v1:'),
    lpString(ceremony.question),
    ceremonyTypeBytes(ceremony.ceremony_type),
    lpString(ceremony.entropy_method),
    u32be(ceremony.required_parties),
    lpString(ceremony.commitment_mode),
    lpString(ceremony.commit_deadline),
    optional(ceremony.reveal_deadline !== null ? lpString(ceremony.reveal_deadline) : null),
    optional(ceremony.non_participation_policy !== null ? lpString(ceremony.non_participation_policy) : null),
    optional(ceremony.beacon_spec !== null ? beaconSpecBytes(ceremony.beacon_spec) : null),
    lpString(ceremony.identity_mode),
  ])
}

/**
 * Compute the SHA-256 hash of canonical ceremony parameters.
 * Returns the hex-encoded hash string.
 */
export async function computeParamsHash(ceremony: CeremonyResponse): Promise<string> {
  const bytes = buildCeremonyParamsBytes(ceremony)
  const hash = await crypto.subtle.digest('SHA-256', bytes)
  return bytesToHex(new Uint8Array(hash))
}

/**
 * Verify that the server's params_hash matches the ceremony parameters.
 * Returns true if the hash is valid, false if there's a mismatch.
 */
export async function verifyParamsHash(ceremony: CeremonyResponse): Promise<boolean> {
  const computed = await computeParamsHash(ceremony)
  return computed === ceremony.params_hash
}
