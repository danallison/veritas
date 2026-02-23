import { bytesToHex, hexToBytes } from './entropy'
import type { CeremonyResponse, CeremonyType } from '../api/types'

const STORAGE_PREFIX = 'veritas_pubkey_'

/** Store a participant's public key (hex) in localStorage. */
export function storePublicKey(participantId: string, publicKeyHex: string): void {
  localStorage.setItem(STORAGE_PREFIX + participantId, publicKeyHex)
}

/** Load a participant's stored public key (hex) from localStorage. */
export function loadPublicKey(participantId: string): string | null {
  return localStorage.getItem(STORAGE_PREFIX + participantId)
}

/** Validate a hex string is a plausible Ed25519 public key (32 bytes = 64 hex chars). */
export function isValidPublicKeyHex(hex: string): boolean {
  return /^[0-9a-fA-F]{64}$/.test(hex)
}

/** Build the canonical roster payload for signing (v2 with params hash). Must match backend exactly. */
export function buildRosterPayload(
  ceremonyId: string,
  paramsHashHex: string,
  roster: { participantId: string; publicKey: string }[],
): Uint8Array {
  const encoder = new TextEncoder()
  const prefix = encoder.encode('veritas-roster-v2:')
  // Sort by participantId (UUID lexicographic = string sort)
  const sorted = [...roster].sort((a, b) => a.participantId.localeCompare(b.participantId))
  // ceremony_id as ASCII bytes (UUID string)
  const cidBytes = encoder.encode(ceremonyId)
  const paramsHashBytes = hexToBytes(paramsHashHex)
  const parts: Uint8Array[] = [prefix, cidBytes, paramsHashBytes]
  for (const entry of sorted) {
    // participant_id as ASCII bytes
    parts.push(encoder.encode(entry.participantId))
    // public key as raw bytes (hex-decode)
    parts.push(hexToBytes(entry.publicKey))
  }
  const totalLen = parts.reduce((sum, p) => sum + p.length, 0)
  const result = new Uint8Array(totalLen)
  let offset = 0
  for (const p of parts) {
    result.set(p, offset)
    offset += p.length
  }
  return result
}

/** Build the commit payload for self-certified ceremonies (v2 with params hash). Must match backend exactly. */
export function buildCommitPayload(
  ceremonyId: string,
  participantId: string,
  paramsHashHex: string,
  sealHex?: string,
): Uint8Array {
  const encoder = new TextEncoder()
  const prefix = encoder.encode('veritas-commit-v2:')
  const cidBytes = encoder.encode(ceremonyId)
  const pidBytes = encoder.encode(participantId)
  const paramsHashBytes = hexToBytes(paramsHashHex)
  const sealBytes = sealHex ? hexToBytes(sealHex) : new Uint8Array(0)
  const result = new Uint8Array(prefix.length + cidBytes.length + pidBytes.length + paramsHashBytes.length + sealBytes.length)
  let offset = 0
  result.set(prefix, offset); offset += prefix.length
  result.set(cidBytes, offset); offset += cidBytes.length
  result.set(pidBytes, offset); offset += pidBytes.length
  result.set(paramsHashBytes, offset); offset += paramsHashBytes.length
  result.set(sealBytes, offset)
  return result
}

/** Describe a ceremony type in human-readable form. */
function describeCeremonyType(ct: CeremonyType): string {
  switch (ct.tag) {
    case 'CoinFlip':
      return `Coin Flip: "${ct.contents[0]}" vs "${ct.contents[1]}"`
    case 'UniformChoice':
      return `Uniform Choice: ${ct.contents.join(', ')}`
    case 'Shuffle':
      return `Shuffle: ${ct.contents.join(', ')}`
    case 'IntRange':
      return `Integer Range: ${ct.contents[0]} to ${ct.contents[1]}`
    case 'WeightedChoice':
      return `Weighted Choice: ${ct.contents.map(([label, weight]) => `${label} (${weight})`).join(', ')}`
  }
}

