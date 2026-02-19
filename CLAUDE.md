# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Veritas is a verifiable social randomness service built in Haskell. It provides cryptographically verifiable, tamper-evident randomness for scenarios where multiple parties need to trust a random outcome (raffles, coin tosses, draft orders, random assignments). Fairness is guaranteed through commitment schemes, an append-only hash-chained audit log, and optional external randomness beacons (drand).

The full design is documented in `randomness-service-design.md`.

## Tech Stack

- **Language:** Haskell (GHC 9.6+)
- **Build:** cabal
- **Web framework:** Servant (type-safe API)
- **Database:** PostgreSQL (SERIALIZABLE isolation for ceremony state)
- **Crypto:** crypton / crypton-x509 (Ed25519, SHA-256, BLAKE2b, VRF)
- **Config:** dhall
- **Logging:** katip
- **Testing:** hspec + QuickCheck (property-based tests are critical)

## Build & Development Commands

```bash
cabal update
cabal build
cabal test            # Run all tests
cabal test --test-option='-m "CeremonySpec"'  # Run a specific test module
cabal run veritas     # Start the server
```

## Architecture

### Core Abstraction: Ceremony

A **ceremony** is the unit of social randomness — a lifecycle from creation through commitment, entropy collection, resolution, and finalization. The ceremony state machine (`src/Veritas/Core/Ceremony/StateMachine.hs`) enforces that commitments are collected *before* any entropy is revealed.

### Ceremony Phases

`Pending` → `Committed` → `Resolving` → `Finalized` (also `Expired`, `Disputed`)

State transitions are pure functions returning either a `TransitionError` or the new phase plus log events.

### Entropy Strategies

Four strategies, configurable per ceremony:
1. **ParticipantReveal** — commit-reveal scheme, highest trust, no single party controls outcome
2. **ExternalBeacon** — drand integration, simplest UX
3. **Combined** — participant entropy XOR'd with beacon (recommended default)
4. **ServerVRF** — VRF-based, lowest friction, requires server trust

### Key Modules

- `src/Veritas/Core/` — Ceremony state machine, commitment logic, entropy, audit log
- `src/Veritas/Crypto/` — Hash utilities, Ed25519 signatures, commit-reveal, VRF
- `src/Veritas/API/` — Servant type definition, handlers, auth
- `src/Veritas/DB/` — PostgreSQL queries, connection pool, migrations
- `src/Veritas/External/` — drand and NIST beacon clients
- `test/Properties/` — QuickCheck property tests (entropy uniformity, state machine validity, deterministic outcomes)

### Audit Log

Every ceremony state transition is recorded in an append-only, hash-chained log. Each entry contains the previous entry's hash. Clients can verify the chain via `/ceremonies/{id}/verify`.

## Critical Invariants

- **No entropy visible before all commitments are in.** The state machine must enforce this.
- **Outcome derivation is deterministic.** Same entropy must always produce the same outcome (pure functions, deterministic ordering by ParticipantId).
- **Audit log entries are hash-chained.** `entry_hash = SHA-256(sequence || ceremony_id || event || timestamp || prev_hash)`.
- **Commitments are cryptographically binding.** `commitment_hash = SHA-256(ceremony_id || participant_id || nonce)`.
