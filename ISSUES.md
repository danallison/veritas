# Issues

## Open

### 1) [High] Audit verification is incomplete
**Problem:** `GET /ceremonies/:id/verify` checks only `prev_hash` chaining and does not recompute each entry hash from persisted event data.

**Where:**
- `src/Veritas/API/Handlers.hs` (`verifyHashChain`)
- `src/Veritas/Core/AuditLog.hs` (`verifyEntry` exists but is not used by API verification)

---

### 2) [High] Audit hash inputs are not fully persisted for deterministic recomputation
**Problem:** Entry hash computation includes sequence number and timestamp, but inserts rely on DB-generated `BIGSERIAL`/`NOW()` while hash is computed in app code before insert. This can break deterministic external verification from stored rows.

**Where:**
- `src/Veritas/Core/AuditLog.hs` (`computeEntryHash` includes sequence and timestamp)
- `src/Veritas/DB/Queries.hs` (`insertAuditLogEntry`, `appendAuditLog`)
- `src/Veritas/DB/Migrations.hs` (`audit_log.sequence_num BIGSERIAL`, `created_at DEFAULT NOW()`)

---

### 3) [Medium] `ExtendDeadline` beacon fallback is not implemented
**Problem:** `ExtendDeadline _` currently does nothing; it just retries on next worker cycle without updating any deadline.

**Where:**
- `src/Veritas/Workers/BeaconFetcher.hs`

---

### 4) [Medium] Fail-open parsing defaults in DB domain conversion
**Problem:** Unknown DB values silently map to defaults (`Pending`, `OfficiantVRF`, `Cancellation`) instead of failing closed.

**Where:**
- `src/Veritas/DB/Queries.hs` (`parsePhase`, `parseEntropyMethod`, `parseNonParticipationPolicy`)

---

### 5) [High] `AutoResolver` degrades silently on malformed/missing data
**Problem:** Invalid `ceremony_type` falls back to `CoinFlip`, and missing beacon in beacon-based methods can produce empty contribution lists instead of failing.

**Where:**
- `src/Veritas/Workers/AutoResolver.hs` (`Aeson.fromJSON` fallback to `CoinFlip`)
- `src/Veritas/Workers/AutoResolver.hs` (`Nothing -> pure []` for missing beacon)
- `src/Veritas/Core/Resolution.hs` (`combineEntropy [] = sha256 "veritas-empty-entropy"`)

---

### 6) [Medium] Missing temporal validation on ceremony creation
**Problem:** Validation enforces field presence/absence by method, but not temporal consistency (`commit_deadline < reveal_deadline`, deadlines in future, etc.).

**Where:**
- `src/Veritas/API/Handlers.hs` (`createCeremony`, `validateMethodParams`)

---

### 7) [Medium] N+1 query pattern in ceremony listing
**Problem:** Listing ceremonies performs per-row follow-up queries for commitment counts and participant lists.

**Where:**
- `src/Veritas/API/Handlers.hs` (`listCeremoniesH`)

---

### 8) [Medium] Missing indexes for worker hot-path queries
**Problem:** Worker loops filter by `phase`, `commit_deadline`, and `reveal_deadline` but schema migrations define no supporting indexes.

**Where:**
- `src/Veritas/DB/Queries.hs` (`getPendingExpiredCeremonies`, `getResolvingCeremonies`, `getAwaitingBeaconCeremonies`, `getAwaitingRevealsCeremonies`)
- `src/Veritas/DB/Migrations.hs` (no `CREATE INDEX` statements)

---

### 9) [Medium] Sensitive entropy material is stored in `localStorage`
**Problem:** Commit/reveal entropy and seals are persisted client-side in `localStorage`, increasing exposure under XSS.

**Where:**
- `web/src/hooks/useCeremonySecrets.ts`

---

### 10) [Low] Duplicate key warning in frontend audit log rendering
**Problem:** Frontend tests surface React warning for duplicate row keys in `AuditLog` table rendering.

**Where:**
- `web/src/components/AuditLog.tsx` (`key={entry.sequence_num}`)

---

### 11) [Low] README/API route mismatch for public key endpoint
**Problem:** README documents `GET /pubkey`, but API exposes `GET /server/pubkey`.

**Where:**
- `README.md`
- `src/Veritas/API/Types.hs`


## Resolved (Historical)

### 1. ~~`textToBS` does ASCII byte conversion instead of hex decode~~
**File:** `src/Veritas/Core/Types.hs`
**Fix:** Replaced ASCII byte packing with `convertFromBase Base16` from the `memory` package. Now properly hex-decodes text back to bytes, making `bsToText`/`textToBS` a correct round-trip.

### 2. ~~Commitment signatures accepted but never verified~~
**Files:** `src/Veritas/Core/Types.hs`, `src/Veritas/API/Types.hs`, `src/Veritas/API/Handlers.hs`, `src/Veritas/DB/Queries.hs`, `src/Veritas/DB/Migrations.hs`, `web/src/api/types.ts`, `web/src/components/CommitForm.tsx`
**Fix:** Removed the `commitSignature` field entirely — from the `Commitment` domain type, `CommitRequest` API type, DB queries, and frontend types. Deleted `src/Veritas/API/Auth.hs` (unused module). DB migration drops the `signature` column. Signatures will be reintroduced properly in Phase 5 alongside public key registration.

### 3. ~~Workers skip audit log entries for some transitions~~
**Files:** `src/Veritas/Workers/ExpiryChecker.hs`, `src/Veritas/Workers/AutoResolver.hs`
**Fix:** ExpiryChecker now appends `CeremonyExpired` to the audit log when expiring a ceremony. AutoResolver now appends `VRFGenerated` (for officiant_vrf method), `CeremonyResolved`, and `CeremonyFinalized` entries. All worker-driven state transitions are now recorded in the hash-chained log.

### 4. ~~`generateRandomBytes` uses hashed UUIDs instead of CSPRNG~~
**File:** `src/Veritas/API/Handlers.hs`
**Fix:** Replaced UUID-hashing approach with `Crypto.Random.getRandomBytes 32` from crypton, which reads directly from the OS CSPRNG.

### 5. ~~`createdBy` hardcoded to nil UUID~~
**Files:** `src/Veritas/API/Handlers.hs`, `src/Veritas/API/Types.hs`, `web/src/api/types.ts`, `web/src/pages/CreateCeremonyPage.tsx`
**Fix:** Added optional `created_by` field to `CreateCeremonyRequest`. When provided, the handler uses it; when omitted, a fresh UUID is generated. The frontend now sends the participant's ID (from `ParticipantContext`) when creating ceremonies.
