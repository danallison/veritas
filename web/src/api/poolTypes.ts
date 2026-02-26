// TypeScript interfaces for pool computing API

export interface CreatePoolRequest {
  name: string
  comparison_method: { method: string; config?: unknown }
  compute_deadline_seconds: number
  min_principals: number
}

export interface JoinPoolRequest {
  agent_id: string
  public_key: string  // hex-encoded
  principal_id: string
}

export interface SubmitComputeRequest {
  agent_id: string
  computation_spec: ComputationSpec
  seal_hash: string  // hex-encoded
  seal_sig: string   // hex-encoded
}

export interface SubmitSealRequest {
  agent_id: string
  seal_hash: string
  seal_sig: string
}

export interface SubmitRevealRequest {
  agent_id: string
  result: string     // hex-encoded
  evidence: ExecutionEvidence
  nonce: string      // hex-encoded
}

export interface PoolResponse {
  id: string
  name: string
  comparison_method: { method: string; config?: unknown }
  compute_deadline_seconds: number
  min_principals: number
  created_at: string
}

export interface PoolMemberResponse {
  agent_id: string
  public_key: string
  principal_id: string
  joined_at: string
}

export interface CacheEntryResponse {
  fingerprint: string
  result: string
  provenance: ResultProvenance
  computation_spec?: ComputationSpec
  created_at: string
  expires_at?: string
}

export interface ValidationRoundResponse {
  round_id: string
  fingerprint: string
  phase: string
  created_at: string
}

export interface RoundStatusResponse {
  round_id: string
  phase: string
  message: string
}

export interface RoundDetailResponse {
  round_id: string
  fingerprint: string
  phase: string
  computation_spec: ComputationSpec
  requester_id: string
  beacon_round?: number
  created_at: string
  seals: SealDetailResponse[]
}

export interface SealDetailResponse {
  agent_id: string
  role: string
  seal_hash: string
  seal_sig: string
  phase: string
  result?: string
  nonce?: string
  evidence?: ExecutionEvidence
}

export interface ComputationSpec {
  provider: string
  model: string
  temperature: number
  seed?: number
  max_tokens?: number
  system_prompt: string
  user_prompt: string
  structured_output?: unknown
  input_refs: string[]
}

export interface ExecutionEvidence {
  provider_request_id?: string
  model_echo?: string
  token_counts?: Record<string, number>
  timestamps?: Record<string, string>
  request_body_hash?: string
}

export interface ResultProvenance {
  outcome: { tag: string; dissenter?: string }
  agreement_count: number
  beacon_round?: number
  selection_proof?: string
  validated_at: string
}
