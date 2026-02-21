# Veritas: A Verifiable Social Randomness Service

## Overview

Veritas is a Haskell application that provides verifiable, tamper-evident randomness utilities with a focus on **social randomness** — scenarios where multiple parties need to commit to accepting the outcome of a random event before it occurs. The system guarantees fairness through cryptographic commitment schemes, an append-only audit log, and optional integration with external randomness beacons.

The name reflects the core promise: the truth of the outcome is established by the protocol, not by trust in any single party.

---

## Problem Statement

Many real-world decisions require shared randomness that no single party controls:

- Selecting who goes first, who gets an item, or how a resource is divided
- Running a raffle, lottery, or random drawing among a group
- Settling disputes via coin toss where both parties must trust the outcome
- Generating random assignments (A/B groups, review assignments, draft orders)

Existing solutions are either informal (someone flips a coin on camera), centralized (a website generates a number — but who trusts the website?), or heavyweight (blockchain-based solutions with token economics).

Veritas occupies the middle ground: a lightweight, auditable service where the randomness protocol is cryptographically verifiable and the commitment log is immutable and publicly inspectable.

---

## Core Concepts

### Ceremony

A **ceremony** is the fundamental unit of social randomness. It represents a complete lifecycle:

1. **Creation** — A ceremony is defined with parameters (type of random event, number of parties, deadline)
2. **Commitment** — Parties join and cryptographically commit to accepting the outcome
3. **Entropy Collection** — Randomness inputs are gathered (see Entropy Sources below)
4. **Resolution** — The random outcome is computed deterministically from the collected entropy
5. **Finalization** — The outcome, all commitments, and all entropy inputs are sealed into the audit log

A ceremony is an immutable, self-contained proof that the process was fair.

### Commitment

A commitment is a signed statement from a party that says: "I agree to accept the outcome of ceremony X, whatever it may be." Commitments are collected *before* any entropy is revealed, which is what makes the protocol fair — no party can see the outcome before committing.

### Entropy Source

The system supports multiple entropy strategies, which can be combined:

- **Participant-contributed entropy** (commit-reveal scheme)
- **External beacon entropy** (drand)
- **Server-generated entropy** (officiant VRF, for lower-stakes use cases)

### Audit Log

Every state transition in a ceremony is recorded in an append-only, hash-chained log. Each entry contains the previous entry's hash, forming a tamper-evident chain. Any party can independently verify the entire history.

---

## Architecture

### System Topology

```
┌─────────────┐     ┌──────────────────────────────────┐     ┌─────────────┐
│   Clients   │────▶│          Veritas Server           │────▶│  External   │
│  (Web/API)  │◀────│                                   │◀────│  Beacons    │
└─────────────┘     │  ┌───────────┐  ┌──────────────┐  │     │  (drand,    │
                    │  │ Ceremony  │  │  Audit Log   │  │     │   NIST)     │
                    │  │  Engine   │  │   (append-   │  │     └─────────────┘
                    │  │           │  │    only)     │  │
                    │  └─────┬─────┘  └──────┬───────┘  │
                    │        │               │          │
                    │  ┌─────▼───────────────▼───────┐  │
                    │  │       PostgreSQL             │  │
                    │  │  (ceremonies, commitments,   │  │
                    │  │   log entries, entropy)      │  │
                    │  └─────────────────────────────┘  │
                    └──────────────────────────────────┘
```

### Technology Choices

| Component | Choice | Rationale |
|-----------|--------|-----------|
| Language | Haskell (GHC 9.6+) | Strong types for modeling ceremony state machines; purity for deterministic entropy derivation; excellent concurrency primitives |
| Web framework | Servant | Type-safe API definitions that double as documentation; compile-time route checking |
| Database | PostgreSQL | ACID transactions for ceremony state transitions; `SERIALIZABLE` isolation for commitment ordering |
| Cryptography | `crypton` / `crypton-x509` | Maintained Haskell crypto library (successor to `cryptonite`) |
| JSON | `aeson` | Standard Haskell JSON encoding/decoding |
| Logging | `katip` | Structured logging with context |
| Configuration | Environment variables | Simple, container-friendly |
| Testing | `hspec` + `QuickCheck` | Property-based testing is critical for randomness protocols |
| Build | `cabal` | Standard Haskell build tool |

### Module Structure

