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
- **External beacon entropy** (drand, NIST Randomness Beacon)
- **Server-generated entropy** (VRF-based, for lower-stakes use cases)

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
| Configuration | `dhall` | Type-safe configuration language |
| Testing | `hspec` + `QuickCheck` | Property-based testing is critical for randomness protocols |
| Build | `cabal` | Standard Haskell build tool |

### Module Structure

```
veritas/
├── app/
│   └── Main.hs                      -- Entry point, server startup
├── src/
│   └── Veritas/
│       ├── API/
│       │   ├── Types.hs             -- Servant API type definition
│       │   ├── Handlers.hs          -- Request handlers
│       │   └── Auth.hs              -- Authentication middleware
│       ├── Core/
│       │   ├── Ceremony.hs          -- Ceremony state machine
│       │   ├── Ceremony/
│       │   │   ├── Types.hs         -- Ceremony, Phase, Outcome types
│       │   │   ├── StateMachine.hs  -- Valid state transitions
│       │   │   └── Resolution.hs    -- Deterministic outcome computation
│       │   ├── Commitment.hs        -- Commitment creation and verification
│       │   ├── Entropy.hs           -- Entropy collection and combination
│       │   ├── Entropy/
│       │   │   ├── ParticipantReveal.hs  -- Commit-reveal participant entropy
│       │   │   ├── Beacon.hs             -- External beacon integration
│       │   │   └── VRF.hs               -- Verifiable Random Function
│       │   └── AuditLog.hs         -- Hash-chained append-only log
│       ├── Crypto/
│       │   ├── Hash.hs             -- SHA-256 / BLAKE2b utilities
│       │   ├── Signatures.hs       -- Ed25519 signing and verification
│       │   ├── CommitReveal.hs     -- Commit-reveal scheme implementation
│       │   └── VRF.hs              -- VRF implementation
│       ├── DB/
│       │   ├── Pool.hs             -- Connection pool management
│       │   ├── Ceremony.hs         -- Ceremony queries
│       │   ├── Commitment.hs       -- Commitment queries
│       │   ├── AuditLog.hs         -- Log entry queries
│       │   └── Migrations.hs       -- Schema migrations
│       ├── External/
│       │   ├── Drand.hs            -- drand beacon client
│       │   └── NIST.hs             -- NIST beacon client (optional)
│       └── Config.hs               -- Application configuration
├── test/
│   ├── Veritas/
│   │   ├── Core/
│   │   │   ├── CeremonySpec.hs
│   │   │   ├── StateMachineSpec.hs
│   │   │   ├── ResolutionSpec.hs
│   │   │   └── EntropySpec.hs
│   │   ├── Crypto/
│   │   │   ├── CommitRevealSpec.hs
│   │   │   └── VRFSpec.hs
│   │   └── AuditLogSpec.hs
│   └── Properties/                  -- QuickCheck property tests
│       ├── CeremonyProperties.hs
│       └── EntropyProperties.hs
└── veritas.cabal
```

---

## Data Model

### Core Types

