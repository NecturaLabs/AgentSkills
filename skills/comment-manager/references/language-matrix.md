# Language Matrix

Per-language deltas only. Everything in `comment-rules.md` still binds; nothing here
overrides it.

## Resolution Order

1. **The project's own configuration.** `.editorconfig`, `rustfmt.toml`, `.prettierrc`,
   `checkstyle.xml`, `ruff.toml`, `.clang-format`, `scalafmt.conf`, `.golangci.yml`.
   If it sets a width or a doc-comment rule, it wins.
2. **A framework, engine or studio coding standard the project follows.** Epic's C++
   standard for Unreal, a studio's GDScript guide, an in-house Java style. These rank with
   the project's own configuration and above this matrix, because they are what the code is
   actually held to. Epic's is the worked example: *"Code documents the implementation while
   comments document the intent"*, and its parameter comments carry units, expected ranges,
   impossible values and error-code meanings.
3. **This matrix.**
4. **The universal core.**

Never reformat a comment that the project's formatter owns. If `rustfmt` has
`wrap_comments = false`, do not hand-wrap its comments.

Where a row says **(house)** the language publishes no rule and the value is our default,
not a citation. Everything else is quoted from the language's own guide.

## Syntax and Width

| Language | Comment prose width | Line | Block | Doc marker | Doc tool |
|---|---|---|---|---|---|
| Python | **72** — PEP 8, even where code is allowed 99 | `#` | — | `"""..."""` | Sphinx, pydoc |
| JavaScript | 80 (Google JS) / 100 (Airbnb) | `//` | `/* */` | `/** */` | JSDoc |
| TypeScript | 80 (Google TS) | `//` | — | `/** */` | TSDoc, JSDoc |
| Java | 100 (Google Java) | `//` | `/* */` | `/** */` | Javadoc |
| Kotlin | project; else 120 (house) | `//` | `/* */` | `/** */` | Dokka |
| Scala | 80 (scalafmt `maxColumn` default) | `//` | `/* */` | `/** */` | Scaladoc |
| C# | project `.editorconfig`; else 100 (house) | `//` | `/* */` | `///` XML | DocFX, IntelliSense |
| Go | none — *"no rigid line length limit"*, break on semantics | `//` | `/* */` | `//` before the declaration | `go doc`, pkgsite |
| Rust | 80 (`comment_width`) while code is 100 | `//` | `/* */` | `///`, `//!` | rustdoc |
| C | 80 (Linux kernel, preferred) | `//` | `/* */`, kernel star style | project | kernel-doc, Doxygen |
| C++ | 80 (Google C++) | `//`, *"much more common"* | `/* */` | `//` or `/** */` | Doxygen |
| Objective-C | 100 (Google Obj-C) | `//` | `/* */` | `/** */` or `///` | Xcode, Doxygen |
| Swift | 100 (Google Swift) | `//` | `/* */` for code only | `///` **only** | DocC |
| Dart | 80 (`dart format` default) | `//` | `/* */` for code only | `///` **only** | `dart doc` |
| Ruby | 80 (Ruby style guide) | `# ` | `=begin`/`=end` (rare) | `#`, YARD `##` | RDoc, YARD |
| PHP | 80 SHOULD, 120 soft limit (PSR-12) | `//`, `#` | `/* */` | `/** */` | phpDocumentor |
| Elixir | 98 (`mix format` default) | `#` | — | `@moduledoc`, `@doc`, `@typedoc` | ExDoc |
| Haskell | project; else 80 (house) | `--` | `{- -}` | `-- \|`, `-- ^`, `{-\| -}` | Haddock |
| Julia | **92** (Julia manual) | `#` | `#= =#` | `"""..."""` above the object | Documenter.jl |
| R | 80 (tidyverse) | `# ` | — | `#'` | roxygen2 |
| Shell, Bash | 80 (Google Shell) | `#` | — | `#` header block | — |
| PowerShell | project; else 100 (house) | `#` | `<# #>` | `<# .SYNOPSIS ... #>` | `Get-Help` |
| Lua, Luau | **80 for comments** while code is 100 (Roblox) | `--` | `--[[ ]]` | `--[[ ]]` header, LDoc | LDoc |
| GDScript | 100, *"try to keep lines under 80"* (Godot) | `# ` | — | `## ` | Godot editor help |
| SQL | 80 (house) | `--`, must end at a newline | `/* */`, preferred | — | — |
| HTML | none stated (Google HTML/CSS) | — | `<!-- -->` | — | — |
| CSS, SCSS | 80 (house) | `//` in SCSS only | `/* */` | — | — |
| YAML | 80 (house) | `#`, must be preceded by whitespace | — | — | — |
| TOML | 80 (house) | `#` | — | — | — |
| **JSON** | — | **none exists** (RFC 8259) | **none exists** | — | — |
| XML | 80 (house) | — | `<!-- -->` | — | — |
| Terraform, HCL | 80 (house) | `#` only | `#` repeated | `description` arguments | terraform-docs |
| GraphQL | 80 (house) | `#`, dropped by the type system | — | `"""..."""` descriptions | introspection |
| Dockerfile | 80 (house) | `#` | — | — | — |
| Makefile | 80 (house) | `#` | — | — | — |

