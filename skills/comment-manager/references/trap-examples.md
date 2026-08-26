# Derived-Language Traps, in Code

One wrong-and-right pair for every row of the trap table in `language-matrix.md`.

Read this when the language you are commenting has a trap row. The table names the wrong
instinct; this shows it. **Wrong** is what gets produced by reasoning from the resembling
language. **Right** is what that language's own creators specify.

The universal core in `comment-rules.md` still binds every "right" example: each one carries
something the signature does not.

Labels live in the prose above each block, never inside the comment being demonstrated. A
label inside a doc comment becomes part of the rendered documentation, which would make
several of the "right" examples violate the rule they teach.

## GDScript — the Python instinct

**Wrong** — a PEP 257 docstring inside the body. Godot's doc tool never sees it.

```gdscript
func take_damage(amount):
    """Apply damage to the player."""
    health -= amount
```

**Right** — `##` above the member, BBCode references, one space after the marker.

```gdscript
## Reduces health by [param amount], clamped at zero. See [method heal].
func take_damage(amount: int) -> void:
    health = max(0, health - amount)
```

## TypeScript — the JavaScript and Java instinct

**Wrong** — JSDoc types restate what the type system already states.

```ts
/**
 * @param {string} userId The user id
 * @returns {Promise<User>} The user
 */
export async function loadUser(userId: string): Promise<User> {}
```

**Right** — the types carry themselves; the comment carries the failure mode.

```ts
/** Loads the account owner. Throws `NotFoundError` when no row matches. */
export async function loadUser(userId: string): Promise<User> {}
```

## Luau — the Lua instinct

**Wrong** — a free-form block for ordinary prose. Blocks are for file and function headers.

```lua
--[[
    Formats a duration as mm:ss.
    Durations above one hour are not representable.
]]
```

**Right** — several single-line comments for prose.

```lua
-- Formats a duration as mm:ss.
-- Durations above one hour are not representable; callers clamp first.
```

## Kotlin — the Java instinct

**Wrong** — Javadoc tags KDoc explicitly avoids.

```kotlin
/**
 * @param userId the user id
 * @return the user
 */
fun loadUser(userId: String): User
```

**Right** — prose with bracket links; tags only where prose cannot carry it.

```kotlin
/** Loads the account owner for [userId], or throws [NotFoundException]. */
fun loadUser(userId: String): User
```

## C# — the Java instinct

**Wrong** — a Javadoc block with at-tags. The XML doc tool ignores it.

```csharp
/**
 * @param userId the user id
 */
public User LoadUser(string userId);
```

**Right** — `///` XML doc, which IntelliSense and DocFX both consume.

```csharp
/// <summary>Loads the account owner.</summary>
/// <exception cref="NotFoundException">No account matches the id.</exception>
public User LoadUser(string userId);
```

## Scala — the Java instinct

**Wrong** — asterisks in column one, and "This method returns".

```scala
/**
* This method returns the total.
*/
```

**Right** — asterisks aligned on column two, "Returns XXX" form.

```scala
/** Returns the order total in minor units.
  *
  * @param lines priced order lines, already tax-adjusted
  * @return the total in minor units
  */
```

## Swift — the Objective-C and Java instinct

**Wrong** — block doc comments are not permitted in Swift.

```swift
/**
 Loads the account owner.
 - Parameter id: the id
 */
```

**Right** — `///` only, summary as a sentence fragment, tags in order.

```swift
/// Loads the account owner.
/// - Parameter id: Stable account identifier, never the display name.
/// - Throws: `StoreError.notFound` if no account matches.
```

## Dart — the Java and JavaScript instinct

**Wrong** — a block comment and at-tags. Neither is Dart's form.

```dart
/**
 * @param id the id
 */
User loadUser(String id) {}
```

**Right** — `///`, prose with bracket references, no tags.

```dart
/// Loads the account owner with [id].
///
/// Throws [StateError] if the store has already been closed.
User loadUser(String id) {}
```

## Go — the C instinct

**Wrong** — a C-style block, and tags Go has no concept of.

```go
/* Encode writes the value.
   @param w the writer */
func Encode(w io.Writer, v any) error
```

**Right** — line comments beginning with the item's own name.

```go
// Encode writes v to w in canonical form.
func Encode(w io.Writer, v any) error

// IsCanonical reports whether b is already in canonical form.
func IsCanonical(b []byte) bool
```

## Rust — the C++ instinct

**Wrong** — a block doc comment, and `//!` used for the next item rather than the
enclosing one.

```rust
/** Parses a frame header. */
//! Returns an error on a short buffer.
pub fn parse(buf: &[u8]) -> Result<Header, Error> { todo!() }
```

**Right** — `///` for what follows, with the published section headings.

```rust
/// Parses a frame header from the first 8 bytes of `buf`.
///
/// # Errors
/// Returns [`Error::Short`] when `buf` is under 8 bytes.
pub fn parse(buf: &[u8]) -> Result<Header, Error> { todo!() }
```

## Objective-C — the C instinct

