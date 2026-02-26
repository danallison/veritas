# Common-Pool Computing: Cross-Validated Computation Cache

## 1. Overview

A shared cache of computation results (primarily LLM inference) that have been independently computed by 3 agents and cross-validated before entry. Members query the cache; hits return validated results, misses trigger a validation round. The cache has two externally visible states: validated entry or no entry.

The requester computes first (they need the result anyway), then 2 validators are selected via drand beacon. All 3 submit sealed results before any are revealed. If 2 or 3 agree, the result is cached. If all 3 differ, nothing is cached.

Trust assumptions are explicit: commit-reveal seals prevent copying, signed seals prevent the server from fabricating participation, per-member sigchains provide independent participation records, and a Merkle tree over the audit log with externally published roots prevents equivocation. The server is trusted for real-time coordination but constrained by after-the-fact verifiability.

---

## 2. The Cache

The cache is a key-value store. Keys are content-addressed computation fingerprints. Values are cross-validated results with provenance. Only pool members can read or write.

### Two-State Rule

For any fingerprint, the cache is either:
1. **Validated entry exists** — cross-validated (2/3 or 3/3 agreement), with provenance and audit trail.
2. **No entry** — not yet requested, validation in progress, or validation failed. These are indistinguishable from outside.

There is no pending, unvalidated, or partial state visible to consumers. Internally, the system tracks in-progress validations and deduplicates concurrent requests for the same fingerprint, but this is invisible to callers. A query returns either a validated result or nothing.

### Immutability

Once cached, an entry cannot be overridden by a new validation. This prevents an attacker from re-triggering validations until they get a favorable validator draw. Removal occurs only through:
- **TTL expiration.** The entry's optional TTL elapses.
- **Successful challenge.** Fresh validators determine the entry is incorrect (Section 5).

### Freshness

The computation spec can include an optional TTL. The preferred approach is point-in-time scoping — referencing inputs by content hash or version — which produces stable cache keys without TTL.

### Data Structures

```
CacheEntry:
  fingerprint:       ContentHash        -- SHA-256 of canonical computation spec
  result:            Bytes
  provenance:        ResultProvenance
  computation_spec:  ComputationSpec
  created_at:        UTCTime
  expires_at:        Maybe UTCTime
  audit_count:       Natural
  last_audited_at:   Maybe UTCTime

ResultProvenance:
  outcome:           Unanimous | Majority
  agreement_count:   3 | 2
  dissenter_id:      Maybe AgentId
  dissent_summary:   Maybe Text
  beacon_round:      Natural            -- drand round used for validator selection
  selection_proof:   Bytes              -- drand signature for the round
  audit_log_hash:    ContentHash        -- Merkle root at time of validation
  evidence_refs:     [EvidenceRef]      -- references to archived execution evidence
  validated_at:      UTCTime
```

---

## 3. Content-Addressed Computation

Every computation has a canonical spec that hashes to a fingerprint:

```
fingerprint = SHA-256(canonical_bytes(computation_spec))
```

The fingerprint is the cache key. Two agents constructing the same spec produce the same fingerprint.

Canonicalization requires deterministic serialization: sorted keys, normalized whitespace, pinned model versions, content-addressed input references. Two semantically identical specs must produce identical bytes.

### What's in the fingerprint

**Included:** full computation spec (model, parameters, prompts, output schema), content-addressed references to all inputs (SHA-256 of input data + retrieval reference: URL, IPFS CID, etc.).

**Excluded:** agent identity, timestamps, requester metadata, comparison method (pool-level setting, not part of what defines the computation).

### Input accessibility

Validators must obtain the same inputs. The computation spec includes both a content hash (authoritative identifier) and a retrieval reference (how to fetch the data). Validators fetch via the retrieval reference, verify the hash matches, then compute. Hash mismatch or retrieval failure is reported as a failure, not a dissent.

### LLM Inference Spec

```
InferenceSpec:
  provider:          "openai" | "anthropic" | "google" | ...
  model:             "claude-sonnet-4-20250514"    -- exact version, not "latest"
  temperature:       0                              -- required for determinism
  seed:              Maybe Integer                  -- if provider supports it
  max_tokens:        Integer
  system_prompt:     Text                           -- exact bytes
  user_prompt:       Text                           -- exact bytes
  tools:             [ToolSpec]
  structured_output: Maybe OutputSchema             -- JSON schema for output
  stop_sequences:    [Text]
```

