# Projectile authoring — speed, width and pierce for all 141 abilities

**2026-08-04.** Implements `docs/AUTOBATTLER_DESIGN.md` §12 #34 (full projectile data per
ability) and §8 #20 (aimed abilities: geometry decides the hit, accuracy governs the lead, no
double jeopardy). **PROPOSAL ONLY** — the data lives in `docs/data/projectiles.json`, keyed by
move name. Nothing in `src/moves.ts` or any other TypeScript was touched. `run_contract.sh`'s
`moves(141)` case is unaffected by this document.

---

## 1. Schema

```
{
  "aimed": bool,
  "projectileSpeed": number | null,   // world units/second
  "projectileWidth": number | null,   // world units
  "pierce": bool | null,
  "rule": string                      // provenance code(s), see §3
}
```

`projectileSpeed`/`projectileWidth`/`pierce` are `null` whenever `aimed` is `false` — a non-aimed
move keeps today's flat accuracy roll unchanged and never touches projectile geometry at all.

### Which world scale these numbers are authored against

⚠️ **This is the load-bearing caveat for the whole document.** `docs/ARENA_BLUEPRINT.md`
(same day, `M` in git status — a rescale in flight) fixes the 5v5 ground at **160×88** and
rescales every spatial constant in the pool by **`k(5) = 4.0`**: the `HARD` reach clamp moves
from `[2.4, 11.0]` to **`[9.6, 44.0]`**, `CHANNEL_RANGE` moves from melee 3.0/ranged 8.0/magic
7.0/support 6.0 to **melee 12.0/ranged 32.0/magic 28.0/support 24.0**, and `LINE_RANGE` is
rescaled per-line (Bloodrage 11.2, Volley 42.0, etc.). This document was instructed to author
against **that** rescaled world, and does — every speed and width value below assumes the
×4.0 world, not the world `src/moves.ts`'s own `range` field currently describes.

