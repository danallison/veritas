# Veritas Pivot: AI Output Verification through Independent Cross-Validation

## Vision

Veritas becomes a platform for **verifiable AI agent output** through independent cross-validation. The core insight: you can't trust a single AI agent's output, but you can trust the *agreement* of multiple independent agents who didn't see each other's work.

Two foundational primitives:

1. **Ceremony** — A cryptographic protocol ensuring fairness through commitment schemes and tamper-evident audit logs. Already exists. Gets repurposed from "social randomness" to "verification round" — the ceremony ensures no validator can copy another's work.

2. **Volunteer Pool** — A collection of agents (human or AI) who commit to performing a task if selected. Selection uses verifiable randomness (drand beacon). Think: drawing straws. Cross-validation is the primary use case, but pools are general-purpose — any task that needs fair random selection from willing participants.

## Conceptual Model

```
Volunteer Pool (general primitive)
├── Members register + commit to availability
├── Task posted → random subset selected (via ceremony/drand)
├── Selected members perform task independently
└── Results collected via commit-reveal ceremony

Cross-Validation (primary application)
├── Someone submits AI output to verify
├── Pool selects N independent validators
├── Each validator independently reproduces the computation
├── Commit-reveal ensures independence
├── Agreement → verified ✓ | Disagreement → flagged ✗
└── Verified results cached (content-addressed)
```

## What Changes

### Identity Shift

| Aspect | Before | After |
|--------|--------|-------|
| Tagline | "Verifiable social randomness" | "Verified AI output through independent cross-validation" |
| Primary user | Humans running raffles/coin flips | Developers & agents verifying AI output |
| Ceremony purpose | Generate trusted random outcomes | Ensure independent verification (commit-reveal) |
| Pool purpose | N/A (just added as "common-pool computing") | First-class primitive: task assignment via fair selection |
| Randomness role | The product | Infrastructure (selection mechanism + independence guarantee) |
| Outcome types | CoinFlip, Shuffle, IntRange, etc. | Verification verdicts (Agree/Disagree/Inconclusive) + original random types as utilities |

### What Stays

- **Ceremony state machine** — Core lifecycle stays. Phases still make sense: gather participants → commit → reveal → resolve.
- **Commit-reveal protocol** — Essential. This is *why* cross-validation works — prevents copying.
- **Hash-chained audit log** — Stays. Tamper-evident record of every verification.
- **Ed25519 identity** — Stays. Agents need cryptographic identity for accountability.
- **drand integration** — Stays. Fair validator selection requires external randomness.
- **PostgreSQL + Docker infrastructure** — Stays.
- **Crypto modules** — All stay (hash, signatures, commit-reveal, BLS, VRF, roster).

### What Gets Restructured

#### 1. Rename & Reorganize: `randomness-service` → `verification-service`

The randomness capabilities don't go away — they become *infrastructure* that powers verification. But the framing, docs, API naming, and frontend all shift.

#### 2. Volunteer Pool as First-Class Primitive

Currently pools exist in `PoolTypes.hs`, `PoolHandlers.hs`, `PoolQueries.hs`, `PoolMigrations.hs` but they're framed as "common-pool computing" cache infrastructure. Restructure:

**New conceptual model:**
```
VolunteerPool
  id:              PoolId
  name:            Text
  description:     Text
  task_type:       TaskType           -- CrossValidation | Custom Text
  selection_size:  Natural            -- how many members selected per task
  selection_method: SelectionMethod   -- DrandBeacon | CeremonyDraw
  members:         [PoolMember]
  created_at:      UTCTime

PoolMember
  pool_id:         PoolId
  agent_id:        AgentId
  public_key:      ByteString         -- Ed25519
  display_name:    Text
  capabilities:    [Text]             -- what models/tools this agent has access to
  reputation:      ReputationScore    -- track record
  joined_at:       UTCTime
  status:          Active | Suspended | Withdrawn

TaskAssignment
  pool_id:         PoolId
  task_id:         TaskId
  task_spec:       TaskSpec           -- what needs to be done
  selected:        [AgentId]          -- randomly chosen from pool
  selection_proof: SelectionProof     -- drand round + derivation
  ceremony_id:     CeremonyId         -- the ceremony governing commit-reveal
  status:          Selecting | InProgress | Complete | Failed
  created_at:      UTCTime
```

