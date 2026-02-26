// Deterministic hash-based computation simulation.
// Ported from tools/agent-sim/src/compute/simulated.ts.

import type { ComputationSpec } from '../api/poolTypes'
import { canonicalJson } from '../crypto/poolSeal'

/**
 * Simulated computation: deterministic hash of the spec.
 * All agents computing the same spec produce the same result.
 */
export async function simulatedCompute(spec: ComputationSpec): Promise<Uint8Array> {
  const json = canonicalJson(spec as unknown as Record<string, unknown>)
  const hash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode('simulated:' + json))
  return new Uint8Array(hash)
}