**The consequence: `src/moves.ts`'s `range` field is NOT yet rescaled** (`tools/authorranges.ts
--force` is still pending per `ARENA_BLUEPRINT.md` §9 item 4). So today, in the live TypeScript
data, `range` values run **2.4–11.7** while this document's `projectileSpeed`/`projectileWidth`
run against a world where reach runs **9.6–44.0**. That is a real, live mismatch, not an error in
either document — they were authored on different days against different scales, and one of them
(the rescale) is not yet applied. **Before this data is integrated, confirm which state
`src/moves.ts`'s `range` field is in:**
- If `authorranges.ts --force` has already landed (range rescaled ×4.0) → these values are
  already in the right scale, use them directly.
- If it has not landed yet → either (a) hold this data until it does, or (b) divide every
  `projectileSpeed` and `projectileWidth` value below by 4.0 to match the *current*,
  not-yet-rescaled `range` field. Do not mix scales — a projectile authored at speed 45 (this
  doc's world) crossing a `range: 8.4` field (today's unscaled Volley) would arrive in 0.19s,
  which is not what either document intended.

### Unit justification

| quantity | anchor | why these numbers |
|---|---|---|
| `projectileSpeed` (15–65 range used here) | unit movement speed is **2.4–6.0 u/s**, explicitly *unscaled* by the ×4.0 rework (`ARENA_BLUEPRINT.md` §3 — "rates and durations are not spatial") | A projectile must be meaningfully faster than the fastest monster (6.0 u/s) or leading becomes trivial in one direction and impossible in the other. At 45 u/s, a shot crossing Volley's new 42.0-unit reach takes ~0.93s, during which even a max-speed target displaces ≤5.6 units — enough for `accuracy` (aim quality) to matter, not enough to make ranged attacks unreliable against anything slower. At the LOBBED tier (17–25 u/s), the same flight stretches to 1.7–2.5s and target displacement grows to 10–15 units — a real, visible dodge window, matching "a lobbed boulder and a snap bolt genuinely differ." |
| `projectileWidth` (1.0–7.2 range used here) | monster collision radius is **0.9** (`ARENA_BLUEPRINT.md` §1) | A narrow bolt (1.0–1.5) is roughly one body-width — a called shot that must actually line up. A wide AoE blast (4.5–7.2) comfortably covers a TIGHT-spread cluster (TIGHT diameter at 5v5 is 38.7, so a 7.2-wide capstone blast is a meaningful fraction of a clustered formation, not the whole board) without being reduced to a formality. |
| `pierce` (bool) | solid bodies + front lines are decision #10 of `AUTOBATTLER_DESIGN.md` ("a front line genuinely shields a back line") | `pierce` is the spatial mechanic that decides whether that shield actually works against a *given* ability — `pierce: false` means an intervening enemy body can catch a shot meant for whoever is behind it; `pierce: true` means the shot ignores what's in the way and reaches its intended target(s) regardless. This is a genuinely new axis of ability identity, not a cosmetic flourish — see §4. |

---

## 2. The default rule

Not 141 arbitrary judgements. Every value is derived from three fields already authored on
every move — `channel`, `target`, `variance` — via one formula, applied uniformly, with a short,
named, auditable list of hand corrections where a line's or a move's own flavour text
contradicts the formula's output.

### 2.1 — `aimed`

```
aimed = channel != 'melee'  AND  target in {'enemy', 'allEnemies'}
```

- **`channel: melee`** is always `aimed: false`. There is no projectile in flight to intercept —
  a melee swing resolves at contact range, and it stays a standard accuracy roll exactly as
  today. This is also the direct enforcement of "no double jeopardy" (§8 #20 of the design doc):
  melee was never "aimed" in the new sense, so nothing about it changes.
- **`target: self | ally | team`** is always `aimed: false`, regardless of channel. A friendly
  delivery never has to catch a resisting, moving body.
- Everything else — `ranged`, `magic`, `voice`, and **`support`-channel moves that target a
  hostile** (WIS's whole "psychic" damage/debuff/control vocabulary uses `channel: 'support'`
  even though it is aimed at an enemy — Silencing Spike, Hush, Mind Crush, Taunt) — is `aimed:
  true`.

**71 of 141 moves are `aimed`; 70 are not.** The split is not even across stats — it falls almost
entirely out of channel mix, which is itself a deliberate identity signal already in the pool:

| stat | aimed | not aimed | why |
|---|---|---|---|
| STR | 2 | 22 | almost pure melee + self-buffs; only the two Warcry *voice* moves (Intimidate, Challenge) are aimed |
| DEX | 20 | 4 | ranged-channel stat; only the three self-buff Volley moves (Sidestep, Acrobatics, Focus Aim) and Vanish are excluded |
| CON | 2 | 21 | tanky/melee/protective; only Taunt and Bulwark's Challenge (both hostile `support`-channel "presence" effects) are aimed |
| WIS | 13 | 10 | mixed — Mender's ally-healing (5 of 6) is excluded, Disruptor/Siphon's hostile psychic kit is aimed |
| INT | 20 | 3 | magic-channel stat; only Firewall, Phase Step, Mirror Image (self-target) are excluded |
| CHA | 14 | 10 | Captain (pure empowerment, 10 moves) is entirely excluded; Enchanter/Demagogue (hostile voice) are entirely aimed |

CON and STR landing at 2 aimed moves each is not an artefact — it is the same finding
`ABILITY_REWORK.md`/`CLAUDE.md` already made about these stats (CON is "the only stat with NO
hard CC by design," STR's control "comes through the voice, not the blade") arriving again from
a completely different angle. Melee-heavy, protective stats were never going to have much
projectile geometry to author.

### 2.2 — `projectileWidth`

**Single-target (`target: 'enemy'`):**
```
width = clamp(1.0 + variance × 4.0, 1.0, 3.2), rounded to 1 decimal
```
`variance` (the existing half-width-of-damage-range field) is repurposed as a precision proxy: a
tight damage roll (Deadeye, variance 0.05 → width 1.2) is a called shot that must actually line
up; a wild spread (Gambler's Volley, variance 0.5 → width 3.0) is forgiving to land, which is the
same trade its damage already makes. This reuses an authored field instead of inventing a new
judgement per move, and it produces the correct ordering without any manual tuning: precision
lines are narrow, volume/gambling lines are wide.

**Fallback (single-target, no authored `variance`):** ten moves are pure status/debuff/control
with `power: 0` and no damage roll to derive precision from (Enfeeble, Hush, Field of Doom, Dread
Whisper, Sap Will, Curse of Ruin, Unmake, Taunt, Challenge, Lullaby). These get a flat **1.6**
width — the value a `variance ≈ 0.15` bolt (the pool's own default variance) would produce, i.e.
"an ordinary bolt," not a judgement call per move.

**AoE (`target: 'allEnemies'`):**
```
width = baseWidthByChannel(channel) + power × 0.02, capped at 10.0
   baseWidthByChannel: ranged = 5.0, magic = 5.5, voice = 4.5, support = 4.5