```haskell
-- Ceremony identity and metadata
newtype CeremonyId = CeremonyId UUID
  deriving (Eq, Ord, Show, ToJSON, FromJSON)

newtype ParticipantId = ParticipantId UUID
  deriving (Eq, Ord, Show, ToJSON, FromJSON)

newtype LogSequence = LogSequence Natural
  deriving (Eq, Ord, Show, ToJSON, FromJSON)

-- A ceremony progresses through phases linearly.
-- The type system enforces that transitions only go forward.
data Phase
  = Pending        -- Created, accepting commitments
  | Committed      -- All parties committed, collecting entropy
  | Resolving      -- Entropy collected, computing outcome
  | Finalized      -- Outcome sealed, ceremony complete
  | Expired        -- Deadline passed without sufficient commitments
  | Disputed       -- A verification check failed (see Security section)
  deriving (Eq, Ord, Show, Generic, ToJSON, FromJSON)

data CeremonyType
  = CoinFlip                           -- Heads or tails
  | UniformChoice (NonEmpty Text)      -- Pick one from a list
  | Shuffle (NonEmpty Text)            -- Random permutation
  | IntRange Int Int                   -- Random integer in [lo, hi]
  | WeightedChoice (NonEmpty (Text, Rational))  -- Weighted selection
  deriving (Show, Generic, ToJSON, FromJSON)

data EntropyStrategy
  = ParticipantReveal    -- Each participant contributes entropy via commit-reveal
  | ExternalBeacon       -- Use drand or NIST beacon
  | Combined             -- Participant entropy XORed with beacon entropy
  | ServerVRF            -- Server generates via VRF (lower trust, simpler UX)
  deriving (Show, Generic, ToJSON, FromJSON)

data Ceremony = Ceremony
  { ceremonyId        :: CeremonyId
  , ceremonyType      :: CeremonyType
  , entropyStrategy   :: EntropyStrategy
  , requiredParties   :: Natural          -- How many commitments needed to proceed
  , commitDeadline    :: UTCTime          -- Commitments must arrive before this
  , createdAt         :: UTCTime
  , phase             :: Phase
  , createdBy         :: ParticipantId
  }

data Commitment = Commitment
  { commitmentCeremony  :: CeremonyId
  , commitmentParty     :: ParticipantId
  , commitmentHash      :: ByteString     -- Hash of (ceremony_id || party_id || nonce)
  , commitmentSignature :: Ed25519.Signature
  , committedAt         :: UTCTime
  }

data Outcome = Outcome
  { outcomeCeremony    :: CeremonyId
  , outcomeValue       :: Value           -- JSON-encoded result
  , outcomeEntropy     :: ByteString      -- Combined entropy used
  , outcomeProof       :: OutcomeProof    -- Verification data
  , resolvedAt         :: UTCTime
  }

data OutcomeProof = OutcomeProof
  { proofEntropySources  :: [EntropyContribution]  -- All inputs
  , proofCombination     :: ByteString             -- XOR/hash of all inputs
  , proofDerivation      :: ByteString             -- HKDF output used for selection
  , proofBeaconRound     :: Maybe Natural          -- drand round number if applicable
  }
```

### Audit Log Entry

```haskell
data LogEntry = LogEntry
  { logSequence    :: LogSequence
  , logCeremony    :: CeremonyId
  , logEvent       :: CeremonyEvent
  , logTimestamp   :: UTCTime
  , logPrevHash    :: ByteString       -- Hash of previous entry (genesis = 0x00)
  , logEntryHash   :: ByteString       -- SHA-256(sequence || ceremony || event || timestamp || prevHash)
  }

data CeremonyEvent
  = CeremonyCreated Ceremony
  | ParticipantCommitted Commitment
  | EntropyContributed EntropyContribution
  | BeaconValueAnchored BeaconAnchor
  | CeremonyResolved Outcome
  | CeremonyFinalized
  | CeremonyExpired
  | CeremonyDisputed DisputeReason
  deriving (Show, Generic, ToJSON, FromJSON)
```

### Database Schema

```sql
CREATE TABLE ceremonies (
    id              UUID PRIMARY KEY,
    ceremony_type   JSONB NOT NULL,
    entropy_strategy TEXT NOT NULL,
    required_parties INTEGER NOT NULL CHECK (required_parties > 0),
    commit_deadline TIMESTAMPTZ NOT NULL,
    phase           TEXT NOT NULL DEFAULT 'pending',
    created_by      UUID NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE commitments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ceremony_id     UUID NOT NULL REFERENCES ceremonies(id),
    participant_id  UUID NOT NULL,
    commitment_hash BYTEA NOT NULL,
    signature       BYTEA NOT NULL,
    committed_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (ceremony_id, participant_id)
);

CREATE TABLE entropy_contributions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ceremony_id     UUID NOT NULL REFERENCES ceremonies(id),
    source_type     TEXT NOT NULL,  -- 'participant_reveal', 'beacon', 'vrf'
    contributor_id  UUID,           -- NULL for beacon/vrf
    commitment_hash BYTEA,          -- For commit-reveal: H(entropy_value)
    revealed_value  BYTEA,          -- NULL until reveal phase
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE outcomes (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ceremony_id     UUID NOT NULL UNIQUE REFERENCES ceremonies(id),
    outcome_value   JSONB NOT NULL,
    combined_entropy BYTEA NOT NULL,
    proof           JSONB NOT NULL,
    resolved_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE audit_log (
    sequence_num    BIGSERIAL PRIMARY KEY,
    ceremony_id     UUID NOT NULL REFERENCES ceremonies(id),
    event_type      TEXT NOT NULL,
    event_data      JSONB NOT NULL,
    prev_hash       BYTEA NOT NULL,
    entry_hash      BYTEA NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for efficient chain verification
CREATE INDEX idx_audit_log_ceremony ON audit_log(ceremony_id, sequence_num);
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
                   ┌────────────┼────────────┐
                   │            │             │
                   ▼            ▼             ▼
            ┌──────────┐  ┌──────────┐  ┌─────────┐
            │ Committed│  │ Expired  │  │Disputed │
            │ (enough  │  │(deadline │  │ (verify │
            │ parties) │  │ passed)  │  │ failed) │
            └────┬─────┘  └──────────┘  └─────────┘
                 │
                 ▼
            ┌──────────┐
            │Resolving │
            │(entropy  │
            │collected)│
            └────┬─────┘
                 │
                 ▼
            ┌──────────┐
            │Finalized │
            │(outcome  │
            │ sealed)  │
            └──────────┘
```

