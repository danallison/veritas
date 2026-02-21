# Issues

## Open

(none)

## Resolved (Historical)

### 6. ~~Audit hash inputs are not fully persisted for deterministic recomputation~~
**Files:** `src/Veritas/DB/Migrations.hs`, `src/Veritas/DB/Queries.hs`
**Fix:** Dropped DB defaults for `sequence_num` and `created_at` on `audit_log`. `appendAuditLog` now computes both app-side and passes them explicitly in the INSERT, ensuring the hash inputs match the stored values.

### 7. ~~Audit verification is incomplete~~
**Files:** `src/Veritas/API/Handlers.hs`, `src/Veritas/Core/Types.hs`
**Fix:** `verifyHashChain` now parses `event_data` JSON back to `CeremonyEvent`, recomputes each entry hash via `computeEntryHash`, and compares to the stored hash. Added `FromJSON` instances for `CeremonyEvent` and its sub-types.

### 8. ~~Fail-open parsing defaults in DB domain conversion~~
**File:** `src/Veritas/DB/Queries.hs`
**Fix:** Changed `parsePhase`, `parseEntropyMethod`, `parseCommitmentMode`, and `parseNonParticipationPolicy` to call `error` on unknown values instead of silently defaulting.

### 9. ~~`AutoResolver` degrades silently on malformed/missing data~~
**Files:** `src/Veritas/Workers/AutoResolver.hs`, `src/Veritas/Core/Resolution.hs`
**Fix:** Invalid `ceremony_type` now logs an error and disputes the ceremony instead of falling back to `CoinFlip`. Empty contribution lists (from missing beacons) now dispute the ceremony. `combineEntropy []` is now an `error` as a safety net.

### 10. ~~Missing temporal validation on ceremony creation~~
**Files:** `src/Veritas/API/Handlers.hs`, `test/Veritas/API/HandlersSpec.hs`
**Fix:** Added `validateTemporalConstraints` checking that deadlines are in the future and `reveal_deadline > commit_deadline`. Called during `createCeremony`.

### 11. ~~N+1 query pattern in ceremony listing~~
**Files:** `src/Veritas/DB/Queries.hs`, `src/Veritas/API/Handlers.hs`
**Fix:** Added `getCommitmentCountsBatch` and `getCommittedParticipantsBatch` batch queries. `listCeremoniesH` now uses 3 queries total instead of 1 + 2N.

### 12. ~~Missing indexes for worker hot-path queries~~
**File:** `src/Veritas/DB/Migrations.hs`
**Fix:** Added indexes on `ceremonies(phase)`, `ceremonies(phase, commit_deadline)`, and `ceremonies(phase, reveal_deadline)`.

### 13. ~~`ExtendDeadline` beacon fallback is not implemented~~
**Files:** `src/Veritas/Workers/BeaconFetcher.hs`, `src/Veritas/DB/Queries.hs`, `src/Veritas/Core/Types.hs`
**Fix:** Implemented the `ExtendDeadline` fallback: reads current deadline, extends it, updates DB, and appends a `DeadlineExtended` audit log entry. Added `DeadlineExtended` event variant and `updateRevealDeadline` query.

### 14. ~~Sensitive entropy material stored in `localStorage`~~
**Files:** `web/src/hooks/useCeremonySecrets.ts`, `web/src/hooks/useCeremonySecrets.test.ts`
**Fix:** Replaced `localStorage` with `sessionStorage` to limit exposure to current tab session.

### 15. ~~Duplicate key warning in frontend audit log rendering~~
**File:** `web/src/components/AuditLog.tsx`
**Fix:** Changed `key={entry.sequence_num}` to `key={entry.entry_hash}` (guaranteed unique).

### 16. ~~README/API route mismatch for public key endpoint~~
**File:** `README.md`
**Fix:** Changed `GET /pubkey` to `GET /server/pubkey` to match actual API route.

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