A volunteer pool is *not* a cache. It's a group of agents ready to work. The cache is a *layer on top* of cross-validation pools.

**Backend changes:**
- `src/Veritas/Core/Pool.hs` — New module: pool lifecycle, member management, task assignment
- `src/Veritas/Core/Selection.hs` — New module: fair random selection from pool (uses drand)
- Rename/refactor `PoolTypes.hs` → split into `Pool.hs` (core types) + `Validation.hs` (cross-validation specific)
- Rename/refactor `PoolHandlers.hs` → split into pool CRUD + task assignment + validation endpoints
- `PoolMigrations.hs` → update schema for new pool model
- `PoolQueries.hs` → update queries

#### 3. Cross-Validation as Primary Application

Cross-validation is the main thing you *do* with a volunteer pool. It becomes the centerpiece of the app.

**Verification flow:**
1. Client submits computation spec + their result to verify
2. System selects N validators from appropriate pool (via drand)
3. Each validator independently executes the computation
4. All results collected via commit-reveal ceremony
5. Comparison determines verdict:
   - **Unanimous agreement** → High confidence, result cached
   - **Majority agreement** → Moderate confidence, dissent noted, result cached
   - **No agreement** → Inconclusive, flagged for review
6. Verdict + provenance recorded in audit log

**New/modified modules:**
- `src/Veritas/Core/Verification.hs` — Verification types, verdict logic, comparison methods
- `src/Veritas/Core/Resolution.hs` — Extend to handle verification verdicts (not just random outcomes)
- `src/Veritas/Core/Cache.hs` — Content-addressed result cache (extracted from current pool code)
- `src/Veritas/Workers/ValidatorSelector.hs` — Already exists, refactor to use pool selection

#### 4. Ceremony Types Restructured

Current `CeremonyType` (CoinFlip, UniformChoice, Shuffle, IntRange, WeightedChoice) stays but becomes secondary. New primary ceremony type:

```haskell
data CeremonyType
  = Verification VerificationSpec    -- NEW: cross-validation round
  | TaskAssignment TaskSpec          -- NEW: general pool task
  -- Legacy random utilities (still useful, just not the main event)
  | CoinFlip Text Text
  | UniformChoice (NonEmpty Text)
  | Shuffle (NonEmpty Text)
  | IntRange Int Int
  | WeightedChoice (NonEmpty (Text, Rational))

data VerificationSpec
  = VerificationSpec
    { computationSpec :: ComputationSpec
    , submittedResult :: ByteString       -- what the client claims
    , comparisonMethod :: ComparisonMethod
    , validatorCount :: Natural           -- how many independent checks
    }
```

#### 5. API Restructure

Current API is ceremony-centric. New API has three top-level resource groups:

```
/pools                              -- Volunteer pool management
  POST   /pools                     -- Create pool
  GET    /pools/{id}                -- Get pool info
  POST   /pools/{id}/join           -- Join pool (register agent)
  GET    /pools/{id}/members        -- List members
  DELETE /pools/{id}/members/{mid}  -- Leave pool

/verify                             -- Cross-validation (primary feature)
  POST   /verify                    -- Submit result for verification
  GET    /verify/{id}               -- Get verification status
  GET    /verify/{id}/verdict       -- Get verdict + provenance
  GET    /verify/{id}/evidence      -- Get all submitted evidence
  GET    /verify/{id}/audit-log     -- Tamper-evident audit trail

/verify/{id}/participate            -- Validator endpoints
  POST   /verify/{id}/seal          -- Submit sealed result
  POST   /verify/{id}/reveal        -- Reveal result

/cache                              -- Verified result cache
  GET    /cache/{fingerprint}       -- Lookup verified result
  GET    /cache/stats               -- Cache statistics

/ceremonies                         -- Direct ceremony access (power users)
  POST   /ceremonies                -- Create ceremony
  GET    /ceremonies/{id}           -- Get ceremony state
  ...                               -- (existing ceremony endpoints)

/random                             -- Utility endpoints (keep)
  GET    /random/coin
  GET    /random/integer
  GET    /random/uuid

/health                             -- Health check
/docs                               -- OpenAPI docs
/server/pubkey                      -- Server public key
```

The `/verify` endpoints are the happy path for most users. `/ceremonies` becomes the low-level building block for advanced use.