```haskell
-- State transitions as a pure function.
-- Returns either a transition error or the new phase + log events.
data TransitionError
  = InvalidPhase Phase Phase          -- Can't go from X to Y
  | InsufficientCommitments Natural Natural  -- Have N, need M
  | DeadlinePassed UTCTime
  | DeadlineNotReached UTCTime
  | EntropyMissing [ParticipantId]
  | EntropyVerificationFailed ParticipantId Text
  | DuplicateCommitment ParticipantId
  deriving (Show, Eq)

transition
  :: Ceremony
  -> UTCTime            -- Current time
  -> CeremonyAction     -- What we're trying to do
  -> Either TransitionError (Phase, [CeremonyEvent])

data CeremonyAction
  = AddCommitment Commitment
  | ContributeEntropy EntropyContribution
  | AnchorBeacon BeaconAnchor
  | Resolve
  | CheckExpiry
```

The key invariant: **no entropy is visible to any participant until all commitments are collected.** The state machine enforces this by only entering the `Committed` phase (which enables entropy revelation) after the required number of commitments are in.

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
data CommitRevealState
  = AwaitingCommitments (Map ParticipantId ByteString)  -- H(entropy)
  | AwaitingReveals (Map ParticipantId (ByteString, Maybe ByteString))
      -- (commitment_hash, maybe revealed_value)
  | AllRevealed (Map ParticipantId ByteString)  -- All verified reveals

verifyReveal :: ParticipantId -> CeremonyId -> ByteString -> ByteString -> Bool
verifyReveal pid cid revealedValue commitHash =
  sha256 (toBytes cid <> toBytes pid <> revealedValue) == commitHash

combineEntropy :: Map ParticipantId ByteString -> ByteString
combineEntropy reveals =
  sha256 . mconcat . map snd . Map.toAscList $ reveals
  -- Deterministic ordering by ParticipantId (ascending)
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
  { beaconNetwork   :: Text          -- e.g., "drand mainnet"
  , beaconRound     :: Natural
  , beaconValue     :: ByteString    -- 256-bit randomness
  , beaconSignature :: ByteString    -- BLS signature for verification
  , fetchedAt       :: UTCTime
  }

-- Verify the beacon value against drand's public key
verifyBeacon :: DrandPublicKey -> BeaconAnchor -> Bool
```

### Strategy 3: Combined (Recommended Default)

XOR participant-contributed entropy with a beacon value. This provides the best of both worlds: even if the beacon is compromised, participant entropy preserves unpredictability, and even if participants collude, the beacon prevents prediction.

```haskell
combinedEntropy :: ByteString -> ByteString -> ByteString
combinedEntropy participantEntropy beaconEntropy =
  sha256 (participantEntropy <> beaconEntropy)
