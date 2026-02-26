import {
  generateKeyPair,
  createSeal,
  computeEvidenceHash,
  computeFingerprint,
  sign,
  randomBytes,
  toHex,
  canonicalJson,
  type KeyPair,
} from "./crypto.js";
import { simulatedCompute, simulatedComputeDisagree } from "./compute/simulated.js";
import { llmCompute } from "./compute/llm.js";
import type { ComputationSpec } from "./compute/simulated.js";
import type { ApiClient } from "./api-client.js";

export interface ExecutionEvidence {
  provider_request_id?: string;
  model_echo?: string;
  token_counts?: object;
  timestamps?: object;
  request_body_hash?: string;
}

export class Agent {
  id: string;
  keypair: KeyPair;
  principalId: string;

  constructor(principalId: string, id?: string) {
    this.id = id ?? crypto.randomUUID();
    this.keypair = generateKeyPair();
    this.principalId = principalId;
  }

  get publicKeyHex(): string {
    return toHex(this.keypair.publicKey);
  }

  async computeResult(
    spec: ComputationSpec,
    mode: "simulated" | "llm",
    disagreeSalt?: string
  ): Promise<Uint8Array> {
    if (mode === "simulated") {
      if (disagreeSalt) {
        return simulatedComputeDisagree(spec, disagreeSalt);
      }
      return simulatedCompute(spec);
    } else {
      return llmCompute(spec);
    }
  }

  createSealData(
    spec: ComputationSpec,
    result: Uint8Array,
    evidence: ExecutionEvidence
  ): {
    fingerprint: Uint8Array;
    nonce: Uint8Array;
    sealHash: Uint8Array;
    sealSig: Uint8Array;
    evidenceHash: Uint8Array;
  } {
    const specJson = canonicalJson(spec);
    const fingerprint = computeFingerprint(specJson);
    const nonce = randomBytes(32);
    const evidenceHash = computeEvidenceHash(evidence);
    const sealHash = createSeal(fingerprint, this.id, result, evidenceHash, nonce);
    const sealSig = sign(sealHash, this.keypair.secretKey);
    return { fingerprint, nonce, sealHash, sealSig, evidenceHash };
  }

  async joinPool(api: ApiClient, poolId: string): Promise<void> {
    await api.joinPool(poolId, this.id, this.publicKeyHex, this.principalId);
  }

  async submitComputation(
    api: ApiClient,
    poolId: string,
    spec: ComputationSpec,
    result: Uint8Array,
    evidence: ExecutionEvidence
  ): Promise<{ roundId: string; fingerprint: string }> {
    const seal = this.createSealData(spec, result, evidence);
    const round = await api.submitCompute(
      poolId,
      this.id,
      spec,
      toHex(seal.sealHash),
      toHex(seal.sealSig)
    );
    return { roundId: round.round_id, fingerprint: round.fingerprint };
  }

  async submitSeal(
    api: ApiClient,
    poolId: string,
    roundId: string,
    spec: ComputationSpec,
    result: Uint8Array,
    evidence: ExecutionEvidence
  ): Promise<void> {
    const seal = this.createSealData(spec, result, evidence);
    await api.submitSeal(
      poolId,
      roundId,
      this.id,
      toHex(seal.sealHash),
      toHex(seal.sealSig)
    );
  }

  async submitReveal(
    api: ApiClient,
    poolId: string,
    roundId: string,
    result: Uint8Array,
    evidence: ExecutionEvidence,
    nonce: Uint8Array
  ): Promise<void> {
    await api.submitReveal(
      poolId,
      roundId,
      this.id,
      toHex(result),
      evidence,
      toHex(nonce)
    );
  }
}
