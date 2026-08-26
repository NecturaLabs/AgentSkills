# Comment Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `necturalabs:comment-manager` — a language-neutral comment authoring skill with a per-language matrix — and wire it into both `iterative-code-review` and `iterative-security-audit` so comment defects cannot pass either loop.

**Architecture:** A universal core (`comment-rules.md`) binds every language; a matrix (`language-matrix.md`) carries only genuine per-language divergences, each with its source named. `SKILL.md` runs three modes (Author / Audit / Fix). A review-side checklist duplicated into `iterative-code-review/references/` is kept in lockstep by a phrase validator and a mutation guard, because a dispatched reviewer subagent can only resolve absolute paths under the skill that dispatched it.

**Tech Stack:** Markdown skill documents; bash test harness (`tests/*.sh`) using `tests/test-helpers.sh`.

**Spec:** `docs/superpowers/specs/2026-08-26-code-comments-design.md`

## Global Constraints

- Branch `feature/comment-manager`, worktree `.claude/worktrees/feature+comment-manager`, merges into **`beta`** — never `main`.
- Conventional Commits; atomic commits; each commit leaves the repo passing `bash tests/run-all.sh`.
- Version bump is **minor** (new skill), applied in the same commit as the change, across all four: `.claude-plugin/plugin.json`, `.cursor-plugin/plugin.json`, `package.json`, `gemini-extension.json`. Current version `1.4.0` → `1.5.0`.
- `SKILL.md` frontmatter: `description` field required, must start with `Use `/`MUST `/`Create `/`Update `, frontmatter under 1024 chars, no `name:` field mismatch with the directory (`tests/validate-skills.sh`).
- Every numeric limit that is our synthesis rather than a published rule must be labelled as such at the point of use.
- Every language row must name its source. No invented conventions — a language with no published convention gets the fallback rule and says so.

---

### Task 1: Universal core — `comment-rules.md`

**Files:**
- Create: `skills/comment-manager/references/comment-rules.md`

**Interfaces:**
- Produces: the canonical phrasings that `tests/validate-comment-rules.sh` (Task 6) asserts, and that `comment-checklist.md` (Task 4) must carry verbatim. The seven headline rules and their actionable tails are the contract.

- [ ] **Step 1: Write the seven headline rules with actionable tails**

Each rule is two guarded halves — a headline and a tail — so truncation to either half fails the validator. Each guarded phrase must sit unbroken on a single line in every copy, because the mutation guard rewrites it with `sed`, which matches within a line:

1. `A comment carries what the code cannot.` / `Restating the code is a defect, not documentation.`
2. `Write no comment that fails the admission test.` / `All three gates, in order, or no comment.`
3. `Interface comments and implementation comments never mix.` / `Implementation detail in an interface comment is a finding.`
4. `A language's comment convention comes from its own creators.` / `never inherited from the language it resembles.`
5. `Never write a rationale you have not verified.` / `An unknown why is silence or a tracked question, never an invention.`
6. `A wrong comment is worse than no comment.` / `Editing code means you own every comment attached to it.`
7. `A comment states facts about the code.` / `it never instructs whoever reads it, human or agent.`

Rule 5 is not drawn from a published style guide. It comes from the RED-phase baselines: told to explain *why* rather than *what*, every agent that met a decision it could not source invented a motive and stated it as fact ("a loyalty/large-order perk", "for future attacker-based modifiers"). Human authors know their own why; an agent commenting code whose history it cannot see does not, and the standard advice invites the fabrication.

- [ ] **Step 2: Write the admission test section**

Three gates in order — necessity (name the thing a competent reader cannot recover in ~30 seconds), irreducibility (could clearer code remove the need — rename, extract, named constant, enum over bool, options object), durability (still true and useful after the next reasonable change). Include the standing exception for public API surface and its published carve-outs.

- [ ] **Step 3: Write the two closed content lists and the ban list**

Content exactly as enumerated in spec §6. The ban list must include the security entries (secrets, keys, internal hostnames, PII, exploit detail) and the agent-directive entry.

- [ ] **Step 4: Write the size limits table with provenance labels**

Table exactly as spec §7, with the sentence marking the 7-line ceiling and ≤3-sentence target as synthesis from Microsoft's Writing Style Guide and Google's documentation style guide, and the design-signal escalation.

- [ ] **Step 5: Write the annotation rules and the sources list**

`TODO`/`FIXME`/`HACK`/`SAFETY` require an owner or a tracked reference; "at a future date" needs a specific date or a specific event. Full source citations with URLs.

- [ ] **Step 6: Verify structure**

Run: `bash tests/validate-skills.sh`
Expected: PASS for every existing skill (this task adds no `SKILL.md` yet, so `comment-manager` is not yet listed).