#### 6. Frontend Overhaul

The frontend shifts from "create a raffle" to "verify AI output."

**New pages:**
- **HomePage** — Dashboard: recent verifications, pool stats, trust metrics
- **VerifyPage** — Submit output for verification (the main action)
- **VerificationDetailPage** — Watch a verification in progress, see verdict
- **PoolsPage** — Browse/create volunteer pools
- **PoolDetailPage** — Pool members, activity, reputation scores
- **CachePage** — Browse verified results, search by fingerprint

**Removed/demoted pages:**
- **CreateCeremonyPage** — Moves to an "Advanced" section
- **RandomToolsPage** — Moves to "Utilities"
- **PoolDemoPage** — Replaced by real pool functionality

**Modified pages:**
- **VerificationGuidePage** — Refocused on verifying AI output (not generic ceremony verification)

**New components:**
- `VerificationSubmitForm` — Input computation spec + result
- `VerificationStatus` — Real-time status of verification round
- `VerdictDisplay` — Show agreement/disagreement with confidence
- `PoolBrowser` — List and filter pools
- `AgentProfile` — Agent identity, reputation, history
- `CacheSearch` — Search verified results

**Modified components:**
- `PhaseIndicator` — Add verification-specific phase labels
- `AuditLog` — Add verification event rendering
- `OutcomeDisplay` — Add verdict rendering

### What Gets Removed

- **Standalone randomness as the product** — `/random/*` endpoints stay as utilities but aren't the point
- **Anonymous ceremony mode** — Already removed (security audit)
- **"Social randomness" framing** — All copy, docs, README, design doc

## Design Document Updates

| Document | Action |
|----------|--------|
| `randomness-service-design.md` | Archive or heavily rewrite. Core crypto/ceremony design is still valid but framing changes entirely. |
| `ceremony-protocol.md` | Keep as-is — it's a protocol spec, still accurate. Add a section on verification ceremonies. |
| `common-pool-computing.md` | Refactor into two docs: (1) volunteer pool primitive, (2) cross-validation protocol. Much of the content migrates directly. |
| `README.md` | Full rewrite — new pitch, new quickstart, new API overview. |
| `CLAUDE.md` | Update project overview, key modules, architecture description. |
| `SECURITY.md` | Update threat model for verification use case (new attack surface: colluding validators, result fabrication). |

## Database Schema Changes

### New Tables

