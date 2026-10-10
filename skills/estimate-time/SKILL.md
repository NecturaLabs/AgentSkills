---
name: estimate-time
description: Estimate the remaining time and percent done for a task, project or port, derived from the pace of its commits on the current approach, and answer in one short block. Use when the user asks "how long", "ETA", "how done are we", "what percent" or similar about work in a repository. Not for timing a command or a pipeline run, not for sizing work in human effort (everything here is built by agents), and not for planning or splitting the work (agent-orchestration).
---

# Estimate time and percent done

The working agreement's Reporting rule governs the answer: all development is done by AI agents,
so never answer in human-days, person-weeks or "a developer would need".

## Method

1. **Scope the work.** Find the unit of progress that is countable: checklist rows, behaviour
   rows, tickets, phases, files to port. Read the checklist or plan and count done and total with
   a command, not by eye.
2. **Pick the current approach.** Count only work on the approach now in use. Drop commits from an
   abandoned approach or from setup that will not repeat. State the date it starts.
3. **Measure the pace.** `git log --format='%ad %s' --date=format:'%m-%d %H:%M'` over those
   commits. Take the wall time from first to last, minus idle gaps (a gap of several hours with
   no commit is idle). Divide units delivered by active hours. Note what each stretch delivered,
   since units are rarely equal.
4. **Size the remainder.** Remaining units divided by the pace gives active time. Add separate
   time for steps whose pace differs from the measured one (heavy exports, builds, performance
   runs, CI, waiting on the user) and name each. Do not apply a UI-row pace to art, stages or
   measurements without saying so.
5. **Percent done.** Done units over total units, then note if the weighted figure differs
   (unequal units, finished infrastructure).
6. **Check it.** If the figure disagrees with an earlier estimate in the session, say so and say
   which one is derived.

## Answer format

Concise, no tables or option lists unless asked:

- First line: percent done and remaining time, as a range in agent time (hours or days of
  continuous work).
- Then the basis in a line or two: the counts, the pace and the date range it came from.
- Then only the limits that change the number: unmeasured pace, user-gated steps.

Never present a guess as derived. If a pace cannot be measured yet, say it is unmeasured and give
the proxy used.
