# Tactics — Progressive Disclosure Map

**Status:** design spec, not yet implemented (2026-07-25).
**Problem it solves:** the tactics layer (wave 1 + wave 2) currently shows every
control at full complexity from a fresh Wood 1v1 monster, where almost none of it
applies — and the whole layer is buried behind "⚔ Edit Abilities", so most players
never discover it. This map defines *what shows when*, keyed to real game state, so
the panel grows with the player instead of front-loading everything.

The `targetPriority` Copper-license lock (`town.ts:teamTacticsUnlocked`) is already
shipped and is the proof-of-pattern this extends to the rest of the surface.

---

## The three treatments

Every control is assigned exactly one, deliberately:

- **Always** — shown from turn one (reads instantly, matters even in 1v1).
- **Hidden** — not rendered until its reveal predicate is true. Used when the thing
  becomes earnable through a *quiet* action (training a stat, learning a move) with
  no obvious "you'll get this later" signal to anchor a lock to.
- **Lock-with-hint** — rendered but disabled, with a `🔒` + "unlock by…" hint. Used
  when there's a *visible milestone* to anticipate (a license), so the lock builds
  intent rather than nagging.
- **Absent (context-only)** — not a dial in the editor at all; only exists inside a
  specific screen the player isn't on yet (team-event sign-up / scouting).

**Invariant:** every Hidden / Absent / Locked control's unset state MUST produce
byte-identical battles (already true — wave 1/2 defaults are inert, pinned by the
golden battle tests). Hiding a control can therefore never change behaviour.

---

## The map

