# Veritas

Verified AI output through independent cross-validation. Veritas ensures AI agent outputs can be trusted by having multiple independent agents reproduce computations and comparing results — no single agent's word is taken at face value.

The name reflects the core promise: truth is established by protocol, not by trust in any single party.

## How It Works

Two foundational primitives:

1. **Volunteer Pool** — A collection of agents (human or AI) who register with Ed25519 identity and commit to performing tasks when randomly selected. Selection uses verifiable randomness (drand beacon), so anyone can prove the draw was fair.

2. **Ceremony** — A cryptographic commit-reveal protocol ensuring no validator can see another's work before submitting their own. This is what makes cross-validation meaningful — independence is enforced, not assumed.

### Verification Flow

```
1. Submit    → Client submits computation + their result to a pool
2. Select    → drand beacon randomly selects N validators from the pool
3. Compute   → Each validator independently reproduces the computation
4. Seal      → All results submitted as cryptographic commitments (no peeking)
5. Reveal    → Once all seals are in, results are revealed simultaneously
6. Verdict   → Compare: Unanimous (all agree) / Majority (2/3) / Inconclusive
7. Cache     → Verified results cached by content-addressed fingerprint
```

### Why It Works

- **Commit-reveal** prevents validators from copying each other's answers
- **drand beacon** makes validator selection verifiable and unpredictable
- **Ed25519 signatures** make participation non-repudiable
- **Hash-chained audit log** makes tampering detectable
- **Content-addressed cache** stores verified results immutably

## Tech Stack

- **Backend:** Haskell (GHC 9.6), Servant, PostgreSQL, crypton, katip
- **Frontend:** React 19, TypeScript, Vite, Tailwind CSS, React Router v7
- **Crypto:** SHA-256, Ed25519, BLS12-381 (drand verification), HKDF
- **Testing:** hspec, QuickCheck, Vitest
- **Infrastructure:** Docker Compose

## Quick Start

```bash
# Start all services (PostgreSQL, backend, frontend)
docker compose up -d

# Frontend: http://localhost:3002
# Backend API: http://localhost:8080
```

## Development

There is no local Haskell tooling required — all Haskell build and test commands run through Docker via the `dev` service.

### Backend

```bash
# Build
docker compose run --rm --entrypoint cabal dev build

# Run tests (448 tests: unit, property-based, statistical)
docker compose run --rm --entrypoint cabal dev test

# Run a specific test module
docker compose run --rm --entrypoint cabal dev test --test-option='-m "CeremonySpec"'

# Rebuild and restart the app container
docker compose up -d --build app
```

### Frontend

```bash
cd web

# Type check
npx tsc --noEmit

# Run tests
npx vitest run

# Dev server (also available via docker compose)
npm run dev
```

## Project Structure

```
veritas/
├── app/                          # Haskell executable entry point
├── src/Veritas/
│   ├── Core/
│   │   ├── Pool.hs              # Volunteer pool: member management, status lifecycle
│   │   ├── TaskAssignment.hs    # Task posting + verifiable random selection (drand)
│   │   ├── Verification.hs     # Cross-validation: submissions, verdict computation
│   │   ├── VerifiedCache.hs    # Content-addressed cache of verified results
│   │   ├── Types.hs            # Ceremony types, phases, entropy methods
│   │   ├── StateMachine.hs     # Ceremony state machine (pure transitions)
│   │   ├── Resolution.hs       # Deterministic outcome derivation
│   │   ├── Entropy.hs          # Entropy combination logic
│   │   └── AuditLog.hs         # Hash-chained tamper-evident audit log
│   ├── Crypto/                   # Hash, Ed25519, commit-reveal, VRF, BLS, roster signing
│   ├── API/
│   │   ├── VerificationTypes.hs # Servant API type for verification pivot
│   │   ├── VerificationHandlers.hs # Pool, verification, and cache handlers
│   │   ├── Types.hs            # Full API composition
│   │   └── Handlers.hs         # Ceremony and utility handlers
│   ├── DB/                       # PostgreSQL queries, pool, migrations
│   ├── Workers/                  # Background workers (expiry, resolver, beacon, reveal)
│   └── External/                 # drand beacon client
├── test/                         # Backend tests (hspec + QuickCheck)
├── web/src/                      # React frontend
│   ├── api/                      # API clients (ceremonies, verification)
│   ├── pages/                    # Route pages (Verify, Pools, Cache, Advanced)
│   ├── components/               # UI components
│   ├── hooks/                    # Custom hooks
│   └── crypto/                   # Client-side Ed25519 identity + entropy
├── docker-compose.yml
├── Dockerfile
├── Dockerfile.prod               # Production multi-stage build
├── veritas.cabal
├── ceremony-protocol.md          # Ceremony protocol specification
└── common-pool-computing.md      # Cross-validated computation protocol
```

## API

The backend serves a REST API at `http://localhost:8080`.

### Verification (Primary)

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/verify` | Submit computation for cross-validation |
| `GET` | `/verify/:id` | Get verification status and verdict |
| `GET` | `/verify` | List all verifications |
| `POST` | `/verify/:id/submit` | Record a validator's submission |

### Volunteer Pools

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/pools` | List all pools with member counts |
| `POST` | `/pools` | Create a new pool |
| `GET` | `/pools/:id` | Get pool details |
| `POST` | `/pools/:id/join` | Join pool with Ed25519 public key |
| `GET` | `/pools/:id/members` | List pool members |

### Verified Cache

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/cache` | List cached verified results |
| `GET` | `/cache/stats` | Cache statistics |
| `GET` | `/cache/:fingerprint` | Lookup by content fingerprint |

### Ceremonies (Advanced)

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/ceremonies` | Create a new ceremony |
| `GET` | `/ceremonies/:id` | Get ceremony status |
| `POST` | `/ceremonies/:id/join` | Register a public key |
| `POST` | `/ceremonies/:id/ack-roster` | Sign the roster |
| `POST` | `/ceremonies/:id/commit` | Submit a commitment |
| `POST` | `/ceremonies/:id/reveal` | Reveal entropy |
| `GET` | `/ceremonies/:id/outcome` | Get the resolved outcome |
| `GET` | `/ceremonies/:id/log` | Get the audit log |
| `GET` | `/ceremonies/:id/verify` | Verify audit log integrity |

### Utilities

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/random/coin` | Fair coin flip |
| `GET` | `/random/integer?min=&max=` | Random integer in range |
| `GET` | `/random/uuid` | Random UUID |
| `GET` | `/health` | Health check |
| `GET` | `/server/pubkey` | Server public key |
| `GET` | `/docs` | OpenAPI 3.0 documentation |

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

## Design Documents

- **[Ceremony Protocol](ceremony-protocol.md)** — The general commit-reveal protocol specification, applicable to both randomness ceremonies and verification rounds
- **[Common-Pool Computing](common-pool-computing.md)** — Detailed protocol for cross-validated computation caching, including threat model, validator selection, and governance
- **[Pivot Plan](PIVOT.md)** — Implementation plan for the verification pivot

## License

MIT
