---
name: dead-wire
description: "Hunt this project's signature failure — a system authored, priced, typed and documented that does nothing because nothing calls it, the caller passes the wrong thing, or the instrument cannot see it. 13+ instances found. USE AUTOMATICALLY: before concluding a feature is missing OR that it works; when a mechanic that should matter measures as noise; when a screen shows a fact nobody can act on; when a doc claims something exists; when asked why a system 'isn't doing anything'; and as a standing audit on any subsystem nobody has opened recently."
argument-hint: "[system-or-file | --sweep]"
user-invocable: true
allowed-tools: Bash, Read, Glob, Grep, Write
model: sonnet
---

# Dead Wire

**This project's most repeated bug, by a wide margin.** Something is authored, priced, typed,
documented — and does nothing. It has been found 13+ times, four in a single round, and it has
twice invalidated a measurement that a later round then acted on.

The failure is not carelessness. It is that **a grep for the feature succeeds**: the constant
exists, the function exists, the data table has the entry. Only the *connection* is missing, and
nothing in the codebase asserts a connection.

---

## The roll of honour — read these before you start

Each one looked fine from the outside:

| what | how it died |
|---|---|
| `Generalist` class | 19 entries in `classBasic`, 18 in `classLines`. `assign_moveset()` cleared the kit and found no bucket to refill from — **empty moveset, forever, and on the save/load path too** |
| bloodline potential | `week.gd:stat_cap_for` had **no shipped caller**. The one thing breeding sells did nothing |
| the entire 13-month season | 5 named marquee events, a 1.75× purse, a deterministic month per league — **rendered by no screen** |
| the whole audio mixer | 698 lines, 21 cues, ducking, priority bands — **referenced only by a dev scene**. The production fight played in silence |
| the entire ranged game | kit ranges lifted ×2.2 where the design scale is ×8.8 — **the widest reach in the game covered 6% of the walk** |
| `positional_intent` | authored, rendered, saved, and read **only by a superseded tree**. A control on the commit screen the fight ignored |
| 141 ability icons | on disk, referenced by exactly one file |
| the bench guard | `capacity > need` while the loop above only ever grew capacity **to** need — dead by construction |
| `stat_ceiling_tier()` | both branches returned the same value, so every caller's other branch was unreachable |

---

## The procedure

### 1. Name the claim

Write down what the system is supposed to DO, in one sentence, in the game's terms — not in
code terms. "Bloodline potential lifts the training ceiling above the league cap." That sentence
is what you are going to try to falsify.

### 2. Find every caller, and be suspicious of one

```bash
grep -rn "the_function\|THE_CONSTANT" scripts/ --include="*.gd" | grep -v _probe
```

- **Zero shipped callers** → dead. Found this way: `stat_cap_for`.
- **Only a probe or a dev scene calls it** → dead in production. Found this way: the audio mixer,
  and the event-presentation fix that landed in `_watch_sim.gd` instead of `arena_3d.gd`.
- **Only a superseded file calls it** → worse than dead, because a grep makes it look wired.
  Check for `SUPERSEDED` banners. Found this way: `positional_intent`.

### 3. Check the caller passes the right thing

A live caller is not proof. The field can be threaded and still wrong:

- `_draw_field()` re-rolled reshaped qualifiers **without** the archetype
- `tactics_ui` derived the rival gameplan from **a hash of species names**
- `enter_league_tournament` built teams with **no plans at all**, so a focus-fire side fought
  identically to a wall
- the species gallery passed the **model id** where the function keyed on **species id**

### 4. Check the two tables agree

Where a feature is keyed by name across two generated tables, assert the key sets match. That is
exactly how `Generalist` shipped kitless — and note the lesson from fixing it: **a key-set diff
is not enough**, because it passes the moment someone silences it with an empty entry. Assert the
BEHAVIOUR (arm a real monster of every class and check it carries moves).

### 5. Check the instrument can see it

A working feature that no probe can observe will be "measured" as noise and then tuned away:

- a nav spike passed on **400 empty paths** (they hash identically)
- a slope probe carried **a second copy of the model it was testing**
- a probe measured a player that **fought with no moves**
- an instrument pinned **above the ceiling** read 100% everywhere
- a capture harness could only ever photograph Breeding **empty**, which manufactured a wrong brief

**Every probe needs a liveness canary that exits non-zero if the thing it perturbed did not move.**

### 6. Prove it, then fix it, then guard it

Show the feature firing — a printed value, a capture, a probe line. Then add the assertion that
would have caught it. The `Generalist` fix shipped with a tripwire that arms a real monster of
every class in `classBasic`; that tripwire is why the next hole will be loud.

---

## `--sweep` mode

Audit for candidates without a target in mind:

1. **Constants with no reader** — grep each `const` in a system file for a second occurrence.
2. **Functions with one caller that is a probe** — the production path never runs them.
3. **Data fields nothing consumes** — dump the JSON schema and grep each key.
4. **Files with a SUPERSEDED banner that are still imported** by live code.
5. **Docs that claim a feature exists** — verify each claim; a stale doc has cost this project
   two rounds, and `CLAUDE.md` itself carries a memory that three "missing" mechanics were
   already built.

Report candidates ranked by **what the game loses if it is dead**, not by how easy they are to
check.

---

## ⚠️ The mirror failure

Equally common and equally expensive: **concluding something is missing when it is already
built.** A whole round was briefed on "no standings table exists" when the season shipped in
`cup_run.gd`; another on "market_ui doesn't preload theme.gd" when it did.

**Grep before concluding it is missing, and grep before concluding it works.**
