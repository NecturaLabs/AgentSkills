# Review checklist

The reviewer's checklist for the code itself. Comments are checked separately, and so are
tests. Everything in `SKILL.md` still binds — in particular, a finding needs evidence, and
style a configured tool owns is not a finding.

Work through the sections the diff actually reaches. A change to one pure function does
not earn a concurrency pass; a change to a shared cache earns two.

## Design

| Check | Typical severity |
|---|---|
| The change fits the architecture it lands in, rather than bolting a second way of doing an existing thing | CRITICAL where it breaks an invariant, else HIGH |
| Behavior lives where its data lives — no method that only reaches through another object to work | HIGH |
| Dependencies point inward: policy does not depend on infrastructure detail | HIGH |
| Adding the next variant will not require editing this code again in the same way | HIGH |
| A long chain of type tests that a polymorphic call would replace | HIGH |
| Injection or an interface where it buys testability or a correct dependency direction — direct construction where it does not | MEDIUM |
| Speculative generality: an abstraction, hook or parameter with exactly one caller and no second one in sight | MEDIUM |
| Duplication of logic that already exists in the repository, rather than reuse of it | MEDIUM |

Two failure directions, and the cure for one is never the other: an unstructured pile of
special cases, and a framework built for requirements nobody has. Flag whichever the diff
actually shows.

## Complexity

These are **signals to check cohesion and intent**, not limits to satisfy mechanically.
Report the confusion, never the number — a function over any threshold that reads clearly
is not a finding, and a short one that hides three responsibilities is.

- A function doing several things, where the name can only describe it with "and".
- Nesting deep enough that the reader must hold the conditions in their head. Early
  returns or an extracted function usually collapse it.
- A parameter list long enough that call sites are unreadable, or that the same group of
  values keeps travelling together — that group is a type waiting to be named.
- A boolean parameter that selects behavior. Two named functions say what one flag hides.
- A hidden side effect: a query that mutates, a getter that lazily writes, a constructor
  that performs work.
- A class accumulating unrelated responsibilities, changing for several unrelated reasons.
- One conceptual change that forces edits in many files — the concept is not located
  anywhere.

## Error handling

| Check | Severity |
|---|---|
| An exception or error swallowed: an empty handler, a discarded result, a bare catch that continues | CRITICAL |
| A resource not released on the error path — use the language's own cleanup construct rather than a manual close | CRITICAL |
| A secret, credential, internal path or stack internal in a message that reaches a user or a log | CRITICAL |
| The original cause dropped when wrapping | HIGH |
| A broad catch where a specific type is meant, swallowing unrelated failures with it | HIGH |
| The same error logged and rethrown, so it is reported twice from two places | HIGH |
| A message that names neither what failed nor what the caller can do | HIGH |
| Null returned where an empty collection or an explicit absent type is the honest answer | MEDIUM |
| An error path with no test, in a change whose point is the error path | HIGH |

## Resources, performance and data access

| Check | Severity |
|---|---|
| A file, socket, connection, lock, subscription or handle that is not released on every path | CRITICAL |
| An unbounded cache, queue or accumulating collection | CRITICAL |
| A connection not returned to its pool | CRITICAL |
| A query per element of a collection where one query would serve | HIGH |
| An event handler or observer registered and never removed | HIGH |
| A data structure whose cost does not match the access pattern — a scan where a lookup is needed | HIGH |
| A performance claim in the change description with no measurement against a baseline | MEDIUM |

## Concurrency

| Check | Severity |
|---|---|
| Shared mutable state reachable from more than one thread or task without protection | CRITICAL |
| Check-then-act on shared state: the value can change between the check and the act | CRITICAL |
| Locks acquired in inconsistent order across paths | CRITICAL |
| An external or overridable call made while holding a lock | CRITICAL |
| A sleep standing in for a signal, condition variable or completion handle | HIGH |
| A critical section wider than the invariant it protects | HIGH |
| Async work started and never awaited, cancelled or joined | HIGH |

## Boundaries and input

