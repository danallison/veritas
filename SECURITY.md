# Security Audit

Last updated: 2026-03-13

## Summary

The codebase has strong fundamentals: parameterized SQL everywhere, proper crypto algorithms (SHA-256, Ed25519, BLS12-381, HKDF), React's default XSS escaping, TLS support, and serializable transactions for critical state transitions. The findings below are areas to address before production deployment.

## Findings

### High

#### 1. ~~No authentication on any endpoint~~ **ADDRESSED**

**Location:** `src/Veritas/API/Types.hs:54-81`

~~All API endpoints are publicly accessible. Anyone who knows (or guesses) a participant UUID can act on their behalf in anonymous ceremonies — committing, revealing, or cancelling. The self-certified ceremony path mitigates this via cryptographic signatures, but anonymous ceremonies have no protection.~~

**Resolution:** Anonymous ceremony mode has been removed. All ceremonies now use self-certified identity (Ed25519 keypair registration, roster signing, signed commitments). Every state-changing action requires a valid cryptographic signature, eliminating the UUID-guessing attack vector. OAuth identity mode is planned as a future addition.

---

### Medium

#### 2. CORS allows all origins

**Location:** `app/Main.hs:80-83`

`simpleCorsResourcePolicy` defaults `corsOrigins` to `Nothing`, meaning all origins are allowed. Any website can make cross-origin requests to the API.

**Recommendation:** Set `corsOrigins` to a whitelist of allowed origins, loaded from an environment variable.

#### 3. Partial `error` calls can crash handler threads

**Location:** `src/Veritas/DB/Queries.hs:592,600,606,613,656` and `src/Veritas/DB/Pool.hs:38`

Haskell's `error` throws an unrecoverable exception. Unexpected database values (e.g., an unknown phase string from a manual edit or migration issue) will crash the request handler thread with an unhelpful 500 error.

**Recommendation:** Replace `error` with `Either`-returning functions and handle failures gracefully with structured logging.

#### 4. ~~No pagination on list endpoints~~ **PARTIALLY ADDRESSED**

**Location:** ~~`src/Veritas/DB/Queries.hs:138-151`~~, `src/Veritas/DB/PoolQueries.hs:174-179,203-209`

~~`listCeremonies`,~~ `getPoolCacheEntries`, and `getPoolRounds` have no `LIMIT` clause. A single request can return all rows, causing high memory usage and potential denial of service.

**Resolution (partial):** The `GET /ceremonies` list endpoint has been removed entirely — ceremonies are now secret, accessible only by ID. The remaining pool list endpoints (`getPoolCacheEntries`, `getPoolRounds`) are scoped to a specific pool ID and are lower risk, but still lack pagination.

**Recommendation:** Add a default `LIMIT` (e.g., 100) and support pagination via query parameters for the remaining pool endpoints.

#### 5. Rate limiter bypassed behind reverse proxy

**Location:** `src/Veritas/API/RateLimit.hs:42,68-71`

The rate limiter identifies clients by TCP socket address (`remoteHost`). Behind a reverse proxy, all requests appear to come from the proxy's IP, making the rate limiter ineffective.

**Recommendation:** Support `X-Forwarded-For` when running behind a trusted proxy, configured via environment variable.

#### 6. Production Docker image runs as root

**Location:** `Dockerfile.prod:30-42`

No `USER` directive. The `veritas` process runs as root inside the container, making container escape easier if a vulnerability is exploited.

**Recommendation:** Add a non-root user:
```dockerfile
RUN useradd --system --create-home veritas
USER veritas
```

#### 7. Ephemeral server keys by default

**Location:** `src/Veritas/Config.hs:111`, `app/Main.hs:46`

When `VERITAS_SERVER_KEY` is not set, the server generates a fresh Ed25519 key pair on every startup. VRF proofs from one server lifetime cannot be verified after a restart, silently breaking verifiability for OfficiantVRF ceremonies.

**Recommendation:** Require `VERITAS_SERVER_KEY` in production or emit a WARNING-level log instead of INFO.

---

### Low

#### 8. `dangerouslySetInnerHTML` in verification code display

**Location:** `web/src/components/verification/RunnableCodeBlock.tsx:85`

Prism.js syntax-highlighted output is rendered as raw HTML. The interpolated values are validated (`assertUuid`, `assertHex`, `assertUrl` in `codeStrings.ts`), but the pattern is fragile — Prism does not HTML-escape all unrecognized content.

**Recommendation:** Sanitize Prism output with DOMPurify, or ensure all interpolated values are escaped as string literals before highlighting.