```
veritas/
├── app/
│   └── Main.hs                      -- Entry point, server startup, TLS, worker threads
├── src/
│   └── Veritas/
│       ├── API/
│       │   ├── Types.hs             -- Servant API type + request/response types + OpenAPI schemas
│       │   ├── Handlers.hs          -- Request handlers
│       │   ├── Auth.hs              -- Authentication middleware
│       │   └── RateLimit.hs         -- Per-IP rate limiting middleware
│       ├── Core/
│       │   ├── Types.hs             -- All domain types (Phase, Ceremony, Commitment, Outcome, etc.)
│       │   ├── StateMachine.hs      -- State transitions as pure functions
│       │   ├── Resolution.hs        -- Deterministic outcome computation
│       │   ├── Entropy.hs           -- Entropy collection and combination
│       │   └── AuditLog.hs          -- Hash-chained append-only log
│       ├── Crypto/
│       │   ├── Hash.hs              -- SHA-256 / BLAKE2b utilities
│       │   ├── Signatures.hs        -- Ed25519 signing and verification
│       │   ├── CommitReveal.hs      -- Commit-reveal scheme (seal/verify)
│       │   └── VRF.hs               -- Verifiable Random Function
│       ├── DB/
│       │   ├── Pool.hs              -- Connection pool management
│       │   ├── Queries.hs           -- All database queries (ceremonies, commitments, entropy, outcomes, log)
│       │   └── Migrations.hs        -- Schema migrations
│       ├── External/
│       │   └── Drand.hs             -- drand beacon client
│       ├── Workers/
│       │   ├── ExpiryChecker.hs     -- Expires pending ceremonies past deadline
│       │   ├── AutoResolver.hs      -- Resolves ceremonies with collected entropy
│       │   ├── BeaconFetcher.hs     -- Fetches drand beacon values
│       │   └── RevealDeadlineChecker.hs -- Enforces reveal deadlines, applies non-participation policies
│       ├── Config.hs                -- Environment-variable-based configuration
│       └── Logging.hs              -- Katip structured logging setup
├── web/                             -- React frontend (see below)
├── test/
│   ├── Veritas/
│   │   ├── Core/
│   │   │   ├── StateMachineSpec.hs
│   │   │   ├── ResolutionSpec.hs
│   │   │   ├── RevealSpec.hs
│   │   │   └── AuditLogSpec.hs
│   │   ├── Crypto/
│   │   │   ├── CommitRevealSpec.hs
│   │   │   └── HashSpec.hs
│   │   └── External/
│   │       └── DrandSpec.hs
│   ├── Properties/
│   │   ├── StateMachineProperties.hs
│   │   ├── ResolutionProperties.hs
│   │   ├── CommitRevealProperties.hs
│   │   ├── AuditLogProperties.hs
│   │   └── StatisticalProperties.hs
│   ├── TestHelpers.hs
│   └── Spec.hs
├── web/
│   └── src/
│       ├── api/
│       │   ├── client.ts            -- TypeScript API client
│       │   └── types.ts             -- TypeScript type definitions
│       ├── pages/                   -- Route pages (Home, Create, CeremonyDetail, RandomTools)
│       ├── components/              -- UI components (CommitForm, RevealForm, OutcomeDisplay, AuditLog, etc.)
│       ├── hooks/                   -- React hooks (useCeremony, useParticipant, useCeremonySecrets)
│       └── context/                 -- React context (ParticipantContext)
├── Dockerfile                       -- Development image
├── Dockerfile.prod                  -- Multi-stage production image
├── docker-compose.yml               -- Full stack: db, app, web, dev
└── veritas.cabal
```

---

## Data Model

### Core Types

```haskell
-- Ceremony identity and metadata
newtype CeremonyId = CeremonyId UUID
newtype ParticipantId = ParticipantId UUID
newtype LogSequence = LogSequence Natural

-- Ceremony lifecycle phase
data Phase
  = Pending          -- Accepting commitments
  | AwaitingReveals  -- Collecting entropy reveals (ParticipantReveal, Combined)
  | AwaitingBeacon   -- Waiting for external beacon value (ExternalBeacon, Combined)
  | Resolving        -- Computing outcome
  | Finalized        -- Outcome sealed
  | Expired          -- Commitment deadline passed without quorum
  | Cancelled        -- Aborted (e.g. non-participation policy = Cancellation)
  | Disputed         -- Verification failed

data CeremonyType
  = CoinFlip
  | UniformChoice (NonEmpty Text)
  | Shuffle (NonEmpty Text)
  | IntRange Int Int
  | WeightedChoice (NonEmpty (Text, Rational))

-- How entropy is sourced (configurable per ceremony)
data EntropyMethod
  = ParticipantReveal  -- Commit-reveal from participants
  | ExternalBeacon     -- External randomness beacon (drand)
  | OfficiantVRF       -- Server-generated VRF
  | Combined           -- Participant reveal + beacon

-- When to transition from Pending after quorum is reached
data CommitmentMode
  = Immediate     -- Proceed as soon as quorum is reached
  | DeadlineWait  -- Wait for commit deadline even if quorum is met early

-- Policy for participants who commit but don't reveal (ParticipantReveal, Combined)
data NonParticipationPolicy
  = DefaultSubstitution  -- Use deterministic default value
  | Exclusion            -- Exclude from entropy combination
  | Cancellation         -- Cancel the entire ceremony

-- Specification for an external randomness beacon source
data BeaconSpec = BeaconSpec
  { beaconNetwork  :: Text
  , beaconRound    :: Maybe Natural
  , beaconFallback :: BeaconFallback
  }

data BeaconFallback
  = ExtendDeadline NominalDiffTime
  | AlternateSource BeaconSpec
  | CancelCeremony

data Ceremony = Ceremony
  { ceremonyId             :: CeremonyId
  , question               :: Text
  , ceremonyType           :: CeremonyType
  , entropyMethod          :: EntropyMethod
  , requiredParties        :: Natural
  , commitmentMode         :: CommitmentMode
  , commitDeadline         :: UTCTime
  , revealDeadline         :: Maybe UTCTime
  , nonParticipationPolicy :: Maybe NonParticipationPolicy
  , beaconSpec             :: Maybe BeaconSpec
  , phase                  :: Phase
  , createdBy              :: ParticipantId
  , createdAt              :: UTCTime
  }

data Commitment = Commitment
  { commitCeremony  :: CeremonyId
  , commitParty     :: ParticipantId
  , commitSignature :: ByteString        -- Ed25519 signature
  , entropySealHash :: Maybe ByteString  -- H(ceremony_id || participant_id || entropy_value)
  , committedAt     :: UTCTime
  }

data Outcome = Outcome
  { outcomeValue     :: CeremonyResult
  , combinedEntropy  :: ByteString
  , outcomeProof     :: OutcomeProof
  }

data CeremonyResult
  = CoinFlipResult Bool
  | ChoiceResult Text
  | ShuffleResult [Text]
  | IntRangeResult Int
  | WeightedChoiceResult Text

data OutcomeProof = OutcomeProof
  { proofEntropyInputs :: [EntropyContribution]
  , proofDerivation    :: Text
  }
```