| Check | Severity |
|---|---|
| External input reaching logic without validation by grammar, schema and bounds at the boundary | CRITICAL |
| A query built by string concatenation rather than parameters | CRITICAL |
| Untrusted data interpolated into command text rather than passed as a separated argument array | CRITICAL |
| A path taken from input and used without resolving it against an allowed root and rejecting anything outside | CRITICAL |
| Output placed into HTML, SQL, a shell, a URL or a log without encoding for that context | CRITICAL |
| An enumerated choice validated by rejecting known-bad values rather than accepting known-good ones | HIGH |
| A failure that opens rather than closes — an error path that grants access it should deny | CRITICAL |

## Compatibility

| Check | Severity |
|---|---|
| A public signature, response shape, error code, status code or field type changed without a stated break and a migration path | CRITICAL |
| A serialized format, wire message or persisted shape changed such that old readers or old data break | CRITICAL |
| A schema migration that is destructive before the code needing the old shape is gone | CRITICAL |
| A migration with no tested rollback, forward-recovery or restore path | HIGH |
| A migration that will not complete at production data volume | HIGH |
| Default behavior changed under an unchanged name, so existing callers get something new silently | HIGH |
| A dependency bumped without reading the changelog, reviewing the lockfile and transitive diff, checking advisories and licence, and running the tests that exercise it | HIGH |
| An application or container pinning a range where it should pin an exact version, or a library pinning exact where a range is correct | MEDIUM |
| A production container image referenced by tag alone rather than by digest | HIGH |

Schema and data changes follow expand, migrate, contract. A diff that does all three at
once is the finding, however correct each step is on its own.

## Naming

No formatter renames an identifier, so naming is reviewable in every language, always.

Language-independent, at HIGH: a name that does not say what the thing is; near-identical
names distinguished only by a digit or a suffix; two words for one concept in the same
module; a magic number or string that should be a named constant. A class is a noun, a
function is a verb, and a boolean reads as a predicate in that language's own form —
`isEmpty`, `is_empty`, `empty?`, `isempty`, `IsEmpty`.

Type-encoding prefixes are a defect — `strName`, `iCount`. Scope and kind markers that the
language's own convention prescribes are not: C# `_camelCase`, `s_`, `t_` and `IFoo`, C++
trailing `_` on class members, Objective-C leading `_ivar`, Kotlin `_name` for a backing
property, Go's lowercase initial as access control.

**Whose rule it is decides the severity.** State whose rule, always.

| Source of the convention | Severity |
|---|---|
| The language's own creators — PEP 8, Effective Go, the Rust Style Guide, Kotlin, Scala, Swift, Dart, Elixir, Julia | HIGH |
| Anyone else — a corporate, project or community guide, or a house default | LOW |

The two most often misfiled: `rubystyle.guide` is community-maintained and Ruby publishes
no style guide of its own; PHP-FIG, which publishes PSR-1 and PSR-12, is independent of
the PHP Group. A `snake_case` PHP method is "the PSR convention this project does not
claim to follow", at LOW — not "PHP's rule", at HIGH. Google's guides for Java,
JavaScript, TypeScript, C++ and Objective-C, the Linux kernel's for C, the tidyverse's for
R, Roblox's for Lua, sqlstyle.guide and Apollo's GraphQL conventions all sit in the lower
tier too.

The project's own configuration outranks both: `.editorconfig`, `rustfmt.toml`,
`.prettierrc`, `checkstyle.xml`, `ruff.toml`, `.clang-format`, `.golangci.yml`, or a
framework or studio standard the project actually follows.

### Acronyms

The most common casing defect, and it genuinely differs by language.

| Rule | Languages |
|---|---|
| Ordinary word — `XmlHttpRequest`, `Uuid`, `maxId` | Java, JavaScript, TypeScript, Rust, Scala, Lua, Haskell |
| Ordinary word, two-letter acronyms keep both capitals — `IOStream` | Kotlin |
| Two letters keep both capitals, but closed compounds are words — `Id`, `Ok`, `Email` | C# |
| Two-letter acronyms English capitalises keep both — `ID`, `UI`; longer are words — `Http` | Dart |
| Uniform case, never mixed — `URL` or `url`, never `Url` | Go |
| Uniformly up- or down-cased by position — `utf8Bytes`, `isRepresentableAsASCII` | Swift |
| Fully capitalised — `SomeXML` | Ruby, Elixir |
| Avoided altogether | Swift, GraphQL, Objective-C, Julia, SQL |

