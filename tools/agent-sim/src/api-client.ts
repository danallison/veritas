export interface PoolResponse {
  id: string;
  name: string;
  comparison_method: object;
  compute_deadline_seconds: number;
  min_principals: number;
  created_at: string;
}

export interface PoolMemberResponse {
  agent_id: string;
  public_key: string;
  principal_id: string;
  joined_at: string;
}

export interface ValidationRoundResponse {
  round_id: string;
  fingerprint: string;
  phase: string;
  created_at: string;
}

export interface RoundStatusResponse {
  round_id: string;
  phase: string;
  message: string;
}

export interface CacheEntryResponse {
  fingerprint: string;
  result: string;
  provenance: {
    outcome: { tag: string; dissenter?: string };
    agreement_count: number;
    beacon_round?: number;
    selection_proof?: string;
    validated_at: string;
  };
  created_at: string;
  expires_at?: string;
}

export class ApiClient {
  constructor(private baseUrl: string) {}

  private async request<T>(
    method: string,
    path: string,
    body?: object
  ): Promise<T> {
    const url = `${this.baseUrl}${path}`;
    const options: RequestInit = {
      method,
      headers: { "Content-Type": "application/json" },
    };
    if (body) {
      options.body = JSON.stringify(body);
    }
    const response = await fetch(url, options);
    if (!response.ok) {
      const text = await response.text();
      throw new Error(`${method} ${path} failed (${response.status}): ${text}`);
    }
    return response.json() as Promise<T>;
  }

  async createPool(
    name: string,
    comparisonMethod: object,
    computeDeadlineSeconds: number,
    minPrincipals: number
  ): Promise<PoolResponse> {
    return this.request("POST", "/pools", {
      name,
      comparison_method: comparisonMethod,
      compute_deadline_seconds: computeDeadlineSeconds,
      min_principals: minPrincipals,
    });
  }

  async getPool(poolId: string): Promise<PoolResponse> {
    return this.request("GET", `/pools/${poolId}`);
  }

  async joinPool(
    poolId: string,
    agentId: string,
    publicKey: string,
    principalId: string
  ): Promise<PoolMemberResponse> {
    return this.request("POST", `/pools/${poolId}/join`, {
      agent_id: agentId,
      public_key: publicKey,
      principal_id: principalId,
    });
  }

  async listMembers(poolId: string): Promise<PoolMemberResponse[]> {
    return this.request("GET", `/pools/${poolId}/members`);
  }

  async queryCache(
    poolId: string,
    fingerprint: string
  ): Promise<CacheEntryResponse | null> {
    try {
      return await this.request(
        "GET",
        `/pools/${poolId}/cache/${fingerprint}`
      );
    } catch (e) {
      if (e instanceof Error && e.message.includes("404")) return null;
      throw e;
    }
  }

  async submitCompute(
    poolId: string,
    agentId: string,
    computationSpec: object,
    sealHash: string,
    sealSig: string
  ): Promise<ValidationRoundResponse> {
    return this.request("POST", `/pools/${poolId}/compute`, {
      agent_id: agentId,
      computation_spec: computationSpec,
      seal_hash: sealHash,
      seal_sig: sealSig,
    });
  }

  async getRoundStatus(
    poolId: string,
    roundId: string
  ): Promise<RoundStatusResponse> {
    return this.request("GET", `/pools/${poolId}/rounds/${roundId}`);
  }

  async submitSeal(
    poolId: string,
    roundId: string,
    agentId: string,
    sealHash: string,
    sealSig: string
  ): Promise<RoundStatusResponse> {
    return this.request("POST", `/pools/${poolId}/rounds/${roundId}/seal`, {
      agent_id: agentId,
      seal_hash: sealHash,
      seal_sig: sealSig,
    });
  }

  async submitReveal(
    poolId: string,
    roundId: string,
    agentId: string,
    result: string,
    evidence: object,
    nonce: string
  ): Promise<RoundStatusResponse> {
    return this.request("POST", `/pools/${poolId}/rounds/${roundId}/reveal`, {
      agent_id: agentId,
      result,
      evidence,
      nonce,
    });
  }
}
