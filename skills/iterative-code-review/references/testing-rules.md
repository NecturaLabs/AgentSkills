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
The ONLY reasons to modify tests: (1) requirements changed, (2) bug found, (3) test had a bug.

## Mocking Rules

### Don't Mock What You Don't Own
Wrap external APIs in your own adapter. Mock the adapter, not the library.

### Don't Over-Mock
If more mock setup than test logic, you're testing mocks, not code. Max 2-3 mocks per test.

### Mock Only External Out-of-Process Dependencies
Use real objects when fast and deterministic. Mock: external APIs, databases, file systems, clocks, random generators.

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
