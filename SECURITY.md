# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Veritas, please report it responsibly.

**Email:** Open a [GitHub issue](https://github.com/danallison/veritas/issues) with the label `security`. If the vulnerability is sensitive (e.g., it could be exploited before a fix is deployed), please reach out privately before disclosing publicly.

Please include:
- A description of the vulnerability
- Steps to reproduce
- The potential impact
- Suggested fix (if you have one)

## Security Model

Veritas is a cryptographic verification platform. Its security relies on:

- **Ed25519 signatures** — All state-changing actions require valid cryptographic signatures. There is no anonymous mode.
- **Commit-reveal protocol** — Results are sealed (hashed) before any are revealed, preventing validators from copying each other.
- **Hash-chained audit log** — Every event is chained via SHA-256, making tampering detectable.
- **Verifiable random selection** — Validator selection uses drand beacon randomness, so anyone can verify the draw was fair.
- **Parameterized SQL** — All database queries use parameterized placeholders (no SQL injection surface).
- **Serializable transactions** — Critical state transitions use `SERIALIZABLE` isolation to prevent race conditions.

## Known Limitations

Veritas is pre-production software. The following are known areas to address before production deployment:

- **CORS is unrestricted** — All origins are currently allowed. Production deployments should whitelist origins.
- **Rate limiter is IP-based** — Behind a reverse proxy, all requests appear from the same IP. `X-Forwarded-For` support is not yet implemented.
- **Docker image runs as root** — The production Dockerfile does not set a non-root `USER`.
- **Server keys are ephemeral by default** — Without `VERITAS_SERVER_KEY` configured, a fresh Ed25519 keypair is generated on each startup.
- **No pagination on pool list endpoints** — Large result sets could cause high memory usage.
- **Verification-specific threats** — See [docs/security-audit.md](docs/security-audit.md) for the full audit, including threats specific to the cross-validation protocol (colluding validators, cache poisoning, replay attacks).

## Cryptographic Dependencies

| Algorithm | Library | Purpose |
|-----------|---------|---------|
| SHA-256 | crypton | Hashing, content addressing, audit log chaining |
| Ed25519 | crypton | Participant and server signatures |
| BLS12-381 | hsblst | drand beacon signature verification |
| HKDF-SHA256 | crypton | Key derivation |

## Full Audit

A detailed security audit with findings, threat analysis, and recommendations is maintained at [docs/security-audit.md](docs/security-audit.md).
