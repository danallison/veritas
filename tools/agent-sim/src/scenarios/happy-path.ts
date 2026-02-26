import { Agent, type ExecutionEvidence } from "../agent.js";
import { ApiClient } from "../api-client.js";
import { toHex, computeFingerprint, canonicalJson } from "../crypto.js";
import { CostTracker, formatUsd, formatSavings } from "../costs.js";
import type { ComputationSpec } from "../compute/simulated.js";

/**
 * Scenario: Deduplication at Scale
 *
 * 10 agents from 10 different organizations all need the answer to the
 * same question. Without a pool, each would call the LLM independently —
 * 10 API calls. With the pool, 3 agents cross-validate and the other 7
 * get instant cache hits.
 *
 * This scenario quantifies the cost and latency savings.
 */
export async function runHappyPath(apiUrl: string): Promise<void> {
  console.log("\n╔══════════════════════════════════════════════════════════════╗");
  console.log("║   Scenario: Deduplication — 10 Agents, Same Question       ║");
  console.log("╚══════════════════════════════════════════════════════════════╝\n");

  const api = new ApiClient(apiUrl);
  const model = "claude-sonnet-4-20250514";
  const costs = new CostTracker(model);

  // --- Setup ---
  console.log("  Setup: 10 agents from 10 organizations join a shared pool.\n");

  const pool = await api.createPool(
    "risk-analysis-pool",
    { method: "exact" },
    300,
    3
  );

  const orgNames = [
    "Acme Corp", "Beacon Labs", "Cirrus AI", "Delphi Inc",
    "Echo Systems", "Flux Analytics", "Granite AI", "Helix Data",
    "Ionic Research", "Jade Partners",
  ];

  const agents: Agent[] = [];
  for (const org of orgNames) {
    const agent = new Agent(org.toLowerCase().replace(/ /g, "-"));
    await agent.joinPool(api, pool.id);
    agents.push(agent);
  }
  console.log(`  Pool created with ${agents.length} agents from ${orgNames.length} organizations.\n`);

  // --- The question every agent needs answered ---
  const spec: ComputationSpec = {
    provider: "anthropic",
    model,
    temperature: 0,
    system_prompt:
      "You are a risk analysis expert. Reply with valid JSON only, no markdown.",
    user_prompt:
      'Analyze this investment scenario and return a JSON object with keys "risk_score" (1-10), "risk_factors" (array of strings), and "recommendation" (string): "Series B startup, 18 months runway, 40% MoM growth, single enterprise client represents 60% of revenue, founding CTO just departed, regulatory approval pending in EU market."',
    input_refs: [],
  };
  const specJson = canonicalJson(spec);
  const fingerprint = computeFingerprint(specJson);

  console.log("  Question: Analyze risk factors for a Series B startup investment.");
  console.log(`  Fingerprint: ${toHex(fingerprint).slice(0, 16)}...\n`);

  // --- Without the pool: every agent calls the LLM ---
  const naiveCost = costs.costForNCalls(10);
  const naiveLatencyEstimate = 10 * 1500; // ~1.5s per call
  console.log("  ┌─────────────────────────────────────────────────────────┐");
  console.log("  │  WITHOUT the pool (naive approach):                    │");
  console.log(`  │    10 agents × 1 LLM call each = 10 API calls          │`);
  console.log(`  │    Estimated cost:   ${formatUsd(naiveCost).padEnd(36)}│`);
  console.log(`  │    Estimated time:   ${(naiveLatencyEstimate / 1000).toFixed(1)}s (sequential)${" ".repeat(19)}│`);
  console.log("  │    Trust guarantee:  NONE — each trusts only itself     │");
  console.log("  └─────────────────────────────────────────────────────────┘\n");

  // --- With the pool: 3 cross-validate, 7 get cache hits ---
  console.log("  WITH the pool:\n");

  // Phase 1: First 3 agents cross-validate
  console.log("  Phase 1: Cross-validation (3 API calls)\n");

  const [agentA, agentB, agentC, ...remainingAgents] = agents;

  // Agent A computes and submits
  const startA = Date.now();
  const resultA = await agentA.computeResult(spec, "simulated");
  const latA = Date.now() - startA;
  costs.recordApiCall(latA);
  const evidenceA: ExecutionEvidence = { model_echo: model };
  const sealA = agentA.createSealData(spec, resultA, evidenceA);

  const round = await api.submitCompute(
    pool.id,
    agentA.id,
    spec,
    toHex(sealA.sealHash),
    toHex(sealA.sealSig)
  );
  console.log(`    Agent 1  (${orgNames[0].padEnd(16)})  computes + submits seal    [${formatUsd(costs.costForNCalls(1))}]`);

  // Agent B computes and submits seal
  const startB = Date.now();
  const resultB = await agentB.computeResult(spec, "simulated");
  const latB = Date.now() - startB;
  costs.recordApiCall(latB);
  const evidenceB: ExecutionEvidence = { model_echo: model };
  const sealB = agentB.createSealData(spec, resultB, evidenceB);
  await api.submitSeal(
    pool.id,
    round.round_id,
    agentB.id,
    toHex(sealB.sealHash),
    toHex(sealB.sealSig)
  );
  console.log(`    Agent 2  (${orgNames[1].padEnd(16)})  computes + submits seal    [${formatUsd(costs.costForNCalls(1))}]`);

  // Agent C computes and submits seal
  const startC = Date.now();
  const resultC = await agentC.computeResult(spec, "simulated");
  const latC = Date.now() - startC;
  costs.recordApiCall(latC);
  const evidenceC: ExecutionEvidence = { model_echo: model };
  const sealC = agentC.createSealData(spec, resultC, evidenceC);
  await api.submitSeal(
    pool.id,
    round.round_id,
    agentC.id,
    toHex(sealC.sealHash),
    toHex(sealC.sealSig)
  );
  console.log(`    Agent 3  (${orgNames[2].padEnd(16)})  computes + submits seal    [${formatUsd(costs.costForNCalls(1))}]`);

  // Reveal phase
  await api.submitReveal(pool.id, round.round_id, agentA.id, toHex(resultA), evidenceA, toHex(sealA.nonce));
  await api.submitReveal(pool.id, round.round_id, agentB.id, toHex(resultB), evidenceB, toHex(sealB.nonce));
  const finalStatus = await api.submitReveal(pool.id, round.round_id, agentC.id, toHex(resultC), evidenceC, toHex(sealC.nonce));

  console.log(`\n    All 3 reveal → ${finalStatus.phase}: ${finalStatus.message}`);
  console.log(`    Cross-validation cost: ${formatUsd(costs.totalCost)} (3 API calls)\n`);

  // Phase 2: Remaining 7 agents get cache hits
  console.log("  Phase 2: Cache hits (0 API calls)\n");

  for (let i = 0; i < remainingAgents.length; i++) {
    const cacheResult = await api.queryCache(pool.id, toHex(fingerprint));
    if (cacheResult) {
      costs.recordCacheHit();
      console.log(
        `    Agent ${(i + 4).toString().padEnd(2)} (${orgNames[i + 3].padEnd(16)})  cache hit — instant result   [$0.0000]`
      );
    }
  }

  // --- Summary ---
  const poolCost = costs.totalCost;
  console.log("\n  ┌─────────────────────────────────────────────────────────┐");
  console.log("  │  RESULT COMPARISON                                     │");
  console.log("  │                                                        │");
  console.log(`  │  Without pool:  10 API calls    ${formatUsd(naiveCost).padEnd(22)} │`);
  console.log(`  │  With pool:      3 API calls    ${formatUsd(poolCost).padEnd(22)} │`);
  console.log(`  │  Savings:        7 calls saved  ${formatSavings(naiveCost, poolCost).padEnd(22)} │`);
  console.log("  │                                                        │");
  console.log(`  │  Cache hits: ${costs.totalCacheHits} of 10 agents got instant results       │`);
  console.log("  │  Trust: all 10 agents have cryptographic provenance     │");
  console.log(`  │  Provenance: Unanimous (3/3 agreement)                  │`);
  console.log("  └─────────────────────────────────────────────────────────┘\n");

  // Scale projection
  const agents50 = costs.costForNCalls(50);
  const pool50 = costs.costForNCalls(3);
  const agents100 = costs.costForNCalls(100);
  const pool100 = costs.costForNCalls(3);

  console.log("  Scale projection (same question, more agents):\n");
  console.log(`    Agents   Without Pool      With Pool        Savings`);
  console.log(`    ──────   ────────────────   ──────────────   ──────────────────`);
  console.log(`    10       ${formatUsd(naiveCost).padEnd(17)}  ${formatUsd(poolCost).padEnd(15)}  ${formatSavings(naiveCost, poolCost)}`);
  console.log(`    50       ${formatUsd(agents50).padEnd(17)}  ${formatUsd(pool50).padEnd(15)}  ${formatSavings(agents50, pool50)}`);
  console.log(`    100      ${formatUsd(agents100).padEnd(17)}  ${formatUsd(pool100).padEnd(15)}  ${formatSavings(agents100, pool100)}`);

  console.log("\n  The cost of the pool is fixed at 3 API calls regardless of");
  console.log("  how many agents need the answer.\n");
}