#### 9. Dynamic code execution in verification page

**Location:** `web/src/components/verification/executeStep.ts:30,47`

`new Function(...)` and `new AsyncFunction(...)` construct JavaScript at runtime from strings that embed API data. Mitigated by input validation but architecturally risky.

**Recommendation:** Run verification code in a sandboxed Web Worker, or escape all interpolated values as JavaScript string literals.

#### 10. ~~`.gitignore` missing sensitive file patterns~~ **ADDRESSED**

**Location:** `.gitignore`

~~No exclusions for `.env`, `*.pem`, or `*.key` files. Sensitive files placed in the project root could be accidentally committed.~~

**Resolution:** Added `.env`, `.env.*`, `*.pem`, and `*.key` patterns to `.gitignore` (with `!.env.example` exception).

---

### Verification Pivot: New Attack Surface

The verification pivot introduces cross-validation of AI agent outputs, which brings new threat vectors not present in the original ceremony-only design.

#### V1. Colluding validators

**Attack:** Two or more validators coordinate out-of-band to submit matching results without independently computing. This defeats the purpose of cross-validation — a fabricated result gets a "Unanimous" verdict.

**Current mitigations:**
- Commit-reveal seals prevent validators from copying each other's on-platform submissions
- Validator identities are hidden from each other and from the submitter until all seals are in
- drand-based selection makes it difficult to predict who will be selected

**Gaps:** Out-of-band coordination between colluding principals is not detectable by protocol alone. Requires the stratified selection constraint from `common-pool-computing.md` (all participants from different principals) to be enforced — currently not implemented. Pool size and principal diversity are the primary defenses.

**Recommendation:** Implement principal-level stratification when pool sizes support it. Track and surface validator agreement patterns to detect suspiciously correlated agents.

#### V2. Result fabrication by submitter

**Attack:** Submitter sends a fabricated result for "verification," hoping validators reproduce the same wrong answer (e.g., by submitting a plausible but subtly incorrect computation spec that deterministically produces the desired output).

**Current mitigations:**
- The computation spec (fingerprint) is what validators execute — if it's correct, validators will produce the correct result
- Unanimous/majority verdict only confirms that validators independently got the same answer, which is the correct behavior

**Risk assessment:** Low. This is by design — if the computation spec itself is wrong, the verification confirms consistency, not correctness. The spec is the contract; verification checks reproducibility. Users must understand that a "verified" result means "independently reproduced," not "correct in an absolute sense."

#### V3. Cache poisoning via small pools

**Attack:** In a pool with very few members, the attacker controls enough agents to guarantee they'll be selected as validators. They submit fabricated results that get cached.

**Current mitigations:**
- Minimum pool size is not currently enforced
- drand selection is verifiable but doesn't help if the attacker controls all eligible agents

**Recommendation:** Enforce a minimum number of distinct principals in a pool before verification requests are accepted. Display pool size and diversity metrics in the UI so users can assess trust.

#### V4. Replay/grinding attacks on verification

**Attack:** Attacker submits the same computation for verification repeatedly, hoping for a favorable validator draw that includes their colluding agents.

**Current mitigations:**
- Cache immutability: once a result is cached, it cannot be overridden by a new verification
- Each verification gets a unique ID and drand round

**Gaps:** Nothing prevents submitting the same fingerprint for re-verification if the first attempt was inconclusive. Rate limiting per agent/fingerprint would help.

---

### Info

#### 11. Hardcoded HKDF salt

**Location:** `src/Veritas/Crypto/Hash.hs:36`

The HKDF extract step uses a fixed salt `"veritas-salt"`. This is acceptable because the input keying material is already high-entropy cryptographic randomness. Per-ceremony or per-deployment salts would be a minor improvement.

---

## Not Found

The following common vulnerability classes were checked and **not found**:

- **SQL injection** — All queries use `postgresql-simple` parameterized placeholders
- **Command injection** — No shell execution anywhere in the backend
- **Hardcoded secrets** — No API keys, passwords, or tokens in source code
- **Weak cryptography** — Uses SHA-256, Ed25519, BLS12-381, HKDF-SHA256 throughout
- **XSS** — React's JSX escapes interpolated values by default; the one `dangerouslySetInnerHTML` usage is noted above
- **Insecure transport** — TLS support present via `VERITAS_TLS_CERT` and `VERITAS_TLS_KEY`
- **Race conditions** — Critical state transitions use `SERIALIZABLE` isolation level
