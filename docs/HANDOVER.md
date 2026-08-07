# Handover — state at 2026-08-03

**Read this first in a fresh session, then `CLAUDE.md`.** Everything below is committed on
`3doverhal`. Tree clean, 292 tests green, all six port contracts passing.

---

## 1. Where the build actually is

**The Godot port's arithmetic layer is DONE and verified.** `monster-tamer/` is a real Godot
4.7.1 project running 219 contract cases across six files, all matching TypeScript exactly.

```bash
cd monster-tamer && ./run_contract.sh     # exit code is the result
npm test                                   # 292 tests, TypeScript side
```

| contract | cases | subject |
|---|---|---|
| `combat.json` | 62 | damage resolution |
| `derive.json` | 46 | pools, mana, cooldowns, cast times |
| `status.json` | 31 | statuses + CC diminishing returns |
| `tick.json` | 34 | timers, regen, attrition, expiry, sudden death |
| `classify.json` | 46 | class, role, mana role, free attack |
| `data.json` | — | 141 moves · 65 species · 18 classes · **130 innate effects** |

**Nothing portable remains.** What is left in `engine.ts` is ~1,140 lines of AI and spatial
code that is being REBUILT, not ported.

---

## 2. The standing rules (all in `CLAUDE.md`)

1. ⚠️ **The port is a skeleton, not a specification.** Nearly every system is reworked in Godot.
2. ⚠️ **The balance baseline is SUSPENDED.** Do not quote `sweep40` figures. Re-baseline once,
   deliberately, when the arena is sized.
3. **`tamerengine` becomes the whole game.** `battle.ts` + React are legacy — keep running, do
   not invest.
4. **This is a Godot studio.** Zero Unity/Unreal references remain.
5. ⚠️ **An inherited value is evidence of what happened, never evidence anyone decided it.**

---

## 3. ⚠️ THE PATTERN THAT MATTERS MOST

**Ten things were found already built, already measured, or already fixed while being discussed
as missing or broken:**

per-unit speed (DEX-derived) · the leash (`LEASH_RADIUS=12`) · `spreadStatus` (live on 5 moves) ·
the cohesion×predation archetype grid · per-ability `range` · the measurement that speed does not
fix chasing · 30 battle sprites on disk · `retargetIn` · `targetPriority` reaching melee ·
`FLANK_*` radii already fixed once

**The codebase is substantially ahead of its own documentation.** Three of those were claims I
made and had to retract.

**So: grep before asserting absence, and read the comment before believing a diagnosis.**

---

## 4. Decisions taken (full record in `docs/DECISIONS_2026-08-03.md`)

**Vision** — you run a stable that produces the party; the player **never intervenes**, they set
tactics and watch; winning is completing **Tamers Apex**; the meta-game is training knowledge +
breeding.

**Settled:** tameness removed · innates + happiness kept and must be wired · arenas far larger,
**playing space** grows (not just the venue) · flat, no elevation · physics-based, fixed-step ·
auras **proximity-sized** · props carry semantic tags · crowd becomes **fans + merch** · The Read
and The Broadcast in, The Chalkboard out · classes become **assignable, stat-gated** · 3-tier
caps · species aptitude = RATE, class cap = CEILING · doctrine **layers over** cohesion×predation
· **30 classes, 10 roles** · Berserker moves to STR/DEX · Guild Colours approved · re-baseline
when the arena is sized · playtest when arenas work.

**⚠️ Roles are coarser than classes on purpose.** A crowded role is the layer working. The test
for a new role: a different thing to DO, not a different way of doing it.

---

## 5. Open decisions — RESOLVED 2026-08-04 (all five; none of this is built yet — see each item)

1. ✅ **Deploy separation vs ground size — DECIDED.** Decoupled: `separation = TARGET_CLOSE_SECONDS
   (12) × SLOW_UNIT_SPEED (2.76) ≈ 33.1 units`, flat across every team size, independent of
   `GROUND_W(N)`. Full derivation, the per-N flank-margin table and the `OPENING_MIT_BONUS`
   follow-up it opens are in `docs/ARENA_BLUEPRINT.md` §2.
