# End-to-End Tests

A user driving the assembled system through its real interface. This level buys the highest fidelity
— proof the pieces are actually wired together — at the highest cost per test in runtime, flakiness,
and diagnosis. Keep the level small, and make what belongs here deterministic. Assertion discipline,
doubles, and determinism that apply everywhere are in `test-quality.md`.

## Contents

- [Admitting a journey to this level](#admitting-a-journey-to-this-level)
- [Locators](#locators)
- [Assertions and waiting](#assertions-and-waiting)
- [State, authentication, and data](#state-authentication-and-data)
- [Isolation and cleanup](#isolation-and-cleanup)
- [Third-party dependencies](#third-party-dependencies)
- [Flake control](#flake-control)
- [Sources](#sources)

## Admitting a journey to this level

Before writing an e2e test, prove it can't be a lower-level test — most of what looks like it needs
this level (validation rules, calculations, error mapping, conditional rendering) is cheaper and
sharper one or two levels down. Admit a journey here only when both hold: it's critical (signup,
login, checkout, publish — the flow whose breakage is an incident) and no lower level can observe it,
because what's actually under test is the wiring — routing, session, build output, server rendering,
real navigation. A journey may pass through a form with fifteen validation rules; the e2e test asserts
that one valid path works, and the fifteen rules are unit tests. Where the backend exposes a public
API, it's often easier to split at that boundary — drive the frontend against a controlled backend
double, and test the backend through its API — than to combine both into one slow, unreliable test.

## Locators

Priority order: role plus accessible name first (`getByRole('button', { name: 'Submit' })`) — this is
how assistive technology and users find a control, and it survives styling changes; a dedicated test
attribute (`data-testid`) second, wherever the accessible name is volatile marketing copy; never a CSS
class chain, `nth-child`, XPath, or a sentence of copy. Chain and filter locators to scope a search to
a region — find the row, then the button inside it — instead of writing one long brittle selector.
Locating by role is user-centric and stable because the accessible name is part of the interface
contract; asserting that a paragraph contains a specific marketing sentence is not — locate by role,
assert on identity, state, count, and URL.

## Assertions and waiting

Use web-first assertions that retry until the condition holds or the timeout expires — a bare boolean
read the instant after an action is a race. Never use a bare duration
(`waitForTimeout`/`cy.wait(3000)`/`Thread.sleep`) — wait on a network alias, a request completion, an
element state, or an application event instead; this is the single largest source of flake at this
level, and it gets copied into every test that follows it. Assert at each meaningful checkpoint of the
journey rather than splitting into one-assertion tests — at this level setup is the expensive part, so
batching assertions is correct, unlike at the unit level. Prefer soft assertions where the runner
offers them and later steps still make sense, so one run reports every failure instead of only the
first.

## State, authentication, and data

Log in through the UI exactly once, in the test that covers login itself. Everywhere else,
authenticate through the API or a saved session/storage state and reuse it — driving the login form in
a `beforeEach` is slow, flaky setup repeated on every test. Create the data a test needs through the
API rather than depending on a record that happens to exist in a shared environment — someone else
will edit it. Key data uniquely per test so parallel runs can't collide, and control the database
state explicitly for anything visual or order-dependent.

## Isolation and cleanup

A fresh browser context per test — no shared cookies, local storage, or session. No test may depend on
a previous one having run; verify by running a single spec alone. Reset state *before* the test, not
after — a mid-test crash or refresh means an `after`/`afterEach` cleanup never runs, so putting the
reset in `before`/`beforeEach` is what actually guarantees every test starts clean.

## Third-party dependencies

Don't visit or drive a site outside the application under test — its content, cookie banners, and
uptime are not this suite's problem until they become its failure. Mock external APIs at the network
layer in the browser context. For third-party auth, use a controlled tenant with a programmatic token
exchange, or stub the OAuth exchange entirely — never automate a social-login UI.

## Flake control

At this level a flaky test is worse than a missing one — it trains the team to re-run red builds.
Remove every fixed delay first; most flakes die there. Prefer subscribing to an event or waiting on a
request over polling the DOM where the application exposes one. Establish the flake rate with repeated
runs before and after a fix — five consecutive clean runs at minimum, more for anything previously
flaky — and report the number rather than a single green run. A retry that's what makes the suite pass
is a reporting tool, not a fix; the test is still broken. Capture a trace (or video plus network log)
on failure, since a screenshot alone rarely explains a race, and keep browser and runner versions
current so a browser release doesn't surface as a mystery failure weeks later.

## Sources

- Google Testing Blog, *Just Say No to More End-to-End Tests* — https://testing.googleblog.com/2015/04/just-say-no-to-more-end-to-end-tests.html
- *Software Engineering at Google*, ch. 14 *Larger Testing* — https://abseil.io/resources/swe-book/html/ch14.html
- Playwright, *Best Practices* and authentication/storage state — https://playwright.dev/docs/best-practices
- Cypress, *Best Practices* — https://docs.cypress.io/app/core-concepts/best-practices
- Testing Library, guiding principles — https://testing-library.com/docs/guiding-principles
- Martin Fowler, *Eradicating Non-Determinism in Tests*, *TestPyramid* — https://martinfowler.com/bliki/TestPyramid.html