### Comparison Methods

**Exact.** Byte-for-byte equality after canonical serialization.

**Canonical.** JSON keys sorted, numbers rounded to specified precision, whitespace/Unicode normalized.

**Field-level.** For structured output: each field compared independently (numeric tolerance, enum exact match, text normalization). Recommended for most LLM tasks.

**Semantic equivalence.** TBD. Requires a judge model, which introduces its own error rate. If used, the judge call itself must be deterministic and specified. Deferred — use field-level comparison for v1.

---

## 4. Validation Protocol

### 4.1. Protocol Flow

```
1. Agent A queries the cache for fingerprint F.
   → Hit: return validated result. Done.
   → Miss: proceed.

2. Agent A computes the result locally.

3. Agent A constructs a seal and signs it:
   evidence_hash_A = SHA-256(canonical_bytes(execution_evidence_A))
   seal_A = SHA-256(fingerprint || agent_A_id || result_bytes_A || evidence_hash_A || nonce_A)
   seal_sig_A = Ed25519_Sign(agent_A_private_key, seal_A)

   Agent A submits (seal_A, seal_sig_A) to the server.
   Agent A records a SealSubmitted link in their sigchain.
   Result bytes and evidence remain with Agent A.

4. Server selects 2 validators:
   eligible = pool_members - {agent_A} - same_principal(agent_A)
   beacon = drand_beacon(next_unpublished_round)
   validators = stratified_select(eligible, beacon.signature, 2)
   -- see Section 4.2 for stratified_select

   Server commits the selection hash to the audit log BEFORE
   notifying validators.

   Validators receive ONLY the computation spec.
   They do not learn: who the requester is, that a sealed
   answer exists, or who the other validator is.

5. Each validator computes independently, constructs and signs a seal:
   evidence_hash_Vi = SHA-256(canonical_bytes(execution_evidence_Vi))
   seal_Vi = SHA-256(fingerprint || validator_i_id || result_bytes_Vi || evidence_hash_Vi || nonce_Vi)
   seal_sig_Vi = Ed25519_Sign(validator_i_private_key, seal_Vi)

   Each validator records a SealSubmitted link in their sigchain.

6. Once all 3 signed seals are received — and ONLY then — all
   3 parties reveal: (result_bytes, execution_evidence, nonce).

7. Server verifies each reveal:
   - Recompute seal from revealed values; must match submitted seal.
   - Verify seal_sig against agent's public key.
   - Recompute evidence_hash from revealed evidence; must match
     the evidence_hash embedded in the seal.

8. Cross-validation:
   - 3/3 agree → cache as Unanimous
   - 2/3 agree → cache as Majority; dissenter recorded
   - 1/1/1    → nothing cached; validation failed
```

### 4.2. Validator Selection

Selection uses the drand external randomness beacon.

**Procedure:**

1. When the requester submits their seal, the server records the next unpublished drand round number.
2. When that round publishes, the server uses `beacon.signature` as seed.
3. Deterministic selection with stratification constraints:

```
stratified_select(eligible, seed, count):
  shuffled = deterministic_shuffle(eligible, seed)
  -- deterministic_shuffle: seed the PRNG with `seed`,
  -- Fisher-Yates shuffle over `eligible`
  selected = []
  used_principals = {requester.principal_id}
  for agent in shuffled:
    if agent.principal_id not in used_principals:
      selected.append(agent)
      used_principals.add(agent.principal_id)
    if len(selected) == count:
      break
  return selected
```

4. The selection, beacon round, and beacon signature are recorded in the audit log.
5. Anyone can verify: fetch the drand round, re-run `stratified_select`, confirm the same validators.

**Stratification constraint (hard):** All 3 participants (requester + 2 validators) must be from different principals. If the pool lacks 3 different principals among eligible members, the validation cannot proceed.

**Exclusion rules (soft):**
- **No self-audit.** A participant in a validation is ineligible to audit or challenge-validate that cache entry.
- **Pair cooling.** Agents who were recently co-validators are deprioritized (not excluded) from being paired again for the next K rounds. K is a pool parameter.
- **Rotation fairness.** After serving as validator, an agent is deprioritized for the next selection cycle.

These soft rules are applied as ordering preferences within `stratified_select`: deprioritized agents sort later in the shuffled list but are not removed from it. If the pool is small, they may still be selected.

