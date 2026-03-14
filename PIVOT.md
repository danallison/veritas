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

### Phase 1: Core Domain Logic — DONE ✓
Pure Haskell modules with no IO, covering all three primitives.

1. ✅ `src/Veritas/Core/Pool.hs` — Volunteer pool types, member management, status guards
2. ✅ `src/Veritas/Core/TaskAssignment.hs` — Task assignment with verifiable random selection, transition guards
3. ✅ `src/Veritas/Core/Verification.hs` — Verification types, phases, verdict computation (Unanimous/MajorityAgree/Inconclusive)
4. ✅ `src/Veritas/Core/VerifiedCache.hs` — Content-addressed cache, immutability, TTL expiration
5. ✅ Tests: hspec + QuickCheck for all modules (pool lifecycle, task transitions, verdict correctness, cache semantics)
6. ✅ Property tests: `Properties/PoolProperties.hs`

### Phase 2: Frontend Rebuild — DONE ✓
New verification-centric UI with routing, pages, and e2e tests.

1. ✅ New routing: `/verify/*`, `/pools/*`, `/cache`, `/advanced/*`
2. ✅ VerifyPage — submission form with pool query param support
3. ✅ VerificationDetailPage — phase progress, polling, verdict display
4. ✅ PoolsPage + PoolDetailPage — browse, create, join pools
5. ✅ CachePage — stats, fingerprint search, entry list
6. ✅ AdvancedPage — index for demoted ceremony/random tools
7. ✅ Updated HomePage, Layout nav, internal links
8. ✅ Shared API client (`api/fetch.ts`) + verification API client
9. ✅ Playwright e2e tests (25 tests)

### Phase 3: Database Migrations — DONE ✓
Idempotent ALTER TABLE + CREATE TABLE migrations for the verification pivot.

1. ✅ Extended `pools` table: `description`, `task_type`, `selection_size` columns (ALTER TABLE IF NOT EXISTS)
2. ✅ Extended `pool_members` table: `display_name`, `capabilities` (JSONB), `status` columns
3. ✅ Created `verifications` table (id, pool_id, description, fingerprint, submitted_result, comparison_method, validator_count, submitter, validators, submission_count, expected_submissions, phase, verdict, created_at)
4. ✅ Existing ceremony + cache tables preserved as-is
5. ✅ All migrations idempotent (safe to re-run)

### Phase 4: Backend API Wiring — DONE ✓
New Servant API type, handlers, and DB queries for the verification pivot.

#### 4a: Pool endpoints ✅
1. ✅ `GET /pools` — list all pools with member counts
2. ✅ `POST /pools` — create pool with new fields (description, task_type, selection_size)
3. ✅ `GET /pools/:id` — get pool with member counts
4. ✅ `POST /pools/:id/join` — join pool with Ed25519 public key validation
5. ✅ `GET /pools/:id/members` — list members with capabilities
6. ✅ New Servant type: `VerificationPivotAPI` in `VerificationTypes.hs`
7. ✅ Handlers in `VerificationHandlers.hs` (new module)
8. ✅ Queries in `PoolQueries.hs` (PoolV2Row, PoolMemberV2Row, new V2 queries)

#### 4b: Verification endpoints ✅
1. ✅ `POST /verify` — submit computation for cross-validation
2. ✅ `GET /verify/:id` — get verification status + verdict
3. ✅ `GET /verify` — list verifications
4. ✅ `POST /verify/:id/submit` — record a validator's submission, auto-transition to "deciding" phase
5. ✅ VerificationRow type + insertVerification, getVerification, listVerifications queries
6. ✅ updateVerificationSubmissionCount, updateVerificationVerdict queries

#### 4c: Cache endpoints ✅
1. ✅ `GET /cache` — list all cached entries with provenance
2. ✅ `GET /cache/:fingerprint` — lookup by fingerprint (hex-decoded)
3. ✅ `GET /cache/stats` — cache statistics (total, unanimous, majority counts)
4. ✅ Provenance format compatibility (old `outcome`/`validated_at` + new `verdict_outcome`/`cached_at`)

#### 4d: Integration ✅
1. ✅ VerificationPivotAPI wired into FullAPI (before PoolAPI so new shapes shadow old routes)
2. ✅ App Main.hs updated to serve verificationServer
3. ✅ Test environment (Integration/TestEnv.hs) updated
4. ✅ All 448 backend tests pass
5. ✅ Frontend ↔ backend verified working (all endpoints return correct data via Vite proxy)

### Phase 4.5: Docker & Build Fixes — DONE ✓
Fixed Docker infrastructure issues discovered during integration testing.

1. ✅ Fixed Dockerfile: `haskell:9.8-slim` → `haskell:9.6-slim` (match dev GHC 9.6.7)
2. ✅ Fixed Debian bullseye expired GPG signatures (`Acquire::Check-Valid-Until`)
3. ✅ Generated `cabal.project.freeze` to pin dependency versions across builds
4. ✅ Updated `docker-compose.yml`: app service mounts source + cabal volumes for fast iteration
5. ✅ Diagnosed and resolved Docker Desktop containerd zombie process blocking all new containers

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
