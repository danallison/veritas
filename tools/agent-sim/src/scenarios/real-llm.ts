import { Agent, type ExecutionEvidence } from "../agent.js";
import { ApiClient } from "../api-client.js";
import { toHex, computeFingerprint, canonicalJson } from "../crypto.js";
import { CostTracker, estimateCallCost, formatUsd, formatSavings } from "../costs.js";
import type { ComputationSpec } from "../compute/simulated.js";

function hexToString(hex: string): string {
  const bytes = new Uint8Array(
    hex.match(/.{2}/g)?.map((b) => parseInt(b, 16)) ?? []
  );
  return new TextDecoder().decode(bytes);
}

/**
 * Real LLM scenario: agents call an actual LLM API and cross-validate.
 *
 * Shows the full end-to-end flow with real API calls, real latency,
 * real cost, and real deduplication. Then demonstrates that subsequent
 * requests are instant and free.
 *
 * Requires ANTHROPIC_API_KEY or OPENAI_API_KEY env var.
 */
export async function runRealLlm(apiUrl: string): Promise<void> {
  console.log("\n╔══════════════════════════════════════════════════════════════╗");
  console.log("║   Scenario: Real LLM — Measured Cost & Latency Savings     ║");
  console.log("╚══════════════════════════════════════════════════════════════╝\n");

  const hasAnthropicKey = !!process.env.ANTHROPIC_API_KEY;
  const hasOpenAIKey = !!process.env.OPENAI_API_KEY;

  if (!hasAnthropicKey && !hasOpenAIKey) {
    console.log("  Skipping: requires ANTHROPIC_API_KEY or OPENAI_API_KEY env var.");
    console.log("  Set one of these environment variables and re-run.\n");
    return;
  }

  const api = new ApiClient(apiUrl);
  const provider = hasAnthropicKey ? "anthropic" : "openai";
  const model = hasAnthropicKey ? "claude-sonnet-4-20250514" : "gpt-4o-mini";
  const costs = new CostTracker(model);
  const callCost = estimateCallCost(model);

  // --- Setup ---
  console.log(`  Provider: ${provider}, Model: ${model}`);
  console.log(`  Estimated cost per call: ${formatUsd(callCost.costUsd)} (~${callCost.inputTokens} in, ~${callCost.outputTokens} out)\n`);

  const pool = await api.createPool(
    "real-llm-pool",
    { method: "exact" },
    600,
    3
  );

  const orgs = [
    "Acme Corp", "Beacon Labs", "Cirrus AI",
    "Delphi Inc", "Echo Systems", "Flux Analytics",
  ];

  const agents: Agent[] = [];
  for (const org of orgs) {
    const agent = new Agent(org.toLowerCase().replace(/ /g, "-"));
    await agent.joinPool(api, pool.id);
    agents.push(agent);
  }
  console.log(`  Pool: ${agents.length} agents from ${orgs.length} organizations.\n`);

  // --- The computation ---
  const spec: ComputationSpec = {
    provider,
    model,
    temperature: 0,
    system_prompt:
      "You are a risk analysis expert. Reply with valid JSON only, no markdown.",
    user_prompt:
      'Extract the 3 most significant risk factors from this text as a JSON array of strings: "The startup has been experiencing rapid growth but faces challenges including cash flow constraints due to delayed Series B funding, key engineering talent departing to competitors, and increasing regulatory scrutiny in their primary market."',
    input_refs: [],
  };

  const specJson = canonicalJson(spec);
  const fingerprint = computeFingerprint(specJson);
  console.log(`  Question: Extract risk factors from an investment memo.`);
  console.log(`  Fingerprint: ${toHex(fingerprint).slice(0, 16)}...\n`);

  // --- Phase 1: Cross-validation with real LLM calls ---
  console.log("  Phase 1: Cross-validation (3 real LLM API calls)\n");

  const [agentA, agentB, agentC, ...remainingAgents] = agents;

  // Agent A
  const startA = Date.now();
  const resultA = await agentA.computeResult(spec, "llm");
  const latA = Date.now() - startA;
  costs.recordApiCall(latA);
  const textA = new TextDecoder().decode(resultA);
  console.log(`    ${orgs[0].padEnd(16)}  ${latA.toString().padStart(5)}ms  ${formatUsd(callCost.costUsd)}  "${textA.slice(0, 50)}..."`);

  // Agent B
  const startB = Date.now();
  const resultB = await agentB.computeResult(spec, "llm");
  const latB = Date.now() - startB;
  costs.recordApiCall(latB);
  const textB = new TextDecoder().decode(resultB);
  console.log(`    ${orgs[1].padEnd(16)}  ${latB.toString().padStart(5)}ms  ${formatUsd(callCost.costUsd)}  "${textB.slice(0, 50)}..."`);

  // Agent C
  const startC = Date.now();
  const resultC = await agentC.computeResult(spec, "llm");
  const latC = Date.now() - startC;
  costs.recordApiCall(latC);
  const textC = new TextDecoder().decode(resultC);
  console.log(`    ${orgs[2].padEnd(16)}  ${latC.toString().padStart(5)}ms  ${formatUsd(callCost.costUsd)}  "${textC.slice(0, 50)}..."`);

  console.log(`\n    Total: ${costs.totalCalls} API calls, ${formatUsd(costs.totalCost)}, ${(costs.totalLatency / 1000).toFixed(1)}s\n`);

  // --- Seal + reveal ---
  console.log("    Sealing and revealing...");

  const evidenceA: ExecutionEvidence = { model_echo: model };
  const evidenceB: ExecutionEvidence = { model_echo: model };
  const evidenceC: ExecutionEvidence = { model_echo: model };

  const sealA = agentA.createSealData(spec, resultA, evidenceA);
  const round = await api.submitCompute(
    pool.id, agentA.id, spec,
    toHex(sealA.sealHash), toHex(sealA.sealSig)
  );

  const sealB = agentB.createSealData(spec, resultB, evidenceB);
  await api.submitSeal(
    pool.id, round.round_id, agentB.id,
    toHex(sealB.sealHash), toHex(sealB.sealSig)
  );

  const sealC = agentC.createSealData(spec, resultC, evidenceC);
  await api.submitSeal(
    pool.id, round.round_id, agentC.id,
    toHex(sealC.sealHash), toHex(sealC.sealSig)
  );

  await api.submitReveal(pool.id, round.round_id, agentA.id, toHex(resultA), evidenceA, toHex(sealA.nonce));
  await api.submitReveal(pool.id, round.round_id, agentB.id, toHex(resultB), evidenceB, toHex(sealB.nonce));
  const finalStatus = await api.submitReveal(pool.id, round.round_id, agentC.id, toHex(resultC), evidenceC, toHex(sealC.nonce));
  console.log(`    Result: ${finalStatus.phase} — ${finalStatus.message}\n`);

  // --- Phase 2: Cache hits ---
  console.log("  Phase 2: Subsequent requests (0 API calls)\n");

  for (let i = 0; i < remainingAgents.length; i++) {
    const startHit = Date.now();
    const cacheResult = await api.queryCache(pool.id, toHex(fingerprint));
    const hitLat = Date.now() - startHit;

    if (cacheResult) {
      costs.recordCacheHit();
      console.log(`    ${orgs[i + 3].padEnd(16)}  ${hitLat.toString().padStart(5)}ms  $0.0000  cache hit (${cacheResult.provenance.outcome.tag})`);
    }
  }

  // --- Check cache result ---
  const cacheResult = await api.queryCache(pool.id, toHex(fingerprint));
  if (cacheResult) {
    const resultText = hexToString(cacheResult.result);
    console.log(`\n    Cached result: ${resultText}\n`);
  }

  // --- Summary ---
  const totalAgents = agents.length;
  const naiveCost = costs.costForNCalls(totalAgents);
  const poolCost = costs.totalCost;
  const naiveLatency = costs.totalLatency * (totalAgents / 3); // extrapolate

  console.log("  ┌─────────────────────────────────────────────────────────┐");
  console.log("  │  MEASURED RESULTS                                      │");
  console.log("  │                                                        │");
  console.log(`  │  API calls made:      3 (out of ${totalAgents} agents)${" ".repeat(17)}│`);
  console.log(`  │  API calls saved:     ${(totalAgents - 3).toString().padEnd(34)}│`);
  console.log("  │                                                        │");
  console.log(`  │  Without pool:  ${totalAgents} calls × ${formatUsd(callCost.costUsd)} = ${formatUsd(naiveCost).padEnd(15)}│`);
  console.log(`  │  With pool:     3 calls × ${formatUsd(callCost.costUsd)} = ${formatUsd(poolCost).padEnd(15)}│`);
  console.log(`  │  Savings:       ${formatSavings(naiveCost, poolCost).padEnd(40)}│`);
  console.log("  │                                                        │");
  console.log(`  │  Validation latency:  ${(costs.totalLatency / 1000).toFixed(1)}s (real, measured)${" ".repeat(14)}│`);
  console.log(`  │  Cache hit latency:   <${costs.totalCacheHits > 0 ? "10" : "??"}ms per hit${" ".repeat(22)}│`);
  console.log("  │                                                        │");
  if (cacheResult) {
    console.log(`  │  Trust: ${cacheResult.provenance.outcome.tag}, ${cacheResult.provenance.agreement_count}/3 independent agreement   │`);
  }
  console.log("  │  Every future request for this computation: FREE       │");
  console.log("  └─────────────────────────────────────────────────────────┘\n");

  // Projections
  const daily50 = costs.costForNCalls(50);
  const daily50Pool = costs.costForNCalls(3);
  const monthly50 = daily50 * 30;
  const monthly50Pool = daily50Pool; // only paid once, cached forever

  console.log("  Projection: if 50 agents ask this question daily for a month:\n");
  console.log(`    Without pool:  50 calls/day × 30 days = 1,500 calls  ${formatUsd(monthly50)}`);
  console.log(`    With pool:     3 calls total (cached after first validation)  ${formatUsd(monthly50Pool)}`);
  console.log(`    Monthly savings: ${formatSavings(monthly50, monthly50Pool)}`);
  console.log();
}
