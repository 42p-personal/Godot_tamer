# Game modes — the seam, not the modes

**2026-08-04.** Implements `docs/AUTOBATTLER_DESIGN.md` §1 #2: *"Modes are pluggable. v1 is Team
Deathmatch. King of the Hill and Capture the Flag come later, varying by cup. Build the mode seam
now, not the modes."*

⚠️ **NOTHING HERE IS BUILT.** This is the interface contract that `spatial_sim.gd` and
`spatial_ai.gd` should be rewritten *against* (§12 #32/#33 put both files in scope right now), so
that adding King of the Hill later is authoring a mode, not rewriting the simulation.

**Scope:** what a mode supplies, how it reaches the behaviour tree, what it needs from the frame
stream, how it attaches to the ladder, and how it stays deterministic. Team Deathmatch is expressed
in the interface to prove it is not vacuous; KotH and CTF are sketched in it to prove it holds.

---

## 0. The finding that shapes everything else — ⚠️ read this before the interface

**The leash mathematically forbids objectives, and it is not a small effect.**

`spatial_sim.gd:_apply_leash` clamps every unit's *desired position* into a circle of
`Spatial.leash_radius(team_size, spread)` around the **centroid of all living units on both sides**.
At 5v5:

| | radius | circle area | share of the 160×88 ground |
|---|---|---|---|
| `formation: tight` | **19.4** | 1,178 | **8.4%** |
| `formation: loose` | **33.4** | 3,513 | **24.9%** |

`ARENA_BLUEPRINT.md` §4 states this as a *feature* — *"a fight never uses more than half the board,
leaving the rest for flank routes and cover."* It is also, exactly, the blob:

- Any objective further than 19–33 units from the living centroid is **unreachable**. A unit ordered
  to contest it walks toward it, gets clamped back, and re-derives the same desired position next
  tick — **the "wandering in circles" failure `AUTOBATTLER_DESIGN.md` §10 names by name**, produced
  by our own code rather than by a bad AI.
- Any objective *inside* that circle is inside the blob already, so it delivers **zero** of the
  anti-blob value §5 promises.
- And the system is self-reinforcing: the centroid is defined by where the units are, and the leash
  keeps the units where the centroid is.

**The fix is one line of the seam and it costs nothing in Team Deathmatch:**

> ⚠️ **The leash anchor becomes the unit's own assigned goal point when it has one, and the fight
> centroid when it does not.**

In TDM no goals exist, every unit's anchor is the centroid, and behaviour is **byte-identical to
today**. In KotH the two or three units assigned to the hill are leashed *to the hill* — they can
actually get there — while the screening units stay leashed to the fight. That is the anti-blob
lever working, and it is available only if the leash is mode-aware.

⚠️ **This must be decided before `spatial_sim.gd` is rewritten.** Retrofitting it later means
reopening movement, which is the file every other workstream depends on.

---

## 1. The mode interface

A mode is a **plain GDScript class**, one file per mode in `scripts/modes/`, instantiated once per
fight. It owns its own state and nothing else. It never touches nodes, never reads the clock, never
calls `randf()`.

```gdscript
## scripts/modes/game_mode.gd — the abstract base. @abstract, no default behaviour worth inheriting.
class_name GameMode
extends RefCounted

# ── identity & configuration ────────────────────────────────────────────────
static func id() -> String                                        # "tdm" | "koth" | "ctf"
static func display() -> Dictionary                               # {name, icon, tell, howYouWin}
static func default_config(team_size: int, league: String) -> Dictionary

# ── setup, once, before tick 0 ──────────────────────────────────────────────
func setup(view: ModeView, cfg: Dictionary, mode_rng: RandomNumberGenerator) -> void
func deploy_bands(view: ModeView) -> Array                        # [] = use Spatial.deploy_positions
func default_team_plan(side: String) -> Dictionary                # tactics.gd vocabulary

# ── per decision tick ───────────────────────────────────────────────────────
func goals(view: ModeView) -> Array                               # Array[Goal], FIXED ORDER

# ── per sim tick, AFTER move+act, BEFORE the frame record ───────────────────
func advance(view: ModeView, events: Array) -> Array              # returns Array[ModeEffect]
func terminal(view: ModeView) -> Dictionary                       # {over, winner, endReason}

# ── presentation ────────────────────────────────────────────────────────────
func header() -> Dictionary                                       # static geometry, once, in the result
func frame_record() -> Dictionary                                 # per tick, into the frame stream

# ── policy the shared tick must respect ─────────────────────────────────────
func tick_policy() -> Dictionary                                  # {timeLimit, suddenDeathAt, ...}
```

### 1.1 `ModeView` — the read-only facade

⚠️ **A mode never sees `spatial_state`, `MonsterInstance` or the rng directly.** It sees a narrow,
read-only view. This is what makes a mode contract-testable in isolation and stops a mode quietly
becoming a second simulation.

```gdscript
class_name ModeView
# ground: Vector2                     # Spatial.ground_size(team_size)
# team_size: int
# obstacles: Array                    # as fought — a mode may not place a zone inside one
# now: float                          # sim seconds
# unit_count: int                     # ids 0..n-1, the sim's FIXED order
# side_of(id) -> String               # "A" | "B"
# pos_of(id) -> Vector2
# alive(id) -> bool
# hp_frac(id) -> float
# incapacitated(id) -> bool           # stunned / slept / feared-noAct
# living(side) -> PackedInt32Array    # ascending id order, always
```

### 1.2 `Goal` — what a mode publishes

⚠️ **A goal declares VALUE. It does not assign work.** See §2.

```gdscript
{
  "id":     int,        # stable for the goal's lifetime; goals array is in ascending id order
  "kind":   String,     # closed set — see below
  "side":   String,     # "A" | "B" — whose goal this is (a symmetric objective emits one per side)
  "point":  Vector2,    # where. For unit-anchored kinds, refreshed each tick from that unit's pos
  "radius": float,      # how close counts
  "unitId": int,        # -1, or the unit this goal is about (escort / deny / carry)
  "weight": float,      # 0.0–1.0 — how badly the mode wants this RIGHT NOW
  "label":  String,     # "Contest the Hill" — the intent string the renderer shows verbatim
}
```

**The goal kinds are a closed set, deliberately.** Each maps to behaviour the tree can already
perform, except `interact`, which is the one new leaf the whole system costs.

| kind | means | tree leaf it uses |
|---|---|---|
| `hold` | be inside `radius` of `point` and stay | existing move-to + hold |
| `reach` | get to `point`; done on arrival | existing move-to |
| `deny` | attack/pressure `unitId` | existing engage (an override on target choice) |
| `escort` | stay within `radius` of `unitId` | existing `guard` positional intent |
| `carry` | acquire the object at `point`, then serve the mode's follow-up goal | `interact` + move-to |
| `interact` | ⚠️ **the one new verb** — be within `radius` of `point` for `T` seconds, uninterrupted | **new leaf** |

⚠️ **`interact` is the honest cost of this design and it is the right cost.** It covers capture,
pickup, plant and channel with one authored leaf. Everything else is composition. A future mode with
a genuinely novel verb (a pushed payload, say) costs *one new kind + one new leaf + one line in the
assignment scorer* — bounded, and vastly cheaper than the alternatives in §2.

### 1.3 `ModeEffect` — the only way a mode changes the world

⚠️ **A mode may mutate its own state freely and sim state never.** It returns effects; the sim
applies them, in array order, at a defined point in the tick.

```gdscript
{"kind": "speedMult", "unitId": int, "mult": float, "tag": String}   # CTF: a carrier runs heavy
{"kind": "attachTag", "unitId": int, "tag": String}                  # "flagCarrier" — for the renderer & tree
{"kind": "detachTag", "unitId": int, "tag": String}
{"kind": "damage",    "unitId": int, "amount": float, "source": String}
{"kind": "log",       "event": Dictionary}                           # into the shared event log
```

**Keep this vocabulary tiny.** Every entry added is a new way for a mode to make the fight
unexplainable. Five is already generous; TDM uses none of them.

### 1.4 What a mode supplies, checklist form

| the brief asks for | where it lives |
|---|---|
| win/lose conditions | `terminal()` — returns `{over, winner: "A"\|"B"\|"draw", endReason}` |
| scoring | mode-internal state, surfaced via `frame_record()` and the result header |
| a clock | `tick_policy().timeLimit`; `terminal()` decides what expiry means |
| spawn/deploy rules | `deploy_bands()`; empty = today's `Spatial.deploy_positions` |
| objects and zones on the board | `setup()` places them; `header()` publishes the static ones; `frame_record()` publishes the live ones |
| what the AI should want | `goals()` |
| defaults for an un-briefed player | `default_team_plan()` |

---

## 2. ⚠️ How a mode talks to the behaviour tree — the crux

**Recommendation: a mode SUPPLIES GOALS. It does not inject subtrees and it does not weight
branches. One authored, mode-agnostic `Objective` subtree consumes the goals; a team-level
assignment step decides which unit serves which goal.**

### 2.1 The three-layer split

> **The mode declares value. The AI allocates effort. The tree executes.**

```
mode.goals(view)                    "the Hill is worth 0.8 to side A; it is at (80,26), r=8"
        │
        ▼
SpatialAi.assign_goals(...)         "given their orders and kits, units 2 and 4 go; 0/1/3 screen"
        │   one call per side per decision tick — the same shape as the existing team_focus()
        ▼
the behaviour tree, per unit        Objective → Move to point → Hold  ⟶  intent: "Contest the Hill"
```

### 2.2 Why goals, and not subtree injection

Subtree injection is the intuitive answer and it is the expensive one.

1. ⚠️ **Tactics already swap subtrees (§9). If modes swap them too, you get an N×M merge problem
   with no owner.** `dive` × KotH: does the KotH branch sit above or below the dive branch? Who
   wins when both want a position? Every new tactic then has to be re-checked against every mode.
   With goals there is exactly **one authority for tree shape (tactics) and one for tree inputs
   (modes)**, and they cannot collide.
2. **Decision #2 says modes vary by cup.** A cup config that swaps a *goal generator* is a thing you
   can ship and data-drive. A cup config that swaps *tree topology* is a thing that needs its own
   test matrix per league.
3. **The legibility argument that seems to favour injection actually doesn't.** §9's real claim is
   *"the active branch IS the explanation"* — and it survives intact here, because **the goal
   carries its own `label`** and the Objective branch composes its intent string from it:
   `Objective → Contest the Hill`. We get the readable branch name without a mode-authored subtree.
4. **Determinism is cheaper.** Goals are a fixed-order array from a pure function; the determinism
   harness covers one tree shape per tactic set, not one per (tactic × mode) pair.
5. **The rewrite is happening now.** One generic Objective subtree + one `interact` leaf, authored
   once against no modes at all, is a smaller ask than a subtree-grafting mechanism nobody yet
   needs.

### 2.3 Why not branch weighting

Pure weighting (option c) **fails this project's own legibility standard**. §6 requires the live
label to be the *reason*. A weighted tree shows `Engage` while the unit walks to the hill, because
"Engage" is the branch that won — the explanation lies. §9 rejects utility-only AI for exactly this
reason: *"0.73 beat 0.71 is not an explanation a player can learn from."* Weighting is fine *inside*
the assignment step (§2.4), where it never becomes a player-facing label.

### 2.4 ⚠️ Assignment is a TEAM decision, and this is the part that is easy to get wrong

If every unit independently reads *"hold the hill, weight 0.8"*, all five go to the hill and **the
objective produces a new blob on a smaller footprint.** The anti-blob lever inverts.

So goal→unit assignment is computed **once per side per decision tick**, exactly mirroring
`spatial_ai.gd:team_focus()` — which exists for the identical reason (`TACTICS_BRAINSTORM.md` §1:
*"target priority lives on the INDIVIDUAL, so five monsters agree only by coincidence"*). The
precedent is already in the codebase and already argued for.

```gdscript
## Deterministic. Iterates `living(side)` in ascending id order; every tie broken by lower id.
static func assign_goals(side_units: PackedInt32Array, view: ModeView, goals: Array,
        plan: Dictionary, orders: Dictionary) -> Dictionary   # unitId -> goalId (-1 = none)
```

**The scoring inside it** — utility scoring inside a node, per §9's division of labour:

- **the player's positional intent gates eligibility.** A unit on `contest` volunteers; a unit on
  `screen`, `guard` or `hold` does not. This is what keeps the order sovereign (§8 #28) — the mode
  never overrides a player's order, it only fills the slots the player left open.
- **kit fit.** A melee bruiser is a better `hold` contester than a Volley-line archer; the archer is
  a better `deny`. Reach and channel already tell us this.
- **cost to serve.** Distance to `point`, discounted like `TEAM_FOCUS_PULL` already discounts a
  distant team focus.
- **saturation.** `goal.radius` and body packing cap how many units a `hold` can usefully take (§5.3).
  Past the cap, additional volunteers score zero — this is the explicit anti-blob term.
- **personality.** `Discipline` raises the chance a unit serves the assignment rather than its own
  read; `Aggression` biases toward `deny` over `hold`.

⚠️ **Assignment must be sticky.** Re-assigning every 0.1s tick produces the classic objective
shuffle. Reuse the `sticky`/`reassess` commitment axis (§2A) — an assignment holds for a minimum
dwell unless the goal dies, the unit dies, or the goal's weight drops below a release threshold.

### 2.5 The two new positional intents

The mode axis the player controls is **not a new axis** — it is two new values on the existing
positional-intent axis (§2B: `push` / `hold` / `wings` / `dive` / `guard`):

| value | means | shown only when |
|---|---|---|
| `contest` | serve the mode's objectives; fight only what gets in the way | the cup's mode publishes goals |
| `screen` | ignore the objective; kill whatever comes near it | the cup's mode publishes goals |

In TDM neither appears, because there are no goals. **The tactics UI gains nothing in TDM and the
player learns the new options exactly when the ladder first hands them an objective cup** — which
is also the answer to *"how does a player know KotH is different"*.

### 2.6 The interface, restated in one paragraph

`spatial_sim.gd` calls `mode.goals(view)` once per decision tick and hands the array to
`spatial_ai.gd`, which calls `assign_goals()` once per side and then `choose_target()` /
`desired_position()` per unit **with the unit's assigned goal as a new parameter**. The tree's
Objective branch is selected when a goal is assigned and the unit's intent permits it; it emits its
`intent` and `reason` strings from the goal's `label` and the assignment's winning term. The mode
never sees the tree; the tree never sees the mode.

---

## 3. Team Deathmatch, expressed in the interface

⚠️ **The test of an abstraction is whether the trivial case is trivial in it.** TDM is.

```gdscript
class_name ModeTdm
extends GameMode

static func id() -> String: return "tdm"
static func display() -> Dictionary:
    return {"name": "Team Deathmatch", "icon": "⚔", "tell": "No objective. Last team standing.",
            "howYouWin": "Eliminate every rival monster."}

static func default_config(_team_size: int, _league: String) -> Dictionary:
    return {"timeLimit": 180.0}

func setup(_view, cfg, _rng) -> void:      _limit = float(cfg.get("timeLimit", 180.0))
func deploy_bands(_view) -> Array:         return []          # Spatial's own bands
func default_team_plan(_side) -> Dictionary: return {}        # whatever the player set
func goals(_view) -> Array:                return []          # ⚠️ THE WHOLE POINT
func advance(_view, _events) -> Array:     return []
func header() -> Dictionary:               return {"id": "tdm", "zones": [], "objects": []}
func frame_record() -> Dictionary:         return {}          # nothing to draw
func tick_policy() -> Dictionary:          return {"timeLimit": _limit, "suddenDeathAt": INF}

func terminal(view) -> Dictionary:
    var a := view.living("A").size()
    var b := view.living("B").size()
    if a == 0 and b == 0:  return {"over": true, "winner": "draw",  "endReason": "mutual"}
    if b == 0:             return {"over": true, "winner": "A",     "endReason": "elimination"}
    if a == 0:             return {"over": true, "winner": "B",     "endReason": "elimination"}
    if view.now >= _limit:
        if a != b:         return {"over": true, "winner": ("A" if a > b else "B"), "endReason": "clock"}
        return {"over": true, "winner": "draw", "endReason": "clock"}
    return {"over": false}
```

**What this proves, and what it costs.** TDM is ~25 lines, publishes an **empty goal array**, and
therefore leaves the tree, the leash anchor, the assignment step and the frame stream in exactly the
state they would be in with no mode system at all. **The seam's runtime cost in v1 is one empty
`Array` per tick.**

**What it also fixes.** Three things currently hardcoded into `spatial_sim.gd:run()` move into this
file where they belong and become inspectable: the 180s limit, the survivor-count tiebreak, and the
absence of an `endReason`. See §9 #1.

---

## 4. King of the Hill, sketched

```gdscript
static func default_config(team_size, _league) -> Dictionary:
    return {"timeLimit": 240.0, "scoreToWin": 100.0, "tickRate": 1.0,
            "contestedPolicy": "freeze", "hillRadius": _hill_radius(team_size),
            "rotateEvery": 60.0}
```

| element | design |
|---|---|
| **zone** | one circular hill. ⚠️ **Not at the ground's centre** — see below. |
| **advance** | count each side's living, non-incapacitated bodies inside the radius. Sole occupancy → that side accrues `tickRate × DT`. Contested → frozen (`freeze`) or both decay (`decay`); config, not code. |
| **terminal** | first side to `scoreToWin` wins (`endReason: "objective"`); elimination still wins instantly (`"elimination"`); at `timeLimit`, higher score, then survivors, then draw (`"clock"`). |
| **goals** | per side: `hold(hill, weight = f(deficit))` while not held; `hold` at lower weight while held; plus `deny(unitId)` on the enemy unit deepest inside the hill when the enemy is scoring. |
| **default team plan** | `{"positional": "contest"}` on roughly half the roster, `"screen"` on the rest — so a player who never opens the tactics screen still plays the mode. |
| **frame record** | `{"scoreA", "scoreB", "zones": [{"id", "pos", "radius", "controlling", "progress", "contested"}], "headline"}` |

### ⚠️ 4.1 A hill at the centre of the board reinforces the blob

The centre is where the leash already gathers everyone. Putting the objective there buys variety in
the *scoreboard* and **none in the shape of the fight** — which is the entire reason
`AUTOBATTLER_DESIGN.md` §5 lists objectives as an anti-blob lever.

**Place the hill on the vertical midline (`x = W/2`) at a varying `y`.** This is provably fair — the
deploy bands sit at `x = W/2 ∓ DEPLOY_SEPARATION/2`, so *every* point on `x = W/2` is exactly
equidistant from both bands — and it moves the fight off the centroid line. At 5v5, `y` ranging over
`[0.25·H, 0.75·H]` = `[22, 66]` puts the hill up to 22 units off centre, comfortably outside the
tight leash radius (19.4). **That is the whole anti-blob effect, and it only works because of §0.**

`rotateEvery` moves the hill to a new midline `y` on a fixed schedule, drawn from the **mode's own
rng stream** (§8). A rotating hill is also the cleanest answer to a team that turtles a won point.

### 4.2 Hill radius must be sized for bodies, not for looks

`Spatial.BODY_RADIUS` is 0.9 and `_separate()` pushes overlapping bodies apart every tick. A hill
too small to hold the units that want to stand on it becomes a shoving deadlock — §7 risk #2 at its
worst. Floor it at roughly `2.5 × BODY_RADIUS × sqrt(team_size)` (5v5 → ~5.0) and then **round well
up for readability**; ~8–10 at 5v5 is the honest starting point. ⚠️ **Measure it; do not assert it.**

---

## 5. Capture the Flag, sketched

CTF is the mode that stresses the seam hardest, which is why it is worth sketching now.

| element | design |
|---|---|
| **objects** | two flags at mirrored home points (`ArenaLayout`'s own 180°-rotational rule applies). A flag is `atHome` / `carried(unitId)` / `dropped(pos, returnAt)`. |
| **pickup** | goal kind `interact` — be within `radius` of the flag for `pickupTime` seconds. ⚠️ Interrupted by taking hard control, by design. |
| **drop** | on the carrier's death or hard-CC — a mode reacting to a sim **event**, which is why `advance()` takes `events` and not just the view. |
| **return** | a dropped flag returns home after `returnSeconds` at rest. |
| **capture** | carry the enemy flag to your own home while your own flag is home. `capturesToWin` decides the match. |
| **goals** | to the side without the enemy flag: `carry(enemyFlag)` + `escort(carrier)` once it is up. To the side whose flag is taken: `deny(carrierId)` + `hold(ownHome)`. |
| **effects** | `speedMult 0.85` + `attachTag "flagCarrier"` on the carrier — the only ModeEffect any of the three modes uses. |
| **terminal** | `capturesToWin`, elimination, or clock on captures-then-survivors. |

**Three decisions CTF forces, listed so they are not discovered during implementation:**

1. ⚠️ **Can a carrier cast?** `spatial_sim.gd` roots a unit for `Derive.cast_time_of(move)` while
   casting. A carrier who casts is a stationary target holding the match's win condition.
   **Recommend: a carrier may cast only moves with cast time 0** — legible ("she can't stop to
   throw a spell while running the flag"), and it makes carrier selection a real kit decision.
2. ⚠️ **Zero intervention + a long solo run is swingy.** One unlucky root at midfield loses a match
   the player cannot influence. Mitigations: short field (home points on the midline-mirrored inner
   third rather than at the back wall), or a dropped flag that must be *re-picked* rather than
   instantly returned. **This is a creative-director call, not mine.**
3. **The `escort` goal is where CTF earns its variety** — it is the only one of the three modes that
   makes a *unit* the place worth being, which is a genuinely different fight shape from TDM and
   KotH both.

---

## 6. What the frame stream must carry

⚠️ **The frame-stream contract is being redesigned right now (§12 #33), so this is input, not a
request to extend it later.** The governing rule from that section holds absolutely: **the renderer
must derive nothing.** A capture bar the renderer computes from unit positions will be subtly wrong
the first time `contestedPolicy` changes.

### 6.1 In the result header — once, static

```gdscript
"mode": {
  "id": "koth",
  "display": {"name": "King of the Hill", "icon": "⛳", "howYouWin": "..."},
  "config": {...},                 # the exact config fought, for replay
  "zones":   [{"id": int, "pos": Vector2, "radius": float, "kind": "hill"}],
  "homes":   [{"id": int, "pos": Vector2, "side": "A"}],   # CTF
}
```

Static mode geometry belongs beside `obstacles`, for the same reason: the renderer builds it once.

### 6.2 In every frame — live

```gdscript
"mode": {
  "scoreA": float, "scoreB": float,
  "clock": float,                        # seconds remaining, or -1 for none
  "zones":   [{"id": int, "controlling": "A"|"B"|"", "progress": float, "contested": bool,
               "occupantsA": int, "occupantsB": int}],
  "objects": [{"id": int, "pos": Vector2, "state": "home"|"carried"|"dropped",
               "carrierId": int, "returnIn": float, "side": "A"}],
  "headline": String,                    # "A holds the Hill · 62–41" — authored by the mode
}
```

⚠️ **`headline` is authored by the mode, not composed by the UI.** Same reasoning as `intent` and
`reason`: the thing that knows why writes the words.

### 6.3 Per unit — two fields

Riding on the redesign §12 #33 already specifies:

- **`goalId: int`** (-1 when none). Lets the renderer draw the assignment — a line to the hill, a
  ring on the carrier. ⚠️ **This makes the anti-blob split visible**, which is the difference between
  a player seeing "two of mine went for the point" and seeing "everyone ran at each other again".
- **`tags: Array[String]`** — `"flagCarrier"`, `"capturing"`. Cheap, and it is how the renderer
  knows to put the flag model in someone's hand.

`intent` and `reason` are already in the redesign and need no mode-specific extension — the goal's
`label` flows into `intent` verbatim, and `reason` carries the assignment's winning term
(`"assigned: Contest the Hill (nearest eligible, Discipline 71)"`).

### 6.4 In the result

`winner` **stays** a `"A"|"B"|"draw"` string. `career.gd`, `battle_ui.gd`, `report_ui.gd` and
`arena_view.gd` all read it today and none of them need to change. Add alongside it:

```gdscript
"endReason": "elimination" | "clock" | "objective" | "mutual",
"scoreA": float, "scoreB": float,
```

`endReason` is what lets the post-fight card say *"you won on points, not on kills"* — a
one-word difference that is the whole read of an objective match.

---

## 7. How modes attach to cups and leagues

### 7.1 The data

Mode assignment is **data, beside `teamSizeByLeague`** in `data/data.json` — never hardcoded, per
`.claude/docs/coding-standards.md`. `career.gd` already reads `leagues` and `teamSizeByLeague` from
there and hardcodes nothing.

```json
"modes": {
  "tdm":  {"unlocksAt": 0},
  "koth": {"unlocksAt": 5},
  "ctf":  {"unlocksAt": 8}
},
"cupModeWeights": {
  "Wood": {"tdm": 1.0},
  "Gold": {"tdm": 0.7, "koth": 0.3},
  "Platinum": {"tdm": 0.5, "koth": 0.3, "ctf": 0.2}
}
```

```gdscript
# career.gd — additive, no existing signature changes
func mode_for_cup(league_idx: int, cup_seed: int) -> String     # deterministic; defaults "tdm"
```

**Why weights and not a fixed schedule:** decision #2 says modes vary *by cup*, and
`town.ts`'s tournament calendar is already a seeded per-year generator. A weight table drops
straight into that when the calendar is ported, and degenerates to "always TDM" for every league
that has not unlocked anything else.

### 7.2 ⚠️ The mode must be known at TACTICS time, not at fight time

This is the ordering constraint and it is cheap now and expensive later.

`career.gd:enter_league_tournament()` today generates rivals and fights, in one call, with no
player-facing step in between. **The player commits orders before watching (§1 #3), so the mode has
to be on the sign-up and tactics screens** — otherwise a player sets a KotH plan for a TDM cup, or
worse, has no idea why they lost a match nobody told them was scored.

So: **the cup's mode is decided when the cup is generated and is part of the scouting read**, sitting
next to the rival gameplan `Tactics.GAMEPLANS` already exposes. `enter_league_tournament()` gains a
`mode_id` parameter defaulted to `"tdm"`; the tactics screen reads it and shows the mode's
`display()` block and the `contest`/`screen` intents.

### 7.3 ⚠️ Objective modes require the spatial sim, and `career.gd` does not use it

`career.gd` fights via `BattleSimScript` — `battle_sim.gd`, which has **no positions at all**. A hill
cannot exist in it. There are only two honest options:

- **(recommended) objective cups run `SpatialSim`.** Career selects the engine by mode. `battle_sim.gd`
  stays as the non-spatial control (`SPATIAL_HANDOFF.md` §5) and keeps fighting TDM cups until the
  ladder migrates wholesale.
- **(rejected) a non-spatial approximation of KotH**, in the spirit of `Tactics._spread_subset`'s
  honest approximation of formation. ⚠️ **Do not.** That helper is explicitly flagged in its own
  source as something that *"can't yet be WATCHED happening"* — and a mode whose entire value is that
  the player watches where monsters chose to stand has nothing left when you remove the watching.

---

## 8. Determinism

Every rule in `SPATIAL_HANDOFF.md` §1 binds mode code without exception. Specifically:

1. **Mode state advances on `Spatial.DT`, at a pinned phase of the tick.** The order is:
   `statuses → decide → move → act → mode.advance → apply ModeEffects → record frame → mode.terminal`.
   Capture is judged on **end-of-tick positions**, the frame shows what `advance` just computed, and
   the terminal check runs after both. ⚠️ Today's loop tests the living count at the *top*, so the
   final tick's deaths are recorded and the loop exits one iteration later — with a mode that must
   become an explicit post-advance check or the last frame's score is a tick stale.
2. **Fixed iteration order, always.** `ModeView.living(side)` returns ascending unit ids. A mode may
   never iterate a Dictionary, and every tie (nearest occupant, deepest inside the zone) breaks on
   lower id.
3. ⚠️ **The mode gets its OWN derived rng stream.** `mode_rng.seed = base_seed ^ MODE_SALT`.
   **Do not let a mode draw from the combat rng.** A rotating hill drawing one `randf()` shifts every
   subsequent accuracy, crit and variance roll in the fight — which silently destroys the project's
   paired-A/B doctrine (`tools/ab.ts`: *the SAME fights under both settings*) and makes
   mode-on/mode-off comparisons non-paired without anyone noticing. This is the single easiest
   determinism mistake to make here.
4. **Float accumulation is fine, ordering is not.** `progress += rate * DT` over 2,400 ticks
   reproduces exactly, because it is the same operations in the same order. A sum over *"units inside
   the zone"* does not, unless that set is built by walking the fixed array.
5. **No `Array.shuffle()`, no `randf()`, no node access, no physics query** — the standing four.

**Acceptance criteria**

- Same seed + same orders + same mode → **byte-identical frame stream including every `mode` record**.
  This is the existing determinism harness (stream G, `_spatial_test.gd`); it extends to modes for
  free, provided `frame_record()` returns only ints, floats, strings and Vector2s.
- `ModeTdm` produces a frame stream **identical to the mode-less sim** on the same seed. ⚠️ **This is
  the seam's real regression test** — if the seam changes TDM's behaviour at all, it has leaked.
- A `modes.json`-style contract in the style of the existing six: a scripted position stream in, the
  mode's score/zone/terminal trace out. Pure, exact equality, no baseline needed — the kind of test
  `CLAUDE.md` says still works while the balance baseline is suspended.

---

## 9. ⚠️ What the current simulation shape cannot cleanly support

The brief asked for this specifically, and it is the most valuable section here. Six findings, worst
first.

### 1. The leash makes the blob mandatory — §0

Restated here because it is the finding, not a footnote. `_apply_leash` confines every unit to
8.4–24.9% of the board around the *living centroid of both sides*. Objectives outside it are
unreachable; objectives inside it are inside the blob. **The leash anchor must become goal-aware, and
that decision has to be made before `spatial_sim.gd` is rewritten**, because it is a movement change
and movement is what every other workstream depends on.

### 2. The win condition is the shape of the loop, not a value

```gdscript
while now < MAX_DURATION:
    if _living(team_a).is_empty() or _living(team_b).is_empty():
        break
```

Elimination is not a parameter — it is `run()`'s control flow, and the tiebreak
(`a_alive != b_alive → more survivors wins`) is a hardcoded tail. **There is no place to put a
different win condition.** Cheap to fix while the file is being rewritten; a genuine surgery
afterwards.

### 3. ⚠️ There are two clocks, they disagree, and one of them is dead code

- `spatial_sim.gd` / `battle_sim.gd`: `MAX_DURATION = 180.0`.
- `tick.gd`: `SUDDEN_DEATH_AT = 255.0`, a ramping `max_hp × rate × dt` attrition applied per unit.

**`now` can never reach 255 because the loop stops at 180, so `sudden_death_loss()` returns 0.0 on
every call in both engines.** It is unreachable code that both sims call every tick for every unit.

Two things follow. First, someone should decide which number is wrong — this is a live bug, not a
mode concern. Second, and for this document: **forced attrition is mode policy living inside
`tick.gd`, which is shared with `battle_sim.gd` and locked by the tick contract.** If it is ever
made reachable, it corrupts KotH (the score clock is supposed to resolve the match) and kills CTF
carriers mid-run. `tick_policy().suddenDeathAt` in §1 is the seam for it; `INF` disables it, which is
what TDM should probably pass anyway.

### 4. There is no verb but "cast a move at a body"

`_choose_move_for` → `_start_cast` → `_resolve_cast` is the entire action space, and each branch ends
in `_resolve_hit` or `_apply_team_effect`. **Capturing, picking up and planting are not expressible.**
This is the one place the seam genuinely costs new machinery: the `interact` goal kind needs a leaf
that occupies a unit for a duration, is interruptible, and is *not* a cast. It interacts with the
cast state machine (a unit cannot be rooted casting and dwelling at once) and with
`is_incapacitated()`. **One leaf, authored once — but it must be authored, not assumed.**

### 5. `desired_position()` has nowhere to put "where I was told to be"

```gdscript
static func desired_position(unit, unit_pos, target_pos, ally_positions, team_centre,
        tactics, team_size, obstacles) -> Vector2
```

Position is derived **entirely from the current target's position**. There is no goal parameter and
no concept of a destination that is not an enemy. Free to add now (the file is being rewritten from
scratch); a signature change touching every call site later.

### 6. Small but real

- **`_fight_centre()` averages both sides.** With objectives, "my team's centre" and "the fight's
  centre" stop being the same thing.
- **Solid bodies + a small zone = the §7 risk #2 deadlock at its worst.** Ten monsters, one hill,
  `_separate()` shoving every tick. §4.2 sizes it; QA must measure it.
- **Stunned bodies on the point.** `is_incapacitated()` units are skipped by decide/move/act
  entirely. Do they hold the hill? **Recommend: a body holds, but a *contested* zone is not captured
  by stunned bodies alone** — legible, and it gives hard control a real objective use, which the
  Control doctrine badly needs (`CLASS_REWORK.md` finds Control owned by 1 of 18 classes). Designer's
  call, but it must be a decided flag in the config, not an accident of the loop.
- **`side` is a two-value enum and objects have no side.** A dropped flag and a neutral hill belong
  in their own frame arrays, not in `units`.

---

## 10. Open questions needing sign-off

| # | question | who |
|---|---|---|
| 1 | **The goal-aware leash anchor (§0).** Blocks the `spatial_sim.gd` rewrite. | technical-director + spatial core |
| 2 | Do `contest` / `screen` join the positional-intent axis, or become a separate axis? (§2.5 — recommend joining) | game-designer |
| 3 | KotH hill on the midline at varying `y`, and does it rotate? (§4.1) | game-designer |
| 4 | Can a flag carrier cast? (§5, recommend: cast-time-0 only) | game-designer |
| 5 | Which clock is wrong — 180 or 255? (§9.3) — a live bug either way | technical-director |
| 6 | Do stunned bodies hold a point? (§9.6) | game-designer |
| 7 | Mode unlock pacing on the ladder (§7.1) — does KotH arrive at Gold? | economy/systems-designer |
| 8 | Does the ladder migrate wholesale to `SpatialSim` before objective modes ship? (§7.3) | producer + technical-director |

---

## 11. Build order

Nothing below is v1 content. **The seam is v1; the modes are not.**

1. **Now, inside the rewrite** — goal-aware leash anchor (§0); `mode` object owning terminal, clock
   and tiebreak (§3); `goals()` called and threaded to `assign_goals()`; `goalId` and `mode` records
   in the redesigned frame stream (§6). **`ModeTdm` is the only mode, and it must reproduce the
   mode-less sim byte for byte.**
2. **With the tree** — the generic `Objective` subtree and the `interact` leaf, authored against
   zero live modes.
3. **After assignable classes** (§12 #35, so kit-fit scoring is tuned against the final role set) —
   `ModeKoth`, plus the hill-radius and deadlock measurements §4.2 asks for.
4. **Later** — `ModeCtf`, once §5's three decisions are signed off.

**We will know the seam was right if:** adding `ModeKoth` touches `scripts/modes/koth.gd`,
`data/data.json` and one line of `career.gd` — and **nothing** in `spatial_sim.gd`, `spatial_ai.gd`
or the behaviour tree.