2. ✅ **Arena variety — DECIDED.** Scale/proportion/density scheme for varying arenas within one
   team-size pool, folded into `docs/ARENA_BLUEPRINT.md` alongside §1's ground table.
3. ✅ **STR/INT class name — DECIDED: `Warblade`.** Matches the roster's existing mundane/arcane
   mirror-naming convention (`Warrior`↔`Spellsword` → `Warblade`↔`Spellblade`). Applied throughout
   `docs/DOCTRINES_AND_CLASSES.md`, including a knock-on fix to the STR/DEX row (`Skirmisher` →
   `Berserker`/Duellist) that the earlier swap had left stale. Doc-only — no source file touched;
   the 30-class expansion itself is still a proposal.
4. ✅ **The 9 aura innate fields — design DECIDED** (radius/cadence/stacking,
   `docs/INNATES_ON_FIELD.md` §2 Group K/L). Implementation is correctly understood to be a
   multi-stage engine-wiring project (Groups A/C/D/H/B aren't wired in `engine.ts` at all yet),
   not a 9-field add-on — queued for a programmer, not done.
5. ✅ **Meta-game disposition — WRITTEN.** `docs/META_GAME_DISPOSITION.md` goes system-by-system
   through `town.ts`/`game.ts`/`monster.ts` against the decided "3D ranch + UI overlay" model and
   leaves 5 concrete open questions for the next pass (tick presentation, feeding interaction,
   training-station granularity, lab/Hall-of-Fame presence, port trigger condition).

---

## 6. Where the design lives

| doc | what |
|---|---|
| `CLAUDE.md` | vision, standing rules, file map — **always current** |
| `DECISIONS_2026-08-03.md` | every decision + its reasoning |
| `OUTSTANDING.md` | unfinished / weak / unchecked, in three sections |
| `TECHNICAL_ISSUES.md` | the technical audit |
| `ARENA_BLUEPRINT.md` | ground + venue sizes, SPREAD formula ⚠️ needs the §2 rethink |
| `MECHANICS_REWORK.md` | what a large field needs ⚠️ carries a correction at the top |
| `DOCTRINES_AND_CLASSES.md` | 10 roles, 30 classes, derived from line data |
| `CLASS_REWORK.md` | assignable classes, stat gate, caps |
| `SPATIAL_MODEL.md` · `ENGAGEMENT_DESIGN.md` | spatial layers · the chase problem |
| `ABILITY_BALANCE_REVIEW.md` · `POOL_AUDIT.md` | the pool at scale · `pool.ts` calibration |
| `FUN_ADDITIONS.md` · `ART_THEME.md` · `ART_PRODUCTION.md` | fun · Guild Colours · production |
| `INNATES_ON_FIELD.md` | the 31 innate effect kinds and their port status |
| `GODOT_MIGRATION.md` | what ports, what is rebuilt, what is thrown away |

---

## 7. Three measurements worth more than more design

1. **Scale the field 2× and 4×, run `sweep40`.** Quantifies the diffuse-fight risk before anyone
   designs against it. Structural, so do it before the re-baseline.
2. **Watch ten fights and write down whether they were fun.** ⚠️ Still the biggest unchecked
   assumption in the project — and sharper now, because with no intervention, watching IS the
   game. There is not one playtest record in the repo.
3. **Time a headless physics fight.** If physics ties the sim to real time, `sweep40` goes from
   seconds to hours and the instrument dies of cost rather than noise.

---

## 8. Numbers worth remembering

- **1,708 matches** available across a Wood→Apex career (~214/year) — compression is a blocker
- **`maxHp = 40 + CON×2 + CON²/1600`** — quadratic; the docs said linear until today
- **CON control-resist saturates at CON 900** = the Platinum cap, so CON buys nothing above it
- **7 of 18 ability lines are never any class's primary** — the 30-class set is the repair
- **`pool.ts` now flags 4** (was 0): Duelist 10.7× · Assassin 10.6× · Bloodrage 9.7× · World Ender