### 4.3. Execution Evidence

Every participant submits execution evidence. The evidence hash is included in the seal, so evidence is committed at seal time and cannot be changed after.

```
ExecutionEvidence:
  provider_request_id:    Text        -- unique ID from inference provider
  provider_model_echo:    Text        -- model version echoed by provider
  token_count_prompt:     Natural
  token_count_completion: Natural
  request_timestamp:      UTCTime
  response_timestamp:     UTCTime
  full_response_body:     Bytes       -- complete provider response
  request_body_hash:      ContentHash -- SHA-256 of the exact request sent
```

Evidence is archival and deterrent. It is not programmatically verified during validation — it is archived in the audit log for community auditors to review. Auditors can check:
- Plausibility of timing (response after request, latency consistent with model/prompt)
- Consistency of `provider_request_id` format with real provider IDs
- Whether `request_body_hash` matches the computation spec
- Whether `full_response_body` contains metadata consistent with provider output

Evidence is revealed alongside the result in step 6 (not submitted separately). The evidence hash in the seal binds the evidence at seal time.

### 4.4. Timing

The requester seals *before* the drand round is published. This means the requester cannot know the validator draw when they commit. The server records the next unpublished round number at seal submission time; the actual selection happens when that round publishes.

**Deadlines.** Each phase has a configurable deadline (pool parameter). If a validator fails to submit a seal by the compute deadline, the pool's non-performance policy applies (see Section 6).

### 4.5. Independence Guarantees

Organized by strength:

**Cryptographic (mathematically enforced):**
- Commit-reveal: all seals submitted before any reveal. Copying requires a SHA-256 collision.
- Server never holds plaintext results during sealing — only hashes. The server cannot leak what it doesn't have.
- Signed seals: every seal is Ed25519-signed by the participant. Server cannot fabricate participation.

**Structural (enforced by protocol design):**
- Validators receive only the computation spec. No information about the requester, existing seals, or other validators.
- Validator identities hidden from each other and from the requester until reveal.
- Stratified selection: all 3 from different principals (hard constraint).

**Accountable (detectable after the fact):**
- Execution evidence makes lazy copying detectable by auditors.
- Audit log records all server actions; sigchains provide independent participant records; cross-verification detects discrepancies.

---

## 5. Challenges and Audits

### 5.1. Random Audits

The protocol periodically selects an auditor (via drand beacon) to audit a cache entry. The auditor:
1. Re-runs the computation.
2. Compares against the cached result.
3. Reviews execution evidence from the original 3 participants.
4. Submits: Confirmed, Suspicious, or Invalidated.

If Suspicious or Invalidated, escalates to a challenge.

### 5.2. Challenge Process

Any member can challenge a cache entry. The process is the same whether triggered by a random audit, an original dissenter, or any member who doubts an entry.

1. Challenger posts a challenge stake.
2. Server selects 3 fresh validators via drand beacon. Ineligible: the original 3 participants and the challenger.
3. The 3 fresh validators independently compute, seal, and reveal (same commit-reveal protocol as initial validation, including signed seals and execution evidence).
4. Outcome:
   - **2+ fresh validators disagree with cached entry** → challenge succeeds. Entry removed. Original participants' evidence reviewed. Challenger's stake returned + reward.
   - **2+ fresh validators confirm cached entry** → challenge fails. Challenger's stake forfeited.
   - **1/1/1** → inconclusive. Entry removed as unreliable. No sanctions. Challenger's stake returned.

The challenger never votes. Outcome is determined entirely by the 3 fresh validators.

### 5.3. Standing Audit Committee

Individual random auditors see one entry in isolation. A standing committee provides pattern detection across entries.

A group of N members (pool parameter, e.g., 5) is selected by lot (drand beacon) for a fixed term (pool parameter, e.g., 30 days). Committee members:
- Review validation evidence across entries (detecting patterns like sequential provider_request_ids from supposedly different providers).
- Initiate challenges based on pattern analysis.
- Cross-verify server audit log against participants' sigchains.

At term end, a new committee is selected. No member serves consecutive terms.

### Data Structures