## Summary Form, Contract and Annotations

| Language | Summary form | Contract sections | Annotation | Prohibitions |
|---|---|---|---|---|
| Python | **Imperative**: *"Return the pathname"*, never *"Returns the…"* (PEP 257) | `Args:`, `Returns:`/`Yields:`, `Raises:` | `# TODO: <bug or link> - <action>` | Never restate the signature; summary is one physical line |
| JavaScript | Third-person verb phrase | `@param`, `@returns`, `@throws` | `// TODO:`, `// FIXME:` | No asterisk boxes; comment on its own line above, blank line before |
| TypeScript | Third-person verb phrase | prose; types come from the type system | `// TODO:` | **Never restate a type in JSDoc**; `@override`, `@implements`, `@private` are forbidden |
| Java | **Fragment, not a sentence**: *"Returns the customer ID"*, never *"This method returns…"* | `@param` → `@return` → `@throws` → `@deprecated`, never empty | `// TODO(<id>):` | Required on all visible classes and members; omit for simple obvious members and overrides |
| Kotlin | Prose sentence; *"Returns…"* is fine | **Prose, with `[name]` links** | `// TODO:` | **Avoid `@param` and `@return`**; use them only when prose cannot carry it |
| Scala | *"Returns XXX"* for methods; for classes omit *"This class does XXX"* | `@param`, `@tparam`, `@return`, `@throws` | `// TODO:` | Don't repeat a one-line description in `@return`; asterisks align on column two |
| C# | Complete sentence ending in a full stop | `<summary>` minimum, `<param>`, `<returns>`, `<exception cref>`, `<remarks>` | `// TODO:` | Use `<inheritdoc/>` rather than copying a base member's docs |
| Go | **Full sentence beginning with the item's name**: *"Encode writes…"*; *"Package x …"*; *"reports whether"* for bools | none exist — prose only | `// TODO(<user>):` | **No tags at all**; a doc comment must not describe internals; gofmt does not rewrap |
| Rust | One concise sentence | `# Examples`, `# Panics`, `# Errors`, `# Safety` | `// TODO:`, `// SAFETY:` | `# Safety` is mandatory on `unsafe fn`; examples use `?`, not `unwrap` |
| C | Descriptive | Function-head comment stating purpose and rationale | `/* TODO: */` | Minimise comments inside function bodies — heavy in-body commentary means split the function |
| C++ | **Descriptive with implied subject**: *"Opens the file"*, never *"Open the file"* | null-allowed, ownership, output-argument semantics, performance implications | `// TODO: bug 12345678 - <action>` | Declaration comment describes *use*; definition comment describes *operation* |
| Objective-C | Descriptive: *"Opens the file"* | thread and queue assumptions, sentinel values | `// TODO(<name>):` | Every non-trivial interface, public **and private**; end-of-line comments at least 2 spaces out |
| Swift | **Single-sentence fragment**, ends with a full stop, no *"This method…"* | `Parameter(s)` → `Returns` → `Throws`, in that order, never empty | `// TODO:` | **Block `/** */` is not permitted**; omit tags only when the summary fully covers them |
| Dart | Single-sentence summary in its own paragraph; third-person verb for functions; noun phrase for properties; **"Whether"** for bools | **Prose with `[brackets]`** | `// TODO(<user>):` | Params, returns and exceptions go in prose, not tags; never document both getter and setter; doc goes above metadata annotations |
| Ruby | Prose | YARD tags where YARD is in use | `# TODO:`, `# FIXME:`, `# OPTIMIZE:`, `# HACK:`, `# REVIEW:` on the line above | **Avoid end-of-line annotations** |
| PHP | Prose | `@param`, `@return`, `@throws` | `// TODO:` | A closing brace must not be followed by a comment on the same line; `// no break` marks intentional fall-through |
| Elixir | First paragraph concise, typically one line | `## Examples` (run as doctests), sections start at `##` | `# TODO:` | **`@doc` is the public contract, `#` is for source readers**; private functions get comments, never `@doc` |
| Haskell | First paragraph is the summary | module header fields, in order | `-- TODO:` | `-- \|` documents what follows, `-- ^` what precedes — do not mix them up |
| Julia | **Imperative**: *"Return that"*, not third person | signature indented 4 spaces first, then summary, then `# Examples` as `jldoctest` | `# TODO:` | Do not repeat the signature in prose; docstring sits above the object with no blank line |
| R | Prose | roxygen2 `@param`, `@return`, `@examples` | `# TODO:` | Record findings and analysis decisions, not how the code works; more comments than code means it belongs in R Markdown |
| Shell, Bash | Descriptive | **`Globals:`, `Arguments:`, `Outputs:`, `Returns:`** | `# TODO(<name>): <action> (bug ####)` | File header describes the file's contents; all library functions need a header |
| PowerShell | `.SYNOPSIS` is one brief description, once per topic | `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER <name>`, `.EXAMPLE`, `.INPUTS`, `.OUTPUTS`, `.NOTES`, `.LINK` | `# TODO:` | The help block must be contiguous, and in one of the three legal positions only |
| Lua, Luau | Why-focused | LDoc tags where LDoc is in use | `-- TODO:` | Multi-line means several single-line comments, not a block; blocks are for file and function headers |
| GDScript | Brief description, blank line, then detail | `@tutorial:`, `@deprecated`, `@experimental`; refs `[param x]`, `[method C.m]`, `[member C.f]`, `[br]` | `# TODO:` | `#` and `##` take a space; **commented-out code does not**; `#region`/`#endregion` take no space; prefer own-line over inline |
| SQL | Why-focused | — | `-- TODO:` | A `--` comment runs to end of line and must be terminated by a newline |
| HTML | Why-focused | — | `<!-- TODO: action item -->` | `TODO` only, never `@@`; a comment body cannot contain `--` |
| CSS, SCSS | Why-focused | — | `/* TODO: */` | Section comments group blocks and are separated by a blank line; `//` in SCSS is stripped from output, `/* */` survives |
| YAML | Why-focused | — | `# TODO:` | Comments are presentation only and must never be load-bearing; they cannot appear inside a scalar |
| TOML | Why-focused | — | `# TODO:` | A parser must not act on comment content |
| **JSON** | — | — | — | **Never emit a comment — the format has none.** Put the note in a sibling document or a JSON Schema `description`. JSONC or JSON5 only where the toolchain explicitly supports it |
| XML | Why-focused | — | `<!-- TODO: -->` | A comment body cannot contain `--` |
| Terraform, HCL | Why-focused | **`description` on every variable and every output**; `type` on every variable | `# TODO:` | `//` and `/* */` are explicitly non-idiomatic; comment only where a meta-argument's effect is not obvious |
| GraphQL | One-sentence description | `"""` descriptions on types and fields | `# TODO:` | **`#` comments are dropped by the type system** and never reach consumers — document with descriptions |
| Dockerfile | Why-focused | — | `# TODO:` | A `#` line at the very top may be parsed as a parser directive (`# syntax=`) — never put prose there |
| Makefile | Why-focused | — | `# TODO:` | A `#` inside a recipe line is passed to the shell, not stripped by make |