### Derived-language naming traps

A language that borrows another's syntax almost never borrows its naming. The instinct
comes from the ancestor and is wrong. Check the row before filing — or accepting — a name.

| Language | Reads like | The wrong instinct | What its creators specify |
|---|---|---|---|
| TypeScript | JavaScript | A trailing `_` on private fields; `IFoo` interfaces | `_` is banned as prefix **and** suffix; no `I` prefix |
| Dart | Java, C# | `SCREAMING_CASE` constants | `lowerCamelCase` constants and enum values; leading `_` is real privacy |
| Scala | Java | `MAX_VALUE`, `XHTML` | `UpperCamelCase` constants; acronyms as words |
| Kotlin | Java | `mFoo`, `sFoo` prefixes | No prefixes; `_name` only for a backing property; `const val` is `SCREAMING_SNAKE_CASE` |
| C# | Java | `camelCase` methods, `MAX_SIZE` | `PascalCase` for methods **and** constants; `_camelCase` private fields |
| Java | C# | `PascalCase` methods, `XMLHTTPRequest` | `lowerCamelCase` methods; acronyms as words |
| Go | C, Java | `get_user()`, `GetUser()`, `my_package` | No `Get` prefix, no underscores, `MixedCaps`; packages one lowercase word |
| Rust | C++ | `get_len()`, `UUID` | No `get_`; `Uuid`; `SCREAMING_SNAKE_CASE` for consts and statics only |
| C++ | C | A trailing `_` on every member | **Class** members take it; **struct** members do not. Constants are `kName` |
| Objective-C | C++ | Trailing-underscore instance variables | **Leading** `_ivar`; C functions `UpperCamelCase`, methods `lowerCamelCase` |
| Swift | Objective-C | `NSFoo` prefixes, `kConstant` | Modules namespace types; `lowerCamelCase` constants |
| Ruby | Python | `is_empty()`, `delete_all_destructive()` | `empty?` for predicates, `!` for the dangerous variant |
| Elixir | Ruby | `empty?` for every boolean | `?` for booleans, **`is_` for anything guard-safe** |
| Julia | Python | `is_equal`, `has_key` | Squashed lowercase: `isequal`, `haskey`; mutating functions end `!` |
| R | Python, S | `myVar`, `my.var` | `snake_case`; `.` is reserved for the S3 system |
| PHP | Java, C | `snake_case` methods | `camelCase` methods, `StudlyCaps` classes; property casing deliberately unspecified |
| GDScript | Python | 4 spaces, `snake_case` classes | Tabs; `PascalCase` classes, `CONSTANT_CASE` constants and enum members |
| Luau | Lua | `snake_case` locals, 2-space indent | Tabs; `camelCase` locals, `PascalCase` classes and Roblox APIs |
| Shell | C, Java | `CamelCase` function names | `snake_case`; constants and exported variables `UPPER_SNAKE_CASE` |
| SQL | Application code | `tbl_users`, `spGetUser` | No `tbl_`/`sp_` prefixes; tables collective, **columns singular** |
| GraphQL | REST JSON | `snake_case` fields, `getUser` queries | `camelCase` fields, `PascalCase` types, `SCREAMING_SNAKE_CASE` enum values; only mutations lead with a verb |
| Terraform | Ruby, JSON | `resource "aws_instance" "web_aws_instance"` | Never repeat the resource type in its name |
| CSS | JavaScript | `userProfile` class names | Lowercase, hyphen-separated: `user-profile` |

For a language not listed: apply the project's configuration, then that language's own
published guide. Do not infer a convention from a language it resembles — that is the trap
above. If the language publishes none, say so rather than inventing one, review for
internal consistency, and state that the convention was derived rather than looked up.

## Layout

A formatter fixes layout and never fixes a name. So layout is a finding in five cases
only. Everywhere else the tool owns it, and reporting it spends real effort on nothing.

1. **Indentation is syntax** — Python, YAML, a Makefile recipe, Haskell, Nim, F#.
   Re-indenting changes meaning or stops the file parsing. **CRITICAL.**
2. **Indentation misleads** — it implies a block the delimiters do not create. This is
   CWE-483, the class behind `goto fail`. Report it as the correctness bug it is,
   never as style. **CRITICAL.**
