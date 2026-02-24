/**
 * Audit log event parsing for the interactive verification guide.
 *
 * Extracts structured data from audit log entries so that verification
 * code strings can be generated with real values baked in.
 */

import type { AuditLogEntryResponse, CeremonyResponse } from '../../api/types'

// --- Extracted data types ---

export interface BeaconData {
  network: string
  round: number
  value: string
  signature: string
}

export interface CommitRevealEntry {
  participantId: string
  sealHash: string
  entropy: string
}

export interface RosterEntry {
  participantId: string
  publicKey: string
}

export interface CommitSigEntry {
  participantId: string
  signature: string
  sealHash: string | null
}

export interface EntropyInputEntry {
  sourceType: 'ParticipantEntropy' | 'DefaultEntropy' | 'BeaconEntropy' | 'VRFEntropy'
  sourceId: string
  valueHex: string
}

export interface CeremonyVerificationData {
  beacon: BeaconData | null
  commitReveals: CommitRevealEntry[]
  roster: RosterEntry[]
  ackSignatures: Record<string, string>
  commitSignatures: CommitSigEntry[]
  entropyInputs: EntropyInputEntry[]
  combinedEntropy: string
  outcomeValue: unknown
}

// --- Extraction functions ---

export function extractBeaconData(entries: AuditLogEntryResponse[]): BeaconData | null {
  const event = entries.find((e) => e.event_type === 'beacon_anchored')
  if (!event) return null
  const data = event.event_data as Record<string, unknown>
  const anchor = data?.anchor as Record<string, unknown> | undefined
  if (!anchor) return null
  return {
    network: anchor.baNetwork as string,
    round: anchor.baRound as number,
    value: anchor.baValue as string,
    signature: anchor.baSignature as string,
  }
}

function extractCommitReveals(entries: AuditLogEntryResponse[]): CommitRevealEntry[] {
  const commits = new Map<string, string>()
  const reveals = new Map<string, string>()

  for (const entry of entries) {
    if (entry.event_type === 'participant_committed') {
      const data = entry.event_data as Record<string, unknown>
      const pid = data?.participant as string
      const seal = data?.entropySealHash as string
      if (pid && seal) commits.set(pid, seal)
    }
    if (entry.event_type === 'entropy_revealed') {
      const data = entry.event_data as Record<string, unknown>
      const pid = data?.participant as string
      const entropy = data?.entropy as string
      if (pid && entropy) reveals.set(pid, entropy)
    }
  }

  const result: CommitRevealEntry[] = []
  for (const [pid, seal] of commits) {
    const entropy = reveals.get(pid)
    if (entropy) {
      result.push({ participantId: pid, sealHash: seal, entropy })
    }
  }
  return result
}

function extractRoster(entries: AuditLogEntryResponse[]): RosterEntry[] {
  const event = entries.find((e) => e.event_type === 'roster_finalized')
  if (!event) return []
  const data = event.event_data as Record<string, unknown>
  const contents = data?.contents as [string, string][] | undefined
  if (!contents) return []
  return contents.map(([pid, pk]) => ({ participantId: pid, publicKey: pk }))
}

function extractAckSignatures(entries: AuditLogEntryResponse[]): Record<string, string> {
  const result: Record<string, string> = {}
  for (const entry of entries) {
    if (entry.event_type === 'roster_acknowledged') {
      const data = entry.event_data as Record<string, unknown>
      const pid = data?.participant as string
      const sig = data?.signature as string
      if (pid && sig) result[pid] = sig
    }
  }
  return result
}

function extractCommitSignatures(entries: AuditLogEntryResponse[]): CommitSigEntry[] {
  const result: CommitSigEntry[] = []
  for (const entry of entries) {
    if (entry.event_type === 'participant_committed') {
      const data = entry.event_data as Record<string, unknown>
      const pid = data?.participant as string
      const sig = data?.signature as string | undefined
      const seal = data?.entropySealHash as string | undefined
      if (pid && sig) {
        result.push({ participantId: pid, signature: sig, sealHash: seal ?? null })
      }
    }
  }
  return result
}

function extractEntropyInputs(resolvedData: Record<string, unknown>): EntropyInputEntry[] {
  const outcome = resolvedData?.outcome as Record<string, unknown>
  const proof = outcome?.outcomeProof as Record<string, unknown>
  const inputs = (proof?.proofEntropyInputs ?? []) as Array<Record<string, unknown>>

  return inputs.map((input) => {
    const source = input.ecSource as Record<string, unknown>
    const tag = source?.tag as string
    let sourceId: string

    switch (tag) {
      case 'ParticipantEntropy':
      case 'DefaultEntropy':
        sourceId = source.participant as string
        break
      case 'BeaconEntropy':
        sourceId = 'beacon'
        break
      case 'VRFEntropy':
        sourceId = 'vrf'
        break
      default:
        sourceId = 'unknown'
    }

    return {
      sourceType: tag as EntropyInputEntry['sourceType'],
      sourceId,
      valueHex: input.ecValue as string,
    }
  })
}

export function unwrapOutcomeValue(value: unknown): unknown {
  const v = value as { tag?: string; contents?: unknown }
  return v?.contents
}

/**
 * Extract all verification data from a ceremony response and its audit log.
 * Returns null if the ceremony hasn't been resolved yet.
 */
export function extractVerificationData(
  ceremony: CeremonyResponse,
  entries: AuditLogEntryResponse[],
): CeremonyVerificationData | null {
  const resolvedEvent = entries.find((e) => e.event_type === 'ceremony_resolved')
  if (!resolvedEvent) return null

  const resolvedData = resolvedEvent.event_data as Record<string, unknown>
  const outcome = resolvedData?.outcome as Record<string, unknown>
  if (!outcome) return null

  const entropyMethod = ceremony.entropy_method
  const beacon = (entropyMethod === 'ExternalBeacon' || entropyMethod === 'Combined')
    ? extractBeaconData(entries)
    : null

  return {
    beacon,
    commitReveals: extractCommitReveals(entries),
    roster: extractRoster(entries),
    ackSignatures: extractAckSignatures(entries),
    commitSignatures: extractCommitSignatures(entries),
    entropyInputs: extractEntropyInputs(resolvedData),
    combinedEntropy: outcome.combinedEntropy as string,
    outcomeValue: outcome.outcomeValue,
  }
}
