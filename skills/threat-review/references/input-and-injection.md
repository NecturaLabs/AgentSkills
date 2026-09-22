# Input and injection

Load this when the change accepts data from outside the trust boundary, builds a query or a command,
renders output, or parses, decodes or deserializes anything.

The single question behind every check here: **does data cross from a place an attacker controls
into a place that interprets it?** Injection is a confusion between data and code, and the fix is
always structural separation, never cleverer escaping.

## Where the data comes from

Treat all of these as attacker-influenced: request paths, query strings, headers, cookies and
bodies; uploaded files and their names and declared types; form fields; websocket frames; message
queue payloads; webhook bodies; rows a different tenant can write; responses from third-party
services; environment variables and command-line arguments on a multi-tenant host; and text a model
or agent produced from any of the above.

The mistake to look for in a diff is a **second-hand source**: data that was validated at one
boundary, stored, and later read back as if it were trusted. Stored values are only as trustworthy
as the weakest writer of that store.

## Validation (CWE-20)

- Validate on the server. A client-side check is a user-experience feature.
- Validate by **grammar, schema and bounds**: type, shape, required fields, length, range, character
  class, format. Reject rather than repair — a sanitizer that strips and continues turns a rejected
  input into an accepted, altered one.
- Use an **allowlist** for any enumerated choice: sort column, file extension, redirect target,
  content type, locale, status transition. A blocklist enumerates yesterday's attacks.
- Enforce bounds on size and count before allocating: body size, array length, page size, nesting
  depth, decompressed size, regex input length (CWE-400, CWE-1333).
- Canonicalize once, then validate the canonical form (CWE-180). Validating before decoding means
  validating a different string than the one that reaches the sink.

## SQL and other query languages (CWE-89, CWE-943)

- Parameterized statements or a parameterizing query builder. Never string concatenation or
  interpolation, including in an `IN` list, a `LIKE` pattern, or a fragment assembled conditionally.
- Identifiers — table, column, sort direction — cannot be parameters. Map user input through an
  allowlist to a literal identifier the code owns.
- A raw-SQL escape hatch in an ORM (`raw`, `literal`, `whereRaw`, `text`) in a diff is a signal:
  check where every interpolated value came from.
- The same rule holds for NoSQL filters, LDAP filters, XPath, GraphQL and search-engine query
  strings. In document stores, watch for an operator object arriving where a scalar was expected —
  a JSON body can smuggle a query operator into a filter.
- Bound the result set. A query that can return every row is a disclosure amplifier when anything
  else goes wrong.

## Command execution (CWE-78)

- Run processes with an argument array and no shell. If a shell is genuinely required, the command
  must be a constant and the untrusted parts must arrive as arguments, never spliced into the text.
- Watch for the shell arriving implicitly: a helper whose "shell" flag defaults on, a string form of
  a spawn call, a `system`-style call, a pipeline built as text.
- Argument injection is distinct from command injection: a value starting with `-` can become a
  flag. Where the value can be attacker-controlled, validate its shape, and use `--` where the tool
  supports it.
- The environment is part of the call. Do not pass attacker-influenced values into loader,
  interpreter or proxy variables.

## Code and template evaluation (CWE-94, CWE-95, CWE-1336)

- No evaluation of untrusted data: dynamic evaluation, dynamic import of a caller-named module,
  deserialization into code, a template compiled from user input.
- Server-side template injection is the quiet one — user input must be a **value passed to** a
  template, never part of the template text.
- Dynamic attribute or function lookup by a user-supplied name is the same defect in a different
  shape; resolve through an explicit map.

## Output encoding and cross-site scripting (CWE-79, CWE-116)

- Encode at the point of output, for that exact context: HTML text, attribute value, URL component,
  JavaScript literal, CSS. A single generic escape applied everywhere is wrong in most of them.
- Prefer a template engine's automatic contextual escaping. In a diff, the finding is usually the
  deliberate bypass: a raw-HTML helper, a "trust this string" marker, direct assignment of markup to
  an element, or a sanitizer replaced with a pass-through.
- Client-side sinks matter as much as server-rendered markup: assignment of untrusted data to
  markup-parsing properties, to a script or style element, or to a URL that may carry a script
  scheme (CWE-79, DOM-based).
- URLs built from input need scheme allowlisting; `javascript:` and `data:` are the classic escapes.
- Serialized data embedded in a page must be encoded for the surrounding script context, not merely
  serialized.
- A Content Security Policy is defense in depth. It does not make an unencoded sink acceptable, and
  a policy with a permissive fallback contributes little.
- Log lines are an output context too: strip or encode newlines and control characters in logged
  values (CWE-117), and never log a value that carries a credential or personal data.

## Deserialization and structured formats (CWE-502)

- Never deserialize untrusted data into arbitrary types. Native or reflection-based deserializers
  that can instantiate types named in the payload are remote code execution waiting for a gadget.
- Use a data-only format and a schema, and deserialize into an explicit type. Where a
  polymorphic-type feature exists, keep it off or allowlist the permitted types.
- Where a payload must survive a round trip through a client, verify integrity on the way back.
- XML parsers: disable external entity resolution and DTD processing (CWE-611), and cap expansion
  (CWE-776).
- Archive extraction: reject entries whose resolved destination escapes the target directory, and
  cap entry count, entry size and total expanded size (CWE-22, CWE-409).

## File uploads (CWE-434)

- Validate content type by inspecting the bytes, not the declared header or the extension.
- Generate the stored name; never build a path from the supplied name. Store outside any directory
  the server will execute or serve directly from.
- Cap size and count before writing, and enforce a per-principal quota.
- Serve back with an explicit content type and a disposition that prevents inline interpretation for
  anything that is not a format you deliberately render.

## Mass assignment and over-posting (CWE-915)

Binding a request body straight onto a persisted model lets a caller set fields the form never
showed — role, owner, price, verified flags. Bind to an explicit input type listing exactly the
fields the endpoint accepts.

## Error and response surfaces (CWE-209, CWE-497)

An error message is an output context with an attacker as a reader. Return a generic message and an
identifier; keep the stack trace, query text, file path and internal hostname in the log. Watch for
a diff that adds a detailed message "to help debugging" on a request path.

## How this shows up in a diff

- A new parameter threaded into an existing query, command, path or template.
- A validation call removed, loosened, or moved after the sink.
- A raw or unescaped helper introduced, or a sanitizer swapped for a pass-through.
- A type widened — a string where an enum was, a map where a record was, `any` where a shape was.
- A new format parsed, or a new deserializer configured.
- A test fixture that proves the happy path only, with no case for a hostile value.