### Audit Log Entry

```haskell
data LogEntry = LogEntry
  { logSequence  :: LogSequence
  , logCeremony  :: CeremonyId
  , logEvent     :: CeremonyEvent
  , logTimestamp  :: UTCTime
  , logPrevHash  :: ByteString       -- Hash of previous entry (genesis = 0x00)
  , logEntryHash :: ByteString       -- SHA-256(sequence || ceremony || event || timestamp || prevHash)
  }

data CeremonyEvent
  = CeremonyCreated Ceremony
  | ParticipantCommitted Commitment
  | EntropyRevealed ParticipantId ByteString
  | RevealsPublished [EntropyContribution]
  | NonParticipationApplied NonParticipationEntry
  | BeaconAnchored BeaconAnchor
  | VRFGenerated VRFOutput
  | CeremonyResolved Outcome
  | CeremonyFinalized
  | CeremonyExpired
  | CeremonyCancelled Text
  | CeremonyDisputed Text
```

### Database Schema

```sql
CREATE TABLE ceremonies (
    id                       UUID PRIMARY KEY,
    question                 TEXT NOT NULL,
    ceremony_type            JSONB NOT NULL,
    entropy_method           TEXT NOT NULL,
    required_parties         INTEGER NOT NULL CHECK (required_parties > 0),
    commitment_mode          TEXT NOT NULL DEFAULT 'immediate',
    commit_deadline          TIMESTAMPTZ NOT NULL,
    reveal_deadline          TIMESTAMPTZ,
    non_participation_policy TEXT,
    beacon_spec              JSONB,
    phase                    TEXT NOT NULL DEFAULT 'pending',
    created_by               UUID NOT NULL,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE commitments (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ceremony_id      UUID NOT NULL REFERENCES ceremonies(id),
    participant_id   UUID NOT NULL,
    signature        BYTEA NOT NULL,
    entropy_seal     BYTEA,              -- H(ceremony_id || participant_id || entropy_value)
    display_name     TEXT,               -- Optional human-readable name
    committed_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (ceremony_id, participant_id)
);

CREATE TABLE entropy_reveals (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ceremony_id      UUID NOT NULL REFERENCES ceremonies(id),
    participant_id   UUID NOT NULL,
    revealed_value   BYTEA NOT NULL,
    is_default       BOOLEAN NOT NULL DEFAULT FALSE,
    is_published     BOOLEAN NOT NULL DEFAULT FALSE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (ceremony_id, participant_id)
);

CREATE TABLE beacon_anchors (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ceremony_id      UUID NOT NULL UNIQUE REFERENCES ceremonies(id),
    network          TEXT NOT NULL,
    round_number     BIGINT NOT NULL,
    value            BYTEA NOT NULL,
    signature        BYTEA NOT NULL,
    fetched_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE outcomes (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ceremony_id      UUID NOT NULL UNIQUE REFERENCES ceremonies(id),
    outcome_value    JSONB NOT NULL,
    combined_entropy BYTEA NOT NULL,
    proof            JSONB NOT NULL,
    resolved_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE audit_log (
    sequence_num     BIGSERIAL,
    ceremony_id      UUID NOT NULL REFERENCES ceremonies(id),
    event_type       TEXT NOT NULL,
    event_data       JSONB NOT NULL,
    prev_hash        BYTEA NOT NULL,
    entry_hash       BYTEA NOT NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (ceremony_id, sequence_num)  -- Per-ceremony scoping
);
```

---

## Ceremony State Machine

The ceremony lifecycle is modeled as a state machine with strictly typed transitions. Invalid transitions are rejected at the type level where possible and at runtime with explicit error types otherwise.

```
                         ┌──────────────┐
                         │   Pending    │
                         │  (accepting  │
                         │ commitments) │
                         └──────┬───────┘
                                │
              ┌─────────────────┼─────────────────┐
              │                 │                  │
              ▼                 ▼                  ▼
     ┌────────────────┐  ┌──────────┐  ┌──────────────┐
     │AwaitingReveals │  │ Expired  │  │  Cancelled   │
     │ (commit-reveal │  │(deadline │  │  (aborted)   │
     │  methods)      │  │ passed)  │  └──────────────┘
     └───────┬────────┘  └──────────┘
              │
              ▼
     ┌────────────────┐
     │AwaitingBeacon  │
     │ (drand fetch)  │
     └───────┬────────┘
              │
              ▼
     ┌────────────────┐
     │   Resolving    │──────────▶ ┌──────────┐
     │  (computing    │            │ Disputed │
     │   outcome)     │            │ (verify  │
     └───────┬────────┘            │  failed) │
              │                    └──────────┘
              ▼
     ┌────────────────┐
     │   Finalized    │
     │ (outcome       │
     │  sealed)       │
     └────────────────┘
```

