# Secrets and cryptography

Load this when the change handles credentials or key material, hashes, encrypts, signs, or generates
a value that must be unguessable.

Two rules carry most of the weight: **use a vetted construction rather than assembling primitives**,
and **keep key material out of the artifact**. Almost every finding in this area is one of those two.

## Standing policy on pre-existing exposure

Credentials, tokens or other sensitive values already present in git history, chat history, logs,
files or other existing artifacts are **accepted risk**. Do not rotate, scrub, redact, rewrite
history, remove, report or otherwise remediate them unless explicitly asked.

What this review enforces is that the change introduces **no new** secret. Everything below is about
the diff in front of you.

## Secrets in the change (CWE-798, CWE-540, CWE-615)

A secret is any value whose disclosure grants access: passwords, API keys, tokens, private keys,
signing keys, connection strings with credentials, webhook signing secrets, session and encryption
keys.

- None of them belong in source, in a committed configuration file, in a container or build
  manifest, in infrastructure definitions, in a test fixture, in a snapshot, or in a comment.
- They come from a secret manager or an injected environment value, resolved at run time, with the
  code referencing a name rather than a value.
- A committed example or template file carries placeholders, and the real file is ignored by version
  control. Check that a newly added configuration file is actually ignored.
- Secrets never reach logs, traces, metrics labels, analytics events, error messages, crash reports
  or a response body. Look for a whole request, header map, configuration object or model instance
  being logged or serialized wholesale — that is how a credential escapes without anyone writing it
  down.
- Redact in the type, not at the call site: a wrapper whose string representation hides the value is
  reliable; remembering to redact at every log line is not.
- Comments are part of the shipped artifact, and for client-side and interpreted code they ship to
  users. A credential, internal hostname, bucket, queue, internal path or personal data in a comment
  is a finding, as is commented-out code carrying any of them.

## Randomness (CWE-330, CWE-338)

- Anything security-relevant — session identifiers, tokens, reset codes, nonces, initialization
  vectors, salts, one-time values, generated passwords — comes from the platform's cryptographically
  secure generator.
- A general-purpose pseudo-random function, a time value, a counter, a process identifier or a hash
  of predictable inputs is a finding wherever unguessability is the point (CWE-340).
- Seeding a generator with a fixed or low-entropy value is a finding (CWE-336, CWE-337).
- Give tokens enough entropy that online guessing is hopeless, and compare them in constant time.

## Password and credential storage (CWE-916)

Use a memory-hard or purpose-built password hash with a per-user random salt and current work
factors, and re-hash on login when the factors move. A fast general-purpose digest, a digest with a
static salt, or an unsalted digest is a finding whatever the iteration count. Encrypting a password
instead of hashing it is a finding: it means the plaintext is recoverable.

For a stored API key or long-lived token, store a hash and compare in constant time, exactly as for
a password.

## Algorithms and modes (CWE-327, CWE-328)

- Prefer a high-level, misuse-resistant library over assembling primitives by hand.
- Encryption uses an authenticated construction. Unauthenticated modes invite tampering and padding
  oracles (CWE-696, CWE-353). Encrypt-then-authenticate, never authenticate-then-encrypt.
- Broken or obsolete primitives for a security purpose are findings: legacy digests used for
  signatures or integrity, single-block legacy ciphers, and stream ciphers long since withdrawn.
  A legacy digest used purely as a non-security checksum is not a finding; say so explicitly when
  ruling it out.
- Never reuse a nonce or initialization vector with the same key, and never derive one from a
  counter that can restart. This is the most common way a correct algorithm choice still fails.
- Follow the platform's own official cryptography guidance and current NIST publications for
  parameter choices rather than a remembered number.
- Do not invent a construction: no home-made encryption, no home-made key derivation, no signature
  built out of a digest and a shared secret where a message authentication code exists.

## Keys (CWE-320, CWE-321)

- Keys are generated with a proper generator, stored in a key manager or a platform keystore, and
  scoped to one purpose. One key, one job — signing keys do not encrypt, and per-tenant data does
  not share one key with everything else.
- Rotation is possible: key identifiers travel with the ciphertext or the token so old material can
  be verified while new material is issued. A design with no rotation path is a MEDIUM finding at
  minimum.
- Derive sub-keys with a proper key derivation function, not by hashing a password or concatenating
  strings.
- Keys are not logged, not serialized into an object dump, and not held longer than needed.

## Transport and data at rest

- Transport uses current TLS with certificate validation enabled. Disabled verification, a permissive
  hostname check, or a blanket "accept all certificates" helper is a finding even when it is guarded
  by a development flag (CWE-295).
- Pin production container images by digest, keeping the tag alongside for readability.
- Sensitive data at rest is encrypted where the threat model calls for it, and sensitive responses
  are not cached by intermediaries.
- Store only what is needed. Data never collected cannot leak.

## Signature verification (CWE-347)

Verify the signature before acting on the payload, using a key the verifier selected and an
algorithm the verifier fixed. Compare in constant time. For inbound webhooks, verify against the raw
body bytes — verifying a re-serialized parse is a bypass.

## How this shows up in a diff

- A literal that looks like a key, a long opaque string, or a connection string with an embedded
  password.
- A new configuration file, manifest or fixture added without a corresponding ignore rule.
- A logging or error-reporting call taking a whole request, configuration or model object.
- A general-purpose random call in a token, identifier or salt path.
- A digest chosen for a signature, a password, or an integrity check.
- A certificate-validation or hostname-check flag turned off.
- A new nonce or initialization vector derived from anything other than a secure generator.
- A comparison of two secret values with an ordinary equality operator.
