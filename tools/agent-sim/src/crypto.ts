import nacl from "tweetnacl";
import { sha256 } from "@noble/hashes/sha256";
import { bytesToHex } from "@noble/hashes/utils";

export interface KeyPair {
  publicKey: Uint8Array;
  secretKey: Uint8Array;
}

export function generateKeyPair(): KeyPair {
  const kp = nacl.sign.keyPair();
  return { publicKey: kp.publicKey, secretKey: kp.secretKey };
}

export function sign(message: Uint8Array, secretKey: Uint8Array): Uint8Array {
  return nacl.sign.detached(message, secretKey);
}

export function computeFingerprint(specJson: string): Uint8Array {
  return sha256(new TextEncoder().encode(specJson));
}

export function createSeal(
  fingerprint: Uint8Array,
  agentId: string,
  result: Uint8Array,
  evidenceHash: Uint8Array,
  nonce: Uint8Array
): Uint8Array {
  const agentBytes = new TextEncoder().encode(agentId);
  const combined = new Uint8Array(
    fingerprint.length +
      agentBytes.length +
      result.length +
      evidenceHash.length +
      nonce.length
  );
  let offset = 0;
  combined.set(fingerprint, offset);
  offset += fingerprint.length;
  combined.set(agentBytes, offset);
  offset += agentBytes.length;
  combined.set(result, offset);
  offset += result.length;
  combined.set(evidenceHash, offset);
  offset += evidenceHash.length;
  combined.set(nonce, offset);
  return sha256(combined);
}

export function computeEvidenceHash(evidence: object): Uint8Array {
  const json = JSON.stringify(evidence, Object.keys(evidence).sort());
  return sha256(new TextEncoder().encode(json));
}

export function randomBytes(n: number): Uint8Array {
  return nacl.randomBytes(n);
}

export function toHex(bytes: Uint8Array): string {
  return bytesToHex(bytes);
}

export function canonicalJson(obj: object): string {
  return JSON.stringify(obj, Object.keys(obj).sort());
}
