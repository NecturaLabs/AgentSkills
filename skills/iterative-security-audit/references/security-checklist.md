# Security Audit Checklist

> Sources: OWASP Top 10 (2021), CWE/SANS Top 25 (2025), OWASP ASVS, OWASP Secure Coding Practices, NIST SP 800-218, CERT SEI, Microsoft SDL

## A01: Broken Access Control [CRITICAL]

- [ ] Default-deny access control policy
- [ ] Access controls centralized and reused
- [ ] Record ownership enforced (not just CRUD)
- [ ] Directory listing disabled
- [ ] Access control failures logged and alerted
- [ ] APIs rate-limited
- [ ] Session IDs invalidated on logout; JWTs short-lived
- [ ] No URL/parameter tampering bypasses (IDOR)
- [ ] No privilege escalation paths
- [ ] CORS properly configured
- [ ] Functional access control tests present

## A02: Cryptographic Failures [CRITICAL]

- [ ] No sensitive data stored unnecessarily
- [ ] All sensitive data encrypted at rest
- [ ] TLS enforced with HSTS for data in transit
- [ ] Strong algorithms only (no MD5, SHA1, DES, RC4)
- [ ] Passwords: Argon2, scrypt, bcrypt, or PBKDF2
- [ ] No hardcoded keys, secrets, or passwords
- [ ] Proper key management and rotation
- [ ] Authenticated encryption (not just encryption)
- [ ] Cryptographically secure RNG
- [ ] Caching disabled for sensitive responses

## A03: Injection [CRITICAL]

- [ ] Parameterized queries/prepared statements (no string concat in SQL)
- [ ] ORM with parameterized interfaces
- [ ] Server-side input validation (positive/allowlist)
- [ ] Special characters escaped (interpreter-specific)
- [ ] LIMIT clauses to prevent mass disclosure
- [ ] User data never directly in interpreter calls
- [ ] Context-aware output encoding (XSS prevention)
- [ ] Content Security Policy (CSP) deployed
- [ ] No eval/exec of user-supplied data

## A04: Insecure Design [HIGH]

- [ ] Threat modeling for critical flows
- [ ] Security requirements in user stories
- [ ] Plausibility checks at all tiers
- [ ] Tier layer segregation by exposure
- [ ] Resource consumption limited per user/service
- [ ] Tenant segregation enforced (multi-tenant)

## A05: Security Misconfiguration [HIGH]

- [ ] Repeatable hardening process
- [ ] Minimal platform (unused features removed)
- [ ] Security headers sent (CSP, X-Frame-Options, X-Content-Type-Options, Strict-Transport-Security)
- [ ] No default credentials in production
- [ ] Error handling hides stack traces
- [ ] XXE processing disabled
- [ ] Cloud storage permissions reviewed
- [ ] Debug mode disabled in production

## A06: Vulnerable Components [HIGH]

- [ ] Component version inventory maintained
- [ ] Unused dependencies removed
- [ ] CVE/NVD monitoring active
- [ ] SCA tools integrated (Dependency Check, Snyk, etc.)
- [ ] Components from official sources with signed packages
- [ ] Unmaintained libraries tracked

## A07: Authentication Failures [HIGH]

- [ ] MFA implemented
- [ ] No default credentials
- [ ] Passwords checked against known-bad lists
- [ ] NIST 800-63b password guidelines followed
- [ ] Registration/recovery resist account enumeration
- [ ] Failed login attempts limited with logging
- [ ] Server-side session management with random IDs
- [ ] Sessions invalidated on logout/idle timeout
- [ ] Brute force protections active

## A08: Integrity Failures [HIGH]

- [ ] Digital signatures verify software/data sources
- [ ] Libraries from trusted repositories
- [ ] Supply chain security tools deployed
- [ ] CI/CD pipeline access controlled
- [ ] Serialized data integrity-checked
- [ ] Deserialization of untrusted data avoided

## A09: Logging & Monitoring [MEDIUM]

- [ ] Logins, failed logins, high-value transactions logged
- [ ] Access control failures logged with context
- [ ] Log format compatible with management solutions
- [ ] Log data encoded (prevent injection)
- [ ] Audit trails with integrity controls
- [ ] Monitoring and alerting configured
- [ ] No sensitive data in logs