- [ ] **Step 7: Commit**

```bash
git add skills/comment-manager/references/comment-rules.md
git commit -m "feat(comment-manager): add universal comment rule canon"
```

---

### Task 2: Language matrix — `language-matrix.md`

**Files:**
- Create: `skills/comment-manager/references/language-matrix.md`

**Interfaces:**
- Consumes: the universal core from Task 1 (the matrix carries deltas only, never restates the core).
- Produces: the per-language rows and the derived-language trap table that `SKILL.md` (Task 3) routes into.

- [ ] **Step 1: Write the resolution order**

Project formatter config (`.editorconfig`, `rustfmt.toml`, `.prettierrc`, checkstyle, ruff) → matrix row → universal core. Never reformat comments a project's formatter owns.

- [ ] **Step 2: Write the matrix rows**

One row per language with columns: comment prose width (and its source) · line/block syntax · doc marker · doc tool · summary form · required contract sections · tag policy · annotation form · language-specific prohibitions.

Rows: Python, JavaScript, TypeScript, Java, Kotlin, Scala, C#, Go, Rust, C, C++, Objective-C, Swift, Dart, Ruby, PHP, Elixir, Haskell, Julia, R, Shell/Bash, PowerShell, Lua/Luau, GDScript, SQL, HTML, CSS/SCSS, YAML, TOML, JSON, XML, Terraform/HCL, GraphQL, Dockerfile, Makefile.

- [ ] **Step 3: Write the derived-language trap table**

This is the section that stops a parent language's convention leaking into a derived one. One row per trap, each naming the wrong instinct and the creators' actual rule. Must cover at minimum: GDScript←Python, TypeScript←JavaScript/Java, Luau←Lua, Kotlin←Java, C#←Java, Scala←Java, Swift←Objective-C, Dart←Java/JS, Go←C, Rust←C++, Objective-C←C, C++←C, PHP←C/Java, Elixir←Erlang/Ruby, Julia←Python/MATLAB, R←S, PowerShell←Bash, HCL←JSON, GraphQL←JS, JSON←JavaScript, SCSS←CSS.

- [ ] **Step 4: Write the three "comments are not the mechanism" rows**

JSON has no comment syntax (RFC 8259) — never emit one. GraphQL documents with `"""` descriptions; `#` comments are dropped by the type system. Terraform documents via `description` arguments on variables and outputs.

- [ ] **Step 5: Write the fallback rule**

Unlisted language → obey the project's formatter config, else 80 columns for comment prose; use the language's canonical doc syntax and generator; the universal core applies unchanged; state explicitly that no convention is being invented.

- [ ] **Step 6: Commit**

```bash
git add skills/comment-manager/references/language-matrix.md
git commit -m "feat(comment-manager): add per-language comment matrix"
```

---

### Task 3: `SKILL.md`

**Files:**
- Create: `skills/comment-manager/SKILL.md`

**Interfaces:**
- Consumes: `references/comment-rules.md`, `references/language-matrix.md`.
- Produces: the skill name `necturalabs:comment-manager` referenced by Tasks 4, 5 and 7.

- [ ] **Step 1: Write frontmatter**

```yaml
---
description: MUST invoke when writing or changing code that will carry comments, when adding or editing doc comments, docstrings, or API documentation in source, and when auditing or cleaning up existing comments. Also use when the user asks to document, comment, or add docstrings to code.
---
```

Must start with `MUST `, stay under 1024 chars, and describe triggering conditions only — never the workflow (per `superpowers:writing-skills`, a description that summarises the workflow becomes a shortcut agents take instead of reading the skill).

- [ ] **Step 2: Write the admission gate as a HARD-GATE block**

The three-part test, stated as a gate the agent must pass before writing any comment, with the default-to-no-comment rule and the explicit ban on per-construct mandates and density targets.

- [ ] **Step 3: Write the mode flowchart**

`dot` digraph with three entry points (Author / Audit / Fix) routing through language resolution to the rule files. Flowchart only for the routing decision, per writing-skills guidance.

- [ ] **Step 4: Write the rationalization table and red flags list**

Populated from the RED-phase baseline transcripts, verbatim where possible.

- [ ] **Step 5: Write the reporting format**

Same severity ladder and one-line finding format as `iterative-code-review`, so audit output drops straight into a review.

- [ ] **Step 6: Verify**

Run: `bash tests/validate-skills.sh`
Expected: `PASS: comment-manager -- valid structure`

- [ ] **Step 7: Commit**

```bash
git add skills/comment-manager/SKILL.md
git commit -m "feat(comment-manager): add skill entry point"
```

---

### Task 4: Code review integration