```
An AoE's width represents its effective blast/effect radius rather than a shot's precision, so it
is driven by channel (a spell nova reads slightly larger than an arrow-fall; a voice/presence
effect reads slightly smaller than either, being closer to a personal aura than a thrown weapon)
plus a small bump from `power` so the biggest capstones (World Ender, 7.2) read visibly larger
than a level-160 opener (Intimidate, 4.5).

### 2.3 — `projectileSpeed`

```
base(channel): ranged = 45, magic = 32, voice = 42, support(hostile) = 38
```
Ordering is deliberate: `ranged` (physical arrows/bolts, purely kinetic) is fastest; `voice`
(sound) is close behind; `support`-channel hostile effects (WIS's willed psychic push) sit a step
under voice; `magic` (a spell has to coalesce before it travels) is the slowest baseline —
consistent with Elementalist and Hexer's capstones being explicitly described as eruptions/
detonations rather than snap shots (see line modifiers below).

### 2.4 — `pierce`

```
default: target == 'enemy' → false   |   target == 'allEnemies' → true
```
A single-target shot is stopped by whatever it first collides with — this is what makes a front
line matter at all against most kits. An AoE is not "blocked" by a body in the conventional
sense; it resolves against everyone inside its footprint by definition, so `pierce: true` here is
confirmatory of existing `target: allEnemies` semantics, not a new mechanic.

---

## 3. Exceptions — the hand-corrected departures, named and justified

**21 of the 71 aimed moves (≈30%) carry at least one hand correction.** Kept to line-level and
capstone-level groups rather than per-move guesswork, because a line is a shared win condition
(`src/lines.ts`) and its projectile behaviour should read as consistently as its reach does.

### 3.1 Speed exceptions (15 moves)

| tag | moves | modifier | why |
|---|---|---|---|
| `SNAP` (Assassin line) | Shadowstep, Ambush, Smoke Bomb, Hamstring, Throat Cut, Heartseeker | channel base **+15** | Stealth-burst is the line's entire identity — "the only reliable way past a front line" reads as fast and decisive, not measured. Applied to the whole line (not per-move) because it is a *line* trait. |
| `SNAP` (Deadeye) | Deadeye | ranged base **+15** | "One shot. It goes exactly where it was sent" — a called shot is fast once released, even though its 7.8s cooldown represents a long charge-up. Not part of the Assassin line, so authored individually. |
| `ARTILLERY` | Rain of Arrows, Pinning Volley, Plague Shot | channel base **−20** | Explicit "bombardment," "onto a chosen patch of ground," "nails several of them to the spot" flavour — these are lobbed, not snapped, and the slower flight is the mechanism that makes them dodgeable by a fast target that reads the incoming arc. |
| `GROUNDERUPT` | Frost Nova, Inferno, Seismic Crush, World Ender | magic base **−15** | "A ring of hoarfrost bursts outward," "the ground itself comes up" — these erupt from/around the target area rather than travelling as a compact bolt; the whole Elementalist AoE sub-group reads as slower-building than a Hexer or Arcanist bolt. |
| `DETCAP` | Detonate | magic base **−10** | "Sets off everything still burning" — a triggered detonation, not a snap cast; smaller penalty than GROUNDERUPT since it is one move, not a line-wide identity. |

### 3.2 Pierce exceptions (9 moves)

| tag | moves | why |
|---|---|---|
| `PIERCE-LINE` (Assassin) | Shadowstep, Ambush, Hamstring, Throat Cut, Heartseeker (Smoke Bomb is already `true` by the AoE default) | The line's stated job is bypassing a front line. If Assassin bolts stopped at the first body, the line could never do the one thing it exists to do — this is not a flavour nicety, it is the mechanical expression of the line's win condition. |
| `PIERCE-NAME` | Piercing Shot | The move is *named* "Piercing Shot." A literal, easily-audited exception — if this one doesn't pierce, the name is a lie the player will notice. |
| `PIERCE-CAP` | Deadeye | "It goes exactly where it was sent" — the capstone marksman shot is not stopped by incidental cover. |
| `PIERCE-VOID` | Void Lance | "Pure void. Half of everything they are wearing simply does not apply." Its existing `effects.pierce: 0.5` is *armour* penetration (an unrelated field, see §6.2) — this is the flavour argument for extending the same idea to physical obstruction. |
| `PIERCE-CALL` | Displace | The move must reliably connect with its called target to teleport it ("rips a diver out of your back line") — if it could be intercepted by an incidental body, the move would sometimes grab the wrong target or whiff its entire purpose. |

### 3.3 Width exceptions (2 moves)

| tag | moves | why |
|---|---|---|
| `CHAINWIDTH` | Static Chain, Ricochet | Both are `target: allEnemies` and would default to the wide AoE blast formula, but both are explicitly *chain/bounce* flavour ("leaps body to body along a line," "it bounces... does not much care whose") rather than a blast — a chain is narrow, not wide. These use the single-target `variance`-derived width formula instead (Static Chain 1.8, Ricochet 2.2) while keeping `pierce: true` from the AoE default, which is the correct mechanical expression of "hits several bodies via a narrow path," not "hits several bodies via a wide radius." |

---

## 4. Balance implications — stated honestly, not re-tuned

⚠️ **The balance baseline is SUSPENDED (`CLAUDE.md`).** Nothing below is a request to change any
number in `src/moves.ts`, `combat.json` or the damage tiers. This section exists to flag the risk
for the deliberate, later re-baseline pass — re-tuning now, against a system that is not built,
is exactly the mistake that suspension exists to prevent.

**The core risk is real and asymmetric.** Today, every ability resolves against a flat accuracy
roll — hitting a mobile target costs a ranged attacker nothing extra. Under this design, 71 of
141 moves now also have to *geometrically* connect, which is a strictly harder bar than "pass an
accuracy check" whenever the defender is moving fast enough to matter. **This is a real nerf to
every aimed line, and it was never priced into the median effective DPS figures** (STR 42.6 · DEX
38.2 · INT 35.2 · CON 28.0 · CHA 26.8 · WIS 22.8) — those numbers assume today's flat-roll model.

**Which lines are most exposed, ranked:**

1. **DEX Venomcraft and Volley (non-Assassin, non-exception moves) — highest exposure.** DEX is
   the stat whose own kit-mates are the *fastest movers in the game* (DEX drove `speed_of(dex)`
   before it became independent — see `AUTOBATTLER_DESIGN.md` §4). A DEX archer standing off at
   its 42.0-unit Volley reach, shooting at *another* fast DEX target, is the single worst-case
   pairing for geometry-based leading: both the shooter's aim-quality problem and the target's
   evasion are governed by the same stat, so a DEX mirror match should see the largest accuracy
   erosion in the pool. These moves have **no pierce or speed exception** (only Assassin and
   Deadeye do) — they are the control group for how hard the base formula bites.
2. **WIS Disruptor's hard CC (Hush, Dread Whisper, Field of Doom, Silencing Spike, Mind Crush) —
   second highest, and the most mechanically consequential.** These were previously guaranteed to
   at least attempt a lock on their intended target every time (flat accuracy roll, target choice
   never in question). They are now geometry-dependent for the first time. `Hush`/`Dread Whisper`
   are WIS's *only* hard control (§ design notes in `moves.ts`) — if a kiting DEX target can now
   simply out-run WIS's lockdown tools, WIS loses its one counter to exactly the archetype this
   list already flags as highest-risk (#1), which would be a genuine rock-paper-scissors gap, not
   a tuning nit.
3. **INT Elementalist and Hexer's `GROUNDERUPT`/`DETCAP` AoE — lower risk, opposite direction.**
   These are wide (5.5–7.2 width) and, being AoE, do not need to intercept a single moving body —
   width alone absorbs most of the accuracy cost geometry would otherwise impose. If anything
   these are UNDER-exposed relative to single-target aimed moves, which may look like a relative
   buff to AoE casters once this lands, worth checking specifically.
4. **CHA Enchanter/Demagogue AoE CC (Screech, Cacophony, Mass Hysteria, Dirge, etc.) — same
   direction as #3.** Wide width, AoE pierce, and CHA's control kit was already the most CC-dense
   stat in the pool; geometry cost here is small for the same reason as INT's AoE.

**What this is NOT flagging:** single-target melee (STR/CON, `aimed: false` throughout) is
entirely unaffected — this design change cannot touch 44 of the pool's melee moves at all, which
is a second-order balance shift in itself (melee becomes *relatively* more reliable against a
fast target than any single-target ranged/magic/voice move, purely because it never rolls
geometry). That shift compounds with #1 and #2 above rather than being independent of them.

**The honest summary for whoever re-baselines:** this system, once built, will most likely
require (a) a genuine buff to DEX's non-Assassin, non-Deadeye lines to compensate for the
geometry tax paid by the stat whose own targets are hardest to hit, and (b) a specific look at
whether WIS's hard CC still functions as a kiting counter once it can be dodged. Neither should be
guessed at now — both are `sweep40`/`ab.ts` questions once the spatial layer and aim-quality
formula actually exist.

---

## 5. Rule code legend (for `docs/data/projectiles.json`)

| code | meaning |
|---|---|
| `MELEE` | `aimed: false` — melee channel, contact-range, no projectile geometry |
| `FRIEND` | `aimed: false` — target is self/ally/team, never resists geometrically |
| `SINGLE` | `aimed: true`, single-target baseline (width from `variance`, base channel speed, `pierce: false`) |
| `AOE` | `aimed: true`, `target: allEnemies` baseline (width from channel+power, base channel speed, `pierce: true`) |
| `NOVAR` | width defaulted to 1.6 — move has no authored `variance` to derive precision from |
| `SNAP` | Assassin-line or Deadeye speed **+15** |
| `ARTILLERY` | bombardment-flavoured AoE speed **−20** |
| `GROUNDERUPT` | Elementalist ground-effect AoE speed **−15** |
| `DETCAP` | Hexer's Detonate speed **−10** |
| `PIERCE-LINE` | Assassin-line pierce override → `true` (front-line bypass is the line's identity) |
| `PIERCE-NAME` | Piercing Shot pierce override → `true` (literal name) |
| `PIERCE-CAP` | Deadeye pierce override → `true` (capstone precision) |
| `PIERCE-VOID` | Void Lance pierce override → `true` (armour-pierce flavour extended to spatial) |
| `PIERCE-CALL` | Displace pierce override → `true` (must reliably reach its called target) |
| `CHAINWIDTH` | Static Chain / Ricochet use the single-target width formula despite being AoE-targeted (chain/bounce flavour, not a blast) |

---

## 6. What integrating this into `src/moves.ts` would require

### 6.1 — Mechanical steps
1. Add `aimed`, `projectileSpeed`, `projectileWidth`, `pierce` to the `Move` type in `core.ts`
   (all optional/nullable, since `aimed` is only meaningful once the spatial/aiming system that
   consumes it exists).
2. Add the four fields to each of the 141 rows in `src/moves.ts`, using the values in
   `docs/data/projectiles.json` — **after** resolving the scale question in §1 (confirm whether
   `authorranges.ts --force` has landed and rescale this data ÷4.0 if not).
3. Regenerate `monster-tamer/data/data.json` (the `moves(141)` table gains four columns) and
   extend the corresponding contract case in the Godot port to check them.
4. Rename the new spatial `pierce` field before it lands next to the *existing*
   `effects.pierce` (armour-penetration percentage, e.g. Titanfall, Void Lance, Reckless Slam) —
   **these are two different mechanics that happen to share a name.** `effects.pierce` already
   means "ignores N% of the target's mitigation." The new field means "ignores intervening bodies
   in its flight path." Landing both as `pierce` on the same `Move` object (one at the top level,
   one inside `effects`) is a foot-gun for the next person reading the type — recommend the new
   field be named `spatialPierce` (or similar) at integration time. This document uses the bare
   `pierce` key throughout for readability, on the understanding that the integrator renames it.
5. Build (or stub) the aim-quality formula the accuracy stat feeds into for `aimed: true` moves —
   this document only supplies the *geometry inputs* (speed/width/pierce); it does not specify how
   `accuracy` converts into a probability of leading a moving target correctly. That is a
   `systems-designer` formula, not a data-authoring task, and is the actual mechanism the balance
   risk in §4 depends on.

### 6.2 — Does this move any contract case?

**No, not by itself.** `run_contract.sh`'s `moves(141)` case currently checks the fields already
on `Move` (name, learnLevel, type, channel, target, cooldown, accuracy, power, mana, variance,
range, effects, status, line). Adding four new optional fields to the TypeScript `Move` type and
to `data.json` does not change any of those existing values, so the existing contract case is
unaffected as written. **It WOULD move the contract** the moment step 2 above is actually done
(the TypeScript rows are edited) — at that point `data.json`'s `moves` table gains new columns
and whoever ported the Godot side's `moves(141)` case needs to extend it to check the same four
fields, or the port silently stops verifying them. That extension is new work, not a value that
moves under the existing check — nothing here is "the same test now returns something different,"
it is "the test needs four more columns to still be complete."

---

## 7. Summary for the report

- **71 of 141 moves are `aimed`**; 70 are not (melee + all self/ally/team moves).
- **Default rule**: `aimed` from `channel`+`target`; `projectileWidth` from `variance` (single) or
  `channel`+`power` (AoE); `projectileSpeed` from `channel` base; `pierce` from `target`
  (single=false, AoE=true).
- **21 of 71 aimed moves (≈30%) carry a named exception** — 15 speed exceptions (2 line/capstone
  SNAP groups, 3 ARTILLERY, 4 GROUNDERUPT, 1 DETCAP), 9 pierce exceptions (5 from the Assassin
  line, 4 individual: Piercing Shot, Deadeye, Void Lance, Displace), 2 width exceptions
  (Static Chain, Ricochet — chain flavour, not a blast). None are per-move guesswork; all trace to
  a line's stated identity or a move's own name/flavour text.
- **Highest balance risk**: DEX Venomcraft/Volley (excluding Assassin and Deadeye) facing another
  fast DEX target — worst-case pairing for the new geometry tax, and not currently priced into the
  median DPS figures. Second: WIS Disruptor's hard CC (Hush, Dread Whisper) becoming dodgeable for
  the first time, which may remove WIS's only counter to a kiting archetype. Full reasoning in §4.
  **No numbers were re-tuned to address this** — flagged for the deliberate re-baseline pass only.
- **Integration does not move any existing contract case by itself**; it WILL require extending
  the Godot port's `moves(141)` contract case once the TypeScript rows are actually edited, and it
  surfaces a real naming collision (`pierce`, spatial vs. the existing armour-pierce `effects.pierce`)
  that the integrator should resolve by renaming the new field — recommended `spatialPierce`.
