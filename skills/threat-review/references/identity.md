# Identity: authentication, sessions, tokens, authorization

Load this when the change touches who the caller is, how that is remembered, or what they are
allowed to do.

Two questions, and they fail independently: **authentication** asks whether the claimed identity is
proven; **authorization** asks whether that identity may perform this operation on this object. A
change that gets the first right and skips the second is the most common serious defect in this
area.

## Authentication (CWE-287)

- Verify the credential server-side, every time, against the stored verifier. A comparison against a
  value the client also supplied proves nothing.
- Compare secrets with a constant-time comparison (CWE-208).
- No default, shared, embedded or fallback credential on any path that reaches production
  (CWE-798, CWE-1392). A "development" bypass guarded only by a configuration flag is one
  misconfiguration away from being the production path.
- Rate-limit and lock out on repeated failure, keyed on the account and on the source, with the
  failure logged (CWE-307). Apply the same limit to password reset, one-time-code entry and token
  refresh, not only to the login form.
- Keep registration, login, reset and resend responses uniform in message, status and observable
  timing, so they do not disclose whether an account exists (CWE-204).
- Password storage: a memory-hard or purpose-built password hash with a per-user salt and current
  work factors. A general-purpose fast digest is a finding regardless of iteration count
  (CWE-916, CWE-759). Follow the current NIST SP 800-63B digital identity guidance for length,
  composition and screening against known-breached values rather than legacy complexity rules.
- Second factors and one-time codes: bind to the session that requested them, expire in minutes,
  accept once, and limit verification attempts.
- Recovery flows are authentication. A reset token is a credential: single use, short lived, high
  entropy, invalidated on use and on password change.

## Sessions (CWE-384, CWE-613)

- Generate the session identifier server-side from a cryptographically secure source, with enough
  entropy that guessing is infeasible.
- **Issue a new identifier at every privilege change** — login, step-up, impersonation, role switch.
  Reusing a pre-authentication identifier is session fixation.
- Invalidate server-side on logout, on password or credential change, and on idle and absolute
  timeout. Clearing the cookie alone leaves a usable session.
- Cookies carrying session state: `HttpOnly`, `Secure`, an explicit `SameSite`, the narrowest `Path`
  and `Domain`, and no host-wide scope on a shared parent domain.
- Never place a session identifier in a URL, a log, an error message or a referrer-visible location.
- State-changing requests need cross-site request forgery protection (CWE-352): a per-session
  synchronizer token, or an origin-bound scheme, with `SameSite` as defense in depth rather than the
  whole control. A change that makes a previously safe endpoint accept a simple cross-origin form
  post reopens this.

## Tokens and claims (CWE-347, CWE-345)

- Verify the signature before reading any claim, with an algorithm and key the **verifier** chose.
  Never let the token's own header select the algorithm or the key, and never accept an unsigned
  token.
- Validate the standard claims the deployment depends on: issuer, audience, expiry, not-before, and
  subject. An expired-token check that is missing or clock-skewed by hours is a finding.
- Keep access tokens short-lived. A long-lived bearer token cannot be revoked by anything other than
  a denylist, so if the design needs revocation, check that the denylist actually exists and is
  consulted.
- Refresh tokens: store hashed, bind to a client and session, rotate on use, and treat reuse of a
  rotated token as theft — revoke the whole family and log it.
- A token is a bearer credential. It does not belong in a URL, in browser storage reachable by
  injected script, in a log, or in an analytics payload.
- Delegated-authorization flows: allowlist exact redirect targets rather than matching a prefix or a
  wildcard subdomain (CWE-601); require proof-key exchange for public clients; validate the state
  parameter; and verify the identity token rather than trusting an endpoint response.
- API keys and service credentials carry a scope and an owner, and are verifiable without the
  ability to forge others.

## Authorization and access control (CWE-862, CWE-863, CWE-639)

- **Default deny.** A route, action, field or message handler without an explicit permission
  decision is unauthorized, and a diff that adds one without a check is a finding (CWE-862).
- Decide server-side, in one place the whole application reuses. A permission enforced in the
  client, in the navigation, or by omitting a link is not enforced.
- **Object-level authorization is separate from route-level.** Authorization to call an endpoint is
  not authorization to touch the identifier passed to it. Every read, update and delete scopes by
  owner or tenant in the query itself, rather than fetching and then comparing — the fetch-then-check
  shape leaks existence and invites the check being dropped later.
- An unguessable identifier is not an access control.
- Multi-tenant code: the tenant comes from the authenticated session, never from a request field.
  Look for a repository call, background job, cache key, export or admin helper that omits the
  tenant predicate.
- Vertical escalation: check that a role or permission field cannot be set through ordinary input,
  that privileged operations re-verify at the point of effect, and that an impersonation or support
  path is itself authorized, bounded and logged.
- Field-level authorization matters where a response serializer or a graph query can return more
  than the caller may see.
- Failure denies: an error resolving permissions is a deny, never a fallback to allow (CWE-636).
- Log authorization failures with enough context to investigate, and none of the secret material.

## Cross-origin exposure

A permissive cross-origin resource sharing policy is an authorization decision. Reflecting the
request origin, or allowing any origin together with credentials, exposes authenticated endpoints to
any site. Allowlist exact origins and allow credentials only where the endpoint genuinely needs
them.

## How this shows up in a diff

- A new endpoint, handler, message consumer or scheduled job with no authorization decision.
- An identifier taken from the request and used to fetch without an ownership or tenant predicate.
- A permission check moved earlier than the data it should constrain, or replaced by a client-side
  guard.
- A session lifetime, cookie attribute, token expiry or clock-skew tolerance widened.
- A new claim trusted from a token without a corresponding verification.
- A test that asserts an allowed caller succeeds, with no case asserting a forbidden caller is
  denied.