**Files:**
- Create: `skills/iterative-code-review/references/comment-checklist.md`
- Modify: `skills/iterative-code-review/SKILL.md` (dispatch table, checklist summary table)
- Modify: `skills/iterative-code-review/references/review-checklist.md` (§9 Style, replace the three comment lines with a full section)

**Interfaces:**
- Consumes: the seven headline rules and size limits from Task 1, carried verbatim.
- Produces: the third checklist path the reviewer subagent receives.

- [ ] **Step 1: Write `comment-checklist.md`**

Review-side framing: how to *find* a bad comment. Carries the seven headline rules verbatim, the size limits table, the severity mapping, and the per-language spot-checks a reviewer needs.

- [ ] **Step 2: Add the third path to the dispatch table in `SKILL.md`**

The `[PLAN_OR_REQUIREMENTS]` row already names two absolute checklist paths. Add `<necturalabs:iterative-code-review base>/references/comment-checklist.md` as the third, and extend the verification demand so the reviewer must confirm it read all three files.

- [ ] **Step 3: Add Comments to the checklist summary table in `SKILL.md`**

New row: `| Comments | Ousterhout, Google, Clean Code | See references/comment-checklist.md |`

- [ ] **Step 4: Replace §9's three comment lines in `review-checklist.md`**

Delete `Comments explain WHY, not WHAT`, `No commented-out code`, `Public APIs have doc comments` from §9 and add a full `## 12. Comments & Documentation` section with the severity mapping.

- [ ] **Step 5: Verify**

Run: `bash tests/run-all.sh`
Expected: all suites pass.

- [ ] **Step 6: Commit**

```bash
git add skills/iterative-code-review
git commit -m "feat(code-review): enforce comment rules in the review loop"
```

---

### Task 5: Security audit integration

**Files:**
- Modify: `skills/iterative-security-audit/SKILL.md` (frontmatter trigger list, checklist summary table)
- Modify: `skills/iterative-security-audit/references/security-checklist.md` (new category)

- [ ] **Step 1: Add comments to the frontmatter trigger list**

So a change touching only comments still routes through the audit. Keep the frontmatter under 1024 chars.

- [ ] **Step 2: Add the Comment-Borne Disclosure category**

CWE-615 (sensitive information in source code comments), CWE-540 (sensitive information in source code), CWE-546 (suspicious comment), and the OWASP SCP requirement to remove comments in user-accessible production code that reveal backend or other sensitive information. Severity CRITICAL for live credentials, keys and tokens; HIGH for internal hostnames, paths and infrastructure detail; MEDIUM for commented-out code carrying either.

- [ ] **Step 3: Verify**

Run: `bash tests/run-all.sh`
Expected: all suites pass.

- [ ] **Step 4: Commit**

```bash
git add skills/iterative-security-audit
git commit -m "feat(security-audit): add comment-borne disclosure category"
```

---

### Task 6: Anti-drift validators

**Files:**
- Create: `tests/validate-comment-rules.sh`
- Create: `tests/comment-rules-guard.sh`
- Modify: `tests/run-all.sh` (register both suites)

**Interfaces:**
- Consumes: the exact phrasings from Task 1 and Task 4.
- Produces: two suites registered in `run-all.sh`.

- [ ] **Step 1: Write `validate-comment-rules.sh`**

Model on `tests/validate-house-rules.sh`: normalise whitespace, then assert two disjoint phrases per rule (headline + actionable tail) in both `skills/comment-manager/references/comment-rules.md` and `skills/iterative-code-review/references/comment-checklist.md`. Also assert the size-limit numbers appear in both. Match in-process with bash pattern tests, not by piping to grep — the guard runs this script a dozen times and a subprocess per phrase per file is minutes on Windows.

- [ ] **Step 2: Run it and watch it pass**

Run: `bash tests/validate-comment-rules.sh`
Expected: PASS for both files.

- [ ] **Step 3: Write `comment-rules-guard.sh`**

Model on `tests/house-rules-guard.sh`: copy the tree to a temp dir, assert the unmutated copy passes (negative control), then mutate one anchor phrase per case and assert the validator fails each time. Cover one phrase from each of the seven rules plus one size-limit number, against the canon; plus two canaries against the review checklist so a validator that silently stopped checking that file is caught.

- [ ] **Step 4: Run it and watch it pass**

Run: `bash tests/comment-rules-guard.sh`
Expected: negative control passes, every mutation detected.

- [ ] **Step 5: Register both in `run-all.sh`**

Add two `run_test_suite` blocks after the existing House Rules Guard block, following the same `if [ -f ... ]` pattern.

- [ ] **Step 6: Verify the whole suite**

Run: `bash tests/run-all.sh`
Expected: all suites pass, total test count increased.

- [ ] **Step 7: Commit**