/** Human-readable breakdown of the roster payload structure. */
export function describeRosterPayload(
  ceremonyId: string,
  paramsHashHex: string,
  roster: { participantId: string; publicKey: string }[],
  ceremony?: CeremonyResponse,
): string {
  const sorted = [...roster].sort((a, b) => a.participantId.localeCompare(b.participantId))
  const lines: string[] = [
    'Roster payload structure (concatenated bytes):',
    '',
    '  prefix:                  veritas-roster-v2:',
    `  ceremony_id (UTF-8):     ${ceremonyId}`,
    `  params_hash (32 bytes):  ${paramsHashHex}`,
  ]
  if (ceremony) {
    lines.push('')
    lines.push('  === Ceremony Parameters (covered by params_hash) ===')
    lines.push(`  Question:         ${ceremony.question}`)
    lines.push(`  Type:             ${describeCeremonyType(ceremony.ceremony_type)}`)
    lines.push(`  Entropy Method:   ${ceremony.entropy_method}`)
    lines.push(`  Required Parties: ${ceremony.required_parties}`)
    lines.push(`  Commitment Mode:  ${ceremony.commitment_mode}`)
    lines.push(`  Commit Deadline:  ${ceremony.commit_deadline}`)
    if (ceremony.reveal_deadline) {
      lines.push(`  Reveal Deadline:  ${ceremony.reveal_deadline}`)
    }
    if (ceremony.non_participation_policy) {
      lines.push(`  Non-Participation: ${ceremony.non_participation_policy}`)
    }
    lines.push(`  Identity Mode:    ${ceremony.identity_mode}`)
  }
  lines.push('')
  lines.push('  === Roster ===')
  for (const entry of sorted) {
    lines.push(`  participant_id (UTF-8): ${entry.participantId}`)
    lines.push(`  public_key (32 bytes):  ${entry.publicKey}`)
  }
  lines.push('')
  lines.push('Participants are sorted by participant_id (lexicographic).')
  return lines.join('\n')
}

/** Human-readable breakdown of the commit payload structure. */
export function describeCommitPayload(
  ceremonyId: string,
  participantId: string,
  paramsHashHex: string,
  sealHex?: string,
  ceremony?: CeremonyResponse,
): string {
  const lines: string[] = [
    'Commit payload structure (concatenated bytes):',
    '',
    '  prefix (UTF-8):         veritas-commit-v2:',
    `  ceremony_id (UTF-8):    ${ceremonyId}`,
    `  participant_id (UTF-8): ${participantId}`,
    `  params_hash (32 bytes): ${paramsHashHex}`,
  ]
  if (sealHex) {
    lines.push(`  seal (32 bytes):        ${sealHex}`)
  }
  if (ceremony) {
    lines.push('')
    lines.push('  === Ceremony Parameters (covered by params_hash) ===')
    lines.push(`  Question:         ${ceremony.question}`)
    lines.push(`  Type:             ${describeCeremonyType(ceremony.ceremony_type)}`)
    lines.push(`  Entropy Method:   ${ceremony.entropy_method}`)
    lines.push(`  Required Parties: ${ceremony.required_parties}`)
    lines.push(`  Commitment Mode:  ${ceremony.commitment_mode}`)
    lines.push(`  Commit Deadline:  ${ceremony.commit_deadline}`)
    if (ceremony.reveal_deadline) {
      lines.push(`  Reveal Deadline:  ${ceremony.reveal_deadline}`)
    }
    if (ceremony.non_participation_policy) {
      lines.push(`  Non-Participation: ${ceremony.non_participation_policy}`)
    }
    lines.push(`  Identity Mode:    ${ceremony.identity_mode}`)
  }
  return lines.join('\n')
}

/** Convert a roster payload to hex for display / external signing. */
export function rosterPayloadHex(
  ceremonyId: string,
  paramsHashHex: string,
  roster: { participantId: string; publicKey: string }[],
): string {
  return bytesToHex(buildRosterPayload(ceremonyId, paramsHashHex, roster))
}

/** Convert a commit payload to hex for display / external signing. */
export function commitPayloadHex(
  ceremonyId: string,
  participantId: string,
  paramsHashHex: string,
  sealHex?: string,
): string {
  return bytesToHex(buildCommitPayload(ceremonyId, participantId, paramsHashHex, sealHex))
}