The exact path through the middle phases depends on the entropy method:
- **OfficiantVRF:** `Pending` → `Resolving` → `Finalized` (server generates entropy immediately)
- **ParticipantReveal:** `Pending` → `AwaitingReveals` → `Resolving` → `Finalized`
- **ExternalBeacon:** `Pending` → `AwaitingBeacon` → `Resolving` → `Finalized`
- **Combined:** `Pending` → `AwaitingReveals` → `AwaitingBeacon` → `Resolving` → `Finalized`

```haskell
data TransitionError
  = InvalidPhase Phase Phase
  | QuorumNotReached Natural Natural
  | DeadlineNotPassed UTCTime UTCTime
  | DeadlinePassed UTCTime UTCTime
  | AlreadyCommitted ParticipantId
  | NotCommitted ParticipantId
  | AlreadyRevealed ParticipantId
  | SealMismatch ParticipantId
  | MethodMismatch EntropyMethod
  | MissingRevealDeadline
  | MissingBeaconSpec
  | InvariantViolation Text
```

The key invariant: **no entropy is visible to any participant until all commitments are collected.** The state machine enforces this by only entering the `AwaitingReveals` phase (which enables entropy revelation) after the required number of commitments are in.

---

## Entropy and Randomness

### Strategy 1: Participant Commit-Reveal (Highest Trust)

This is the gold standard for fairness. No single party (including the server) can influence the outcome.

**Protocol:**

1. Each participant generates a random 256-bit value `s_i`
2. Each participant computes `c_i = SHA-256(ceremony_id || participant_id || s_i)` and submits `c_i` as their entropy commitment alongside their participation commitment
3. Once all participation commitments are in, each participant reveals `s_i`
4. The server verifies each `s_i` against its `c_i`
5. Combined entropy: `E = SHA-256(s_1 || s_2 || ... || s_n)` (ordered by participant ID)
6. The outcome is deterministically derived from `E`

**Security properties:**
- No party can change their entropy after seeing others' commitments (binding)
- No party learns others' entropy before committing their own (hiding)
- The outcome depends on ALL participants' entropy — even one honest party guarantees unpredictability
- The server cannot influence the outcome because it contributes no entropy

**Tradeoff:** Requires all participants to complete a two-phase interaction (commit then reveal). A participant who refuses to reveal after seeing others' commitments can stall the ceremony (addressed in Liveness section below).

```haskell
-- Create an entropy seal: H(ceremony_id || participant_id || entropy_value)
createSeal :: CeremonyId -> ParticipantId -> ByteString -> ByteString

-- Verify that a revealed value matches its seal
verifySeal :: CeremonyId -> ParticipantId -> ByteString -> ByteString -> Bool

-- Deterministic default value for non-participating participants
-- (used when NonParticipationPolicy = DefaultSubstitution)
defaultEntropyValue :: CeremonyId -> ParticipantId -> ByteString
```

### Strategy 2: External Beacon (Simplest UX)

