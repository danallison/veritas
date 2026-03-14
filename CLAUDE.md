# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Veritas is a platform for **verified AI agent output through independent cross-validation**, built in Haskell. It ensures AI outputs can be trusted by having multiple independent agents reproduce computations and comparing results via cryptographic commitment schemes.

Two foundational primitives:
1. **Ceremony** — A cryptographic protocol ensuring fairness through commit-reveal schemes and tamper-evident audit logs. Ensures no validator can copy another's work.
2. **Volunteer Pool** — A collection of agents (human or AI) who commit to performing a task if randomly selected. Selection uses verifiable randomness (drand). Cross-validation is the primary use case, but pools are general-purpose.

The pivot plan is documented in `PIVOT.md`. Legacy design docs: `randomness-service-design.md`, `ceremony-protocol.md`, `common-pool-computing.md`.

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

### New Core Modules (Verification Pivot)

- `src/Veritas/Core/Pool.hs` — **Volunteer Pool** primitive: member management, status lifecycle, capability filtering
- `src/Veritas/Core/TaskAssignment.hs` — Task posting and verifiable random volunteer selection (uses drand via `Pool.Selection`)
- `src/Veritas/Core/Verification.hs` — Cross-validation protocol: submission collection, verdict computation (Unanimous/Majority/Inconclusive)
- `src/Veritas/Core/VerifiedCache.hs` — Content-addressed cache of verified results, immutable entries, TTL expiration

### Existing Core Modules (Ceremony Infrastructure)

- `src/Veritas/Core/Types.hs` — Ceremony types, phases, entropy methods, audit events
- `src/Veritas/Core/StateMachine.hs` — Ceremony state machine (pure transitions)
- `src/Veritas/Core/Resolution.hs` — Deterministic outcome derivation
- `src/Veritas/Core/Entropy.hs` — Entropy combination logic
- `src/Veritas/Core/AuditLog.hs` — Hash-chained tamper-evident audit log

### Pool Computing Modules (Being Refactored)

- `src/Veritas/Pool/Types.hs` — Pool/agent/validation types (being generalized)
- `src/Veritas/Pool/Selection.hs` — Stratified drand-based validator selection
- `src/Veritas/Pool/Seal.hs` — Commit-reveal seal construction/verification
- `src/Veritas/Pool/Comparison.hs` — Result comparison (exact, canonical, field-level)
- `src/Veritas/Pool/StateMachine.hs` — Validation round state machine

### API Modules

- `src/Veritas/API/Types.hs` — Full API type composition (`FullAPI` = VerificationPivotAPI + legacy APIs)
- `src/Veritas/API/VerificationTypes.hs` — Servant type for verification pivot: pool, verify, and cache endpoints
- `src/Veritas/API/VerificationHandlers.hs` — Handlers for all verification pivot endpoints
- `src/Veritas/API/Handlers.hs` — Legacy ceremony and utility handlers
- `src/Veritas/API/RateLimit.hs` — IP-based rate limiting middleware

### Supporting Modules

- `src/Veritas/Crypto/` — Hash, Ed25519 signatures, commit-reveal, VRF, BLS, roster signing
- `src/Veritas/DB/` — PostgreSQL queries, connection pool, migrations
- `src/Veritas/DB/PoolQueries.hs` — V2 pool/member/verification/cache queries (verification pivot)
- `src/Veritas/DB/PoolMigrations.hs` — Idempotent schema migrations for verification pivot tables
- `src/Veritas/External/` — drand beacon client
- `src/Veritas/Workers/` — Background workers (expiry, auto-resolver, beacon fetcher, reveal deadline)
- `web/src/` — React frontend (pages, components, API client, hooks, Ed25519 client crypto)
- `test/Properties/` — QuickCheck property tests

### Ceremony Phases

`Gathering` → `AwaitingRosterAcks` → `Pending` → `AwaitingReveals` → `AwaitingBeacon` → `Resolving` → `Finalized`

Terminal phases: `Expired`, `Cancelled`, `Disputed`

### Verification Flow

1. **Pool** — Agents register with capabilities and Ed25519 identity
2. **Task Assignment** — drand beacon selects random subset of volunteers
3. **Verification Round** — Submitter + validators independently produce results
4. **Commit-Reveal** — All results sealed before any are revealed (prevents copying)
5. **Verdict** — Compare results: Unanimous (all agree), Majority (2/3), Inconclusive
6. **Cache** — Verified results cached by content-addressed fingerprint (immutable)

## Critical Invariants

- **No results visible before all submissions are in.** Commit-reveal ensures independence.
- **Volunteer selection is verifiable.** drand beacon + deterministic shuffle = anyone can verify the selection was fair.
- **Outcome derivation is deterministic.** Same entropy must always produce the same outcome.
- **Audit log entries are hash-chained.** `entry_hash = SHA-256(sequence || ceremony_id || event || timestamp || prev_hash)`.
- **Cache entries are immutable.** Once verified, a result cannot be overwritten. Removal only through TTL or challenge.
- **Self-certified identity is non-repudiable.** Ed25519 signatures throughout.
