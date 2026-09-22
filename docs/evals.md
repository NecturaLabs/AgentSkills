# Eval results

The routing evals under `evals/` run with `claude plugin eval .` once per release. The run is
recorded here, newest first, so a regression in routing shows up as a change between releases.

Each case runs three times in two arms: with this plugin, and without it as a baseline. A score is
the weighted share of graders that passed in the with-plugin arm, and Δ is that score minus the
baseline's. Every run starts in an empty workspace with read-only tools and none of the user's own
settings or instruction files, so a judge-graded prompt must carry any code or diff it refers to;
a case graded only on which skill fired may describe the work instead.

## 4.0.0 — 2026-09-22

Claude Code 2.1.280. The command, run from the repository root:

```sh
claude plugin eval . --trust-plugin --no-publish -j 4 --threshold 0
```

Two passes are combined below. The full suite ran first against the installed 3.0.0 skills (30
cases, 180 runs, 788 s, $16.42): overall score 0.72, mean Δ +0.42. Nine cases scored low because
their prompts pointed at code the empty workspace did not have, or a grader described a different
prompt than the one it graded. Those nine were rewritten to carry their content inline and re-run
against this release's tree (54 runs, 382 s, $5.43). The other 21 cases are unchanged from the
first pass.

Combined: **overall score 0.97, mean Δ +0.55**, 30 of 30 cases above the zero threshold.

| Case | With | Without | Δ | Graders passed, with plugin | Pass |
|---|---|---|---|---|---|
| agent-instructions-ambiguous | 0.67 | 0.67 | +0.00 | response-is-proportional 2/3 | first |
| agent-instructions-contextual | 1.00 | 0.00 | +1.00 | routes-to-agent-instructions 3/3 | first |
| agent-instructions-explicit | 1.00 | 0.00 | +1.00 | routes-to-agent-instructions 3/3 | first |
| agent-instructions-implicit | 1.00 | 0.00 | +1.00 | routes-to-agent-instructions 3/3 | first |
| agent-instructions-negative | 1.00 | 0.67 | +0.33 | answers-without-editing 3/3; does-not-route-to-agent-instructions 3/3 | re-run |
| agent-orchestration-ambiguous | 1.00 | 1.00 | +0.00 | proportional-response 3/3 | first |
| agent-orchestration-contextual | 1.00 | 0.00 | +1.00 | routes-to-agent-orchestration 3/3 | first |
| agent-orchestration-explicit | 1.00 | 0.00 | +1.00 | routes-to-agent-orchestration 3/3 | first |
| agent-orchestration-implicit | 1.00 | 0.00 | +1.00 | routes-to-agent-orchestration 3/3 | first |
| agent-orchestration-negative | 1.00 | 1.00 | +0.00 | answers-without-delegating 3/3; does-not-route-to-agent-orchestration 3/3 | first |
| independent-review-ambiguous | 0.67 | 1.00 | −0.33 | response-is-proportional 2/3 | re-run |
| independent-review-contextual | 1.00 | 0.00 | +1.00 | routes-to-a-review 3/3 | re-run |
| independent-review-explicit | 1.00 | 0.50 | +0.50 | does-not-route-to-a-security-pass 3/3; routes-to-independent-review 3/3 | first |
| independent-review-implicit | 1.00 | 0.00 | +1.00 | routes-to-a-review 3/3 | first |
| independent-review-negative | 1.00 | 1.00 | +0.00 | does-not-route-to-a-review 3/3; handled-as-a-typo-fix 3/3 | re-run |
| project-docs-ambiguous | 1.00 | 1.00 | +0.00 | response-is-proportional 3/3 | first |
| project-docs-contextual | 1.00 | 0.00 | +1.00 | routes-to-project-docs 3/3 | re-run |
| project-docs-explicit | 1.00 | 0.00 | +1.00 | routes-to-project-docs 3/3 | first |
| project-docs-implicit | 1.00 | 0.00 | +1.00 | routes-to-project-docs 3/3 | first |
| project-docs-negative | 1.00 | 1.00 | +0.00 | does-not-route-to-project-docs 3/3; explained-not-documented 3/3 | re-run |
| testing-ambiguous | 1.00 | 1.00 | +0.00 | proportional-response 3/3 | re-run |
| testing-contextual | 1.00 | 0.00 | +1.00 | routes-to-testing 3/3 | re-run |
| testing-explicit | 1.00 | 0.00 | +1.00 | routes-to-testing 3/3 | first |
| testing-implicit | 1.00 | 0.00 | +1.00 | routes-to-testing 3/3 | first |
| testing-negative | 0.67 | 0.67 | +0.00 | does-not-route-to-testing 3/3; explains-without-authoring 2/3 | first |
| threat-review-ambiguous | 1.00 | 1.00 | +0.00 | response-is-proportional 3/3 | first |
| threat-review-contextual | 1.00 | 0.00 | +1.00 | routes-to-threat-review 3/3 | re-run |
| threat-review-explicit | 1.00 | 1.00 | +0.00 | routes-to-a-security-pass 3/3 | first |
| threat-review-implicit | 1.00 | 0.00 | +1.00 | routes-to-a-security-pass 3/3 | first |
| threat-review-negative | 1.00 | 1.00 | +0.00 | does-not-route-to-a-security-pass 3/3; handled-as-a-copy-change 3/3 | first |

What the numbers do and do not say:

- Every negative case keeps its skill from firing (3/3 on each `does-not-route` grader). No skill's
  description is broad enough to fire on a neighbour's work.
- The three cases below 1.00 are all judge-graded, each at 2 of 3. The failing
  answers read much like the passing ones, so at three runs this is within judge variance, not a
  demonstrated regression. `independent-review-ambiguous` scored 1/3 and then 2/3 with the plugin
  and 2/3 then 3/3 without it; it is the case to watch next release.
- A Δ of +0.00 on an ambiguous, negative or native-first case is the expected result: the baseline
  answers those well without the plugin, and the plugin must not make them worse.
- The combined figures mix two passes on the same Claude Code version. The next release's run
  should be a single full pass.
- After both passes, the prose bodies of ten deterministic routing graders were written or
  corrected to describe their prompts. Those graders match on the skill invoked, not on their
  prose, so the scores above still stand.
