# Veritas

A verifiable social randomness service. Veritas provides cryptographically verifiable, tamper-evident randomness for scenarios where multiple parties need to trust a random outcome — raffles, coin tosses, draft orders, random assignments. Fairness is guaranteed through commitment schemes, an append-only hash-chained audit log, and optional external randomness beacons (drand).

The name reflects the core promise: the truth of the outcome is established by the protocol, not by trust in any single party.

## How It Works

A **ceremony** is the unit of social randomness — a complete lifecycle from creation through commitment, entropy collection, resolution, and finalization.

```
Gathering → AwaitingRosterAcks → Pending → AwaitingReveals → AwaitingBeacon → Resolving → Finalized
```

1. **Creation** — Define parameters: type of random event, number of parties, identity mode, deadline
2. **Registration** (self-certified only) — Parties register Ed25519 public keys, then sign the roster to prove mutual awareness
3. **Commitment** — Parties cryptographically commit to accepting the outcome *before* any randomness is visible (self-certified: commitments are signed)
4. **Entropy Collection** — Randomness inputs are gathered via one of four strategies
5. **Resolution** — The outcome is computed deterministically from collected entropy
6. **Finalization** — The outcome, commitments, and entropy are sealed into a tamper-evident audit log

### Entropy Strategies

| Strategy | Description | Trust Model |
|----------|-------------|-------------|
| **ParticipantReveal** | Commit-reveal scheme — each party contributes entropy | No single party controls outcome |
| **ExternalBeacon** | drand network randomness | Trust the beacon network |
| **Combined** | Participant entropy XOR'd with beacon | Best of both (recommended) |
| **OfficiantVRF** | Server-generated VRF randomness | Requires server trust, lowest friction |

### Participant Identity

All ceremonies use **self-certified identity**: each participant registers an Ed25519 keypair, signs the roster (proving they saw who else is participating), and signs their commitment. The ceremony record contains three layers of cryptographic evidence per participant — denying involvement requires claiming private key compromise.

<!-- TODO: OAuth identity mode planned as a second option -->

### Critical Invariants

- No entropy is visible before all commitments are collected
- Outcome derivation is deterministic — same entropy always produces the same result
- Audit log entries are hash-chained — any tampering is detectable
- Commitments are cryptographically binding
- Self-certified identity is non-repudiable — public key, roster signature, and signed commitment are all recorded in the tamper-evident hash chain

## Tech Stack

- **Backend:** Haskell (GHC 9.6), Servant, PostgreSQL, crypton, katip
- **Frontend:** React 19, TypeScript, Vite, Tailwind CSS, React Router v7
- **Crypto:** SHA-256, Ed25519 (server signing + participant identity), BLS12-381 (drand verification), HKDF
- **Testing:** hspec, QuickCheck, Vitest
- **Infrastructure:** Docker Compose

## Quick Start

```bash
# Start all services (PostgreSQL, backend, frontend)
docker compose up -d

# Frontend is at http://localhost:3002
# Backend API is at http://localhost:8080
```

## Development

There is no local Haskell tooling required — all Haskell build and test commands run through Docker via the `dev` service.

### Backend

```bash
# Build
docker compose run --rm --entrypoint cabal dev build

# Run tests (255 tests: unit, property-based, statistical)
docker compose run --rm --entrypoint cabal dev test

# Run a specific test module
docker compose run --rm --entrypoint cabal dev test --test-option='-m "CeremonySpec"'

# Rebuild and restart the app container
docker compose up -d --build app
```

### Frontend

```bash
cd web

# Install dependencies
npm install

# Type check
npx tsc --noEmit

# Run tests (105 tests)
npx vitest run

# Dev server (also available via docker compose)
npm run dev
```

## Project Structure

```
veritas/
├── app/                          # Haskell executable entry point
├── src/Veritas/
│   ├── Core/                     # Ceremony state machine, resolution, entropy, audit log
│   ├── Crypto/                   # Hash, signatures, commit-reveal, VRF, BLS
│   ├── API/                      # Servant API types, handlers, rate limiting
│   ├── DB/                       # PostgreSQL queries, pool, migrations
│   ├── Workers/                  # Background workers (expiry, resolver, beacon, reveal deadline)
│   ├── External/                 # drand beacon client
│   ├── Config.hs                 # Environment-variable configuration
│   └── Logging.hs               # Katip structured logging
├── test/                         # Backend tests (hspec + QuickCheck)
├── web/src/                      # React frontend
│   ├── api/                      # API client and TypeScript types
│   ├── components/               # UI components (PhaseIndicator, OutcomeDisplay, AuditLog, ...)
│   ├── hooks/                    # Custom hooks (useCeremony, useCeremonySecrets, useParticipant)
│   ├── pages/                    # Route pages
│   └── crypto/                   # Client-side entropy generation + Ed25519 identity
├── docker-compose.yml
├── Dockerfile                    # Development build
├── Dockerfile.prod               # Production multi-stage build
├── veritas.cabal
└── randomness-service-design.md  # Full design document and roadmap
```

## API

The backend serves a REST API with OpenAPI 3.0 documentation at `GET /docs`.

### Ceremony Lifecycle

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/ceremonies` | Create a new ceremony |
| `GET` | `/ceremonies/:id` | Get ceremony status |
| `POST` | `/ceremonies/:id/join` | Register a public key (self-certified) |
| `POST` | `/ceremonies/:id/ack-roster` | Sign the roster (self-certified) |
| `GET` | `/ceremonies/:id/roster` | Get the participant roster |
| `POST` | `/ceremonies/:id/commit` | Submit a commitment |
| `POST` | `/ceremonies/:id/reveal` | Reveal entropy |
| `GET` | `/ceremonies/:id/outcome` | Get the resolved outcome |
| `GET` | `/ceremonies/:id/log` | Get the audit log |
| `GET` | `/ceremonies/:id/verify` | Verify audit log integrity |

### Standalone Randomness

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/random/coin` | Fair coin flip |
| `GET` | `/random/integer?min=&max=` | Random integer in range |
| `GET` | `/random/uuid` | Random UUID |

### Info

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Health check |
| `GET` | `/server/pubkey` | Server public key |
| `GET` | `/verify/beacon` | drand beacon verification guide |

## Configuration

All configuration is via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `VERITAS_PORT` | `8080` | Server port |
| `VERITAS_DB` | `host=localhost ...` | PostgreSQL connection string |
| `VERITAS_DB_POOL_SIZE` | `10` | Connection pool size |
| `VERITAS_SERVER_KEY` | — | Path to Ed25519 key file (generated if absent) |
| `VERITAS_DRAND_RELAY_URL` | `https://api.drand.sh` | drand relay URL |
| `VERITAS_DRAND_CHAIN_HASH` | quicknet hash | drand chain hash |
| `VERITAS_DRAND_PUBLIC_KEY` | — | drand BLS public key (hex) |
| `VERITAS_RATE_LIMIT` | `60` | Max requests per window |
| `VERITAS_RATE_WINDOW` | `60` | Rate limit window (seconds) |
| `VERITAS_TLS_CERT` | — | TLS certificate path |
| `VERITAS_TLS_KEY` | — | TLS key path |

## License

MIT