```bash
git add tests/validate-comment-rules.sh tests/comment-rules-guard.sh tests/run-all.sh
git commit -m "test: guard comment-rule consistency across skills"
```

---

### Task 7: Registration and version bump

**Files:**
- Create: `tests/skill-triggering/prompts/comment-manager.txt`
- Modify: `skills/using-necturalabs/SKILL.md` (skills table, decision flow)
- Modify: `README.md` (Available Skills table)
- Modify: `AGENTS.md` (gate line)
- Modify: `.claude-plugin/plugin.json`, `.cursor-plugin/plugin.json`, `package.json`, `gemini-extension.json` (1.4.0 → 1.5.0)

- [ ] **Step 1: Write the triggering prompt**

```
# necturalabs:comment-manager
Add docstrings to the payment retry helper I just wrote
```

- [ ] **Step 2: Add the row to the `using-necturalabs` skills table**

```
| `necturalabs:comment-manager` | Comment and doc-comment authoring, auditing and repair | Writing or changing code that carries comments |
```

- [ ] **Step 3: Add the README row**

```
| **`comment-manager`** — Comment and doc-comment rules across languages, with a per-language matrix | Writing or changing code that carries comments |
```

- [ ] **Step 4: Add the AGENTS.md gate line**

State that comment work routes through the skill and that both review loops enforce it.

- [ ] **Step 5: Bump all four config files to 1.5.0**

- [ ] **Step 6: Verify**

Run: `bash tests/run-all.sh`
Expected: all suites pass.

- [ ] **Step 7: Commit**

```bash
git add tests/skill-triggering/prompts/comment-manager.txt skills/using-necturalabs README.md AGENTS.md .claude-plugin/plugin.json .cursor-plugin/plugin.json package.json gemini-extension.json
git commit -m "feat: register comment-manager and bump to 1.5.0"
```

---

### Task 8: GREEN verification

**Files:** none modified unless a scenario fails.

- [ ] **Step 1: Re-run the three RED baseline scenarios with the skill present**

Same three prompts used for the baseline — over-commenting under quota and time pressure (TypeScript), derived-language documentation (GDScript), comment tidy-up containing a credential and commented-out code (Python) — dispatched with `skills/comment-manager/SKILL.md` and both reference files in context.

- [ ] **Step 2: Score each against the baseline**

Pass criteria, per scenario: no comment restating the code; no journal, byline or banner; commented-out code deleted; the credential and internal hostname removed; GDScript documented with `##` and Godot tags, not Python docstrings; every comment within the size limits.

- [ ] **Step 3: If any scenario fails, add the specific counter to the rationalization table and re-test**

Loop until all three pass. Record each new rationalization verbatim.

- [ ] **Step 4: Commit any skill changes**

```bash
git add skills/comment-manager
git commit -m "fix(comment-manager): close loopholes found in verification"
```

---

### Task 9: Review and merge

- [ ] **Step 1: Run the full suite**

Run: `bash tests/run-all.sh`
Expected: all suites pass, zero failures.

- [ ] **Step 2: Run `necturalabs:iterative-security-audit`**

The change adds a security category and touches security-relevant guidance, so the audit runs first and chains into code review. Dispatch with the absolute worktree path and the exact diff scope (`beta..feature/comment-manager`).

- [ ] **Step 3: Fix every finding — no deferral**

- [ ] **Step 4: Merge into `beta`**

```bash
git checkout beta
git merge --no-ff feature/comment-manager
bash tests/run-all.sh
```

- [ ] **Step 5: Clean up the worktree**

```bash
git worktree remove .claude/worktrees/feature+comment-manager
git branch -d feature/comment-manager
```

---

## Self-Review

**Spec coverage:** §4 D1→Task 3; D2→Tasks 1,2; D3→Tasks 1,3; D4→Task 1; D5→Tasks 4,5; D6→Tasks 4,6; D7→Task 2. §5→Task 1 Step 2. §6→Task 1 Step 3. §7→Task 1 Step 4. §8→Tasks 4,5. §9→Tasks 1–3,6,7. §10 non-goals need no task. The user's derived-language requirement is Task 2 Step 3, and is also rule 4 of the seven in Task 1 Step 1 so the validator guards it.

**Placeholder scan:** no TBD, no "handle edge cases", no "similar to Task N". Every phrase the validator asserts is written out in Task 1 Step 1 rather than referenced.

**Consistency:** the seven rule phrasings in Task 1 Step 1 are the same strings asserted in Task 6 Step 1 and carried in Task 4 Step 1. The version `1.4.0 → 1.5.0` is stated once in Global Constraints and used in Task 7. Skill name `necturalabs:comment-manager` is identical across Tasks 3, 4, 5, 7.