```

### Strategy 4: Server VRF (Lowest Friction)

For low-stakes scenarios where UX simplicity matters most. The server uses a Verifiable Random Function (VRF) to produce randomness that is provably derived from a specific input and can be verified by anyone with the server's public VRF key.

```haskell
-- VRF: given a secret key and input, produces a random output + proof
-- Anyone with the public key can verify that the output was correctly derived
data VRFOutput = VRFOutput
  { vrfValue :: ByteString   -- The random output
  , vrfProof :: ByteString   -- Proof of correct derivation
  , vrfInput :: ByteString   -- The input (ceremony_id || commitment_hashes)
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

```haskell
data RevealPolicy
  = DefaultEntropy          -- Use deterministic fallback
  | ExcludeNonRevealers     -- Resolve without them
  | AbortCeremony           -- Cancel entirely
  deriving (Show, Generic, ToJSON, FromJSON)
```

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

### Key Management

- **Server signing key (Ed25519):** Used to sign audit log entries and VRF outputs. Stored encrypted at rest. The public key is published and well-known.
- **Participant keys:** Participants authenticate via Ed25519 keypairs. For lightweight use, the system can generate ephemeral keypairs for participants who don't bring their own.
- **drand verification key:** Hardcoded public key for the drand network, used to verify beacon values.

---

## API Design

The API is defined as a Servant type, providing compile-time route safety and automatic documentation generation.

```haskell
type VeritasAPI =
  -- Ceremony lifecycle
       "ceremonies" :> ReqBody '[JSON] CreateCeremonyRequest
                    :> Post '[JSON] Ceremony
  :<|> "ceremonies" :> Capture "id" CeremonyId
                    :> Get '[JSON] CeremonyDetail
  :<|> "ceremonies" :> QueryParam "phase" Phase
                    :> QueryParam "limit" Natural
                    :> Get '[JSON] [CeremonySummary]

  -- Commitments
  :<|> "ceremonies" :> Capture "id" CeremonyId
                    :> "commit"
                    :> ReqBody '[JSON] CommitRequest
                    :> Post '[JSON] Commitment

  -- Entropy (commit-reveal flow)
  :<|> "ceremonies" :> Capture "id" CeremonyId
                    :> "entropy" :> "commit"
                    :> ReqBody '[JSON] EntropyCommitRequest
                    :> Post '[JSON] EntropyCommitResponse
  :<|> "ceremonies" :> Capture "id" CeremonyId
                    :> "entropy" :> "reveal"
                    :> ReqBody '[JSON] EntropyRevealRequest
                    :> Post '[JSON] EntropyRevealResponse

  -- Resolution and outcome
  :<|> "ceremonies" :> Capture "id" CeremonyId
                    :> "outcome"
                    :> Get '[JSON] Outcome

  -- Audit log
  :<|> "ceremonies" :> Capture "id" CeremonyId
                    :> "log"
                    :> QueryParam "from" LogSequence
                    :> Get '[JSON] [LogEntry]
  :<|> "ceremonies" :> Capture "id" CeremonyId
                    :> "verify"
                    :> Get '[JSON] VerificationResult

  -- Standalone randomness utilities (no ceremony needed)
  :<|> "random" :> "coin"    :> Get '[JSON] CoinFlipResult
  :<|> "random" :> "integer" :> QueryParam' '[Required] "min" Int
                             :> QueryParam' '[Required] "max" Int
                             :> Get '[JSON] IntegerResult
  :<|> "random" :> "uuid"    :> Get '[JSON] UUIDResult
  :<|> "random" :> "beacon"  :> Get '[JSON] BeaconAnchor

  -- Server identity and verification
  :<|> "server" :> "pubkey"  :> Get '[JSON] PublicKeyInfo
  :<|> "health"              :> Get '[JSON] HealthCheck
```

### Request/Response Examples

**Create a ceremony:**
```json
POST /ceremonies
{
  "type": { "tag": "CoinFlip" },
  "entropy_strategy": "Combined",
  "required_parties": 2,
  "commit_deadline": "2026-03-01T12:00:00Z",
  "reveal_policy": "DefaultEntropy",
  "description": "Who picks the restaurant tonight"
}
```

**Commit to a ceremony:**
```json
POST /ceremonies/{id}/commit
{
  "participant_id": "550e8400-e29b-41d4-a716-446655440000",
  "commitment_hash": "a3f2b8c1...",
  "signature": "ed25519_sig_bytes..."
}
```

**Fetch outcome (after resolution):**
```json
GET /ceremonies/{id}/outcome
{
  "ceremony_id": "...",
  "value": "heads",
  "combined_entropy": "0xabcdef...",
  "proof": {
    "entropy_sources": [
      { "type": "participant_reveal", "participant": "...", "value": "0x..." },
      { "type": "participant_reveal", "participant": "...", "value": "0x..." },
      { "type": "beacon", "network": "drand mainnet", "round": 4829103, "value": "0x..." }
    ],
    "combination_method": "sha256_concat",
    "derived_via": "hkdf_sha256"
  },
  "resolved_at": "2026-03-01T12:00:03Z"
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

- **Expiry checker:** Periodic task that moves ceremonies past their deadline from `Pending` to `Expired`
- **Beacon fetcher:** Watches drand for new rounds and anchors values for ceremonies awaiting beacon entropy
- **Auto-resolver:** Resolves ceremonies where all entropy has been collected

These can be modeled as lightweight Haskell threads using `async` or as a simple `forkIO`-based scheduler, since the expected load is modest.

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

```dockerfile
FROM haskell:9.6 AS builder
WORKDIR /app
COPY veritas.cabal cabal.project ./
RUN cabal update && cabal build --only-dependencies
COPY . .
RUN cabal build && cabal install --install-method=copy --installdir=/app/dist

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y libpq-dev ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/dist/veritas /usr/local/bin/
EXPOSE 8080
CMD ["veritas"]
```

### Environment Configuration

```dhall
{ server =
    { port = 8080
    , host = "0.0.0.0"
    , tlsCert = Some "/etc/veritas/cert.pem"
    , tlsKey = Some "/etc/veritas/key.pem"
    }
, database =
    { host = "localhost"
    , port = 5432
    , name = "veritas"
    , poolSize = 10
    }
, crypto =
    { serverKeyPath = "/etc/veritas/server.ed25519"
    , vrfKeyPath = "/etc/veritas/server.vrf"
    }
, beacon =
    { drandUrl = "https://api.drand.sh"
    , drandChainHash = "8990e7a9aaed2ffed73dbd7092123d6f289930540d7651336225dc172e51b2ce"
    }
, ceremonies =
    { defaultRevealPolicy = "DefaultEntropy"
    , maxCommitDeadlineHours = 168  -- 1 week
    , revealTimeoutMinutes = 60
    }
}
```

---

## Future Extensions

These are out of scope for the initial implementation but inform architectural decisions:

- **WebSocket subscriptions** for real-time ceremony status updates
- **Client SDKs** (TypeScript, Python) for easy integration
- **Web UI** for non-technical participants to join ceremonies via link
- **Ceremony templates** — save and reuse configurations (e.g., "weekly team lunch picker")
- **Federation** — multiple Veritas servers can cross-verify each other's audit logs
- **Threshold signatures** — require M-of-N server operators to sign outcomes (decentralize the server itself)
- **SNARK/STARK proofs** — zero-knowledge proofs that a ceremony was conducted correctly, without revealing participant identities
- **Mobile push notifications** when a ceremony you've committed to reaches the reveal phase

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
- WebSocket real-time updates
- Client SDKs
- Ceremony templates

---

## Appendix: Why Haskell

The choice of Haskell is not incidental. Several properties of this system align unusually well with Haskell's strengths:

- **The ceremony state machine** benefits from algebraic data types and exhaustive pattern matching. The compiler catches missing transitions.
- **Deterministic entropy derivation** benefits from purity. A pure function from entropy to outcome is easy to test, reproduce, and audit. There's no hidden state that could influence the result.
- **Cryptographic correctness** benefits from strong types. A `ByteString` is not a `CeremonyId` is not a `ParticipantId` — newtypes prevent accidentally hashing the wrong thing.
- **Concurrency** for background workers (beacon fetching, expiry checking) uses Haskell's lightweight green threads and STM, which are well-suited to this kind of cooperative I/O-bound work.
- **Property-based testing** with QuickCheck is native to the Haskell ecosystem and is essential for testing randomness properties.

The tradeoffs (smaller ecosystem, longer compile times, steeper onboarding) are acceptable for a service where correctness is the primary value proposition.
