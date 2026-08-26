# Naming and Layout

Identifier naming and code layout, per language. Everything in `review-checklist.md`
still binds; this file is the detail behind its sections 4 (Naming) and 9 (Style &
Consistency), and nothing here overrides it.

Two concerns live here because they fail in opposite ways. **A formatter fixes layout and
never fixes a name.** So layout is mostly not a review finding — the tool owns it — while
naming always is, in every language, forever. The gate below is what keeps that distinction
from collapsing into whitespace nitpicking.

## Resolution Order

1. **The project's own configuration.** `.editorconfig`, `.gitattributes`, `rustfmt.toml`,
   `.prettierrc`, `checkstyle.xml`, `ruff.toml`, `.clang-format`, `scalafmt.conf`,
   `.golangci.yml`, `.eslintrc`, `stylelint.config`. If it sets a case style, an indent or
   a line ending, it wins. `.gitattributes` governs line endings in the repository;
   `.editorconfig` governs them in the editor via `end_of_line`.
2. **A framework, engine or studio coding standard the project follows.** Epic's C++
   standard for Unreal, a studio's GDScript guide, an in-house Java style. These rank with
   the project's own configuration and above this matrix, because they are what the code is
   actually held to.
3. **This matrix.**
4. **The universal core** in `review-checklist.md` section 4.

Where a row says **(house)** the language publishes no rule and the value is our default,
not a citation. Everything else is quoted from the guide the Sources list names for that
row — which is not always the language's own creators. Which authority a row carries decides
its severity: see *Rules this file did not get from the language's creators* below.

## What Is and Is Not a Finding

**Naming is always reviewable.** No formatter renames identifiers, so a name that
contradicts its language's convention is a finding in every language, forever. Exactly two
things set the severity, and the same ladder governs every casing and acronym rule in this
file and in `review-checklist.md` section 4:

| Where the rule comes from | Severity |
|---|---|
| **The language's own creators** — PEP 8, Effective Go, the Rust Style Guide, Kotlin, Scala, Swift, Dart, Elixir, Julia | **High** |
| **Anyone else** — a corporate, project or community guide, or a row marked `(house)` | **Low** |

**This ladder governs naming only.** It does not reach layout: gate cases 1–3 below keep
their own severities, so a tab in YAML indentation or a space-indented Makefile recipe stays
**CRITICAL** no matter who published the casing rule for that format.

Ambiguity is a separate axis and keeps its own severities from `review-checklist.md`
section 4: a name that is unclear, inconsistent, or a magic number is a finding on its own
terms whatever its casing does.

**Layout is reviewable only in five cases.** Everywhere else, the formatter owns it:

1. **Indentation is syntax.** Re-indenting changes what the program means or stops it
   parsing. Python, YAML, Makefile recipes, Haskell/Nim/F# layout. **CRITICAL.**