3. **Tabs and spaces mixed**, or the indent character contradicts the language's rule in a
   language where indentation is not syntax — tabs in Rust, spaces in Go. **HIGH.**
4. **A file in the diff is unformatted** against the formatter config the project already
   has. Once for the diff, not once per line. **MEDIUM.**
5. **Line endings, encoding or the final newline are wrong** — below.

Cases 1 and 2 are line-scoped and fire on a line the author wrote. Cases 3 to 5 are
whole-file properties, where authorship decides: a defect the diff introduced or worsened
is a finding at the severity above, while the same defect already present in a file the
diff merely edited is **INFO once**, with a separate normalisation commit recommended.

Two specific traps: a shell here-document opened with `<<-` strips **leading tabs only**,
so retabbing it to spaces silently changes its content; and a `#` inside a Makefile recipe
line is passed to the shell rather than stripped by make.

### Line endings, encoding and the last line

Invisible in a rendered diff, and they break execution rather than looks. Nothing else in
the review surfaces them. Authority: `.gitattributes` governs what is stored,
`.editorconfig` `end_of_line` governs what the editor writes, and a per-clone
`core.autocrlf` is neither reviewable nor shareable and is not a policy.

| Defect | Why | Severity |
|---|---|---|
| CRLF in a file with a shebang | The `\r` joins the interpreter path: `bad interpreter: /bin/bash^M`. The file is valid and simply will not run | CRITICAL |
| CRLF in a Makefile recipe or a strict LF-only parser's input | Same class — the `\r` is data | CRITICAL |
| A UTF-8 BOM where the format forbids one — shell, JSON, PHP before headers | It precedes the shebang or first token and breaks parsing | CRITICAL |
| Mixed line endings inside one file | Consumers disagree where lines end; diff, patch and hashing diverge | HIGH |
| Missing final newline | POSIX leaves the file ending in an incomplete line, which line-oriented tools drop or miscount | MEDIUM, and not a finding where the formatter or `insert_final_newline` owns it |
| A line-ending or encoding flip bundled into a behavioral change | It rewrites every line and makes the real change unreviewable | HIGH |
| A CRLF working tree on Windows under `* text=auto` | The mechanism working as designed; the index holds LF | Not a finding |

## Not a finding

- A column count, wrap point, blank line, trailing whitespace or alignment a configured
  formatter produced or would fix.
- A missing `.gitattributes`, formatter config or linter — a fact about the repository,
  raised once as INFO. As a finding it would recur on every review of that repository
  forever, and the no-deferral rule would then force an unrelated repo-wide change.
- A convention from a guide the project does not claim to follow, reported as the
  language's rule. Report it at LOW, and name whose rule it is.
- A complexity number on code that reads clearly.
- A warning class the repository already carries at scale. Note once; do not open a
  cleanup campaign inside someone else's diff.

## Sources

[Google engineering practices](https://google.github.io/eng-practices/review/reviewer/looking-for.html) ·
[PEP 8](https://peps.python.org/pep-0008/) ·
[Effective Go](https://go.dev/doc/effective_go) ·
[Rust API guidelines](https://rust-lang.github.io/api-guidelines/naming.html) ·
[Kotlin coding conventions](https://kotlinlang.org/docs/coding-conventions.html) ·
[Scala naming conventions](https://docs.scala-lang.org/style/naming-conventions.html) ·
[.NET capitalization conventions](https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/capitalization-conventions) ·
[Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) ·
[Effective Dart — style](https://dart.dev/effective-dart/style) ·
[Elixir naming conventions](https://elixir.hexdocs.pm/naming-conventions.html) ·
[Julia style guide](https://docs.julialang.org/en/v1/manual/style-guide/) ·
[CWE-483 Incorrect Block Delimitation](https://cwe.mitre.org/data/definitions/483.html) ·
[gitattributes](https://git-scm.com/docs/gitattributes) ·
[EditorConfig specification](https://spec.editorconfig.org/) ·
[POSIX.1 base definitions — line, incomplete line](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap03.html) ·
[OWASP Top 10](https://owasp.org/www-project-top-ten/) ·
[CWE Top 25](https://cwe.mitre.org/top25/)
