// Seal construction, fingerprint, and signing for pool computing protocol.
// Ported from tools/agent-sim/src/crypto.ts to match Haskell backend's createSeal.
// Uses Web Crypto API (crypto.subtle) for SHA-256, matching existing codebase patterns.

import * as ed from '@noble/ed25519'
import { bytesToHex, hexToBytes } from './entropy'
import type { ComputationSpec, ExecutionEvidence } from '../api/poolTypes'

export { bytesToHex as toHex, hexToBytes }

export interface KeyPair {
  publicKey: Uint8Array
  secretKey: Uint8Array
}

async function sha256(data: Uint8Array): Promise<Uint8Array> {
  const hash = await crypto.subtle.digest('SHA-256', data)
  return new Uint8Array(hash)
}

/** Generate an Ed25519 keypair in-browser. */
export async function generateKeyPair(): Promise<KeyPair> {
  const secretKey = ed.utils.randomSecretKey()
  const publicKey = await ed.getPublicKeyAsync(secretKey)
  return { publicKey, secretKey }
}

/** Sign a message with Ed25519. */
export async function signMessage(message: Uint8Array, secretKey: Uint8Array): Promise<Uint8Array> {
  return ed.signAsync(message, secretKey)
}

/** Canonical JSON: keys sorted alphabetically. */
export function canonicalJson(obj: Record<string, unknown>): string {
  return JSON.stringify(obj, Object.keys(obj).sort())
}

/** Compute content-addressed fingerprint for a computation spec.
 *  fingerprint = SHA-256(canonical_json(spec))
 */
export async function computeFingerprint(spec: ComputationSpec): Promise<Uint8Array> {
  const json = canonicalJson(spec as unknown as Record<string, unknown>)
  return sha256(new TextEncoder().encode(json))
}

/** Create a seal over a computation result.
 *  seal = SHA-256(fingerprint || agent_id_ascii || result || evidence_hash || nonce)
 */
export async function createSeal(
  fingerprint: Uint8Array,
  agentId: string,
  result: Uint8Array,
  evidenceHash: Uint8Array,
  nonce: Uint8Array,
): Promise<Uint8Array> {
  const agentBytes = new TextEncoder().encode(agentId)
  const combined = new Uint8Array(
    fingerprint.length + agentBytes.length + result.length + evidenceHash.length + nonce.length,
  )
  let offset = 0
  combined.set(fingerprint, offset); offset += fingerprint.length
  combined.set(agentBytes, offset); offset += agentBytes.length
  combined.set(result, offset); offset += result.length
  combined.set(evidenceHash, offset); offset += evidenceHash.length
  combined.set(nonce, offset)
  return sha256(combined)
}

/** Compute evidence hash: SHA-256(canonical_json(evidence)) */
export async function computeEvidenceHash(evidence: ExecutionEvidence): Promise<Uint8Array> {
  const json = canonicalJson(evidence as unknown as Record<string, unknown>)
  return sha256(new TextEncoder().encode(json))
}

/** Generate cryptographically random bytes. */
export function randomBytes(n: number): Uint8Array {
  const buf = new Uint8Array(n)
  crypto.getRandomValues(buf)
  return buf
}

/** Full seal creation workflow matching agent-sim Agent.createSealData(). */
export async function createSealData(
  spec: ComputationSpec,
  agentId: string,
  result: Uint8Array,
  evidence: ExecutionEvidence,
  secretKey: Uint8Array,
) {
  const fingerprint = await computeFingerprint(spec)
  const nonce = randomBytes(32)
  const evidenceHash = await computeEvidenceHash(evidence)
  const sealHash = await createSeal(fingerprint, agentId, result, evidenceHash, nonce)
  const sealSig = await signMessage(sealHash, secretKey)
  return { fingerprint, nonce, sealHash, sealSig, evidenceHash }
}