**Wrong** — a plain C block. Xcode's Quick Help cannot parse it.

```objc
/* Opens the file. */
- (BOOL)openFile:(NSString *)path;
```

**Right** — Doxygen-style, descriptive, and it states the queue assumption.

```objc
/** Opens the file at @c path for reading. Main queue only.
 @return NO, populating @c error, if the path is unreadable.
 */
- (BOOL)openFile:(NSString *)path error:(NSError **)error;
```

## C++ — the C instinct

**Wrong** — kernel-style block, imperative mood.

```cpp
/* Open the file */
bool OpenFile(const std::string& path, File* out);
```

**Right** — `//` is much more common, the mood is descriptive, and the declaration
comment describes use rather than mechanism.

```cpp
// Opens the file for reading. `path` is borrowed, not retained.
// Returns false and leaves *out untouched if the path is unreadable.
bool OpenFile(const std::string& path, File* out);
```

## PHP — the C and Java instinct

**Wrong** — a bare block comment. phpDocumentor does not read it.

```php
/* Loads the user.
   @param string $id */
function loadUser(string $id): User {}
```

**Right** — PHPDoc, and the tag earns its place by naming the failure.

```php
/**
 * Loads the account owner.
 *
 * @throws NotFoundException when no row matches $id.
 */
function loadUser(string $id): User {}
```

## Elixir — the Erlang and Ruby instinct

**Wrong** — a `#` comment is for source readers. It is not the contract and never
reaches ExDoc.

```elixir
# Loads the user by id.
def load_user(id) do
```

**Right** — `@doc` is the public contract.

```elixir
@doc """
Loads the account owner by `id`.

Raises `Store.NotFound` if no row matches `id`.
"""
def load_user(id) do
```

## Julia — the Python and MATLAB instinct

**Wrong** — a docstring inside the function body.

```julia
function encode(buf, v)
    """Encode v into buf."""
```

**Right** — the docstring sits above the object with no blank line, signature indented
four spaces first, and the mood is imperative.

```julia
"""
    encode(buf, v)

Encode `v` into `buf`, returning the number of bytes written.
"""
function encode(buf, v)
```

## R — the S and Python instinct

**Wrong** — plain `#` prose is a source note. It generates no documentation.

```r
# x: predictors, y: response
fit_model <- function(x, y) {}
```

**Right** — roxygen2 blocks generate the help page.

```r
#' Fit the calibration model
#'
#' @param x Numeric matrix of predictors, one row per sample.
#' @return An object of class `calfit`.
fit_model <- function(x, y) {}
```

## PowerShell — the Bash and Perl instinct

**Wrong** — a prose header above the function. Get-Help finds nothing.

```powershell
# Gets the build log for a run.
function Get-BuildLog {
```

**Right** — comment-based help, contiguous, in a legal position.

```powershell
function Get-BuildLog {
    <#
    .SYNOPSIS
    Gets the build log for a run.
    .PARAMETER RunId
    Numeric run id as returned by Get-Build, not the display name.
    #>
```

## Terraform, HCL — the JSON and Ruby instinct

**Wrong** — `//` is explicitly non-idiomatic, and a comment is not documentation here.

```hcl
// Retention in days.
variable "retention_days" {
  type = number
}
```

**Right** — `description` is the documentation, and terraform-docs reads it.

```hcl
variable "retention_days" {
  type        = number
  description = "Days to retain logs before expiry. Audit requires 30+."
}
```

## GraphQL — the JavaScript and JSON instinct

**Wrong** — `#` comments are dropped by the type system and never reach a consumer.

```graphql
# The account that owns the order.
type Order {
  account: Account!
}
```

**Right** — a description survives introspection and reaches consumers.

```graphql
type Order {
  """The account charged, which is not always the recipient."""
  account: Account!
}
```

## JSON — the JavaScript instinct

**Wrong** — JSON has no comment syntax at all. A `//` line is a parse error, and a
`"//"` key is a comment smuggled in as data.

```json
{
  "//": "retention in days",
  "retentionDays": 30
}
```

**Right** — the file carries data only, and the note goes in a sibling document, here
the schema.

```json
{ "retentionDays": 30 }
```

```json
{
  "properties": {
    "retentionDays": {
      "description": "Days to retain logs before expiry. Audit requires 30+."
    }
  }
}
```

## SCSS — the CSS instinct

**Wrong** — a CSS-style block survives into the compiled output, so an internal note
ships to every browser that loads the stylesheet.

```scss
/* bumped for the Q3 redesign */
$gutter: 24px;
```

**Right** — `//` is stripped from the output, so the note stays internal.

```scss
// internal note, stripped from the compiled CSS
$gutter: 24px;
```

## Java — the C++ instinct

**Wrong** — a line comment, and a full sentence restating the name.

```java
// Returns the customer ID.
public String getCustomerId();
```

**Right** — Javadoc, summary as a fragment, at-clauses in order.

```java
/**
 * Returns the customer ID, or null for a guest checkout.
 *
 * @throws IllegalStateException if the order is not yet priced
 */
public String getCustomerId();
```