## A10: SSRF [HIGH]

- [ ] Remote resource access in separate networks
- [ ] Deny-by-default firewall for intranet
- [ ] Client URLs sanitized and validated
- [ ] URL schema/port/destination allowlisted
- [ ] Raw responses not forwarded to clients
- [ ] HTTP redirections disabled

## Input Validation (Cross-Cutting)

- [ ] All inputs validated server-side
- [ ] Allowlists over blocklists
- [ ] Input length restrictions enforced
- [ ] File uploads validated (type, size, content)
- [ ] Files stored outside webroot, renamed
- [ ] Path traversal prevented (canonicalize paths)

## Data Protection (Cross-Cutting)

- [ ] Sensitive data NEVER logged (passwords, tokens, PII)
- [ ] No sensitive info in error responses
- [ ] PII handled per data protection regulations
- [ ] Secure defaults for all configurations

## Session Management (ASVS V7 + OWASP SCP)

- [ ] Session IDs generated server-side with sufficient entropy
- [ ] Session timeout configured (idle + absolute)
- [ ] New session ID generated on authentication
- [ ] Session fixation prevented
- [ ] Session IDs not in URLs, error messages, or logs
- [ ] Cookies: Secure, HttpOnly, SameSite attributes set
- [ ] Concurrent session controls enforced
- [ ] Per-session CSRF tokens for sensitive operations

## API & Web Service Security (ASVS V4)

- [ ] API endpoints enforce authentication and authorization
- [ ] HTTP methods restricted to those required
- [ ] GraphQL query depth and complexity limited
- [ ] WebSocket connections authenticated
- [ ] API rate limiting enforced
- [ ] JWT signatures verified (no "none" algorithm)
- [ ] Token expiration enforced
- [ ] PKCE enforced for OAuth public clients
- [ ] Redirect URIs strictly validated

## Secure Communication (ASVS V12)

- [ ] TLS 1.2+ enforced (1.3 preferred)
- [ ] Strong cipher suites only
- [ ] Certificate validation enabled (no self-signed in prod)
- [ ] HSTS with adequate max-age
- [ ] Internal service-to-service encrypted

## Configuration & Secrets (ASVS V13)

- [ ] Secrets not in code, config files, or env vars — use secret manager
- [ ] Error messages hide system internals
- [ ] Debug mode disabled in production
- [ ] Default configurations hardened
- [ ] Test code and credentials removed before deployment

## Supply Chain (NIST SSDF + Microsoft SDL)

- [ ] SBOM generated for releases
- [ ] Dependencies scanned before integration
- [ ] Build pipeline integrity protected
- [ ] Third-party code reviewed and approved
- [ ] Code signing for release artifacts
- [ ] Source repo access restricted and audited

## Memory Safety (CERT + CWE)

- [ ] Integer operations checked for overflow (CWE-190)
- [ ] Buffer sizes validated before access (CWE-120/121/122)
- [ ] No use-after-free (CWE-416)
- [ ] Format strings never from user input (CWE-134)
- [ ] Pointers nullified after free
- [ ] Memory-safe languages preferred for new code

## CWE/SANS Top 25 Quick Reference

| CWE | Name | Check |
|-----|------|-------|
| 79 | XSS | Output encoding, CSP, auto-escaping templates |
| 89 | SQLi | Parameterized queries only |
| 352 | CSRF | Anti-CSRF tokens, SameSite cookies |
| 862 | Missing Auth | Authorization on every restricted resource |
| 787 | OOB Write | Bounds checking, memory-safe languages |
| 22 | Path Traversal | Canonicalize, validate, chroot |
| 416 | Use After Free | Nullify after free, smart pointers |
| 125 | OOB Read | Buffer size validation |
| 78 | OS Cmd Injection | No shell with user input, use APIs |
| 94 | Code Injection | No eval/exec of user data |
| 434 | File Upload | Validate type/size/content, store outside webroot |
| 502 | Deserialization | Avoid untrusted data, allowlist classes |
| 918 | SSRF | Allowlist destinations, block internal network |
| 770 | Resource Exhaustion | Rate limiting, timeouts, quotas |
| 20 | Input Validation | Server-side, allowlists |