| Control | Where | Treatment | Reveal predicate (real state) | Why then (relevance) | Unset default (inert) |
|---|---|---|---|---|---|
| **Temperament** | AbilitySelector | Always | — | Block/heal/parry timing matters even at Wood 1v1; the one dial that reads instantly. | `balanced` = all-zero deltas |
| **Opening move** | AbilitySelector | Hidden | `m.loadout.length >= 2` | Loadout becomes a *sequence*, not a bag — "which move first" only exists with ≥2 equipped. | `openerId` absent = 🎲 Instinct |
| **Mana policy** | AbilitySelector | Hidden | `m.loadout.filter(mv => manaCost(mv) > 0).length >= 2` | MP management is only a real choice once there's >1 skill competing for a limited pool. | `manaPolicy` absent = Natural (zeros) |
| **Combo play** | AbilitySelector | Hidden | a learned payoff (`mv.effects?.bonusVsStatus`) AND a learned move whose `status.kind` matches that payoff's `bonusVsStatus.kind` both exist in `m.learned` | The setup→payoff pair exists; discipline converts it from ~14% opportunistic to deliberate. Reveal on *learned* (not equipped) so the player is prompted to equip both. | `comboDiscipline` absent/false = Free play |
| **Target priority** | AbilitySelector | Lock-with-hint | `teamTacticsUnlocked(g)` (any stable/frozen monster holds the `firstTeamLeagueIndex()` license — currently **Copper**) | Priorities are meaningless with one enemy; they start mattering at the first team league. **(shipped)** | forced `weakest` while locked |
| **Formation** | TeamPicker (sign-up) | Absent | `teamSizeForLeague(t.league) > 1` (you're on a team-event sign-up) | Roster ORDER is the formation; it only exists when you field >1 monster. | solo team = all front row |
| **Protect target** | Sign-up panel (signed block) | Absent | `signedHere && signedMonsters.length > 1` | A "guard this one" order needs a team to guard with. **(shipped)** | no `protectId` = nobody guarded |
| **Mark target** | Scout panel (per rival) | Absent | `signedHere && rival team length > 1` | A kill order needs a multi-monster enemy to single out, and intel to act on. **(shipped)** | no `marks[r]` = normal priority |

---

## Discovery beats

Per-control reveals don't help if the player never learns the *layer* exists. Three
one-shot beats, all via the existing `TipBanner` / `GameState.tipsSeen` system
(same as the `signup` / `injury` / `rankup` tips):

- **Beat A — the master discovery.** First tournament sign-up (any league), tip id
  `tactics`: *"Your monsters fight on standing orders you set. Open ⚔ Edit Abilities
  to coach how they fight."* Even at Wood — where only Temperament is visible — this
  is what points a main-loop player into the layer at all. Sits alongside the
  existing `signup` tip.
- **Beat B — the combo unlock.** The first time a monster's learned moves satisfy the
  Combo-play predicate, mark the newly-appeared "Combo play" group header with a
  small `NEW` pip (not another full banner — avoid banner fatigue). The reveal itself
  is the teaching.
- **Beat C — team play arrives.** First team-event (Copper) sign-up, tip id
  `formation` on the TeamPicker: *"Slot order is your formation — the front line
  shields the back. Melee can't reach the back line until the front falls."* This is
  the one deep rule that otherwise hides in a single grey hint line.

---

## Player timeline (the sanity check)

The order a typical player actually meets these — no dead ends, no cliff where four
brand-new dials land at once:

| Moment | Editor gains | In-context gains | Discovery |
|---|---|---|---|
| Wood, fresh monster | **Temperament** only | — | — |
| Wood, first sign-up | — | — | **Beat A** (tip: the layer exists) |
| After training fills the kit (`loadout` ≥2 moves, ≥2 castable) | **Opening move**, **Mana policy** | — | (reveals speak for themselves) |
| Learns a setup→payoff pair (any league) | **Combo play** | — | **Beat B** (NEW pip) |
| Earns **Copper** license | **Target priority** becomes *usable* (was visible-but-locked) | — | — |
| First **Copper** team sign-up | — | **Formation** (slot rows), **Protect** picker, **Mark** (when scouting) | **Beat C** (formation rule) |

**Cliff check:** Copper is the busiest moment, but it's manageable because the
*editor* only gains ONE newly-usable group there (Target priority — and it was
already on-screen, locked, so it reads as "now usable", not "brand new"). Formation /
Protect / Mark are introduced *in their own screens* by Beat C and the existing
"🛡 Protect:" / "🎯 Mark:" rows — never dumped into the editor. So no single screen
ever gains more than ~1 new decision at a time.

---

## Implementation notes

- **All predicates are already computable** from shipped hooks: `teamTacticsUnlocked`
  / `firstTeamLeagueIndex` (town.ts), `m.learned` / `m.loadout` (core), `manaCost`
  (monster.ts), `effects.bonusVsStatus.kind` + `status.kind` (move data),
  `pendingTournament` + `teamSizeForLeague` (town.ts). No new engine state required —
  this is a pure presentation gate over data that already exists.
- **AbilitySelector** takes the monster `m` and can derive every editor-side predicate
  locally; add a `revealed(control)` helper rather than scattering conditions. It
  already receives `teamTacticsOpen` for the Target-priority lock — extend that pattern.
- **Sandbox** stays fully open (every control revealed) — it's the testing ground; pass
  an `allRevealed` flag the same way it passes `teamTacticsOpen = true` today.
- **No behaviour change, ever:** because unset defaults are inert, the golden battle
  tests must stay green with zero recapture after this work. If a golden moves, a
  reveal accidentally changed a default — that's the regression signal.
- **Copy source of truth:** the `TEMPERAMENT_INFO` / `TARGET_PRIORITY_INFO` /
  `MANA_POLICY_INFO` / `COMBO_INFO` tables in core.ts already hold desc==data strings;
  reuse them for reveal copy so the panel and the map can't drift.

---

## Out of scope (deliberately deferred)

- **Reflecting orders back in battle** ("Corok targets the caster — your order" in the
  turn log; a post-battle "Your tactics" line). This is the *trust* half of the design
  review and is a separate task — disclosure makes tactics discoverable; feedback makes
  them believable.
- **Editor restructure** (Moves · Innate · Tactics tabs). Orthogonal to disclosure;
  worth doing but doesn't depend on this map.