## Doc Comment Required On

The standing exception in `comment-rules.md` is "public API surface, where the language's
own guide requires a doc comment". This table is what that means per language. Without it
the exception is unusable, and the admission gate silently swallows API surface that its
own language mandates be documented.

Under-documenting is a defect in the same way over-commenting is. The gate suppresses noise;
it does not repeal these.

| Language | Required on |
|---|---|
| Python | All public modules, functions, classes and methods |
| JavaScript | Exported symbols; classes, methods and properties |
| TypeScript | **All top-level exports** |
| Java | All visible classes, members and record components |
| Kotlin | Public API |
| Scala | All packages, classes, traits, methods and other members |
| C# | All publicly visible types and their public members, `<summary>` at minimum |
| Go | **Every exported (capitalized) name**, plus non-trivial unexported declarations |
| Rust | Every public item — *"If an item is public then it should be documented"* |
| C | Any function whose purpose is not obvious, at the function head |
| C++ | Almost every function declaration; private methods and `.cc` functions are not exempt |
| Objective-C | Every non-trivial interface, **public and private** |
| Swift | Every open or public declaration, and every open or public member of one |
| Dart | Most public libraries, top-level variables, types and members |
| Ruby | Public API |
| PHP | Public API |
| Elixir | Every module via `@moduledoc` and every public function via `@doc` — **never** a private function |
| Haskell | Exported items |
| Julia | Exported functions and types |
| R | Every exported function |
| Shell, Bash | **All library functions**, and any function not both obvious and short |
| PowerShell | Every exported function and every script |
| Lua, Luau | File headers, and headers on functions and objects |
| GDScript | Public members; underscore-prefixed members are excluded unless documented deliberately |
| Terraform, HCL | A `description` on **every** variable and **every** output |
| GraphQL | Descriptions on public types and fields |

