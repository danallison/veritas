// TypeScript interfaces for the verification pivot API

// === Pool Management ===

export interface VolunteerPool {
  id: string
  name: string
  description: string
  task_type: string          // 'cross_validation' or 'custom:...'
  selection_size: number
  member_count: number
  active_member_count: number
  created_at: string
}

export interface PoolMember {
  agent_id: string
  public_key: string         // hex-encoded Ed25519
  display_name: string
  capabilities: string[]
  status: 'active' | 'suspended' | 'withdrawn'
  joined_at: string
}

export interface CreatePoolRequest {
  name: string
  description: string
  task_type: string
  selection_size: number
}

export interface JoinPoolRequest {
  agent_id: string
  public_key: string
  display_name: string
  capabilities: string[]
}

// === Verification ===

export type VerificationPhase = 'collecting' | 'deciding' | 'decided'

export type VerdictOutcome =
  | { tag: 'unanimous' }
  | { tag: 'majority_agree'; dissenters: string[] }
  | { tag: 'inconclusive' }

export interface VerificationSpec {
  description: string
  computation_fingerprint: string
  submitted_result?: string   // hex-encoded
  comparison_method: string
  validator_count: number
}

export interface Verdict {
  outcome: VerdictOutcome
  agreement_count: number
  majority_result?: string    // hex-encoded
  decided_at: string
}

export interface Verification {
  id: string
  pool_id: string
  spec: VerificationSpec
  submitter: string           // agent_id
  validators: string[]        // agent_ids
  submission_count: number
  expected_submissions: number
  phase: VerificationPhase
  verdict?: Verdict
  created_at: string
}

export interface SubmitVerificationRequest {
  pool_id: string
  description: string
  computation_fingerprint: string
  submitted_result?: string
  comparison_method: string
  validator_count: number
}

export interface RecordSubmissionRequest {
  agent_id: string
  result: string              // hex-encoded
}

// === Cache ===

export interface CacheProvenance {
  verdict_outcome: VerdictOutcome
  agreement_count: number
  cached_at: string
}

export interface CacheEntry {
  fingerprint: string
  result: string              // hex-encoded
  provenance: CacheProvenance
  ttl_seconds?: number
}

export interface CacheStats {
  total_entries: number
  unanimous_count: number
  majority_count: number
}