```
ChallengeRound:
  cache_fingerprint:   ContentHash
  challenger_id:       AgentId
  challenge_stake:     Natural
  validator_1_id:      Maybe AgentId
  validator_1_seal:    Maybe ByteString
  validator_1_seal_sig: Maybe Ed25519Signature
  validator_1_evidence: Maybe ExecutionEvidence
  validator_2_id:      Maybe AgentId
  validator_2_seal:    Maybe ByteString
  validator_2_seal_sig: Maybe Ed25519Signature
  validator_2_evidence: Maybe ExecutionEvidence
  validator_3_id:      Maybe AgentId
  validator_3_seal:    Maybe ByteString
  validator_3_seal_sig: Maybe Ed25519Signature
  validator_3_evidence: Maybe ExecutionEvidence
  beacon_round:        Maybe Natural
  selection_proof:     Maybe Bytes
  phase:               Filed | Selecting | Computing | Sealing
                       | Revealing | Done
  outcome:             Maybe (Upheld | Overturned | Inconclusive)
  created_at:          UTCTime
  deadline:            UTCTime

AuditRecord:
  cache_fingerprint:   ContentHash
  auditor_id:          AgentId
  audit_type:          Random | Challenge
  auditor_result:      Bytes
  auditor_evidence:    ExecutionEvidence
  outcome:             Confirmed | Suspicious | Invalidated
  beacon_round:        Natural
  challenge_stake:     Maybe Natural
  created_at:          UTCTime

AuditCommittee:
  members:             [AgentId]
  beacon_round:        Natural
  selection_proof:     Bytes
  term_start:          UTCTime
  term_end:            UTCTime
```

---

## 6. Membership and Governance

### 6.1. Joining

Joining the pool requires:

- **Principal attestation.** The agent's Ed25519 public key is countersigned by its principal (the organization operating the agent). The principal's identity is the unit of Sybil resistance — one principal can operate multiple agents, but they share a reputation and stake.
- **Stake deposit.** Amount set by pool founding parameters. Forfeited for proven misbehavior.

TBD: How principal identity is verified. Options include DNS-based proof (principal hosts a signed record at a known domain), existing PKI (X.509 certificate chain), or manual vetting by founding members. v1 can start with manual vetting and a small founding pool.

TBD: What form the stake takes. Options include cryptocurrency deposit, escrow with a trusted third party, or a credit-based system where the pool operator holds deposits. v1 should specify one concrete mechanism.

### 6.2. Maintaining Membership

- Respond to validation selections at a reasonable rate (chronic non-performance → sanctions).
- Keep stake topped up after partial slashes.
- Remain below the expulsion threshold on the sanction ladder.

### 6.3. Graduated Sanctions

**Level 0: Good standing.** No issues.

**Level 1: Noted.** A single dissent in a validation. No penalty. Recorded.

**Level 2: Warning.** A pattern of dissents (rate significantly above pool average, threshold is a pool parameter). Agent notified. Execution evidence reviewed.

