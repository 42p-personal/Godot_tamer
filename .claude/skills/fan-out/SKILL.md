---
name: fan-out
description: "Author and run a multi-agent Workflow round on Monster Tamer, using the structure that fifteen rounds converged on — a diagnosis phase that gates the builders, one owner per file, an integrator whose first check is the thing most likely to be broken, and an explicit instruction that refuting the brief is the highest-value move. Use when the user says fan out, get the team on it, run a round, or asks for work that spans several subsystems at once. Do NOT use for a single focused change — one agent that has to re-derive this project's context is slower and worse than doing it inline."
argument-hint: "[what the round is about]"
user-invocable: true
allowed-tools: Bash, Read, Glob, Grep, Write, Workflow, AskUserQuestion
model: opus
---

# Fan Out

The round structure this project converged on over fifteen workflows. It is not a template to
fill in — it encodes specific things that went wrong and the fix for each.

⚠️ **Requires explicit user opt-in** (they said "fan out" / "get the team on it" / named a round).
Never infer it from a task merely being large.

---

## 1. Ground the brief BEFORE writing it

**Non-negotiable, and the highest-leverage step.** Spend real tool calls verifying the premises
you are about to hand three agents. Grep the constants, dump the schema, run the probe, read the
capture. A wrong brief costs every agent in the round.

**My briefs have been wrong in most rounds.** Recorded so the next author budgets for it:

| the claim | the truth |
|---|---|
| "the ladder is calibrated against this sim" | it runs on `battle_sim.gd` and cannot see spatial changes |
| "AoE is catching whole teams" | it catches **1.43** — mechanism right, consequence backwards |
| "32 cups clears the ladder" | off by ~4× — ADVANCE is a step function of roster fill, not a price |
| "141 off-scale labels in three files" | right attribution, **wrong unit** (source call-sites vs rendered labels differ 4–5×) |
| "inversion mass ≤ 38.5" | a guard taken from a *different instrument's* metric |
| "`recompute_class()` has six callers" | five — **plus two files that overwrote the field without calling it** |
| "the management screens were carried by whatever was quickest" | the content was thoughtful; the ARRANGEMENT was wrong — a much cheaper cure |

So: **state where every number came from, and mark the ones you did not measure yourself.**

## 2. Phase 1 — a diagnosis agent, when the cause is not established

Gate the builders behind one agent that measures before anyone changes a constant. It has twice
recommended **stopping the round**, correctly — once proving a feature would buy 0.97×, once
refuting the round's own premise by 4×.

- Give it **authority to stop the round** and say so explicitly.
- Give it its own new probe files to own; it must not edit shipped code.
- **Return prose, not a schema.** A diagnostician died on the StructuredOutput retry cap after
  52 tool calls of good work; its probe survived on disk and I recovered the finding by running
  it myself. Prose costs nothing to emit.

## 3. Phase 2 — builders, one owner per file

**One owner per file, always.** Cross-file needs go to the integrator, never edited directly.
Two agents in `arena_3d.gd` at once is how a file-wipe race happens.

Each builder brief needs:

- **The measured baseline** it must not regress, as numbers.
- **Acceptance settled by capture or probe**, not by adjective.
- **The trade-off named**, when there is one (e.g. "do not turn the market into a recommendation
  engine — name the gap and let the player judge").
- **The specific trap** that applies to its files.
- **"If my brief is wrong, say so with the number."** This produces the round's best finding
  more often than compliance does — round 14 had *both* builders correctly refuse part of a brief.

## 4. Phase 3 — the integrator

Its **first instruction must be the check most likely to fail**, before anything else:

- sim round → determinism across **three separate processes** (in-process cannot catch hash-order)
- meta round → did completion move? (a difficulty change wearing a scoreboard costume)
- UI round → did the house numbers regress? (prettier and less readable is a **loss**)
- any round with a known trap → spring-test it (e.g. "measure a reach and compare to round 23's
  figures; a doubled reach means the consolidation trap sprung")

Then: run everything, **fix the seams** (round 19 found four defects by looking that no probe
reported, including a regression an agent had just caused while the style probe stayed green),
and give an **honest verdict**. Ask for it in those words — the honest negative has been the most
valuable line in the report for six consecutive rounds.

## 5. Scope fences

State what is **out of scope** and why. Rounds routinely need "do not touch the arena / the sim /
the camera / the audio" because those carry contracts the round is not paying for. A round that
quietly widens its own scope cannot be verified.

---

## Mechanics that matter

- **Write the script to a file** and invoke with `scriptPath`, so it can be edited and resumed.
- **Backticks break the template literal.** Build long briefs as `[...].join('\n')` arrays.
- **Keep schemas small.** Two agents have died on the StructuredOutput retry cap; the diagnosis
  phase should have no schema at all.
- **On failure, check the tree before retrying.** `resumeFromRunId` replays completed agents from
  cache and re-runs only the failures. Usage-limit deaths leave nothing partial; a mid-flight
  death may leave files on disk worth recovering — read `journal.jsonl` before assuming loss.
- **Agents run in parallel with the user's tree.** Do not `git stash` during a round; an agent
  did and swept other agents' uncommitted files for 60 seconds.

## After it lands

Do not take the report on trust. **Re-run the battery yourself** (`/verify`), re-measure the one
number the round turned on, and read any capture with its **timestamp checked**. Integrators have
reported probes red that were their own headless invocations of window-only probes, and a stale
PNG once cost three consecutive wrong conclusions.

Then commit with the *finding* in the message, not the file list — the commit log is this
project's real changelog.
