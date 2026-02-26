/**
 * Cost model for LLM inference.
 *
 * Prices per 1M tokens (as of early 2025):
 *   claude-sonnet-4: $3 input, $15 output
 *   gpt-4o-mini:     $0.15 input, $0.60 output
 *
 * For the demo we estimate a fixed cost per call based on typical
 * prompt size (~500 input tokens, ~200 output tokens).
 */

export interface CostEstimate {
  inputTokens: number;
  outputTokens: number;
  costUsd: number;
  latencyMs: number;
}

const MODEL_PRICING: Record<string, { inputPer1M: number; outputPer1M: number }> = {
  "claude-sonnet-4-20250514": { inputPer1M: 3.0, outputPer1M: 15.0 },
  "gpt-4o-mini": { inputPer1M: 0.15, outputPer1M: 0.60 },
};

const DEFAULT_INPUT_TOKENS = 500;
const DEFAULT_OUTPUT_TOKENS = 200;

export function estimateCallCost(model: string): CostEstimate {
  const pricing = MODEL_PRICING[model] ?? { inputPer1M: 3.0, outputPer1M: 15.0 };
  const inputCost = (DEFAULT_INPUT_TOKENS / 1_000_000) * pricing.inputPer1M;
  const outputCost = (DEFAULT_OUTPUT_TOKENS / 1_000_000) * pricing.outputPer1M;
  return {
    inputTokens: DEFAULT_INPUT_TOKENS,
    outputTokens: DEFAULT_OUTPUT_TOKENS,
    costUsd: inputCost + outputCost,
    latencyMs: 0, // filled in by caller
  };
}

export function formatUsd(amount: number): string {
  if (amount < 0.01) {
    return `$${(amount * 100).toFixed(3)}¢`.replace("$", "").replace("¢", "") + "¢";
  }
  return `$${amount.toFixed(4)}`;
}

export function formatSavings(withoutPool: number, withPool: number): string {
  const saved = withoutPool - withPool;
  const pct = ((saved / withoutPool) * 100).toFixed(0);
  return `${formatUsd(saved)} saved (${pct}% reduction)`;
}

export class CostTracker {
  private calls: CostEstimate[] = [];
  private cacheHits = 0;
  private model: string;

  constructor(model: string) {
    this.model = model;
  }

  recordApiCall(latencyMs: number): CostEstimate {
    const est = estimateCallCost(this.model);
    est.latencyMs = latencyMs;
    this.calls.push(est);
    return est;
  }

  recordCacheHit(): void {
    this.cacheHits++;
  }

  get totalCalls(): number {
    return this.calls.length;
  }

  get totalCost(): number {
    return this.calls.reduce((sum, c) => sum + c.costUsd, 0);
  }

  get totalLatency(): number {
    return this.calls.reduce((sum, c) => sum + c.latencyMs, 0);
  }

  get totalCacheHits(): number {
    return this.cacheHits;
  }

  costForNCalls(n: number): number {
    return n * estimateCallCost(this.model).costUsd;
  }
}