Uses a public randomness beacon (primarily [drand](https://drand.love)) as the entropy source. Participants commit to accepting the outcome of a *future* beacon round.

**Protocol:**

1. Ceremony is created, specifying a future drand round number `R`
2. Participants commit before round `R` is published
3. When round `R` is published, the server fetches and anchors the beacon value
4. The outcome is derived from `SHA-256(ceremony_id || beacon_value_R)`

**Security properties:**
- drand is a decentralized threshold network — no single node controls the output
- Beacon values are publicly verifiable via BLS signature verification
- The server anchors the beacon value in the audit log, so any party can cross-check against drand's public record

**Tradeoff:** Requires trust in the drand network. Suitable for most casual to medium-stakes use cases.

```haskell
data BeaconAnchor = BeaconAnchor
  { baNetwork   :: Text          -- e.g., "drand-quicknet"
  , baRound     :: Natural
  , baValue     :: ByteString    -- 256-bit randomness
  , baSignature :: ByteString    -- BLS signature for verification
  , baFetchedAt :: UTCTime
  }
```

### Strategy 3: Combined (Recommended Default)

XOR participant-contributed entropy with a beacon value. This provides the best of both worlds: even if the beacon is compromised, participant entropy preserves unpredictability, and even if participants collude, the beacon prevents prediction.

```haskell
combinedEntropy :: ByteString -> ByteString -> ByteString
combinedEntropy participantEntropy beaconEntropy =
  sha256 (participantEntropy <> beaconEntropy)
```

### Strategy 4: Officiant VRF (Lowest Friction)

For low-stakes scenarios where UX simplicity matters most. The server (the "officiant") uses a Verifiable Random Function (VRF) to produce randomness that is provably derived from a specific input and can be verified by anyone with the server's public VRF key.

```haskell
-- VRF: given a secret key and input, produces a random output + proof
-- Anyone with the public key can verify that the output was correctly derived
data VRFOutput = VRFOutput
  { vrfValue     :: ByteString   -- The random output
  , vrfProof     :: ByteString   -- Proof of correct derivation
  , vrfPublicKey :: ByteString   -- Public key for verification
  }
```

**Tradeoff:** Requires trust that the server hasn't pre-computed outcomes. The VRF proof demonstrates the output was derived correctly from the input, but the server chooses *when* to evaluate the VRF. Suitable for raffles, random assignments, and other scenarios where the server is a trusted-enough neutral party.

### Deterministic Outcome Derivation

Given combined entropy `E`, the outcome must be computed deterministically so anyone can reproduce it:

```haskell
-- Derive a uniform random value in [0, 1) from entropy
deriveUniform :: ByteString -> Rational
deriveUniform entropy =
  let n = bytesToInteger (hkdf "veritas-uniform" entropy 32)
  in n % (2 ^ 256)

-- Apply to ceremony type
resolveOutcome :: CeremonyType -> ByteString -> Value
resolveOutcome CoinFlip entropy =
  let r = deriveUniform entropy
  in toJSON $ if r < 1 % 2 then "heads" else "tails"

resolveOutcome (UniformChoice options) entropy =
  let r = deriveUniform entropy
      idx = floor (r * fromIntegral (length options))
  in toJSON (options !! idx)

resolveOutcome (Shuffle items) entropy =
  -- Fisher-Yates using successive HKDF derivations for each step
  toJSON (fisherYatesDeterministic entropy items)

resolveOutcome (IntRange lo hi) entropy =
  let range = hi - lo + 1
      r = deriveUniform entropy
  in toJSON (lo + floor (r * fromIntegral range))

resolveOutcome (WeightedChoice items) entropy =
  let r = deriveUniform entropy
  in toJSON (weightedSelect r items)
```

---

## Security Model

### Threat Model

| Threat | Mitigation |
|--------|-----------|
| **Server manipulates outcome** | Combined entropy strategy ensures server alone cannot determine outcome; VRF strategy provides proof of correct derivation; all entropy inputs are in audit log |
| **Participant sees outcome before committing** | State machine enforces commitment before entropy revelation |
| **Participant contributes biased entropy** | Combined strategy: even one honest input makes output unpredictable; beacon adds external entropy |
| **Participant refuses to reveal (griefing)** | Timeout mechanism with configurable penalty (see Liveness) |
| **Audit log tampering** | Hash chain — altering any entry breaks the chain from that point forward |
| **Replay attacks** | Ceremony IDs are UUIDs; commitments include ceremony ID in the hash |
| **Timing attacks on entropy** | Server processes reveals in batch after deadline, not incrementally |
| **Man-in-the-middle** | All commitments are Ed25519 signed; TLS for transport |

### Liveness: Handling Non-Revealing Participants

A known weakness in commit-reveal protocols: a participant who sees that the outcome might be unfavorable (by colluding with other revealers) can refuse to reveal, stalling the ceremony.

Mitigations (configurable per ceremony):

1. **Timeout with default entropy:** If a participant fails to reveal within the window, the ceremony uses `SHA-256("default" || participant_id || ceremony_id)` as their entropy contribution. This is deterministic and known, but the other participants' hidden entropy still provides randomness.

2. **Timeout with exclusion:** The non-revealing participant is excluded and the ceremony resolves with remaining entropy. Their commitment is logged as "defaulted."

3. **Deposit/penalty system (future):** For higher-stakes ceremonies, participants could post a small cryptographic token or external deposit that is forfeited on non-reveal.

The `NonParticipationPolicy` type (defined in the Data Model section) configures which mitigation is used: `DefaultSubstitution`, `Exclusion`, or `Cancellation`.

### Audit Log Verification

Any client can verify the audit log integrity:

```haskell
verifyLogChain :: [LogEntry] -> Bool
verifyLogChain [] = True
verifyLogChain [e] = logPrevHash e == genesisHash
verifyLogChain (e1 : e2 : rest) =
  logPrevHash e2 == logEntryHash e1
  && verifyEntryHash e1
  && verifyLogChain (e2 : rest)

verifyEntryHash :: LogEntry -> Bool
verifyEntryHash entry =
  logEntryHash entry == sha256 (
    toBytes (logSequence entry)
    <> toBytes (logCeremony entry)
    <> toBytes (logEvent entry)
    <> toBytes (logTimestamp entry)
    <> logPrevHash entry
  )
```

Clients should be encouraged to periodically fetch and verify the chain, and the system should expose a `/verify` endpoint that performs full chain verification on demand.

### Beacon Verification

Ceremonies using the **ExternalBeacon** or **Combined** entropy method anchor their randomness to a drand distributed randomness beacon. The audit log's `BeaconAnchored` event exposes all raw cryptographic material needed for independent verification.

**What clients receive** — the `BeaconAnchored` audit log event's `event_data` contains an `anchor` object with:
- `baRound` — the drand round number
- `baSignature` — hex-encoded 48-byte BLS G1 signature
- `baValue` — hex-encoded 32-byte randomness value (= SHA-256 of the signature)
- `baNetwork` — the drand chain hash
- `baFetchedAt` — ISO 8601 timestamp of when the beacon was fetched

**How to verify:**

1. Fetch the ceremony's audit log (`GET /ceremonies/{id}/log`) and locate the `BeaconAnchored` event. The beacon data is in `event_data.anchor`.
2. Verify that `baValue == SHA-256(baSignature)` — this confirms the randomness is derived from the signature.
3. Construct the message: `message = SHA-256(big_endian_uint64(baRound))`.
4. Obtain the drand public key — either from the Veritas server (`GET /verify/beacon`) or directly from the drand network (`GET https://api.drand.sh/{chain_hash}/info`).
5. Verify the BLS12-381 signature (`baSignature`) over the message using the public key and DST `BLS_SIG_BLS12381G1_XMD:SHA-256_SSWU_RO_NUL_`.

The scheme is `bls-unchained-g1-rfc9380` (drand quicknet): signatures on G1 (48 bytes compressed), public key on G2 (96 bytes compressed).

**Reference implementations:**
- **Go / JavaScript:** `drand/drand-client`
- **Rust:** `drand/drand-verify`
- **Haskell:** `Veritas.Crypto.BLS` (this project's `verifyDrandBeacon` function)

**Trust model note:** For maximum assurance, clients should fetch the drand public key directly from the drand network rather than relying on the Veritas server's `/verify/beacon` endpoint. This eliminates the Veritas server from the trust chain entirely — the only trust assumption is in the drand distributed network itself.

### Key Management

- **Server signing key (Ed25519):** Used to sign audit log entries and VRF outputs. Stored encrypted at rest. The public key is published and well-known.
- **Participant keys:** Participants authenticate via Ed25519 keypairs. For lightweight use, the system can generate ephemeral keypairs for participants who don't bring their own.
- **drand verification key:** Hardcoded public key for the drand network, used to verify beacon values.

---

## API Design

The API is defined as a Servant type, providing compile-time route safety and automatic documentation generation. OpenAPI 3.0 docs are served at `/docs`.

```haskell
type VeritasAPI =
  -- Ceremony lifecycle
       "ceremonies" :> ReqBody '[JSON] CreateCeremonyRequest :> Post '[JSON] CeremonyResponse
  :<|> "ceremonies" :> Capture "id" UUID :> Get '[JSON] CeremonyResponse
  :<|> "ceremonies" :> QueryParam "phase" Text :> Get '[JSON] [CeremonyResponse]
  :<|> "ceremonies" :> Capture "id" UUID :> "commit" :> ReqBody '[JSON] CommitRequest :> Post '[JSON] CommitResponse
  :<|> "ceremonies" :> Capture "id" UUID :> "reveal" :> ReqBody '[JSON] RevealRequest :> Post '[JSON] RevealResponse
  :<|> "ceremonies" :> Capture "id" UUID :> "outcome" :> Get '[JSON] OutcomeResponse
  :<|> "ceremonies" :> Capture "id" UUID :> "log" :> Get '[JSON] AuditLogResponse
  :<|> "ceremonies" :> Capture "id" UUID :> "verify" :> Get '[JSON] VerifyResponse

  -- Standalone random
  :<|> "random" :> "coin" :> Get '[JSON] RandomCoinResponse
  :<|> "random" :> "integer" :> QueryParam "min" Int :> QueryParam "max" Int :> Get '[JSON] RandomIntResponse
  :<|> "random" :> "uuid" :> Get '[JSON] RandomUUIDResponse

  -- Server info
  :<|> "server" :> "pubkey" :> Get '[JSON] ServerPubKeyResponse
  :<|> "health" :> Get '[JSON] HealthResponse

  -- Verification guides
  :<|> "verify" :> "beacon" :> Get '[JSON] BeaconVerificationGuideResponse

-- OpenAPI docs endpoint (separate from VeritasAPI)
type FullAPI = VeritasAPI :<|> "docs" :> Get '[JSON] OpenApi
```

The commit and reveal endpoints handle both the participation commitment and the entropy seal/reveal in a single request — there are no separate `/entropy/commit` and `/entropy/reveal` endpoints.

### Request/Response Examples

**Create a ceremony:**
```json
POST /ceremonies
{
  "question": "Who picks the restaurant tonight",
  "ceremony_type": { "tag": "CoinFlip" },
  "entropy_method": "Combined",
  "required_parties": 2,
  "commitment_mode": "Immediate",
  "commit_deadline": "2026-03-01T12:00:00Z",
  "reveal_deadline": "2026-03-01T12:30:00Z",
  "non_participation_policy": "DefaultSubstitution",
  "beacon_spec": { "beaconNetwork": "drand-quicknet", "beaconRound": null, "beaconFallback": { "tag": "CancelCeremony" } }
}
```

**Commit to a ceremony:**
```json
POST /ceremonies/{id}/commit
{
  "participant_id": "550e8400-e29b-41d4-a716-446655440000",
  "signature": "ed25519_sig_hex...",
  "entropy_seal": "sha256_hex...",
  "display_name": "Alice"
}
```

**Reveal entropy:**
```json
POST /ceremonies/{id}/reveal
{
  "participant_id": "550e8400-e29b-41d4-a716-446655440000",
  "entropy_value": "random_256_bit_hex..."
}
```

---

## Concurrency and Performance

### Ceremony Isolation

Each ceremony's state transitions must be serializable. The system uses PostgreSQL `SERIALIZABLE` transactions for commitment and entropy operations on a per-ceremony basis.

```haskell
-- All ceremony mutations go through this function,
-- which handles serialization and retry on conflicts.
withCeremonyLock
  :: Pool Connection
  -> CeremonyId
  -> (Ceremony -> IO (Either TransitionError a))
  -> IO (Either TransitionError a)
```

### Background Workers

Four background workers run as lightweight Haskell threads (`forkIO`), each on a configurable polling interval:

- **Expiry checker:** Moves ceremonies past their commit deadline from `Pending` to `Expired`
- **Beacon fetcher:** Watches drand for new rounds and anchors values for ceremonies in `AwaitingBeacon`
- **Reveal deadline checker:** Enforces reveal deadlines for ceremonies in `AwaitingReveals`, applying the non-participation policy for non-revealers
- **Auto-resolver:** Resolves ceremonies where all entropy has been collected

### Scaling Considerations

For the initial implementation, a single server with PostgreSQL is sufficient. The architecture supports horizontal scaling by:

- Partitioning ceremonies across server instances (ceremony ID hash → instance)
- Read replicas for audit log verification queries
- The audit log hash chain is per-ceremony, not global, so there's no cross-ceremony contention

---

## Testing Strategy

### Property-Based Tests (QuickCheck)

These are the most critical tests for a randomness service:

```haskell
-- The state machine never reaches an invalid state
prop_validTransitions :: [CeremonyAction] -> Property

-- Combined entropy is uniformly distributed
prop_entropyUniformity :: [ByteString] -> Property

-- Outcome derivation is deterministic: same entropy → same outcome
prop_deterministicOutcome :: CeremonyType -> ByteString -> Property

-- Audit log chain is always valid after any sequence of operations
prop_logChainIntegrity :: [CeremonyEvent] -> Property

-- Commit-reveal binding: can't find s' ≠ s such that H(s') = H(s)
-- (This is a property of SHA-256, but we test our usage is correct)
prop_commitmentBinding :: ByteString -> ByteString -> Property

-- Shuffles are uniform: over many runs, each permutation appears ~equally
prop_shuffleUniformity :: NonEmpty Text -> Property
```

### Integration Tests

- Full ceremony lifecycle (create → commit → entropy → resolve → verify)
- Concurrent commitment submission (race conditions)
- Beacon integration with drand testnet
- Log chain verification across ceremony boundaries
- Timeout and expiry behavior

### Statistical Tests

- Run NIST SP 800-22 randomness tests on output sequences
- Verify uniform distribution of outcomes over large sample sizes
- Chi-squared tests for weighted selection accuracy

---

## Deployment

### Docker Configuration

Two Dockerfiles: a development image (`Dockerfile`) and a multi-stage production image (`Dockerfile.prod`). Both use `haskell:9.6-slim` as the base and install libpq from the PostgreSQL APT repository.

Docker Compose defines four services:
- `db` — PostgreSQL 16
- `app` — development backend (builds from `Dockerfile`, runs via `cabal run veritas`)
- `web` — Vite dev server for the React frontend (Node 20, port 3002, proxies API to `app`)
- `dev` — build/test container (mounts source, cabal caches; entrypoint is `sleep infinity`, override with `--entrypoint cabal`)

```bash
# Build and test (no local Haskell tooling required)
docker compose run --rm --entrypoint cabal dev build
docker compose run --rm --entrypoint cabal dev test

# Start everything
docker compose up -d
```

### Environment Configuration

Configuration is via environment variables (no dhall):

| Variable | Default | Description |
|----------|---------|-------------|
| `VERITAS_PORT` | `8080` | Server port |
| `VERITAS_DB` | `host=localhost port=5432 dbname=veritas` | PostgreSQL connection string |
| `VERITAS_DB_POOL_SIZE` | `10` | Connection pool size |
| `VERITAS_SERVER_KEY` | (none) | Path to Ed25519 server key file |
| `VERITAS_DRAND_RELAY_URL` | `https://api.drand.sh` | drand relay base URL |
| `VERITAS_DRAND_CHAIN_HASH` | `52db9ba7...` (quicknet) | drand chain hash |
| `VERITAS_RATE_LIMIT` | `60` | Max requests per window |
| `VERITAS_RATE_WINDOW` | `60` | Rate limit window (seconds) |
| `VERITAS_TLS_CERT` | (none) | TLS certificate path (enables TLS if set) |
| `VERITAS_TLS_KEY` | (none) | TLS key path |

---

## Future Extensions

Beyond the roadmap, these ideas inform architectural decisions:

- **Federation** — multiple Veritas servers can cross-verify each other's audit logs
- **Threshold signatures** — require M-of-N server operators to sign outcomes (decentralize the server itself)
- **SNARK/STARK proofs** — zero-knowledge proofs that a ceremony was conducted correctly, without revealing participant identities
- **Mobile push notifications** when a ceremony you've committed to reaches the reveal phase
- **Deposit/penalty system** — for higher-stakes ceremonies, participants post a stake that is forfeited on non-reveal

---

## Implementation Roadmap

### Phase 1: Core (MVP)

- Ceremony state machine with full type safety
- Commitment and basic authentication (ephemeral keys)
- Server VRF entropy strategy (simplest to implement)
- Append-only audit log with hash chaining
- Servant API with ceremony lifecycle endpoints
- Standalone randomness endpoints (coin flip, integer, UUID)
- PostgreSQL persistence
- Basic test suite (hspec + QuickCheck properties)

### Phase 2: Verifiable Randomness

- Participant commit-reveal entropy
- drand beacon integration
- **drand BLS signature verification** — beacon responses are verified against the drand network's BLS12-381 public key (using `hsblst`) before anchoring. The public key is fetched from the drand `/info` endpoint at startup, or can be overridden via `VERITAS_DRAND_PUBLIC_KEY`.
- Combined entropy strategy
- Log verification endpoint
- Statistical test suite for output quality
- Docker packaging

### Phase 3: Production Hardening

- TLS and proper key management
- Rate limiting and abuse prevention
- Comprehensive property-based test coverage
- API documentation generation from Servant types
- Monitoring and structured logging (katip)
- Ceremony expiry and cleanup background workers

### Phase 4: Usability

- Web UI for ceremony participation
- Shareable ceremony links (join via URL)
- Participant display names
- WebSocket real-time updates
- Client SDKs
- Ceremony templates

### Phase 5: Participant Identity & Non-Repudiation

The current system identifies participants by ephemeral UUIDs — sufficient for low-stakes ceremonies where everyone trusts each other, but inadequate when a participant might deny their commitment after an unfavorable outcome. This phase adds two identity strategies that cover different trust models.

**OAuth identity (human participants, low friction)**

- OAuth 2.0 integration (Google, GitHub) for linking commitments to real-world accounts
- Commitments display the authenticated identity (e.g. "alice@example.com committed")
- Optional per-ceremony policy: require authenticated participants, or allow anonymous
- Identity provider is trusted — appropriate for social/casual use cases

**Self-contained ceremony identity (agents and advanced users)**

A zero-infrastructure identity protocol where the ceremony record itself constitutes complete cryptographic proof of participation. No external identity provider, certificate authority, or pre-existing key exchange required.

Protocol:

1. **Join** — Each participant registers a public key with the ceremony. No commitments yet.
2. **Roster acknowledgment** — Once all required parties have joined, each participant signs the full participant roster ("I see that this ceremony has participants with keys [X, Y, Z], and I'm proceeding"). This proves mutual awareness.
3. **Commitment** — Each participant signs their commitment with the same key. The audit log records the signature and sequence.
4. **Resolution + finalization** — Outcome is determined, everything sealed into the hash chain.

Non-repudiation argument: denying involvement requires claiming private key compromise, because the record contains (a) the participant's public key registered before commitments, (b) a roster signature proving they saw who else was participating, and (c) a signed commitment binding them to the outcome — all in a tamper-evident hash chain.

This is particularly suited to AI agent coordination where agents handle cryptography natively and may not have out-of-band channels for key exchange. The ceremony becomes a self-bootstrapping trust context.

Implementation:

- Persistent keypair generation and storage (per-agent or per-session, configurable)
- Roster data structure: ordered list of (participant_id, public_key) tuples
- Roster signing endpoint: POST `/ceremonies/{id}/acknowledge-roster`
- Signed commitments: commitment payload includes Ed25519 signature over (ceremony_id, participant_pubkey, commitment_data)
- Verification: any party can verify all signatures in the ceremony record independently
- API identity mode field on ceremony creation: `anonymous` | `oauth` | `self-certified`

### Phase 6: Educational UX

The app should function as a teaching tool that explains how the protocol works by guiding users through actually using it. Users should come away understanding *why* the outcome is trustworthy, not just that it is.

- Contextual explanations at each ceremony phase ("Why do we collect commitments before revealing entropy?", "What does this signature prove?")
- Visual audit log walkthrough — step through the hash chain with plain-language annotations showing what each entry proves and why it's linked to the previous one
- "How it works" panel on ceremony detail page with progressive disclosure — summary for casual users, full cryptographic detail for those who want it
- Guided first-ceremony flow that highlights each trust guarantee as the user encounters it
- Explanation of identity modes: what each one guarantees and what it doesn't

---

## Appendix: Why Haskell

The choice of Haskell is not incidental. Several properties of this system align unusually well with Haskell's strengths:

- **The ceremony state machine** benefits from algebraic data types and exhaustive pattern matching. The compiler catches missing transitions.
- **Deterministic entropy derivation** benefits from purity. A pure function from entropy to outcome is easy to test, reproduce, and audit. There's no hidden state that could influence the result.
- **Cryptographic correctness** benefits from strong types. A `ByteString` is not a `CeremonyId` is not a `ParticipantId` — newtypes prevent accidentally hashing the wrong thing.
- **Concurrency** for background workers (beacon fetching, expiry checking) uses Haskell's lightweight green threads and STM, which are well-suited to this kind of cooperative I/O-bound work.
- **Property-based testing** with QuickCheck is native to the Haskell ecosystem and is essential for testing randomness properties.

The tradeoffs (smaller ecosystem, longer compile times, steeper onboarding) are acceptable for a service where correctness is the primary value proposition.