**The carve-outs still apply** — they are part of the same guides, not an escape from them:
simple obvious accessors (Java), overrides and protocol conformances (Swift, C++, Java),
self-evident enum cases (Swift), trivial destructors (C++). And a required doc comment is
never a licence to restate the signature in prose.

## Derived-Language Traps

**Rule 4 in operational form.** A language that borrows another's syntax almost never
borrows its documentation conventions. Reaching for the ancestor's habit is the single most
common way to get a derived language's comments wrong. Check the row before you type.

| Language | Reads like | The wrong instinct | What its creators actually specify |
|---|---|---|---|
| **GDScript** | Python | A `"""docstring"""` inside the body, PEP 257 mood | `##` doc comments **above** the member. `#`/`##` take a space. Tags are `@tutorial:`, `@deprecated`, `@experimental`. Cross-references are BBCode: `[param x]`, `[method C.m]`, `[br]`. `#region` takes no space |
| **TypeScript** | JavaScript, Java | `@param {string} name` type annotations in JSDoc | Types live in the type system; restating them in JSDoc is banned. `@override`, `@implements` and `@private` are forbidden outright |
| **Luau** | Lua | Lua's freeform `--[[ ]]` everywhere | `--` for inline notes, several single-line comments for multi-line prose, `--[[ ]]` reserved for file and function headers. Comments wrap at 80 while code runs to 100 |
| **Kotlin** | Java | Javadoc `@param`/`@return` on everything | KDoc **avoids** both; the description goes in prose with `[name]` links, and tags appear only when prose genuinely cannot carry it |
| **C#** | Java | `/** */` blocks with `@param` | `///` XML doc: `<summary>`, `<param name="">`, `<returns>`, `<exception cref="">`. `<inheritdoc/>` instead of copy-paste |
| **Scala** | Java | Javadoc asterisks in column one, *"This method returns…"* | Scaladoc asterisks align on column two, text on column five. *"Returns XXX"* for methods; drop *"This class does XXX"* |
| **Swift** | Objective-C, Java | `/** */` Javadoc-style doc blocks | `///` **only** — block doc comments are not permitted. Summary is a single sentence **fragment**. `Parameter(s)` → `Returns` → `Throws`, in that order |
| **Dart** | Java, JavaScript | `/** */` blocks and `@param` tags | `///` **only**. Parameters, returns and exceptions go in **prose** with `[brackets]`, never tags. Doc comment sits **above** metadata annotations |
| **Go** | C | C-style `/* */` blocks and tag-based docs | `//` line comments are the norm. The doc comment **begins with the item's name**. No tags exist. Bools use *"reports whether"*. gofmt does not rewrap |
| **Rust** | C++ | `/** */`, or `//!` used for the next item | `///` documents what follows, `//!` documents the enclosing item. Sections are `# Examples`, `# Panics`, `# Errors`, `# Safety` |
| **Objective-C** | C | Plain C block comments on interfaces | Doxygen-style so Xcode parses it. **Descriptive**, not imperative. Document thread and queue assumptions and sentinel values |
| **C++** | C | Kernel-style `/* */` everywhere | `//` is *"much more common"*. Declaration comment describes **use**; definition comment describes **operation** |
| **PHP** | C, Java | Bare `/* */` and Javadoc habits | PHPDoc `/** */` for docs, `//` or `#` for line comments. A closing brace must not carry a trailing comment |
| **Elixir** | Erlang, Ruby | `#` comments as the documentation | `@moduledoc`/`@doc`/`@typedoc` are the **contract**; `#` is for source readers only. Private functions get comments, **never `@doc`** |
| **Julia** | Python, MATLAB | Python-style docstring **inside** the function | `"""..."""` goes **above** the object with no blank line, signature indented 4 spaces first. Mood is **imperative** |
| **R** | S, Python | `#` prose treated as the documentation | `#'` roxygen2 blocks generate the docs; plain `#` is for source notes only |
| **PowerShell** | Bash, Perl | A `#` prose header above the function | `<# .SYNOPSIS ... #>` comment-based help with dotted keywords, contiguous, in one of three legal positions |
| **Terraform, HCL** | JSON, Ruby | `//` and `/* */` | `#` only; the others are explicitly non-idiomatic. Documentation is the `description` argument, not a comment |
| **GraphQL** | JavaScript, JSON | `#` comments as documentation | `"""` descriptions are the documentation. `#` comments are dropped and never reach consumers |
| **JSON** | JavaScript | `//` or `/* */`, because JavaScript allows them | **JSON has no comment syntax at all.** Emitting one produces a parse error |
| **SCSS** | CSS | `/* */` for everything | `//` is stripped from the compiled output, `/* */` survives into it. Pick by whether the reader of the CSS should see it |
| **Java** | C++ | C++ `//`-style docs on members | Javadoc `/** */`, summary is a **fragment**, at-clauses ordered `@param` → `@return` → `@throws` → `@deprecated` |

