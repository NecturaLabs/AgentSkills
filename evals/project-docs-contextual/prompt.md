---
name: project-docs-contextual
description: The documentation trigger is embedded in a list of other wrap-up work.
tags: [routing]
plugins: ["../.."]
runs: 3
allowed_tools: [Read, Glob, Grep, Skill]
---

I just finished wiring the new event-bus consumer into the checkout service — it replaces the old
cron-based reconciliation job. Before I hand this off: draft the pull request description, and then
put together something that explains how the consumer, the bus and checkout fit together for
whoever touches this next, plus the steps for restarting a stuck consumer since that's going to come
up on-call.

What changed:

- `checkout/consumers/paymentSettled.ts` subscribes to the `payments.settled` topic on the shared
  Kafka bus as consumer group `checkout-reconciler`, and marks the matching order paid.
- Offsets are committed only after the order update commits, so a crash replays the last batch;
  the handler is idempotent on `paymentId`.
- The old `reconcile-orders` cron job and its Helm CronJob are deleted.
- A stuck consumer shows up as lag on `checkout-reconciler` in the Grafana "Bus lag" board. It
  restarts with `kubectl -n checkout rollout restart deploy/checkout-reconciler`; if one message
  keeps failing, it lands in `payments.settled.dlq` after five attempts.
