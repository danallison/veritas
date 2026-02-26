import { Agent, type ExecutionEvidence } from "../agent.js";
import { ApiClient } from "../api-client.js";
import { toHex, computeFingerprint, canonicalJson } from "../crypto.js";
import { CostTracker, formatUsd } from "../costs.js";
import type { ComputationSpec } from "../compute/simulated.js";

/**
 * Scenario: Error Detection
 *
 * One agent produces a wrong result — maybe a corrupted API response,
 * a misconfigured model, or a compromised agent. Without cross-validation,
 * the bad result gets used silently. With the pool, the error is caught,
 * the correct result is cached, and the bad actor is identified.
 *
 * This scenario shows the cost of NOT detecting errors vs. the cost of
 * cross-validation that catches them.
 */
export async function runDisagreement(apiUrl: string): Promise<void> {
  console.log("\n╔══════════════════════════════════════════════════════════════╗");
  console.log("║   Scenario: Error Detection — Catching a Bad Result        ║");
  console.log("╚══════════════════════════════════════════════════════════════╝\n");

  const api = new ApiClient(apiUrl);
  const model = "claude-sonnet-4-20250514";
  const costs = new CostTracker(model);

  // --- Setup ---
  const pool = await api.createPool(
    "compliance-analysis-pool",
    { method: "exact" },
    300,
    3
  );

  const orgs = ["Alpha Fund", "Beta Capital", "Gamma Advisors", "Delta Partners"];
  const agents: Agent[] = [];
  for (const org of orgs) {
    const agent = new Agent(org.toLowerCase().replace(/ /g, "-"));
    await agent.joinPool(api, pool.id);
    agents.push(agent);
  }

  // A compliance question where the wrong answer has serious consequences
  const spec: ComputationSpec = {
    provider: "anthropic",
    model,
    temperature: 0,
    system_prompt:
      "You are a regulatory compliance expert. Reply with valid JSON only.",
    user_prompt:
      'Analyze this transaction for compliance flags. Return JSON with "compliant" (boolean), "flags" (array of strings), "risk_level" ("low"|"medium"|"high"|"critical"): "Wire transfer of $2.4M from a newly opened account to an offshore entity in a jurisdiction with no bilateral tax treaty, initiated by a recently added authorized signer who was onboarded without in-person verification."',
    input_refs: [],
  };

  const [agentA, agentB, agentC] = agents;

  console.log("  Situation: 3 agents independently analyze a suspicious transaction");
  console.log("  for regulatory compliance. One agent returns a WRONG answer.\n");

  // --- Without cross-validation ---
  console.log("  ┌─────────────────────────────────────────────────────────┐");
  console.log("  │  WITHOUT cross-validation:                             │");
  console.log("  │                                                        │");
  console.log("  │    Agent asks LLM → gets answer → uses it directly     │");
  console.log("  │                                                        │");
  console.log('  │    If the answer is wrong (e.g., says "compliant"      │');
  console.log("  │    when the transaction is clearly suspicious):        │");
  console.log("  │                                                        │");
  console.log("  │    • No way to detect the error                        │");
  console.log("  │    • Bad result gets acted on silently                  │");
  console.log("  │    • Potential regulatory violation                     │");
  console.log("  │    • Cost of undetected error: $$$$ (fines, liability) │");
  console.log("  └─────────────────────────────────────────────────────────┘\n");

  // --- With cross-validation ---
  console.log("  WITH cross-validation:\n");

  // Agent A computes honestly
  console.log("    Step 1: All 3 agents compute independently and submit sealed results\n");

  const resultA = await agentA.computeResult(spec, "simulated");
  costs.recordApiCall(1200);
  const evidenceA: ExecutionEvidence = { model_echo: model };
  const sealA = agentA.createSealData(spec, resultA, evidenceA);

  const round = await api.submitCompute(
    pool.id,
    agentA.id,
    spec,
    toHex(sealA.sealHash),
    toHex(sealA.sealSig)
  );
  console.log(`      ${orgs[0].padEnd(16)}  computes honestly    → sealed  [${formatUsd(costs.costForNCalls(1))}]`);

  // Agent B computes honestly
  const resultB = await agentB.computeResult(spec, "simulated");
  costs.recordApiCall(1100);
  const evidenceB: ExecutionEvidence = { model_echo: model };
  const sealB = agentB.createSealData(spec, resultB, evidenceB);
  await api.submitSeal(
    pool.id,
    round.round_id,
    agentB.id,
    toHex(sealB.sealHash),
    toHex(sealB.sealSig)
  );
  console.log(`      ${orgs[1].padEnd(16)}  computes honestly    → sealed  [${formatUsd(costs.costForNCalls(1))}]`);

  // Agent C produces WRONG result
  const resultC = await agentC.computeResult(spec, "simulated", "corrupted-response");
  costs.recordApiCall(1300);
  const evidenceC: ExecutionEvidence = { model_echo: model };
  const sealC = agentC.createSealData(spec, resultC, evidenceC);
  await api.submitSeal(
    pool.id,
    round.round_id,
    agentC.id,
    toHex(sealC.sealHash),
    toHex(sealC.sealSig)
  );
  console.log(`      ${orgs[2].padEnd(16)}  WRONG result (!)     → sealed  [${formatUsd(costs.costForNCalls(1))}]`);

  // Reveal phase
  console.log("\n    Step 2: All 3 reveal their results\n");

  await api.submitReveal(pool.id, round.round_id, agentA.id, toHex(resultA), evidenceA, toHex(sealA.nonce));
  console.log(`      ${orgs[0].padEnd(16)}  reveals → matches majority`);

  await api.submitReveal(pool.id, round.round_id, agentB.id, toHex(resultB), evidenceB, toHex(sealB.nonce));
  console.log(`      ${orgs[1].padEnd(16)}  reveals → matches majority`);

  const finalStatus = await api.submitReveal(
    pool.id,
    round.round_id,
    agentC.id,
    toHex(resultC),
    evidenceC,
    toHex(sealC.nonce)
  );
  console.log(`      ${orgs[2].padEnd(16)}  reveals → DOES NOT MATCH ✗`);

  // Check provenance
  console.log("\n    Step 3: Protocol outcome\n");
  const fp = computeFingerprint(canonicalJson(spec));
  const cacheResult = await api.queryCache(pool.id, toHex(fp));
  if (cacheResult) {
    const outcome = cacheResult.provenance.outcome;
    console.log(`      Outcome:    ${outcome.tag} (${cacheResult.provenance.agreement_count}/3 agree)`);
    if (outcome.dissenter) {
      // Find which org the dissenter is
      const dissenterAgent = agents.find(a => a.id === outcome.dissenter);
      const dissenterOrg = dissenterAgent
        ? orgs[agents.indexOf(dissenterAgent)]
        : "unknown";
      console.log(`      Dissenter:  ${dissenterOrg} (agent ${outcome.dissenter.slice(0, 8)}...)`);
    }
    console.log(`      Result:     Correct (majority) result is cached`);
    console.log(`      Bad result: Discarded — never reaches any consumer`);
  }

  // Summary
  const validationCost = costs.totalCost;
  const singleCallCost = costs.costForNCalls(1);

  console.log("\n  ┌─────────────────────────────────────────────────────────┐");
  console.log("  │  RESULT                                                │");
  console.log("  │                                                        │");
  console.log(`  │  Cross-validation cost: ${formatUsd(validationCost).padEnd(32)}│`);
  console.log(`  │  Cost per agent (amortized over pool): ${formatUsd(validationCost).padEnd(17)}│`);
  console.log(`  │  Additional cost vs. single call: ${formatUsd(validationCost - singleCallCost).padEnd(22)}│`);
  console.log("  │                                                        │");
  console.log("  │  What you get for that cost:                           │");
  console.log("  │    ✓ Bad result caught before anyone acts on it        │");
  console.log("  │    ✓ Correct result identified and cached              │");
  console.log("  │    ✓ Bad actor identified with cryptographic proof     │");
  console.log("  │    ✓ All future queries get the validated result free  │");
  console.log("  │                                                        │");
  console.log("  │  Cost of NOT detecting (compliance scenario):          │");
  console.log("  │    Regulatory fines, legal liability, reputational     │");
  console.log("  │    damage — orders of magnitude more expensive than    │");
  console.log(`  │    the ${formatUsd(validationCost - singleCallCost)} cross-validation overhead.${" ".repeat(14)}│`);
  console.log("  └─────────────────────────────────────────────────────────┘\n");
}