```sql
-- Volunteer pools (replaces current 'pools' table)
CREATE TABLE volunteer_pools (
  id             UUID PRIMARY KEY,
  name           TEXT NOT NULL,
  description    TEXT,
  task_type      TEXT NOT NULL,         -- 'cross_validation', 'custom:...'
  selection_size INTEGER NOT NULL,
  selection_method TEXT NOT NULL DEFAULT 'drand',
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Pool members (extends current 'pool_members')
CREATE TABLE pool_members (
  pool_id        UUID REFERENCES volunteer_pools(id),
  agent_id       TEXT NOT NULL,
  public_key     BYTEA NOT NULL,
  display_name   TEXT,
  capabilities   JSONB DEFAULT '[]',
  reputation     JSONB DEFAULT '{"score": 1.0}',
  status         TEXT NOT NULL DEFAULT 'active',
  joined_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (pool_id, agent_id)
);

-- Verification requests (new, primary table)
CREATE TABLE verifications (
  id                UUID PRIMARY KEY,
  pool_id           UUID REFERENCES volunteer_pools(id),
  ceremony_id       UUID REFERENCES ceremonies(id),
  computation_spec  JSONB NOT NULL,
  fingerprint       TEXT NOT NULL,        -- content hash
  submitted_result  BYTEA,               -- what the requester claims
  comparison_method TEXT NOT NULL DEFAULT 'exact',
  validator_count   INTEGER NOT NULL DEFAULT 2,
  verdict           TEXT,                 -- 'unanimous', 'majority', 'inconclusive', NULL
  verdict_detail    JSONB,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at       TIMESTAMPTZ
);

-- Verified result cache (extracted from current cache tables)
CREATE TABLE verified_cache (
  fingerprint    TEXT PRIMARY KEY,
  result         BYTEA NOT NULL,
  provenance     JSONB NOT NULL,
  computation_spec JSONB NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at     TIMESTAMPTZ,
  verification_id UUID REFERENCES verifications(id)
);

-- Task assignments (general pool tasks)
CREATE TABLE task_assignments (
  id              UUID PRIMARY KEY,
  pool_id         UUID REFERENCES volunteer_pools(id),
  task_spec       JSONB NOT NULL,
  selected_agents JSONB NOT NULL,        -- [AgentId]
  selection_proof JSONB NOT NULL,        -- drand round + derivation
  ceremony_id     UUID REFERENCES ceremonies(id),
  status          TEXT NOT NULL DEFAULT 'selecting',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### Migration Strategy

- Write new migration that creates new tables
- Migrate existing `pools`, `pool_members`, `cache_entries`, `validation_rounds`, `seal_records` data if any exists
- Keep `ceremonies`, `commitments`, `entropy_reveals`, `beacon_anchors`, `outcomes`, `audit_log`, `ceremony_participants` — all still needed

## Implementation Order

### Phase 1: Volunteer Pool Primitive
1. Define core pool types in `src/Veritas/Core/Pool.hs`
2. Database migration for `volunteer_pools`, `pool_members`, `task_assignments`
3. Pool CRUD API endpoints
4. Pool member management (join, leave, status)
5. Selection logic: fair random subset selection via drand
6. Tests: pool lifecycle, selection fairness properties

### Phase 2: Cross-Validation Protocol
1. Define verification types in `src/Veritas/Core/Verification.hs`
2. Wire verification to ceremony (verification round = ceremony with pool-selected participants)
3. Database migration for `verifications` table
4. `/verify` API endpoints (submit, status, verdict)
5. Validator participation endpoints (seal, reveal)
6. Verdict computation logic (comparison methods: exact, canonical, field-level)
7. Tests: verification lifecycle, verdict correctness

### Phase 3: Result Cache
1. Define cache types in `src/Veritas/Core/Cache.hs`
2. Database migration for `verified_cache`
3. Cache API endpoints (lookup, stats)
4. Wire cache to verification (auto-cache on successful verification)
5. TTL expiration worker
6. Tests: cache semantics, content addressing

### Phase 4: Frontend Rebuild
1. New routing structure (verify-centric)
2. VerifyPage + VerificationSubmitForm
3. VerificationDetailPage + VerdictDisplay
4. PoolsPage + PoolDetailPage
5. CachePage + CacheSearch
6. Updated HomePage dashboard
7. Demote ceremony/random pages to "Advanced" section
8. Frontend tests

### Phase 5: Documentation & Polish
1. Rewrite README.md
2. Update CLAUDE.md
3. Write new design doc (or rewrite randomness-service-design.md)
4. Split common-pool-computing.md into pool + verification docs
5. Update SECURITY.md threat model
6. Update OpenAPI docs
7. Update ceremony-protocol.md with verification ceremony section

### Phase 6: Advanced Features (Future)
- Reputation system (track validator reliability)
- Semantic comparison methods (for non-deterministic AI output)
- Challenge/dispute mechanism for cached results
- Webhook notifications for verification completion
- Agent SDK (TypeScript/Python) for programmatic integration
- Multi-pool verification (cross-pool consensus)

## Open Questions

1. **Should the old random ceremony types (CoinFlip, etc.) remain in the API?** They're useful utilities and demonstrate the ceremony protocol. Recommendation: keep but deprioritize in UI.

2. **How should non-deterministic AI output be compared?** Temperature=0 helps but doesn't guarantee identical output. Need semantic comparison — cosine similarity? LLM-as-judge? Structured output schemas? This is the hardest unsolved problem.

3. **Should volunteer pools be cross-task or task-specific?** A pool of "agents who can call Claude Sonnet" vs a pool per verification type. Recommendation: pools define capabilities, tasks specify requirements, matching happens at selection time.

4. **What's the minimum pool size for meaningful cross-validation?** With 2 validators + 1 requester = 3 independent computations. Could go higher for critical tasks. Pool should have enough members that selection isn't predictable.

5. **How do we handle validator incentives?** In a volunteer pool, what motivates agents to actually do the work when selected? Reputation scores? Token economics? For now, assume cooperative participants (like the current ceremony model).

6. **Should the app name stay "Veritas"?** It means "truth" in Latin — still fits perfectly for verification. The name stays.
