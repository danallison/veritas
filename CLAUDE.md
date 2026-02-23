# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Veritas is a verifiable social randomness service built in Haskell. It provides cryptographically verifiable, tamper-evident randomness for scenarios where multiple parties need to trust a random outcome (raffles, coin tosses, draft orders, random assignments). Fairness is guaranteed through commitment schemes, an append-only hash-chained audit log, and optional external randomness beacons (drand).

The full design and roadmap are documented in `randomness-service-design.md`.

## Tech Stack

- **Backend:** Haskell (GHC 9.6+), Servant, PostgreSQL, crypton, katip, hspec + QuickCheck
- **Frontend:** React 19, TypeScript, Vite, Tailwind CSS, React Router v7
- **Build:** cabal (backend), npm (frontend)
- **Infrastructure:** Docker Compose (PostgreSQL, backend, frontend dev server)

## Build & Development Commands

**There is no local Haskell tooling.** GHC and cabal are not installed on the host machine. All Haskell build/test commands must run through Docker.

```bash
# Backend (Haskell) — always use Docker
docker compose run --rm --entrypoint cabal dev build
docker compose run --rm --entrypoint cabal dev test
docker compose run --rm --entrypoint cabal dev test --test-option='-m "CeremonySpec"'

# Rebuild and restart the backend app container
docker compose up -d --build app

# Frontend (TypeScript/React)
cd web && npx tsc --noEmit        # Type check
cd web && npx vitest run          # Run tests

# Start everything
docker compose up -d              # db + app + web
```

The `dev` service mounts the source directory and has cabal caches. Its entrypoint is `sleep infinity`, so you must override it with `--entrypoint cabal`.

## Architecture

### Core Abstraction: Ceremony

A **ceremony** is the unit of social randomness — a lifecycle from creation through commitment, entropy collection, resolution, and finalization. The ceremony state machine (`src/Veritas/Core/StateMachine.hs`) enforces that commitments are collected *before* any entropy is revealed.

### Ceremony Phases

Anonymous ceremonies: `Pending` → `AwaitingReveals` → `AwaitingBeacon` → `Resolving` → `Finalized`

Self-certified ceremonies: `Gathering` → `AwaitingRosterAcks` → `Pending` → (same as above)

Terminal phases: `Expired`, `Cancelled`, `Disputed`

State transitions are pure functions returning either a `TransitionError` or the new phase plus log events. Self-certified ceremonies use `transitionWith` which takes the roster and ack count as additional parameters.

### Entropy Strategies

Four strategies, configurable per ceremony:
1. **ParticipantReveal** — commit-reveal scheme, highest trust, no single party controls outcome
2. **ExternalBeacon** — drand integration, simplest UX
3. **Combined** — participant entropy XOR'd with beacon (recommended default)
4. **OfficiantVRF** — server-generated randomness, lowest friction, requires server trust

### Key Modules

- `src/Veritas/Core/` — Ceremony state machine, types, commitment logic, entropy, audit log
- `src/Veritas/Crypto/` — Hash utilities, Ed25519 signatures, commit-reveal, VRF, roster signing
- `src/Veritas/API/` — Servant API type definition, handlers, auth, rate limiting
- `src/Veritas/DB/` — PostgreSQL queries, connection pool, migrations
- `src/Veritas/External/` — drand beacon client
- `src/Veritas/Workers/` — Background workers (expiry, auto-resolver, beacon fetcher, reveal deadline)
- `src/Veritas/Logging.hs` — Katip structured logging
- `web/src/` — React frontend (pages, components, API client, hooks, Ed25519 client crypto)
- `test/Properties/` — QuickCheck property tests (entropy uniformity, state machine validity, deterministic outcomes)

### Audit Log

Every ceremony state transition is recorded in an append-only, hash-chained log. Each entry contains the previous entry's hash, forming a tamper-evident chain.

### Participant Identity

Ceremonies support two identity modes, chosen at creation:

- **Anonymous** (default) — Participants are identified by ephemeral UUIDs. Ceremonies start in `Pending`. Appropriate for low-stakes scenarios with mutual trust.
- **SelfCertified** — Each participant registers an Ed25519 public key, signs a roster acknowledgment, and signs their commitment. Ceremonies start in `Gathering` and progress through `AwaitingRosterAcks` before reaching `Pending`. The ceremony record itself constitutes complete cryptographic proof of participation — denying involvement requires claiming private key compromise. Designed for AI agent coordination and high-stakes scenarios.

Key modules: `Veritas.Crypto.Roster` (backend signing/verification), `web/src/crypto/identity.ts` (frontend Ed25519 keypair management and signing). See `ceremony-protocol.md` Section 10 for the full protocol specification.

## Critical Invariants

- **No entropy visible before all commitments are in.** The state machine must enforce this.
- **Outcome derivation is deterministic.** Same entropy must always produce the same outcome (pure functions, deterministic ordering by ParticipantId).
- **Audit log entries are hash-chained.** `entry_hash = SHA-256(sequence || ceremony_id || event || timestamp || prev_hash)`.
- **Commitments are cryptographically binding.** `commitment_hash = SHA-256(ceremony_id || participant_id || nonce)`.
- **Self-certified identity is non-repudiable.** The audit log contains the participant's public key, their roster signature, and their signed commitment — three layers of cryptographic evidence recorded in the tamper-evident hash chain.
