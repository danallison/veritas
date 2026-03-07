// TypeScript types matching the Haskell ToJSON instances exactly.

// --- Enums (nullary constructors → plain strings via generic deriving) ---

export type CommitmentMode = 'Immediate' | 'DeadlineWait'

export type EntropyMethod =
  | 'ParticipantReveal'
  | 'ExternalBeacon'
  | 'OfficiantVRF'
  | 'Combined'

export type NonParticipationPolicy =
  | 'DefaultSubstitution'
  | 'Exclusion'
  | 'Cancellation'

// TODO: Add 'OAuth' here when OAuth identity mode is implemented
export type IdentityMode = 'SelfCertified'

export type Phase =
  | 'Gathering'
  | 'AwaitingRosterAcks'
  | 'Pending'
  | 'AwaitingReveals'
  | 'AwaitingBeacon'
  | 'Resolving'
  | 'Finalized'
  | 'Expired'
  | 'Cancelled'
  | 'Disputed'

// --- Rational (Haskell's Data.Ratio.Rational, serialized by aeson) ---

export interface Rational {
  numerator: number
  denominator: number
}

export function rationalToNumber(r: Rational): number {
  return r.numerator / r.denominator
}

export function numberToRational(n: number): Rational {
  if (Number.isInteger(n)) return { numerator: n, denominator: 1 }
  const str = String(n)
  const dotIndex = str.indexOf('.')
  if (dotIndex === -1) return { numerator: n, denominator: 1 }
  const fracPart = str.slice(dotIndex + 1)
  const denominator = 10 ** fracPart.length
  const numerator = parseInt(str.replace('.', ''), 10)
  const g = gcd(Math.abs(numerator), denominator)
  return { numerator: numerator / g, denominator: denominator / g }
}

function gcd(a: number, b: number): number {
  while (b !== 0) { [a, b] = [b, a % b] }
  return a
}

// --- CeremonyType (generic deriving with tagged constructors) ---

export type CeremonyType =
  | { tag: 'CoinFlip'; contents: [string, string] }
  | { tag: 'UniformChoice'; contents: string[] }
  | { tag: 'Shuffle'; contents: string[] }
  | { tag: 'IntRange'; contents: [number, number] }
  | { tag: 'WeightedChoice'; contents: [string, Rational][] }

// --- BeaconSpec ---

export interface BeaconSpec {
  beaconNetwork: string
  beaconRound: number | null
  beaconFallback: BeaconFallback
}

export type BeaconFallback =
  | { tag: 'ExtendDeadline'; contents: number }
  | { tag: 'AlternateSource'; contents: BeaconSpec }
  | { tag: 'CancelCeremony' }

// --- Request types ---

export interface CreateCeremonyRequest {
  question: string
  ceremony_type: CeremonyType
  entropy_method: EntropyMethod
  required_parties: number
  commitment_mode: CommitmentMode
  commit_deadline: string  // ISO 8601
  reveal_deadline?: string
  non_participation_policy?: NonParticipationPolicy
  created_by?: string  // participant UUID
  beacon_spec?: BeaconSpec
  identity_mode?: IdentityMode
}

export interface CommitRequest {
  participant_id: string
  entropy_seal?: string  // hex-encoded SHA-256
  display_name?: string
  signature?: string     // hex-encoded Ed25519 signature (for self-certified)
}

export interface RevealRequest {
  participant_id: string
  entropy_value: string  // hex-encoded
}

// --- Response types ---

export interface CommittedParticipant {
  participant_id: string
  display_name: string | null
}

export interface RosterEntry {
  participant_id: string
  public_key: string
  display_name: string | null
  acknowledged: boolean
}

export interface CeremonyResponse {
  id: string
  question: string
  ceremony_type: CeremonyType
  entropy_method: EntropyMethod
  required_parties: number
  commitment_mode: CommitmentMode
  commit_deadline: string
  reveal_deadline: string | null
  non_participation_policy: NonParticipationPolicy | null
  beacon_spec: BeaconSpec | null
  identity_mode: IdentityMode
  phase: Phase
  created_by: string
  created_at: string
  commitment_count: number
  committed_participants: CommittedParticipant[]
  roster: RosterEntry[] | null
  params_hash: string
}

export interface CommitResponse {
  status: string
  phase: Phase
}

export interface RevealResponse {
  status: string
}

export interface OutcomeResponse {
  outcome: unknown
  combined_entropy: string
  resolved_at: string
}

export interface AuditLogEntryResponse {
  sequence_num: number
  event_type: string
  event_data: unknown
  prev_hash: string
  entry_hash: string
  created_at: string
}

export interface AuditLogResponse {
  entries: AuditLogEntryResponse[]
}

export interface VerifyResponse {
  valid: boolean
  errors: string[]
}

export interface HealthResponse {
  status: string
  version: string
}

export interface RandomCoinResponse {
  result: boolean
}

export interface RandomIntResponse {
  result: number
  min: number
  max: number
}

export interface RandomUUIDResponse {
  result: string
}

export interface ServerPubKeyResponse {
  public_key: string
}

export interface BeaconVerificationGuideResponse {
  scheme: string
  public_key: string | null
  chain_hash: string
  drand_info_url: string
  dst: string
  steps: string[]
}

// --- Self-certified identity request/response types ---

export interface JoinRequest {
  participant_id: string
  public_key: string    // hex-encoded Ed25519 public key
  display_name?: string
}

export interface JoinResponse {
  status: string
  phase: Phase
}

export interface AckRosterRequest {
  participant_id: string
  signature: string     // hex-encoded Ed25519 signature
}

export interface AckRosterResponse {
  status: string
  phase: Phase
}

export interface RosterResponse {
  participants: RosterEntry[]
  locked: boolean
}
