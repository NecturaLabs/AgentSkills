# Testing Rules

> Sources: Google SWE Book (Ch.12), Martin Fowler (Mocks Aren't Stubs, Test Pyramid), Kent Beck (Test Desiderata), Microsoft Best Practices, xUnit Test Patterns, Vladimir Khorikov, Kent C. Dodds

## What to Test

### Test YOUR Code, Not External Dependencies
- Test that YOUR code calls externals correctly — don't test the library itself
- Mock/stub external dependencies at YOUR code's boundary
- Wrap externals in adapters, test the adapter's consumers

### Don't Test Trivial Code
- No tests for: simple getters/setters, DTOs, auto-generated code, constructors without logic
- DO test: validation logic, conditional branches, calculations, error handling, state transitions

### Test at the Right Level
- Critical business logic (payments, auth): exhaustive behavioral coverage
- Core features: thorough testing
- Plumbing/config: test through integration or not at all

### Don't Assert on Human-Readable Copy
Rendered sentences, labels, error prose, formatted dates, currency strings, and whole serialized
documents change for reasons that are not defects. Assert roles, ids, `data-*` attributes, counts,
status codes, error types and codes, and state. When a specific string genuinely is the requirement,
assert the identifier the application renders it from — the message key, id, or code — never a
duplicated literal sentence.

## Test Structure

### Arrange-Act-Assert
Every test has exactly 3 phases, clearly separated. ONE act per test.

### One Behavior Per Test
If test name contains "and", split it. Each test verifies ONE logical behavior.

### DAMP Over DRY
Accept duplication in tests if it makes them self-evidently correct. Reader should never scroll away to understand the test.

## Test Quality (FIRST)

- **Fast**: Milliseconds for unit tests
- **Independent**: No shared mutable state, no ordering dependencies
- **Repeatable**: Same result any time, any order, any environment
- **Self-validating**: Boolean pass/fail, no human interpretation
- **Timely**: Written close to the production code

## Behavior, Not Implementation

### Test Public APIs
Never break encapsulation to test private methods. If a private method needs testing, extract it to its own class.

### Test State Over Interactions
Prefer verifying RESULTS over verifying method calls. Mock interactions only when the interaction IS the behavior.

### Resilient to Refactoring
The ONLY reasons to modify an existing test: (1) the requirement changed, (2) the test
itself had a bug. A *product* bug gets a new regression test, never an edit to an existing test —
editing one to accommodate a fix destroys the evidence that the fix was needed.

## Mocking Rules

### Don't Mock What You Don't Own
Wrap external APIs in your own adapter. Mock the adapter, not the library.

### Don't Over-Mock
If more mock setup than test logic, you're testing mocks, not code. Max 2-3 mocks per test.

### Mock Only External Out-of-Process Dependencies
Use real objects when fast and deterministic. Mock: external APIs, databases, file systems, clocks, random generators.

## Proving a Test Works

### Every New Test Must Be Observed Failing
A test that has never been seen red is not yet a test. For a bug fix, the regression test is written
first and watched failing against the unfixed code. For code that already works, break the line the
test claims to cover, confirm the failure, then restore. Flag any new test whose author cannot say
how they saw it fail.

### Never Weaken a Test to Get Green
Flag any diff that relaxes an assertion, widens a tolerance, adds a `skip`/`only`/`xfail` marker, or
deletes a test — unless the author states which legitimate case applies: the behavior no longer
exists, the test duplicates another at the same level, the test was itself defective with no
salvageable assertion, or the behavior moved to a cheaper level and that replacement was written and
observed failing first. A failing test means the code is wrong or the requirement changed; neither is
repaired by editing the assertion to match the output.

### Never Encode a Known Bug as Expected Behavior
If writing a test reveals a defect, the defect gets fixed. A passing test that asserts the buggy
output pins the bug in place and guards it against repair — worse than no test at all.

## Anti-Patterns to Flag

| Anti-Pattern | Description |
|-------------|-------------|
| **Tautological Test** | Uses same logic as production code for expected values |
| **The Liar** | Test that always passes regardless of correctness |
| **No Logic in Tests** | Loops, conditionals, string concatenation in tests = bugs |
| **Fragile Test** | Breaks on refactoring that doesn't change behavior |
| **The Inspector** | Uses reflection to access private state |
| **Excessive Setup** | Hundreds of lines of setup = too many dependencies |
| **Line Hitter** | Executes code without asserting results |
| **Generous Leftovers** | Tests depend on state from previous tests |
| **Free Ride** | New assertions added to existing tests instead of new tests |
| **Flaky Test** | Non-deterministic — worse than no test |
| **Assertion Roulette** | Multiple assertions without descriptive messages |
| **Mystery Guest** | External files/resources not visible in test code |

## Reuse Existing Logic

- **Use existing test helpers, builders, factories** from the codebase — never fabricate parallel implementations
- **Use existing assertion matchers** — don't write raw assertions when project has rich matchers
- **Use parameterized tests** when framework supports them — don't write loops

## Test Naming

Names must describe: what is tested, conditions, expected outcome.
```
MethodName_Scenario_ExpectedBehavior
Should_ExpectedBehavior_When_Condition
```
Never: `test1`, `test2`, `testStuff`.

## Coverage Philosophy

Coverage is a diagnostic, not a goal. High coverage with no meaningful assertions is worthless (Line Hitter anti-pattern). Mutation testing is a better quality measure.

## Production Bug Response

Every production bug gets a failing test BEFORE the fix. Proves the fix works and prevents regression.
