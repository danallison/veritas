# Technical Debt

## Open


## Resolved

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
