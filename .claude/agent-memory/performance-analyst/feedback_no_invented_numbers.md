---
name: feedback-no-invented-numbers
description: Never invent acceptance thresholds/target numbers for a new metric — defend methodology, not magic values
metadata:
  type: feedback
---

When designing instrumentation or performance criteria for Monster Tamer, do not propose
concrete target values (e.g. "polarization must be below 0.4") for a metric nobody has measured
yet. Defend the *methodology* instead (sign test vs. mean CI, "must beat 2×sd" from the
instrument's own `--noise` run, paired A/B over pooled means) and say plainly where you refuse
to invent a number.

**Why:** `CLAUDE.md` states this as a recurring, named failure mode on this project — "a value
in the codebase is evidence of what happened, never evidence that anyone decided it." The
balance tooling docs (`tools/sweep40.ts`, `tools/ab.ts`) already paid for this lesson once: a
12-fight sweep had sd 0.7, and several past tuning decisions were made on differences smaller
than that noise before a paired A/B caught it. Judge on a sign test over paired identical-seed
runs, never on a mean confidence interval alone (mean CIs are wide/misleading because a handful
of fights swing wildly when they tip from timeout to a kill).

**How to apply:** any time asked to define "better" for a new system (performance, AI behaviour,
balance), (1) propose the statistical test/process, (2) propose capturing a *reference
population* via the existing sim/build as a noise baseline rather than asserting a target, and
(3) explicitly flag which numbers in the response are "process I'll defend" vs. "a number I
won't invent." See [[project-suspended-balance-baseline]] for the specific standing rule this
generalizes from.