## Unlisted Languages

Apply, in order: the project's formatter configuration; failing that, 80 columns for
comment prose; the language's canonical doc-comment syntax and its doc generator, taken
from that language's own documentation; and the universal core unchanged.

**The doc-required surface for an unlisted language.** The standing exception in
`comment-rules.md` says to read the surface off the table rather than reason about it. That
instruction is unfollowable when there is no row, so it has a branch, and the branch is not
"write nothing":

1. Take the surface from that language's own published guide, the same way every row above
   was derived — most languages state what must be documented even when they state no width.
2. Where the language publishes nothing, document what its ecosystem's doc generator
   consumes: whatever appears in generated API documentation is the public surface.
3. Say in your summary that the surface was **derived, not looked up**, so the next reader
   knows which it was.

Falling through to "no row, therefore no obligation" reproduces the failure this table was
added to fix: an agent reasoned that TypeScript had no blanket doc rule and documented
nothing. Under-documenting is a defect in the same way over-commenting is, and an absent
row is not a licence.

Do not infer a convention from a language this one resembles — that is exactly the trap
above. If the language publishes no convention, say so rather than inventing one, and fall
back to the universal core.

## Sources

Widths and rules above are quoted from:
[PEP 8](https://peps.python.org/pep-0008/) ·
[PEP 257](https://peps.python.org/pep-0257/) ·
[Google Python](https://google.github.io/styleguide/pyguide.html) ·
[Google JavaScript](https://google.github.io/styleguide/jsguide.html) ·
[Google TypeScript](https://google.github.io/styleguide/tsguide.html) ·
[Google Java](https://google.github.io/styleguide/javaguide.html) ·
[Google C++](https://google.github.io/styleguide/cppguide.html) ·
[Google Objective-C](https://google.github.io/styleguide/objcguide.html) ·
[Google Swift](https://google.github.io/swift/) ·
[Google Shell](https://google.github.io/styleguide/shellguide.html) ·
[Google HTML/CSS](https://google.github.io/styleguide/htmlcssguide.html) ·
[Oracle Javadoc guide](https://www.oracle.com/technical-resources/articles/java/javadoc-tool.html) ·
[Kotlin coding conventions](https://kotlinlang.org/docs/coding-conventions.html) ·
[Scaladoc style](https://docs.scala-lang.org/style/scaladoc.html) ·
[Microsoft XML doc tags](https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/xmldoc/recommended-tags) ·
[PowerShell comment-based help](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_comment_based_help) ·
[Go Doc Comments](https://go.dev/doc/comment) ·
[Go Code Review Comments](https://go.dev/wiki/CodeReviewComments) ·
[Rust API guidelines](https://rust-lang.github.io/api-guidelines/documentation.html) ·
[rustdoc](https://doc.rust-lang.org/rustdoc/how-to-write-documentation.html) ·
[Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) ·
[Effective Dart](https://dart.dev/effective-dart/documentation) ·
[Ruby style guide](https://rubystyle.guide/) ·
[PSR-12](https://www.php-fig.org/psr/psr-12/) ·
[Elixir writing documentation](https://elixir.hexdocs.pm/writing-documentation.html) ·
[Haddock markup](https://haskell-haddock.readthedocs.io/latest/markup.html) ·
[Julia documentation](https://docs.julialang.org/en/v1/manual/documentation/) ·
[tidyverse style guide](https://style.tidyverse.org/syntax.html) ·
[Roblox Lua style guide](https://roblox.github.io/lua-style-guide/) ·
[GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html) ·
[GDScript documentation comments](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_documentation_comments.html) ·
[Epic C++ coding standard](https://dev.epicgames.com/documentation/en-us/unreal-engine/epic-cplusplus-coding-standard-for-unreal-engine) ·
[Terraform style guide](https://developer.hashicorp.com/terraform/language/style) ·
[SQL style guide](https://www.sqlstyle.guide/) ·
[Linux kernel coding style](https://www.kernel.org/doc/html/latest/process/coding-style.html) ·
[Airbnb JavaScript](https://github.com/airbnb/javascript) ·
[RFC 8259](https://www.rfc-editor.org/rfc/rfc8259.html) ·
[YAML 1.2.2](https://yaml.org/spec/1.2.2/) ·
[TOML](https://toml.io/en/v1.1.0)