2. **Indentation misleads.** The indentation implies a block the delimiters do not create —
   [CWE-483 Incorrect Block Delimitation](https://cwe.mitre.org/data/definitions/483.html),
   the class behind Apple's `goto fail` (CVE-2014-1266). `gcc`/`clang` ship
   `-Wmisleading-indentation` for exactly this. **CRITICAL** — a correctness bug, reported
   as one, never as style.
3. **Tabs and spaces are mixed** within a file or a block, or the indent character
   contradicts the language's own rule **in a language where indentation is not syntax** —
   tabs in Rust, spaces in Go, tabs in Ruby. **HIGH.** Where indentation *is* syntax — a
   Makefile recipe, YAML, Python — case 1 governs instead and the severity is CRITICAL.
4. **A file in the diff is unformatted** against the formatter config the project already
   has. Report it once for the diff, not once per column. **MEDIUM.**
5. **Line endings, encoding or the final newline are wrong** — see *Line Endings, Encoding
   and the Last Line* below. These are invisible in a rendered diff and break execution
   rather than looks, so they need checking deliberately; no formatter reliably owns them.

**Every case above is scoped to what the diff did — and for most of them that is not a
line.** Cases 1 and 2 are line-scoped: they fire on a line the author wrote. Cases 3, 4 and
5 describe **whole-file** properties, where "which line" is meaningless — a file has one
indent character, one line ending and one encoding, not one per line. There the test is
authorship, not location:

| What the diff did | Verdict |
|---|---|
| Added the file, wrote unformatted lines into it, or changed its indent character, line endings, encoding or final newline | A finding, at the severity stated above |
| Only edited lines in a file that already had the defect, without adding to it | **INFO**, once — recommend a separate normalisation commit, and let the loop close |

So a **pre-existing** CRLF shebang, BOM or mixed-indent file is an INFO note on this review,
not a CRITICAL one. It is a real bug and it is worth saying so plainly — but it is not this
author's bug, and demanding it here would force exactly the whole-file rewrite that *Line
Endings, Encoding and the Last Line* below forbids putting into a behavioural diff.

### Repository-state observations are advisory, not findings

The absence of a `.gitattributes`, of a formatter config, or of a linter is a fact about the
repository, not about the change under review. Raised as a finding it recurs on **every**
review of that repository forever — a one-line bugfix included — and the no-deferral rule
then forces an unrelated repo-wide fix before the loop can close. It also demands, inside
the reviewed diff, exactly the whole-file normalisation that *Line Endings* below forbids
putting there.

So: note a missing policy **once, as INFO**, and let the loop close. It does not block a
clean pass, it is not escalated on recurrence, and it is never restated in a later
iteration of the same review. Recommend the fix as its own commit; do not require it here.

### Rules this file did not get from the language's creators

Rule 4 of `comment-rules.md` binds here too, and it cuts both ways: a convention is only
the language's if the language published it. Many rows below come from a corporate, project
or community guide that a project is free not to follow — Google's guides, the Linux
kernel's, Tibell's Haskell guide, the tidyverse style guide, the Roblox Lua style guide,
Apollo's GraphQL conventions, sqlstyle.guide, `rubystyle.guide`, PHP-FIG's PSRs, and every
row marked `(house)`. **That list is not exhaustive**: the Sources list names the authority
behind every row, and anything there that is not the language's own creators belongs in
this tier.

Such a contradiction is **LOW** on the ladder above, and it is never described as the
language's rule. Say whose rule it is: *"the kernel style this project does not claim to
follow"*, not *"C requires 8-column tabs"*. This tier covers most of the matrix — Java,
JavaScript, TypeScript, C, C++, Objective-C, Shell, HTML/CSS, R, Ruby, PHP, Lua/Luau,
Haskell, SQL and GraphQL all sit in it — so reaching for HIGH is the exception, not the
default.

**Ruby and PHP are the easiest to misplace**, because both of their guides read official
and neither is. `rubystyle.guide` is community-maintained and Ruby's creators publish no
style guide of their own; PHP-FIG, which publishes PSR-1 and PSR-12, self-describes as a
group of established PHP projects and is independent of the PHP Group. A `snake_case` PHP
method is *"the PSR standard this project does not claim to follow"*, at LOW — not *"PHP's
rule"*, at HIGH.

**Not a finding, ever:** a column count, a wrap point, a blank line, or an alignment that a
configured formatter produced or would fix on its next run. Reporting those inflates the
iteration loop with noise the tool resolves for free, and the no-deferral rule then forces
real work onto them. If `rustfmt` or `dart format` did it, it is correct by definition —
*"the official whitespace-handling rules for Dart are whatever `dart format` produces."*

## Identifier Casing

| Language | Types | Functions / methods | Variables | Constants | Files / modules | Private marker |
|---|---|---|---|---|---|---|
| Python | `CapWords` | `snake_case` | `snake_case` | `UPPER_SNAKE_CASE` | modules `lowercase`, underscores if readable; packages `lowercase`, underscores discouraged | `_single` weak internal; `__double` name-mangles |
| JavaScript | `UpperCamelCase` | `lowerCamelCase` | `lowerCamelCase` | `CONSTANT_CASE` | packages `lowerCamelCase`; **file names all lowercase, underscores or dashes permitted** | optional **trailing** `_` on private fields |
| TypeScript | `UpperCamelCase` (class, interface, type, enum, type params) | `lowerCamelCase` | `lowerCamelCase` | `CONSTANT_CASE`, incl. enum values | module alias `lowerCamelCase` | **none — `_` is banned as prefix *and* suffix** |
| Java | `UpperCamelCase` | `lowerCamelCase` | `lowerCamelCase` | `UPPER_SNAKE_CASE` | packages lowercase + digits, **no underscores**, words concatenated | **none** — `name_`, `mName`, `s_name`, `kName` all rejected |
| Kotlin | `UpperCamelCase` | `lowerCamelCase` | `lowerCamelCase` | `const val` and immutable top-level/object `val`: `SCREAMING_SNAKE_CASE`; `val` holding an object with behavior: `camelCase` | packages lowercase, no underscores | backing property `_name` |
| Scala | `UpperCamelCase` | `lowerCamelCase` | `lowerCamelCase` | **`UpperCamelCase`** | packages follow Java | — |
| C# | `PascalCase` (types, interfaces `IFoo`, methods, properties, events, enum values, namespaces) | `PascalCase` | locals `camelCase`; **parameters `camelCase`** | **`PascalCase`** | — | private/internal instance `_camelCase`, static `s_`, thread-static `t_` |
| Go | `MixedCaps` exported / `mixedCaps` unexported | same; **no `Get` prefix**; one-method interfaces take `-er` | same; length ∝ scope | `MixedCaps` | packages short, lowercase, single word, **no underscores or mixedCaps** | lowercase initial letter *is* the access control |
| Rust | `UpperCamelCase` (types, traits, enum variants) | `snake_case`; **no `get_` prefix**; `as_`/`to_`/`into_` signal conversion cost | `snake_case` | consts and statics `SCREAMING_SNAKE_CASE` | crates and modules `snake_case` | — |
| C **(Linux kernel — C publishes no language-wide convention)** | `snake_case` | `snake_case` | `snake_case`; globals descriptive, locals short; no Hungarian | `SCREAMING_SNAKE_CASE` macros | `snake_case` | — |
| C++ | `UpperCamelCase` | `UpperCamelCase`; accessors may be `snake_case()` matching the member | `snake_case`; **class** members take a **trailing `_`**, **struct** members do **not** | `kUpperCamelCase`, incl. enumerators; macros `SCREAMING_SNAKE_CASE` | files lowercase with `_` or `-`; namespaces lowercase | trailing `_` on class members |
| Objective-C | `UpperCamelCase`; a **3+ character prefix** is *required* on classes and protocols **shared across applications**, and *recommended, not required*, elsewhere | methods and params `lowerCamelCase`; C **functions** `UpperCamelCase` | `lowerCamelCase`; globals `g`-prefixed | file-scope `k` prefix | file name matches the class, including case | instance vars **leading** `_ivar` |
| Swift | `UpperCamelCase` (types, protocols) | `lowerCamelCase` | `lowerCamelCase` | `lowerCamelCase` | — | `private`/`fileprivate` keywords, **not** a name prefix |
| Dart | `UpperCamelCase` (classes, enums, typedefs, type params, extensions) | `lowerCamelCase` | `lowerCamelCase` | **`lowerCamelCase`**, incl. enum values | libraries, packages, directories, files `lowercase_with_underscores` | leading `_` — language-level, not a convention |
| Ruby | `CapitalCase`; acronyms stay uppercase (`SomeXML`) | `snake_case`; predicates end `?`; dangerous variants end `!` | `snake_case` | `SCREAMING_SNAKE_CASE` | files and directories `snake_case` | `_` prefix by convention |
| PHP | `StudlyCaps` (PascalCase) | **`camelCase`** | **deliberately unspecified by PSR-1 — be consistent within scope** | class constants `UPPER_SNAKE_CASE` | PSR-4 maps namespace to path | `_` prefix has **no** visibility meaning |
| Elixir | modules/aliases `CamelCase`, acronym capitals preserved | `snake_case`; booleans end `?`, **but guard-safe checks take an `is_` prefix**; raising variants end `!` | `snake_case` | module attributes `snake_case` | `snake_case.ex` | `_unused`; `__meta__` is compile-time metadata |
| Haskell | `UpperCamelCase` (types, constructors, modules — modules singular) | `camelCase` | `camelCase` | — | module path matches the name | — |
| Julia | `UpperCamelCase` (modules, types) | **lowercase, squashed together where readable** (`isequal`, `haskey`); *"when necessary, use underscores as word separators"*; mutating functions end `!` | lowercase | — | — | — |
| R | — | `snake_case`, verbs | `snake_case`, nouns; lowercase, digits and `_` only | `snake_case` | `snake_case` | **reserve `.` for the S3 system** |
| Shell, Bash | — | `snake_case`; libraries separated with `::` | `snake_case`; declare function-local with `local` | constants and exported environment `UPPER_SNAKE_CASE`, declared at the top of the file | lowercase, underscores if desired | — |
| PowerShell | `PascalCase` | **`Verb-Noun`**, PascalCase, an **approved verb**, and a **singular** noun | `PascalCase` (house) | `PascalCase` (house) | — | — |
| Lua, Luau | `PascalCase` (classes, enum-likes); **Roblox APIs `PascalCase`** | `camelCase` locals | `camelCase`, incl. member values | local constants `LOUD_SNAKE_CASE` | file name matches the object it exports | `_camelCase` |
| GDScript | `PascalCase` (classes, nodes); enum names `PascalCase` | `snake_case` | `snake_case`; signals `snake_case`, past tense | `CONSTANT_CASE`, incl. enum members | files `snake_case.gd` | leading `_` on private and virtual members |
| SQL | — | stored procedures **must contain a verb**, no `sp_` prefix | tables collective or plural; **columns singular**; lowercase `snake_case`; identifiers **≤ 30 characters** | keywords `UPPERCASE` | — | — |
| HTML, CSS, SCSS | — | — | **everything lowercase**; class and id names **hyphen-separated** (`user-profile`) | — | — | — |
| Terraform, HCL | — | — | resources, variables, outputs, locals: `snake_case` descriptive nouns | — | — | — |
| GraphQL | `PascalCase` | fields, arguments and directives `camelCase`; fields do not start with a verb **except mutations, which must** | `camelCase` | enum values `SCREAMING_SNAKE_CASE` | — | — |
| YAML, TOML, JSON, XML | — | — | key casing project-defined; **consistent within a document** (house) | — | — | — |
| Dockerfile, Makefile | — | — | `ARG`/`ENV` and make variables `UPPER_SNAKE_CASE` (house) | — | — | — |

### Acronyms and initialisms

The single most common casing defect, and the rule genuinely differs by language:

| Rule | Languages |
|---|---|
| Treat as an ordinary word — `XmlHttpRequest`, `loadHttpUrl`, `Uuid`, `Stdin`, `HttpServer`, `xHtml`, `maxId`, `aJsonVariable` | Java, JavaScript, TypeScript, Rust, Scala, Lua/Luau, Haskell (`IO`, a Prelude type name, is the standing exception) |
| Ordinary word, **but two-letter acronyms keep both capitals** — `IOStream`, `XmlFormatter`, `HttpInputStream` | Kotlin |
| Two-letter acronyms keep both capitals — `IOStream`, `HtmlTag` — **but closed-form compounds are single words: `Id` not `ID`, `Ok` not `OK`, `Email` not `EMail`** | C# |
| Ordinary word, but two-letter acronyms that English capitalises keep both — `ID`, `TV`, `UI`; longer ones are words — `Http`, `Nasa`, `Uri` | Dart |
| **Uniform case, never mixed** — `URL` or `url`, never `Url`; `XMLAPI`; `iOS`, `gRPC` as prose spells them | Go |
| Uniformly up- or down-cased by position — `utf8Bytes`, `isRepresentableAsASCII`, `userSMTPServer` | Swift |
| **Keep fully capitalised** — `SomeXML`, `XMLSomething` | Ruby, Elixir |
| Avoid acronyms and abbreviations in the first place | Swift, GraphQL, Objective-C, Julia, SQL |

## Indentation and Layout

| Language | Indent | Continuation | Line limit | Formatter that owns it |
|---|---|---|---|---|
| Python | **4 spaces**; tabs only to stay consistent with already-tab-indented code | aligned, or hanging indent; the 4-space rule is optional here | 79 code, **99 by team agreement**; 72 comments | `black`, `ruff format` |
| JavaScript | **2 spaces**; tabs not used; U+0020 is the only whitespace character permitted | +4 | 80 | `prettier`, `clang-format` |
| TypeScript | 2 spaces; tabs not used — **inherited from Google JavaScript. The TS guide publishes no width, no tab rule and no column limit; it delegates formatting to the tool** | +4 (Google JS) | 80 (Google JS) | `prettier` |
| Java | **2 spaces**; **tab characters are not used** | **+4** | 100 | `google-java-format` |
| Kotlin | **4 spaces**; **do not use tabs** | — | — | `ktlint`, `ktfmt` |
| Scala | **2 spaces**; **tabs are not used** | +2 from the first line | 80 (`scalafmt` `maxColumn`) | `scalafmt` |
| C# | **4 spaces, no tabs** | — | — | `.editorconfig` + `dotnet format` |
| Go | **tabs** — *"`gofmt` emits them by default. Use spaces only if you must"* | wrap and indent with **an extra tab** | **none** — *"Go has no line length limit"* | **`gofmt` is the authority** |
| Rust | **4 spaces**; *"use spaces, not tabs"*; all indentation a multiple of 4 | — | 100 | `rustfmt` |
| C | **tabs, 8 columns wide** *(Linux kernel; a project on other settings is not in breach)*; more than 3 nesting levels means the function needs splitting; `switch` and `case` align in the same column | — | 80 preferred (kernel) | `clang-format` |
| C++ | **2 spaces**, no tabs | — | 80 | `clang-format` |
| Objective-C | **2 spaces**; *"do not use tabs"* | — | 100 | `clang-format` |
| Swift | **2 spaces**; **tab characters are not used**; U+0020 only | +2 | 100 | `swift-format` |
| Dart | **2 spaces** | — | 80 preferred | **`dart format` — *"the official whitespace-handling rules for Dart are whatever `dart format` produces"*** |
| Ruby | **2 spaces (soft tabs)**; tabs prohibited | — | 80 | `rubocop` |
| PHP | **4 spaces**; *"MUST NOT use tabs for indenting"* | — | *"The **soft limit** MUST be 120"*; lines **SHOULD NOT** exceed 80 | `php-cs-fixer` |
| Elixir | **2 spaces** | — | 98 (`mix format`) | `mix format` |
| Haskell | 4 spaces, `where` at 2 **(Tibell — a widely-followed project guide, not a language standard; Haskell itself defines tab stops at 8 and does not outlaw tabs)** | — | 80 **(house)** — the language publishes none | `ormolu`, `fourmolu`, `stylish-haskell` |
| Julia | **4 spaces** | — | 92 | `JuliaFormatter` |
| R | **2 spaces** | — | 80 | `styler`, `air` |
| Shell, Bash | **2 spaces, no tabs** — except the body of a `<<-` here-document, which **must** be tab-indented because `<<-` strips tabs and only tabs | — | 80 | `shfmt` |
| PowerShell | 4 spaces (house) | — | — | `PSScriptAnalyzer` |
| Lua, Luau | **tabs** | — | comments 80 / code 100 | `stylua` |
| GDScript | **tabs** | **2 indent levels**; a single level for arrays, dictionaries and enums | 100, *"try to keep lines under 80"* | `gdformat` |
| SQL | spaces, aligned so root keywords end on a common character boundary (the "river") | — | — | `sqlfluff` |
| GraphQL | 2 spaces (house; `prettier` default) | — | — | `prettier` |
| HTML, CSS, SCSS | **2 spaces**; *"don't use tabs or mix tabs and spaces"* | — | — | `prettier`, `stylelint` |
| YAML | **spaces only — a tab in indentation is invalid**; indentation *is* the structure | — | — | `prettier`, `yamlfmt` |
| Makefile | **a recipe line must begin with a literal tab character**; `.RECIPEPREFIX` can change it | — | — | none |
| Terraform, HCL | **2 spaces** | — | — | `terraform fmt` |
| TOML, JSON, XML, Dockerfile | project-defined (house) | — | — | `prettier` for JSON |

## Where Indentation Is Not Cosmetic

These are **not** style findings and never get downgraded to LOW:

- **Python** — indentation is block structure. Re-indenting a line moves it between
  branches. Mixing tabs and spaces raises `TabError`; the language disallows it outright.
- **YAML** — indentation is structure, and *"to maintain portability, tab characters must
  not be used in indentation, since different systems treat tabs differently."* A tab does
  not misformat the document, it changes or breaks it.
- **Makefile** — *"you need to put a tab character at the beginning of every recipe line."*
  Spaces there produce `missing separator`. This survives every reformat, because no
  general-purpose formatter knows it.
- **Shell `<<-` here-documents** — `<<-` strips **leading tabs only**. A well-meaning
  retab to spaces silently breaks the delimiter and changes the here-doc's content.
- **Haskell, Nim, F#** — the layout rule makes indentation significant the same way.
- **Any brace language — misleading indentation.** Indentation that implies a block the
  braces do not create is [CWE-483](https://cwe.mitre.org/data/definitions/483.html), the
  defect behind `goto fail` (CVE-2014-1266). Two statements indented under an unbraced
  `if`, a `for` body that does not include the line beneath it, a macro that swallows a
  statement. Report it as the correctness bug it is. `-Wmisleading-indentation` exists
  because reviewers miss it.

## Line Endings, Encoding and the Last Line

Invisible in a rendered diff, and the failures are execution failures rather than cosmetic
ones. Check these explicitly — nothing else in the review will surface them.

**Authority, in order.** `.gitattributes` governs what is stored: `* text=auto` normalises
to LF in the index on check-in, and `eol=lf`/`eol=crlf` sets what lands in the working
tree. `.editorconfig` `end_of_line` governs what the editor writes. `core.autocrlf` is a
**per-clone, unversioned fallback** and is not a substitute for either — it cannot be
reviewed, shared or enforced, so a project relying on it alone has no line-ending policy.

**Not a finding:** a CRLF working tree on Windows under `* text=auto`. That is the
mechanism working as designed — the index holds LF, and the review sees the index.

| Defect | Why it matters | Severity |
|---|---|---|
| CRLF in a file with a shebang — shell scripts, Python entry points, container entrypoints | The `\r` becomes part of the interpreter path: `bad interpreter: /bin/bash^M`. The file is syntactically fine and simply will not run | **Critical** |
| CRLF in a Makefile recipe, or in a file parsed by a strict LF-only reader | Same class — the `\r` is data, not whitespace | **Critical** |
| A UTF-8 **BOM** where the format forbids one — shell scripts, JSON, PHP before headers, sourced files | The BOM precedes the shebang or the first token and breaks parsing or output. `.editorconfig` distinguishes `utf-8` from `utf-8-bom` for exactly this reason | **Critical** |
| Mixed line endings inside a single file | Every consumer disagrees about where lines end; `diff`, `patch` and hashing all diverge | **High** |
| Missing newline at end of file — git renders `\ No newline at end of file` | POSIX defines a line as *"zero or more non-<newline> characters plus a terminating <newline>"*; without it the file ends in an **incomplete line**, which line-oriented tools (`read`, `wc -l`, concatenation) drop or mis-count | **Medium**, and not a finding where `insert_final_newline` or a formatter owns it |
| Trailing whitespace | Real, but owned by `trim_trailing_whitespace` and every formatter | Not a finding where a formatter or `.editorconfig` covers it |
| A cross-platform repository with no `.gitattributes` normalisation | Line endings churn on every checkout and bury real changes in whole-file diffs | **INFO**, once — a repository-state observation, per the gate above |

**A line-ending flip is a whole-file rewrite.** Converting EOLs rewrites every line, so the
real change becomes unreviewable. This is the same defect as mixing style with logic in
`review-checklist.md` section 9: normalisation belongs in its own commit, and a diff that
silently carries one is a finding regardless of whether the new endings are correct.

## Derived-Language Traps

A language that borrows another's syntax almost never borrows its naming or layout. This is
the same failure the comment matrix documents, in a different register: the instinct comes
from the ancestor, and it is wrong. Check the row before you file — or write — a name.

| Language | Reads like | The wrong instinct | What its creators actually specify |
|---|---|---|---|
| **TypeScript** | JavaScript | A trailing `_` on private fields, the way Google JS permits | **`_` is banned as a prefix *and* a suffix.** Interfaces take no `I` prefix |
| **Dart** | Java, C# | `SCREAMING_CASE` constants | **`lowerCamelCase` constants**, enum values included. Leading `_` is real privacy, not a hint |
| **Scala** | Java | `MAX_VALUE` constants, `XHTML` acronyms | **`UpperCamelCase` constants.** Acronyms are ordinary words: `xHtml`, `maxId` |
| **Kotlin** | Java | `mFoo`, `sFoo` field prefixes | No prefixes; **`_name` only for a backing property**. `const val` is `SCREAMING_SNAKE_CASE` |
| **C#** | Java | `camelCase` methods, `MAX_SIZE` constants | **`PascalCase` for methods *and* constants**; `_camelCase` private fields; `IFoo` interfaces |
| **Java** | C# | `PascalCase` methods, `XMLHTTPRequest` | `lowerCamelCase` methods; acronyms as words — `XmlHttpRequest`, `supportsIpv6OnIos` |
| **Go** | C, Java | `get_user()`, `GetUser()`, `Url`, `my_package` | No `Get` prefix, no underscores, **`MixedCaps`**; initialisms uniform (`URL`/`url`); packages one lowercase word |
| **Rust** | C++ | `get_len()`, `UUID`, `SCREAMING` for locals | No `get_`; **`Uuid`** as one word; `SCREAMING_SNAKE_CASE` for consts and statics only |
| **C++** | C | A trailing `_` on every member | **Class** members take the trailing `_`; **struct** members do not. Constants are `kName`, functions `UpperCamelCase` |
| **Objective-C** | C++ | Trailing-underscore instance variables | **Leading** `_ivar`. C functions are `UpperCamelCase`, methods `lowerCamelCase`, classes take a 3+ character prefix |
| **Swift** | Objective-C | `NSFoo` class prefixes, `kConstant` | Modules namespace types — no prefixes. `lowerCamelCase` constants. Capability protocols end `-able`/`-ible`/`-ing` |
| **Ruby** | Python | `is_empty()`, `delete_all_destructive()` | **`empty?`** for predicates, **`!`** for the dangerous variant of a safe method |
| **Elixir** | Ruby | `empty?` for every boolean | `?` for booleans, **but `is_` for anything usable in a guard** — the Erlang rule, not the Ruby one |
| **Julia** | Python | `is_equal`, `has_key` | **Squashed lowercase**: `isequal`, `haskey`. Mutating functions end `!`. Underscores only join concepts |
| **R** | Python, S | `myVar`, or `my.var` from base R | **`snake_case`**; `.` is reserved for the S3 object system |
| **PHP** | Java, C | `snake_case` methods | **`camelCase` methods**, `StudlyCaps` classes. Property casing is deliberately unspecified — match the file |
| **GDScript** | Python | 4 spaces, `snake_case` classes, PEP 8 continuation | **Tabs.** `PascalCase` classes, `CONSTANT_CASE` constants and enum members, continuation at **2 indent levels** |
| **Luau** | Lua | 2-space indents and `snake_case` locals | **Tabs.** `camelCase` locals, `PascalCase` for classes and Roblox APIs, `LOUD_SNAKE_CASE` local constants |
| **Haskell** | Python | Tabs are fine if consistent | The dominant community guide calls tabs *"illegal"* and uses 4 spaces with `where` at 2. The language itself only fixes tab stops at 8 — so this is a **community** convention, held at LOW, not a rule from Haskell's creators |
| **YAML** | Python | Indentation is indentation, so tabs are fine | **A tab in indentation is invalid** — the spec forbids it for portability |
| **Makefile** | Shell | Indent the recipe with spaces | **A literal tab is required.** Spaces give `missing separator` |
| **Shell** | C, Java | `CamelCase` function names | `snake_case`, `::` between library and function; constants and exported variables `UPPER_SNAKE_CASE` |
| **SQL** | Application code | `tbl_users`, `spGetUser`, `usersTable` | No `tbl_`/`sp_` prefixes, no Hungarian. Tables collective, **columns singular**, keywords uppercase |
| **GraphQL** | REST JSON | `snake_case` fields, `getUser` queries | `camelCase` fields, `PascalCase` types, `SCREAMING_SNAKE_CASE` enum values. Only mutations lead with a verb |
| **Terraform** | Ruby, JSON | `resource "aws_instance" "web_aws_instance"` | **Never repeat the resource type in its name** — the address already carries it |
| **CSS** | JavaScript | `userProfile` class names | Lowercase, **hyphen-separated**: `user-profile`. Never concatenate with anything but a hyphen |
| **Shell scripts authored on Windows** | The editor's default | CRLF, because that is how the OS saves a text file | The shebang absorbs the `\r` and the script will not run. Pin it: `*.sh text eol=lf` in `.gitattributes` |

## Unlisted Languages

Apply, in order: the project's formatter configuration; the language's own published style
guide, taken from that language's own documentation; and the universal core in
`review-checklist.md` section 4.

Do **not** infer a convention from a language this one resembles — that is precisely the
trap above. If the language publishes no convention, say so rather than inventing one, and
review the diff for *internal consistency* instead: one casing scheme per identifier kind,
one indent character per file. Say in your summary that the convention was **derived, not
looked up**, so the next reader knows which it was.

## Sources

[PEP 8](https://peps.python.org/pep-0008/) ·
[Google Java](https://google.github.io/styleguide/javaguide.html) ·
[Google JavaScript](https://google.github.io/styleguide/jsguide.html) ·
[Google TypeScript](https://google.github.io/styleguide/tsguide.html) ·
[Google C++](https://google.github.io/styleguide/cppguide.html) ·
[Google Objective-C](https://google.github.io/styleguide/objcguide.html) ·
[Google Swift](https://google.github.io/swift/) ·
[Google Shell](https://google.github.io/styleguide/shellguide.html) ·
[Google HTML/CSS](https://google.github.io/styleguide/htmlcssguide.html) ·
[Google Go style decisions](https://google.github.io/styleguide/go/decisions) ·
[Effective Go](https://go.dev/doc/effective_go) ·
[Rust API guidelines — naming](https://rust-lang.github.io/api-guidelines/naming.html) ·
[Rust Style Guide](https://doc.rust-lang.org/nightly/style-guide/) ·
[Kotlin coding conventions](https://kotlinlang.org/docs/coding-conventions.html) ·
[Scala naming conventions](https://docs.scala-lang.org/style/naming-conventions.html) ·
[Scala indentation](https://docs.scala-lang.org/style/indentation.html) ·
[.NET capitalization conventions](https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/capitalization-conventions) ·
[dotnet/runtime C# coding style](https://github.com/dotnet/runtime/blob/main/docs/coding-guidelines/coding-style.md) ·
[Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) ·
[Effective Dart — style](https://dart.dev/effective-dart/style) ·
[Ruby style guide](https://rubystyle.guide/) ·
[PSR-1](https://www.php-fig.org/psr/psr-1/) ·
[PSR-12](https://www.php-fig.org/psr/psr-12/) ·
[Elixir naming conventions](https://elixir.hexdocs.pm/naming-conventions.html) ·
[Haskell style guide (Tibell)](https://github.com/tibbe/haskell-style-guide/blob/master/haskell-style.md) ·
[Julia style guide](https://docs.julialang.org/en/v1/manual/style-guide/) ·
[Julia documentation — line width](https://docs.julialang.org/en/v1/manual/documentation/) ·
[Elixir `Code.format_string!/2` — `:line_length`](https://hexdocs.pm/elixir/Code.html#format_string!/2) ·
[scalafmt configuration — `maxColumn`](https://scalameta.org/scalafmt/docs/configuration.html) ·
[tidyverse style guide](https://style.tidyverse.org/syntax.html) ·
[PowerShell development guidelines](https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/strongly-encouraged-development-guidelines) ·
[Roblox Lua style guide](https://roblox.github.io/lua-style-guide/) ·
[GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html) ·
[Linux kernel coding style](https://www.kernel.org/doc/html/latest/process/coding-style.html) ·
[SQL style guide](https://www.sqlstyle.guide/) ·
[Terraform style guide](https://developer.hashicorp.com/terraform/language/style) ·
[Apollo GraphQL schema naming conventions](https://www.apollographql.com/docs/graphos/schema-design/guides/naming-conventions) ·
[YAML 1.2.2 — indentation spaces](https://yaml.org/spec/1.2.2/) ·
[GNU make — rule introduction](https://www.gnu.org/software/make/manual/html_node/Rule-Introduction.html) ·
[CWE-483 Incorrect Block Delimitation](https://cwe.mitre.org/data/definitions/483.html) ·
[gitattributes — `text`, `eol`, `working-tree-encoding`](https://git-scm.com/docs/gitattributes) ·
[EditorConfig specification](https://spec.editorconfig.org/) ·
[POSIX.1 base definitions — line, incomplete line, newline](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap03.html)