**Level 3: Stake slash.** Non-performance after warning, or seal mismatch (revealed result doesn't match sealed result — evidence of active manipulation). A portion of stake forfeited. Amount is a pool parameter.

**Level 4: Expulsion.** Proven cache poisoning (via successful challenge), repeated seal mismatches, or stake depleted by accumulated slashes. Full remaining stake forfeited. Membership revoked. Agent and principal permanently flagged.

**Principal-level ban.** Multiple agents from the same principal expelled → principal banned. No new agents from that principal can join.

### 6.4. Pool Creation

A pool is created by a founding set of principals who set initial parameters: stake amount, default comparison method, sanction thresholds, audit frequency, compute deadline, pair cooling window (K), committee size and term length.

### Data Structures

```
PoolMember:
  agent_id:              AgentId
  agent_public_key:      Ed25519PublicKey
  principal_id:          PrincipalId
  principal_attestation: Ed25519Signature  -- principal's key signs agent's key
  stake_amount:          Natural
  sanction_level:        GoodStanding | Noted | Warning | SlashPending | Expelled
  sigchain_head:         ContentHash       -- hash of latest sigchain link
  sigchain_length:       Natural
  validations_performed: Natural
  unanimous_count:       Natural
  dissent_count:         Natural
  non_performance_count: Natural
  joined_at:             UTCTime
  last_active_at:        UTCTime
```

Note: `reputation_score` from the previous draft has been removed. Reputation in v1 is the raw counters above (unanimous_count, dissent_count, non_performance_count). A composite score formula would need to be specified precisely and justified; deferring to avoid false precision.

---

## 7. Server Accountability

The server is trusted for real-time coordination: routing computation specs, enforcing seal-before-reveal ordering, triggering drand lookups, performing comparisons. A compromised server could delay or withhold messages in real time. The protocol constrains what the server can get away with through three layers.

### Layer 1: Signed Seals

Every seal is Ed25519-signed by the participant. The server cannot fabricate a seal without the participant's private key. This eliminates the phantom validator attack — the server cannot create fake validators who "agree" with a poisoned result.

### Layer 2: Per-Member Sigchains

Each member maintains a personal sigchain — an append-only, hash-chained log of their protocol actions, signed by their own key.

```
SigchainLink:
  agent_id:    AgentId
  sequence:    Natural              -- monotonic counter
  link_type:   SealSubmitted | RevealSubmitted | AuditPerformed
               | ChallengeVote | MembershipAction
  payload:     LinkPayload         -- type-specific data (seal hash, fingerprint, round ID)
  prev_hash:   ContentHash         -- hash of previous link
  timestamp:   UTCTime
  signature:   Ed25519Signature    -- signed by the member's key
```

When an agent submits a seal, they add a `SealSubmitted` link to their sigchain containing the seal hash, fingerprint, and round ID. This creates an independent record that the server cannot fabricate or alter.

**What sigchains prove:**
- Participation is non-repudiable (agent can't deny, server can't fabricate).
- The number of validations an agent has participated in is independently verifiable by replaying their sigchain.

**What sigchains do NOT prove:**
- Outcomes. The sigchain records that you submitted a seal, not whether you were in the majority or the dissenter. Outcomes are in the server's audit log. Sigchains prove *participation*; the audit log records *results*.

**Storage.** Each member stores their own sigchain. The server stores a copy (needed for cross-verification). Members can also replicate their sigchain to external storage. The server stores `sigchain_head` (latest link hash) and `sigchain_length` per member for consistency checks.

### Layer 3: Merkle Tree and External Root Publication

The audit log is organized as a Merkle tree (binary hash tree over log entries).

**Inclusion proofs.** Verifying that a specific event is in the log requires ~log2(N) hashes, not replaying the entire chain.

**Anti-equivocation.** All members who see the same Merkle root are guaranteed the same log. The server cannot show different members different histories under the same root.

The Merkle root is published externally — to independent witnesses — at regular intervals (pool parameter, e.g., every hour or every N events). Members can check: "does my view of the log produce a root matching the published root?"

```
MerkleProof:
  leaf_hash:        ContentHash
  path:             [(ContentHash, Left | Right)]
  root:             ContentHash
  root_publication: Maybe ExternalRef
```

TBD: What external witnesses are used. Options include a public blockchain (expensive, high latency), a Certificate Transparency-style log service, or a set of independent servers that archive roots. v1 should specify at least one concrete option.

### Layer 4: Cross-Verification

The server's audit log says "Agent B submitted seal X for round Y." Agent B's sigchain should contain a `SealSubmitted` link with the same data, signed by Agent B's key. If they disagree:
- The sigchain's Ed25519 signature proves what Agent B actually claimed.
- The server's log is committed via the Merkle tree to an externally published root.

The standing audit committee (Section 5.3) performs this cross-verification systematically.

### What Remains Trust-Based

The server is trusted for real-time behavior: message routing, ordering, timing. A compromised server could delay messages or withhold computation specs. It cannot fabricate participation, alter historical records, or present inconsistent views without detection.

---

## 8. Threat Analysis

### 8.1. Cache Poisoning via Sybil Validators

**Attack:** Requester submits a false answer. If 1 of 2 validators is a Sybil, the false answer gets a 2/3 majority.

**Mitigations:**
- Stratified selection: all 3 must be from different principals. Attacker needs Sybil agents under at least 2 separate principal identities.
- Stake per principal makes each Sybil identity expensive.
- Principal attestation: a new Sybil requires a new organization, not just a new key.
- Signed seals: server cannot fabricate phantom validators.
- Community challenges detect poisoned entries after the fact.

Note: the Sybil probability depends on pool size, attacker's agent count, and *number of principals the attacker controls*. With stratification, a single-principal attacker has zero probability of controlling a majority regardless of how many agents they register. A multi-principal attacker's probability depends on the fraction of principals they control.

### 8.2. Out-of-Band Coordination

**Attack:** Requester learns validator identities and shares answer out-of-band.

**Mitigations:** Validator identities hidden from requester until after all seals submitted. Server holds only hashes during sealing, so even a compromised server cannot relay the answer. Execution evidence makes lazy copying detectable.

### 8.3. Grinding (Repeated Selection)

**Attack:** Requester submits false answer, abandons if validators are unfavorable, retries.

**Mitigations:** Requester seals before drand round is published — cannot know the draw when committing. Cache immutability prevents overriding a completed validation. Abandoned requests are recorded and rate-limited.

### 8.4. Free-Riding

**Attack:** Join pool for cache access, never validate when selected.

**Mitigations:** Graduated sanctions: non-performance → warning → stake slash → expulsion.

### 8.5. Lazy Validation

**Attack:** Submit fabricated results without computing.

**Mitigations:** Execution evidence committed in seal. Consistent dissent triggers sanctions. Community audits review evidence patterns.

### 8.6. Cache Entry Overwrite

**Attack:** Re-trigger validation for an already-cached entry, hoping for favorable validators.

**Mitigations:** Cache immutability — cached entries cannot be overridden. Removal only via TTL or successful challenge.

### 8.7. DoS via Flood

**Attack:** Submit thousands of validation requests to consume validator resources.

**Mitigations:** Rate limiting per agent. Repeated failed validations from the same requester trigger sanctions.

### 8.8. Server Manipulation

**Attack:** Server selects specific validators, fabricates participation, equivocates.

**Mitigations:** drand beacon makes selection verifiable. Signed seals prevent fabricated participation. Merkle tree + external roots prevent equivocation. Sigchain cross-verification detects discrepancies.

---

## 9. Failure Modes

### Validator Non-Performance

Selected validator fails to seal by deadline. Options (pool parameter):
- **Substitute:** Select replacement via next drand beacon. Deadline resets.
- **Proceed with 2:** If requester and remaining validator match, cache with reduced confidence (noted in provenance). If they differ, validation fails.
- **Cancel:** Nothing cached. Requester retains their local result.

Non-performance triggers graduated sanctions.

### Inconclusive Results (1/1/1)

All 3 differ. Nothing cached. Options:
- Retry with 2 new validators.
- Loosen comparison method.
- Flag computation as non-deterministic.

### Seal Mismatch

Revealed result doesn't match seal. Evidence of active manipulation. Level 3 sanction (stake slash). Participant disqualified. Validation falls back to 2-participant case.

### Concurrent Requests

Multiple agents request the same fingerprint before validation completes. The cache returns "no entry" (two-state rule). Internally, the system deduplicates: a validation already in progress for that fingerprint prevents new rounds from starting. The requesting agent can wait for the in-progress validation or compute independently for immediate use.

---

## 10. Protocol State Machine

```
Member queries cache
        │
        ├── Hit → Return validated result. Done.
        │
        └── Miss
                │
                ▼
        ┌──────────────┐
        │  Requested   │  Requester submits signed seal
        └──────┬───────┘
               │
               ▼
        ┌──────────────┐
        │  Selecting   │  Await next drand round,
        │              │  derive 2 validators
        └──────┬───────┘
               │
               ▼
        ┌──────────────┐
        │  Computing   │  Validators working
        └──────┬───────┘
               │
               ▼
        ┌──────────────┐
        │  Sealing     │  Collecting signed seals
        │              │  (all 3 before any reveal)
        └──────┬───────┘
               │
               ▼
        ┌──────────────┐
        │  Revealing   │  All 3 reveal; seals verified
        └──────┬───────┘
               │
     ┌─────────┼──────────┐
     ▼         ▼          ▼
┌────────┐ ┌────────┐ ┌──────────┐
│Validated│ │ Failed │ │Cancelled │
│(3/3 or │ │(1/1/1) │ │(timeout) │
│ 2/3)   │ │        │ │          │
│→ cache │ │        │ │          │
└────────┘ └────────┘ └──────────┘
```

---

## 11. Remaining Data Structures

```
ValidationRound:
  fingerprint:           ContentHash
  computation_spec:      ComputationSpec
  comparison_method:     ComparisonMethod
  requester_id:          AgentId
  requester_seal:        ByteString
  requester_seal_sig:    Ed25519Signature
  requester_evidence:    Maybe ExecutionEvidence  -- populated at reveal
  validator_1_id:        Maybe AgentId
  validator_1_seal:      Maybe ByteString
  validator_1_seal_sig:  Maybe Ed25519Signature
  validator_1_evidence:  Maybe ExecutionEvidence
  validator_2_id:        Maybe AgentId
  validator_2_seal:      Maybe ByteString
  validator_2_seal_sig:  Maybe Ed25519Signature
  validator_2_evidence:  Maybe ExecutionEvidence
  beacon_round:          Maybe Natural
  selection_proof:       Maybe Bytes
  phase:                 Requested | Selecting | Computing | Sealing
                         | Revealing | Done
  result:                Maybe (Validated CacheEntry | Failed | Cancelled)
  created_at:            UTCTime
  deadline:              UTCTime
```

---

## 12. Audit Log Events

```
-- Validation lifecycle
ValidationRequested       -- requester submitted signed seal
ValidatorsSelected        -- beacon round, derived selection, proof
ValidatorComputing        -- validator acknowledged
ResultSealed              -- participant submitted signed seal
AllSealsReceived          -- reveal phase begins
ResultRevealed            -- participant revealed result + nonce + evidence
SealVerified              -- seal match/mismatch against reveal
CrossValidated            -- Unanimous | Majority | Inconclusive
ResultCached              -- entry added to cache
ValidationFailed          -- nothing cached
ValidationCancelled       -- timeout or non-performance
ValidatorSubstituted      -- replacement after non-performance
SealMismatch              -- reveal doesn't match seal

-- Challenges and audits
RandomAuditAssigned       -- auditor selected
AuditCompleted            -- Confirmed | Suspicious | Invalidated
ChallengeFiled            -- includes stake amount
ChallengeValidatorsSelected
ChallengeResultSealed     -- includes seal_sig
ChallengeRevealed
ChallengeResolved         -- Upheld | Overturned | Inconclusive
CacheEntryRemoved         -- challenge or TTL
RevalidationTriggered     -- after challenge overturns entry

-- Governance
MemberJoined              -- includes principal attestation
MemberExpelled            -- reason, stake disposition
StakeSlashed
SanctionIssued            -- level change
PrincipalBanned

-- Committee
AuditCommitteeSelected    -- members, term, beacon round
AuditCommitteeTermEnded

-- Accountability
SigchainLinkRecorded      -- member sigchain link received
SigchainCrossVerified     -- server log matched against sigchain
SigchainDiscrepancy       -- server log and sigchain disagree
MerkleRootPublished       -- root published to external witnesses
```

Each event is hash-chained and incorporated into the Merkle tree.

---

## 13. Relationship to Veritas

Common-pool computing is built on the Veritas platform:

- **Audit log.** Extends Veritas's append-only hash-chained log with a Merkle tree for efficient proofs and anti-equivocation.
- **drand integration.** Reuses Veritas's existing drand beacon integration for validator selection, auditor selection, and committee selection.
- **Cryptographic identity.** Reuses Veritas's Ed25519 keypairs and principal attestation. Extends with per-member sigchains for cross-verification.

---

## 14. Open Questions

- **Validator decline policy.** Should validators be able to decline a selection without penalty (e.g., computation too expensive or outside capability)? Must balance against strategic declines.
- **Who pays validators?** Membership bargain (validate to access cache) is baseline. For expensive computations, should requesters compensate validators? Fee mechanism TBD.
- **Audit frequency.** Optimal frequency depends on stakes and pool trust level. Needs empirical tuning.
- **Non-LLM evidence formats.** The execution evidence format is designed for LLM API calls. Local computations (data processing, statistical analyses) need a different format — perhaps signed execution traces from a trusted runtime.
- **drand round timing.** The protocol depends on the gap between seal submission and the next drand round being short enough for acceptable latency but long enough that the requester can't predict the round. drand mainnet publishes every 3 seconds, which is likely fast enough. The pool should specify which drand network to use.

---

## 15. Future Work

- **Domain-specific pools.** Matching validators to computations they're qualified for.
- **Cross-pool federation.** Pools recognizing each other's validated entries.
- **Vouching and web-of-trust.** Social Sybil resistance on top of economic.
- **Provider-cooperative evidence verification.** APIs to verify provider_request_id legitimacy.
- **Threshold server operation.** Running the server across multiple operators.
- **Collective-choice governance.** Members modifying pool parameters through voting.
- **Capability-filtered selection.** Only selecting validators who can perform the computation.
- **Private information retrieval.** Hiding what members query from the server.
- **Sigchain federation.** Presenting sigchains from one pool as credentials in another.
