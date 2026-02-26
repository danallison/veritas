import { sha256 } from "@noble/hashes/sha256";

export interface ComputationSpec {
  provider: string;
  model: string;
  temperature: number;
  seed?: number;
  max_tokens?: number;
  system_prompt: string;
  user_prompt: string;
  structured_output?: object;
  input_refs: string[];
}

/**
 * Simulated computation: deterministic hash of the spec.
 * All agents computing the same spec produce the same result.
 */
export function simulatedCompute(spec: ComputationSpec): Uint8Array {
  const json = JSON.stringify(spec, Object.keys(spec).sort());
  return sha256(new TextEncoder().encode("simulated:" + json));
}

/**
 * Simulated computation with injected disagreement.
 * Adds a salt to produce a different result from the honest agents.
 */
export function simulatedComputeDisagree(
  spec: ComputationSpec,
  salt: string
): Uint8Array {
  const json = JSON.stringify(spec, Object.keys(spec).sort());
  return sha256(new TextEncoder().encode("simulated:" + json + ":salt:" + salt));
}
