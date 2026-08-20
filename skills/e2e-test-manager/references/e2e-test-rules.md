# E2E Test Authoring Rules

## Contents

- [Choosing what belongs at this level](#choosing-what-belongs-at-this-level)
- [Locators](#locators)
- [Assertions and waiting](#assertions-and-waiting)
- [State, authentication, and data](#state-authentication-and-data)
- [Isolation and cleanup](#isolation-and-cleanup)
- [Third-party dependencies](#third-party-dependencies)
- [Structure and page objects](#structure-and-page-objects)
- [Flake control](#flake-control)
- [Running in CI](#running-in-ci)
- [Sources](#sources)

## Choosing what belongs at this level

Google's argument against E2E-heavy suites is diagnostic, not ideological: when a broad test fails,
the defect could be anywhere in the system, so every failure costs an investigation. Combined with
slow execution and environment fragility, that pushes the recommended mix to roughly 70% unit, 20%
integration, 10% end-to-end — "the exact mix will be different for each team, but in general, it
should retain that pyramid shape".

Admit a journey to this level when both hold:

1. It is critical — signup, login, checkout, publish, the one flow whose breakage is an incident.
2. No lower level can observe it, because what is under test is the wiring: routing, session,
   build output, server rendering, real navigation.

Everything else goes down a level. A journey test may pass through a form with fifteen validation
rules; it asserts that one valid path works, and the fifteen rules are unit tests.

Split at the seams. Google's guidance for larger tests is that when the backend exposes a public
API, it is often easier to split the tests at the UI/API boundary and drive the end-to-end tests
through that API — UI tests are "notoriously unreliable and costly". In practice that means testing
the frontend against a controlled backend double and the backend through its API, rather than
combining both into one slow, unreliable test.

## Locators

Priority order:

1. **Role plus accessible name** — `getByRole('button', { name: 'Submit' })`. This is how assistive
   technology and users find the control, and it survives styling changes. Playwright's stated
   rationale: "Your DOM can easily change so having your tests depend on your DOM structure can lead
   to failing tests."
2. **A dedicated test attribute** — `data-testid`, `data-cy`. Cypress recommends these precisely
   because such an attribute does not change when CSS styling or JS behavior changes, and warns
   against targeting by `id`, `class`, `tag`, or text content. Use one wherever the accessible name
   is volatile marketing copy.
3. **Never** CSS class chains, `nth-child`, XPath, or a full sentence of copy.

Chain and filter locators to scope a search to a region — find the row, then the button inside it —
rather than writing one long brittle selector.

On the tension between "query the way a user does" and "do not assert on copy": locating by role and
accessible name is user-centric and stable, because the accessible name is part of the interface
contract. Asserting that a paragraph contains a particular marketing sentence is not. Locate by role;
assert on identity, state, count, and URL.

## Assertions and waiting

- **Use web-first assertions that retry.** `expect(locator).toBeVisible()` polls until the condition
  holds or the timeout expires. A bare boolean read the instant after an action is a race.
- **Never use a bare duration.** `waitForTimeout`, `cy.wait(3000)`, and `Thread.sleep` are the
  single largest source of flake, and they are copied by everyone who reads the file afterwards.
  Wait on a network alias, a request completion, an element state, or an application event.
- **Assert at each meaningful checkpoint of the journey.** This is not the unit-test rule of one
  assertion per test: at this level setup is the expensive part, so batching assertions in one
  journey is correct. Cypress gives two reasons: resetting tests is far slower than adding
  assertions, and nearly every command carries an implicit assertion anyway, so withholding explicit
  ones saves nothing.
- **Prefer soft assertions** where the runner offers them and the remaining steps still make sense,
  so one run reports every failure rather than only the first.

## State, authentication, and data

- **Log in programmatically.** Drive the login form exactly once, in the test that covers login.
  Everywhere else, authenticate through the API or a session helper and reuse the stored state.
  Cypress states it directly: programmatically log in via `cy.request()` or a task, then cache with
  `cy.session()`. Playwright's equivalent is a saved `storageState` reused by later tests.
- **Create the data the test needs, through the API.** Never depend on a record that happens to
  exist in staging: someone else will edit it.
- **Key data uniquely per test** so parallel runs cannot collide.
- **Control the database state** for anything visual or order-dependent. Playwright's best practices
  call this out for visual comparison specifically, and it applies to any assertion on lists.

## Isolation and cleanup

- **A fresh browser context per test** — no shared cookies, local storage, or session. "Test
  isolation improves reproducibility, makes debugging easier and prevents cascading test failures."
- **No test may depend on a previous test.** Verify by running a single spec on its own; if it fails
  alone, the coupling is a defect.
- **Reset before, not after.** Cypress is explicit that a mid-test refresh means an `after` or
  `afterEach` cleanup function never gets called — put the reset in `before`/`beforeEach` so every
  test starts from a known state regardless of how the previous run ended.

## Third-party dependencies

- **Do not visit or drive sites you do not control.** You cannot control their content, their cookie
  banners, or their uptime, and their failure becomes your red build.
- **Mock external APIs at the network layer** in the browser context, or route them to a controlled
  double.
- **For third-party auth**, use a controlled tenant with a programmatic token exchange, or stub the
  OAuth exchange entirely. Never automate a social login UI.

## Structure and page objects

- Page objects are optional; the failure mode is an abstraction so deep the test no longer says what
  it does. If a test reads as a list of method calls with no visible expectations, it has gone too
  far.
- Keep the journey's meaningful values — the product chosen, the quantity, the plan — in the test
  body. Push only navigation mechanics into helpers. Relevant in, irrelevant out.
- Use the runner's fixture mechanism for setup that every test in a file needs, and keep it to
  mechanics, not to values the assertions depend on.

## Flake control

At this level a flaky test is worse than a missing one: it trains the team to re-run red builds.

- Remove every fixed delay first; most flakes die there.
- Make production timeouts configurable and shorten them for tests, rather than lengthening the
  test's patience.
- Prefer subscribing to an event or waiting on a request over polling the DOM where the app exposes
  one.
- Establish the flake rate by repeated runs before and after a fix — five consecutive clean runs
  minimum, more for anything previously flaky. Report the number.
- Retries in CI are a reporting tool, not a fix. If a retry is what makes the suite pass, the test
  is still broken.

## Running in CI

- Run on every change; the more often the suite runs, the sooner a break is attributable.
- Shard across machines to keep wall-clock time tolerable, and run the same browsers users use.
- Capture a trace (or video plus network log) on failure — a screenshot rarely explains a race.
- Keep the browser and runner versions current so a browser release does not become a mystery
  failure later.

## Sources

- Google Testing Blog, *Just Say No to More End-to-End Tests* — https://testing.googleblog.com/2015/04/just-say-no-to-more-end-to-end-tests.html
- *Software Engineering at Google*, ch. 14 *Larger Testing* — https://abseil.io/resources/swe-book/html/ch14.html
- Playwright, *Best Practices* — https://playwright.dev/docs/best-practices
- Playwright, authentication and storage state — https://playwright.dev/docs/auth
- Cypress, *Best Practices* — https://docs.cypress.io/app/core-concepts/best-practices
- Testing Library, guiding principles — https://testing-library.com/docs/guiding-principles
- Martin Fowler, *Eradicating Non-Determinism in Tests* — https://martinfowler.com/articles/nonDeterminism.html
- Martin Fowler, *TestPyramid* — https://martinfowler.com/bliki/TestPyramid.html
