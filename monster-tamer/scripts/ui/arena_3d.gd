## THE BATTLEFIELD — replays a real spatial simulation.
##
## ⚠️ THIS RENDERER DERIVES NOTHING. It plays back the frame stream the simulation produced
## (`docs/BUILD_CONTRACT.md` §2): positions, facings, states, HP, shots, intent/reason and
## projectiles are all read, never invented. The one thing this file computes for itself is the
## CAMERA's own framing — which world-space box to look at — and that is explicitly a rendering
## decision, built only from positions the stream already gave us, never a guess about where a
## unit "should" be.
##
## The rule to keep: **if the renderer wants to know something about the FIGHT, it asks the frame
## stream.** Any time this file starts computing where a unit "should" be, or what it is doing,
## the spatial layer is missing a field — say so rather than working around it.
##
## ⚠️ THE CAMERA IS THE OTHER HALF OF THE DESIGN, AND TWO PASSES GOT IT WRONG.
## A side-on, eye-level camera renders two ranks facing each other — the visual grammar of
## turn-based combat — no matter how real the simulation behind it is. Looking DOWN at a bounded
## floor is what makes it read as an autobattler board. This pass adds a second requirement on top
## of that: the leash that used to keep every fight inside 24-42% of the board is GONE
## (`docs/BUILD_CONTRACT.md` §0), so a camera that frames the deploy zone alone now regularly
## misses the fight. The camera below FOLLOWS the living units' own spread — center and zoom both
## re-fit every frame from their actual positions — rather than fitting a static formula.
##
## ⚠️ SUPERSEDED 2026-08-08 — THE RENDERER SWITCH LANDED. This paragraph used to say the screen
## ran standalone while `spatial_sim.gd` was mid-rewrite, with `intent`/`reason` and `projectiles`
## promised but unpopulated. All three are now real: this screen runs `scripts/sim/sim.gd` with the
## `combat_tree` brains, which emit intent, reason, posture and in-flight projectiles every tick.
## The guarded `.get(..., default)` reads stay — they are still the correct shape for a stream
## that will keep growing — but they are no longer papering over an absent producer.
extends Node3D

const TacticsScript = preload("res://scripts/tactics.gd")
const Sp = preload("res://scripts/spatial.gd")
## Procedural per-creature animation — see docs/MESHY_SPIKE_RESULT.md's follow-up section.
const CreatureAnimScript = preload("res://scripts/ui/creature_anim.gd")
const CreatureRigScript = preload("res://scripts/ui/creature_rig.gd")
const SPATIAL_SIM_PATH := "res://scripts/spatial_sim.gd"
const ARENA_LAYOUT_PATH := "res://scripts/arena_layout.gd"

## ── THE RENDERER SWITCH (2026-08-08) ────────────────────────────────────────────────────────
## This screen ran `spatial_sim.gd` + `ai/monster_tree.gd` — both carrying SUPERSEDED banners —
## while the rewritten stack (`scripts/sim/`, `scripts/ai/combat_tree.gd`) only ever ran in the
## watch scene and the probes. `USE_NEW_SIM` closes that gap; it is a SEAM, not a deletion, so
## the legacy engine stays one constant away for as long as the comparison is worth having.
##
## ⚠️ THE NEW SIM DOES NOT SPEAK THE OLD FRAME CONTRACT, so the switch is a sim swap PLUS a
## translation (`_adapt_result`). Everything below the translation — 2000 lines of nameplates,
## cast bars, VFX, camera and log — is untouched and still reads the legacy field names.
## The translation is a pure RE-KEYING of what the stream already states: string unit ids become
## the array indices this file addresses nodes by, ticks become seconds, status records become
## their kinds, and the event list becomes the flat log. It invents no fact about the fight.
const USE_NEW_SIM := true
const NewSim = preload("res://scripts/sim/sim.gd")
const KitLib = preload("res://scripts/sim/kit.gd")

## ⚠️ GROUND UNITS ARE NOT WORLD UNITS, DELIBERATELY.
## `ARENA_BLUEPRINT` sizes a 5v5 ground at 160x88 — realistic for a stadium, and far too large to
## read when the fighters are ~2 units tall. Autobattlers in this genre exaggerate unit scale
## against the board so the pieces stay legible. We render the ground shrunk and the creatures
## enlarged; the SIM is unaffected, because this factor is applied only on the way to the screen.
const WORLD_SCALE := 0.34
const UNIT_HEIGHT := 4.4
const WALL_H := 1.4
const STAND_TIERS := 5

const SPEED_OPTIONS := [0.5, 1.0, 2.0, 4.0]
const OPENING_HOLD := 1.5

# ── Camera — steep, dynamic, never the static leash-radius formula that no longer exists. ──────
## ⚠️ RE-FRAMED 2026-08-05 TO THE DIRECTION THAT WAS WRITTEN AND NEVER BUILT.
## Was 58 degrees / 40 fov, chosen so "looking DOWN at a bounded floor reads as an autobattler
## board". That is a defensible instinct, but it is not the direction on file: `ART_DIRECTION.md`
## §Camera and `ARENA_CAMERA_REFERENCE.md` both specify **~38 degrees elevation, 26 fov (long
## lens)** — and the studio owner picked that framing explicitly off a reference image, asking for
## "more zoomed out, bigger arena".
##
## ⚠️ WHAT THE TRADE ACTUALLY IS, so the next person can reverse it knowingly: at 58 you see the
## FLOOR and the fight reads as a board. At 38 you see the VENUE — the far wall, the stands, the
## horizon — and it reads as a place with a crowd in it. The old value優 optimises for tactical
## clarity; this one optimises for spectacle and for the "sport, not war" identity in
## `ART_BIBLE_GUILD_COLOURS.md`. Both are coherent. This one is the one that was decided.
##
## ⚠️ A LONG LENS PUSHES THE CAMERA BACK, IT DOES NOT SHRINK THE SUBJECT. `_apply_camera_now`
## solves `r = span / tan(fov/2)`, so dropping fov 40 -> 26 roughly doubles the camera distance
## for the same framing. That is the point — a short lens bows a wide arena (`ART_DIRECTION.md`),
## and the bow is exactly what made the old framing feel like a diorama rather than a stadium.
const CAM_PITCH_DEG := 38.0     # degrees below horizontal — ART_DIRECTION.md §Camera
const CAM_FOV := 26.0           # long lens; short ones bow a wide arena
## ⚠️ THE CAMERA USED TO FRAME POINTS, AND UNITS ARE NOT POINTS. `_camera_target()` measured the
## bounding box of unit POSITIONS and multiplied it by `CAM_PADDING`. That was survivable while
## every unit was a billboarded sprite, because a multiplier on a spread is roughly a body-width
## when the spread is large. It stopped being survivable the moment real geometry arrived: ten
## bodies converging into a scrum have a near-ZERO positional spread, a multiplier on near-zero is
## near-zero, so the span collapsed to the floor and two creatures filled the screen while the
## fight happened inside them.
##
## The floor was 9.0 world units against creatures 4.4 units tall — barely two bodies wide. The
## three fixes below are independent and all three were needed:
##   1. a BODY RADIUS added to the bounding box, so the frame contains volumes not points
##   2. an ADDITIVE headroom term rather than only a multiplier, so padding survives a scrum
##   3. a floor derived from `UNIT_HEIGHT` rather than a bare number, so it cannot drift out of
##      step with the creatures again
##
## ⚠️ AND NO PROBE WOULD HAVE CAUGHT THIS. Every unit built, every clip resolved, the sim ran and
## the frame stream was intact — the numbers were all green and the fight was still unwatchable.
## It took looking at six sampled frames. Legibility is a first-class requirement here
## (`CLAUDE.md`) precisely because the player cannot intervene, so "the camera is too tight" is a
## defect, not polish.
## ⚠️ TUNED AGAINST A MEASURED TARGET, NOT A GUESS. `span` is the half-extent that fills the
## vertical FOV, so a creature occupies `UNIT_HEIGHT / (2*span)` of frame height. At the old floor
## of 9.0 that was 24% PER CREATURE and ten of them buried the fight; the first correction to 5.5x
## overshot to 9% and the fight became ants on a table. 3.0x puts one creature at ~17% of frame
## height — big enough to read its animation, small enough that ten fit with the venue behind.
const CAM_MIN_SPAN := UNIT_HEIGHT * 2.6   # ~11 units — one creature reads at ~19% of frame height
const CAM_PADDING := 1.18       # multiplier on the spread; small now that headroom is additive
const CAM_HEADROOM := 2.0       # world units added regardless of spread — survives a scrum
## Half a creature's footprint, added on every side so the frame holds BODIES rather than the
## points they stand on. Derived from `UNIT_HEIGHT` so it tracks the creature scale automatically.
const CAM_BODY_RADIUS := UNIT_HEIGHT * 0.5
## A unit's height eats vertical screen space that a ground-plane bounding box knows nothing
## about. At a 38-degree pitch a body of height H covers roughly H*cos(38) of the vertical
## extent, so the span has to allow for it or heads leave the frame in a tight shot.
const CAM_HEIGHT_ALLOWANCE := UNIT_HEIGHT * 0.8
## Nameplate declutter — see `_update_plates`.
const PLATE_MAX_LIFT := 12      # bigger plates stack taller before giving up
const PLATE_GAP := 3.0          # pixels between stacked plates

const CAM_FOLLOW_RATE := 2.4    # exponential smoothing rate/second for center+zoom

## ⚠️ TWO TEMPORARY OBSERVATION SWITCHES (studio owner, 2026-08-05): "lets remove the objects from
## the arena for now... lets make a large arena with clear deployment zones and see how the
## monsters move and interact. the camera should be able to cover the arena."
##
## Both are deliberately named and flagged rather than done by deleting code, because both remove
## something the design actually wants back:
##
##   SHOW_OBSTACLES  — cover is not decoration. `ARENA_DESIGN.md`'s DENSITY LAW (one piece per 300
##                     square units) and `SPATIAL_COMBAT_DESIGN.md`'s graded cover are load-bearing
##                     mechanics, and `arena_layout.gd` still GENERATES the obstacles either way —
##                     this only stops them being drawn and handed to the sim. Turning it back on
##                     restores the whole system with no other change.
##
##   The ARENA camera mode — a fixed wide shot that never moves is the only way to judge MOVEMENT, which
##                     is the entire question being asked. A camera that follows the action hides
##                     exactly the thing under test: whether the monsters use the space at all.
##                     ⚠️ It is not the shipping camera — at 352x194 the bodies fall to ~4% of
##                     frame height, well under the 12-13% the follow camera holds. This is an
##                     instrument, not a decision.
const SHOW_OBSTACLES := true
## ⚠️ Now the STARTING value of a runtime toggle (`C`), not a fixed constant — see `_unhandled_input`.

# ── Tier-1 glyph — from the frame's own `state` enum, never a guess at the tree's branch name.
## `docs/UX_LEGIBILITY.md` §6 Tier 1 wants a branch glyph (engage/hold/flank/dive/...), but the
## frame contract does not promise a `branch` key, only the enumerated `state` field
## ("idle"|"advance"|"retreat"|"attack"|"cast"|"stunned"|"dead") — which the sim DOES guarantee
## today. Using `state` for the always-on glyph and reserving the free-text `intent`/`reason` for
## the on-demand callout (Tier 2) means Tier 1 never has to guess at vocabulary that isn't there
## yet. "attack" gets no separate glyph — the hit/miss float-text already covers that instant,
## exactly as `UX_LEGIBILITY.md` specifies. `stunned` naturally wins precedence because the sim's
## own `_record_frame` already checks incapacitation before movement/casting.
const STATE_GLYPH := {
	"advance": "→", "retreat": "←", "cast": "⚡", "stunned": "⊘",
}

## Status taxonomy, ported from `arena_view.gd`'s (disconnected) `STATUS_META` table per
## `docs/UX_LEGIBILITY.md` §1 rule 1 / `docs/ACCESSIBILITY.md` §1.3's explicit recommendation —
## same abbreviations, same hue families, so a status reads identically wherever it is drawn.
const STATUS_META := {
	# ⚠️ `taunt` and `weary` are SIM-SIDE states, not fieldStatus kinds — taunt is the forced-
	# target entry the 2026-08-06 wiring appends, weary is the care loop's low-stamina flag
	# injected as a pseudo-status below. They still get real chips: a forced target and a tired
	# fighter are exactly the reads a player who cannot intervene needs to see.
	"taunt": {"abbr": "TAUNT", "color": Color(0.92, 0.55, 0.30)},
	"weary": {"abbr": "WEARY", "color": Color(0.58, 0.64, 0.74)},
	# ⚠️ COLOUR FAMILIES (UI team 2026-08-06): seven statuses shared ONE gold, leaving 11px
	# abbreviations as the sole differentiator. Families now: body-lock gold (stun/sleep),
	# mental pink-violet (fear/confusion/charm), silence cool blue-grey (a resource lock, not a
	# body lock), knockback warm neutral (displacement, not control).
	"stun": {"abbr": "STN", "color": Color(0.95, 0.92, 0.62)},
	"sleep": {"abbr": "SLP", "color": Color(0.88, 0.82, 0.55)},
	"fear": {"abbr": "FEAR", "color": Color(0.72, 0.45, 0.85)},
	"confusion": {"abbr": "CONF", "color": Color(0.90, 0.52, 0.78)},
	"charm": {"abbr": "CHRM", "color": Color(0.95, 0.62, 0.68)},
	"silence": {"abbr": "SIL", "color": Color(0.60, 0.74, 0.88)},
	"knockback": {"abbr": "KB", "color": Color(0.74, 0.69, 0.58)},
	"poison": {"abbr": "PSN", "color": Color(0.42, 0.80, 0.36)},
	"burn": {"abbr": "BRN", "color": Color(0.92, 0.52, 0.18)},
	"bleed": {"abbr": "BLD", "color": Color(0.85, 0.24, 0.24)},
	"doom": {"abbr": "DOOM", "color": Color(0.55, 0.24, 0.62)},
	"blind": {"abbr": "BLND", "color": Color(0.62, 0.55, 0.70)},
	"vulnerable": {"abbr": "VULN", "color": Color(0.62, 0.55, 0.70)},
	"healblock": {"abbr": "HBLK", "color": Color(0.62, 0.55, 0.70)},
	"haste": {"abbr": "HASTE", "color": Color(0.35, 0.78, 0.90)},
}

## Obstacle dressing — `kind` (from `arena_layout.gd`'s `KIND_TABLE`) picks the mesh/texture,
## `grade` (already handled below) picks the height, exactly as the brief specifies: what a
## player sees matches what the sim applies.
const OBSTACLE_TEX := {
	"barrel": "res://assets/arena/barrel-wood.jpg",
	"crate": "res://assets/arena/crate-wood.jpg",
	"planter": "res://assets/arena/crate-wood.jpg",
	"low_wall": "res://assets/arena/wall-timber.jpg",
	"pillar": "res://assets/arena/wall-stone.jpg",
	"bench": "res://assets/arena/wall-timber.jpg",
	"fence": "res://assets/arena/wall-timber.jpg",
	"boulder": "res://assets/arena/wall-stone.jpg",
	"shrine": "res://assets/arena/wall-stone.jpg",
}
## Kinds without an authored texture of their own are tinted (StandardMaterial3D.albedo_color
## multiplies albedo_texture) so each still reads as distinct rather than silently reusing an
## unrelated kind's look — planter vs crate, fence vs low_wall, boulder/shrine vs pillar.
const OBSTACLE_TINT := {
	"planter": Color(0.55, 0.72, 0.48),
	"fence": Color(0.95, 0.88, 0.72),
	"boulder": Color(0.72, 0.66, 0.58),
	"shrine": Color(0.92, 0.82, 0.58),
}
const OBSTACLE_FALLBACK := {
	"barrel": Color(0.44, 0.32, 0.20), "crate": Color(0.50, 0.38, 0.24),
	"planter": Color(0.40, 0.52, 0.34), "low_wall": Color(0.55, 0.53, 0.50),
	"pillar": Color(0.50, 0.48, 0.45),
	"bench": Color(0.52, 0.40, 0.26), "fence": Color(0.58, 0.47, 0.32),
	"boulder": Color(0.46, 0.43, 0.38), "shrine": Color(0.56, 0.50, 0.38),
}

const PROJECTILE_COLOUR := {
	"ranged": Color(0.95, 0.85, 0.45), "magic": Color(0.55, 0.62, 0.95),
	"support": Color(0.55, 0.90, 0.65), "melee": Color(0.90, 0.90, 0.92),
}

var camera: Camera3D
var overlay: CanvasLayer
var plates_root: Control
var log_view: RichTextLabel
var log_scroll: ScrollContainer
var banner: PanelContainer
var banner_box: VBoxContainer
var banner_title: Label
var banner_sub: Label
var callout: PanelContainer
var callout_title: Label
var callout_body: RichTextLabel
var mode_label: Label
var resolving_label: Label

var team_a: Array = []
var team_b: Array = []
var all_units: Array = []          # fixed order: A then B — matches frame `id`
var nodes: Array = []              # parallel to all_units: {holder, sprite, plate, hp_fill, ...}
var league_name := "Platinum"

var result: Dictionary = {}
var frames: Array = []
var ground_size := Vector2(160, 88)
var frame_pos := 0.0               # fractional frame index — we interpolate between ticks
var playing := false
var speed := 1.0
var opening_timer := 0.0
var logged_upto := 0
var event_log: Array = []
var used_spatial := false

var selected_idx := -1             # Tier-2 disclosure — one unit's callout open at a time
var shadow_mm: MultiMesh
var vfx = null   # BattleVfx — untyped, BUILD_CONTRACT §4 on bare class_name refs
var spectators = null   # the crowd (spectators.gd)
var _move_by_name := {}   # ability name -> move dict, for play_ability dispatch = null
var _projectile_nodes: Dictionary = {}   # projectile id -> MeshInstance3D
var _seen_tick := -1
var _last_intent: Dictionary = {}        # unit id -> last-seen intent string (transition-only log)

var _cam_max_span := 30.0
var _cam_center := Vector3.ZERO
var _cam_span := 30.0
## Camera modes (user direction 2026-08-06). TEAM is the default — the fight framed from YOUR
## side's point of view (the old all-units follow collapsed onto lone survivors and read as
## "stuck to one monster"). ACTION is that all-units follow, ARENA the wide instrument, FREE is
## manual: hold LMB to pan, wheel to zoom — any mouse camera input enters FREE; C returns.
enum CamMode { TEAM, ACTION, ARENA, FREE }
var _cam_mode: int = CamMode.TEAM
var _free_center: Vector3 = Vector3.ZERO
var _free_span: float = 60.0
var _panning := false
var _layout_name: String = "four_pillar"


func _ready() -> void:
	# ⚠️ ORDER MATTERS, AND IT CHANGED (2026-08-04): `SpatialSim.run()` is now a COROUTINE —
	# `NavigationServer3D` only syncs a freshly-baked navmesh on real `SceneTree` frames, so the
	# sim awaits `process_frame` before its first pathfinding query. `_ready()` cannot block on
	# that, so the build order is: resolve teams -> build the overlay (so a "resolving" state has
	# somewhere to show) -> prepare the LAYOUT synchronously (obstacles + ground size, both
	# deterministic from team size alone, no positions needed yet) -> build the static world from
	# that layout -> THEN await the fight -> THEN build the units and start playback. A frozen
	# first frame while a coroutine silently runs is worse than a deliberate "resolving…" label.
	_resolve_teams()
	_build_overlay()
	_prepare_layout()
	var VfxScript = load("res://scripts/ui/vfx.gd")
	vfx = VfxScript.new()
	add_child(vfx)
	# THE CROWD — monster spectators on the apron, reacting to the fight's beats. fill is a
	# parameter because FAME drives attendance (standing rule), not arena size.
	var SpecScript = load("res://scripts/ui/spectators.gd")
	spectators = SpecScript.new()
	add_child(spectators)
	spectators.build(ground_size, _to_world, 1.0)   # full house for the demo; FAME takes this over
	for gmv in GameData.moves:
		_move_by_name[str(gmv["name"])] = gmv
	_build_world()
	_show_resolving(true)
	await _resolve_fight()
	_show_resolving(false)
	_update_mode_label()
	_build_units()
	_build_innate_tells()
	playing = true


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# SIM
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _resolve_teams() -> void:
	var career := get_node_or_null("/root/Career")
	var size := 5
	var from_career: bool = career != null and not TacticsScript.committed.is_empty()
	if from_career:
		league_name = career.current_league_name()
		size = career.current_team_size()

	var cup := get_node_or_null("/root/CupRun")
	if cup != null and cup.league_idx >= 0 and career != null:
		# The cup may be fighting a league BELOW the player's current frontier (punching down) —
		# the arena's league art/cap label must reflect the cup being fought, not the frontier.
		league_name = career.league_at(cup.league_idx).get("name", league_name)

	# ⚠️ PREFER THE EXACT TEAMS "The Read" SHOWED THE PLAYER. `Tactics.commit()` now carries
	# `teamA`/`teamB` verbatim — regenerating a fresh rival team here (the old behaviour) could
	# silently fight a DIFFERENT roster than the one that was scouted and ordered against. See
	# `tactics.gd:commit()`'s own doc comment for the finding.
	var committed_team_a: Array = TacticsScript.committed.get("teamA", [])
	var committed_team_b: Array = TacticsScript.committed.get("teamB", [])
	if not committed_team_a.is_empty() and not committed_team_b.is_empty():
		team_a = committed_team_a
		team_b = committed_team_b
	else:
		var roster := get_node_or_null("/root/Roster")
		if from_career and roster != null and not roster.monsters.is_empty():
			team_a = roster.monsters.slice(0, mini(size, roster.monsters.size()))
			team_b = roster.make_rival_team(team_a.size(), 0.3)
		else:
			for i in range(size):
				team_a.append(GameData.make_monster(Art.ROSTER[i % Art.ROSTER.size()], 0.3))
				team_b.append(GameData.make_monster(Art.ROSTER[(i + 5) % Art.ROSTER.size()], 0.3))
	all_units = team_a + team_b


## SYNCHRONOUS. Ground size and cover are both deterministic from team size + a seed alone — the
## exact formula `SpatialSim` uses internally too (`Sp.ground_size`) — so the static world (floor,
## walls, stands, obstacles, camera max-zoom) can be built before the fight itself has run.
func _prepare_layout() -> void:
	var team_size: int = maxi(team_a.size(), team_b.size())
	ground_size = Sp.ground_size(team_size)
	_obstacles = []
	# ⚠️ THE SIM MUST SEE THE SAME WORLD THE PLAYER DOES. Suppressing obstacles in the renderer
	# while still handing them to `SpatialSim` would leave units pathing around, and taking cover
	# behind, barrels that are not on screen — the fight would look irrational for reasons nothing
	# visible could explain. So the switch has to cut here, before generation, not at draw time.
	if not SHOW_OBSTACLES:
		return
	if ResourceLoader.exists(ARENA_LAYOUT_PATH):
		var LayoutScript = load(ARENA_LAYOUT_PATH)
		if LayoutScript != null and LayoutScript.has_method("generate"):
			var rng := RandomNumberGenerator.new()
			rng.seed = 20260804
			# The committed orders carry which composition to fight on, so the same screen serves
			# the cup, the sandbox and the viewer without any of them special-casing the others.
			var want_layout: String = str(TacticsScript.committed.get("layout", "four_pillar"))
			var lay: Dictionary = LayoutScript.generate(team_a.size(), league_name, rng, want_layout)
			_layout_name = str(lay.get("layout", want_layout))
			_obstacles = lay.get("obstacles", [])


## ASYNC. ⚠️ `SpatialSim.run()` is a coroutine (2026-08-04) — `NavigationServer3D.map_get_path()`
## returns an empty path with no error until a freshly-baked navmesh has synced across a real
## `SceneTree` frame, and `SpatialSim` has no frame loop of its own, so it awaits `process_frame`
## before its first query. Missing the `await` here does not error — it hands back a
## `GDScriptFunctionState` instead of the result Dictionary, so `frames`/`winner` silently come
## back empty and the arena renders nothing, which looks exactly like a rendering bug and isn't
## one. If this screen ever goes blank, check this line first.
func _resolve_fight() -> void:
	var committed: Dictionary = TacticsScript.committed
	# ⚠️ Prefer the spatial sim; fall back to the non-spatial one if it hasn't landed. The fallback
	# is NOT a shrug — `battle_sim.gd` is deliberately kept as the reference implementation so
	# there is always a control to judge the spatial layer against, and so this screen still runs
	# while the spatial streams are mid-flight.
	# ⚠️ THE COMMIT STORES `ordersA`/`ordersB`; THIS READ SAID `orders` — A KEY THAT HAS NEVER
	# EXISTED. Every per-monster order the tactics screen sold (temperament, target priority,
	# positional intent, guard) silently fell to `{}` in the career path, making the entire
	# per-monster column cosmetic. The seventh feature found built-and-unreachable. Both sides'
	# orders merge into one dict — the sim looks units up by instance, so the keys never collide.
	var orders: Dictionary = {}
	for k in (committed.get("ordersA", {}) as Dictionary):
		orders[k] = committed["ordersA"][k]
	for k in (committed.get("ordersB", {}) as Dictionary):
		orders[k] = committed["ordersB"][k]
	# A dragged chip becomes a real start: inject the committed placement into that monster's own
	# orders, where `spatial_sim._deploy()` now reads it (validated sim-side against the shared
	# deploy_zone — the sim, not the UI, owns what is legal).
	for m in (committed.get("deployA", {}) as Dictionary):
		if not orders.has(m):
			orders[m] = {}
		orders[m]["deployPos"] = committed["deployA"][m]
	# ⚠️ DETERMINISTIC PER FIGHT, DIFFERENT ACROSS FIGHTS. This was the literal 20260804 — every
	# fight in every cup rolled the same sim rng. Career fights now derive from where the career
	# actually is; replaying the same round reproduces it exactly, the next round does not.
	var fight_seed := 20260804
	var career2 := get_node_or_null("/root/Career")
	var cup2 := get_node_or_null("/root/CupRun")
	if career2 != null and not committed.is_empty():
		fight_seed = hash([int(career2.week), int(career2.league_index),
			int(cup2.current_round) if cup2 != null else 0])
	if USE_NEW_SIM:
		result = await _run_new_sim(fight_seed)
		used_spatial = true
	elif ResourceLoader.exists(SPATIAL_SIM_PATH):
		var SimScript = load(SPATIAL_SIM_PATH)
		var sim = SimScript.new(team_a, team_b, fight_seed,
			committed.get("planA", {}), committed.get("planB", {}), orders,
			_obstacles)
		result = await sim.run()
		used_spatial = true
	else:
		var Fallback = load("res://scripts/battle_sim.gd")
		var sim2 = Fallback.new(team_a, team_b, fight_seed,
			committed.get("planA", {}), committed.get("planB", {}), orders)
		result = sim2.run()
		used_spatial = false

	event_log = result.get("log", [])
	frames = result.get("frames", [])
	# Overwrite with the stream's own authoritative value, per "the renderer derives nothing" —
	# `_prepare_layout()`'s copy is the same formula and only exists so the world could be built
	# before the fight resolved; this is the one that actually came from the sim.
	ground_size = result.get("groundSize", ground_size)
	if result.has("obstacles"):
		_obstacles = result["obstacles"]


var _obstacles: Array = []


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# THE NEW STACK — build it, run it, translate its stream into the contract this screen speaks
# ═══════════════════════════════════════════════════════════════════════════════════════════════
#
# ⚠️ THE TWO CONTRACTS, WRITTEN DOWN, because the whole switch hangs on the differences:
#
#   field            legacy (`spatial_sim.gd:_record_frame`)  new (`sim/sim.gd:_emit_frame`)
#   ───────────────  ──────────────────────────────────────  ─────────────────────────────────
#   frame clock      `t`, seconds                            `tick`, int  (× `Sim.DT`)
#   unit key         `id`, int index into `all_units`         `id`, String ("a00"/"b03")
#   statuses         [String]                                 [{kind, left}]   ← RICHER
#   movement         `moveDir`                                `move_dir`
#   states           idle/advance/retreat/attack/stunned/cast  idle/advance/cast/dead
#   per-unit extras  targetId, weary                           team, max_hp, max_mp, posture
#   shots            `shots` (impact records)                  `events` (17 kinds)
#   projectiles      {id, from, to, progress, kind}            {from, target_id, pos, move,
#                                                               will_hit, aim}   ← RICHER
#   result           winner/duration/log/survivors/ground      winner/ticks/frames/decision_logs
#
# WHERE THE NEW STREAM IS RICHER (follow-up wins, none taken this pass so the switch stays one
# change): per-status REMAINING SECONDS (the plate could count a stun down instead of showing a
# bare chip); `posture` (the tree's own words for what it is doing, which is a better ticker line
# than `intent`); `will_hit` on a projectile in flight (a doomed shot could read differently
# BEFORE it lands — the single most legible thing an autobattler can show); `max_hp`/`max_mp` on
# the frame itself, which would retire this file's one honest read of static roster data.
#
# WHERE THE NEW STREAM IS MISSING SOMETHING THIS SCREEN USED — stated, never worked around:
#   • `weary` — the care loop (`innate_fx.gd`: potency-scaled innates, the weary flag, startWard)
#     is NOT wired into `sim/sim.gd` at all. The pseudo-status chip now never lights. Raising a
#     monster once again changes its numbers and nothing else on the field.
#   • GRADED COVER — `sim/sim.gd` hands obstacles to navigation and nothing else. The soft/hard
#     accuracy debuff (`Spatial.cover_between`) has no consumer, so cover is currently pathing
#     furniture only. `SPATIAL_COMBAT_DESIGN.md`'s graded cover is unbuilt on the new stack.
#   • `targetId` — absent. Nothing reads it here, so nothing broke; noted so a future focus-line
#     overlay knows it must be added sim-side rather than guessed at.
#   • `manmark` — `combat_tree` has a "marked" priority but it reads `ordered_id`, a blackboard
#     key `sim.gd` documents as "arrives when the tactics screen wires in (v1: keys absent)".
#     The order therefore degrades to the team default here rather than silently doing nothing
#     under a different name.
#
# ⚠️⚠️ AND THE ONE THAT COSTS A WHOLE FIGHT IF YOU MISS IT: THE TWO ENGINES USE DIFFERENT
# COORDINATE ORIGINS. `Spatial.deploy_positions`/`deploy_zone`/`clamp_to_ground` — and therefore
# this file's `_to_world`, the deployment board and every obstacle rect — put the board's CORNER
# at (0,0) and span [0,W]x[0,H]. `sim/nav_service.build()` lays its floor CENTRED on the origin,
# spanning [-W/2,W/2]x[-H/2,H/2] (`_watch_sim.gd` deploys at x=±38 on a 110-wide ground, which is
# what makes it visible). Feeding corner-frame positions to the new sim puts every unit clean off
# the navmesh: `map_get_path` returns empty, nobody moves, and the fight runs to the 1800-tick cap
# looking exactly like a broken AI. MEASURED HERE: the first run of this switch produced 1800
# frames (the cap) instead of the legacy 252. The offset below is the entire fix — sim-side is
# centred, renderer-side is corner, and the translation happens on the boundary in both directions.


## Build, run and translate. Returns a LEGACY-shaped result dict so `_resolve_fight` and every
## consumer below it (playback, report_ui, cup continuation) need no change.
func _run_new_sim(fight_seed: int) -> Dictionary:
	var us: Array = _new_sim_inputs()
	# ⚠️ ONLY `blocking`-grade obstacles carve the navmesh. `nav_service.build()` carves EVERY
	# rect it is handed, and the graded-cover design is explicit that soft/hard pieces are
	# furniture you walk through and shoot worse across — carving them would make five barrels
	# into five walls. The legacy sim made the same split at its own bake; it has to be made
	# HERE now because the new sim takes the list as given.
	var off: Vector2 = ground_size * 0.5
	var nav_obstacles: Array = []
	for ob in _obstacles:
		if str((ob as Dictionary).get("grade", "blocking")) == Sp.COVER_BLOCKS_LOS_GRADE:
			var r: Rect2 = (ob as Dictionary)["rect"]
			nav_obstacles.append({"rect": Rect2(r.position - off, r.size)})
	var sim = NewSim.new()
	sim.setup(fight_seed, us, ground_size, nav_obstacles)
	# The probe pair spans the board along the deploy axis — the same shape `_watch_sim.gd` uses.
	var half_x: float = ground_size.x * 0.5 - 4.0
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-half_x, 0), Vector2(half_x, 0))
	if not ok:
		# Honest failure: a navmesh that never synced would otherwise produce a fight where every
		# unit stands still, which reads as a rendering bug and is not one.
		push_error("arena_3d: navigation never became ready — the fight cannot resolve")
		return {"winner": "draw", "duration": 0.0, "log": [], "frames": [],
			"survivorsA": team_a.size(), "survivorsB": team_b.size(),
			"groundSize": ground_size, "obstacles": _obstacles}
	var raw: Dictionary = sim.run()
	sim.nav.free_rids()   # the teardown every discarded sim owes (nav_service.gd)
	var adapted: Dictionary = _adapt_result(raw)
	# ⚠️ ONE LINE THAT WOULD HAVE CAUGHT THE COORDINATE BUG IMMEDIATELY. A fight that runs to the
	# 1800-tick cap with an empty log is a sim that never engaged; a headless probe reading only
	# `frames.size()` cannot tell that from a long fight. Mirrors `_watch_sim.gd`'s own WATCH line.
	print("ARENA: winner=%s ticks=%d frames=%d events=%d survivors=%d/%d" % [
		str(adapted.winner), int(raw.get("ticks", 0)), (adapted.frames as Array).size(),
		(adapted.log as Array).size(), int(adapted.survivorsA), int(adapted.survivorsB)])
	return adapted


## `all_units` order IS the address space of this whole file — `nodes[k]`, `all_units[k]` and
## every frame record share the index. The new sim sorts its units by STRING id, so the ids are
## authored `a00…`/`b00…` with zero padding so that sort reproduces exactly this order. The
## assert in `_adapt_result` proves it rather than trusting it.
func _new_sim_inputs() -> Array:
	var committed: Dictionary = TacticsScript.committed
	var team_size: int = maxi(team_a.size(), team_b.size())
	var pos_a: Array = Sp.deploy_positions(team_size, "A")
	var pos_b: Array = Sp.deploy_positions(team_size, "B")
	var deploy_a: Dictionary = committed.get("deployA", {})
	var off: Vector2 = ground_size * 0.5   # corner-frame -> centre-frame (see the ⚠️⚠️ above)
	var out: Array = []
	for k in range(all_units.size()):
		var m = all_units[k]
		var side := "A" if k < team_a.size() else "B"
		var slot: int = k if side == "A" else k - team_a.size()
		var src: Array = pos_a if side == "A" else pos_b
		var p: Vector2 = src[slot] if slot < src.size() else src[src.size() - 1]
		if side == "A" and deploy_a.has(m):
			# The dragged chip is a real start — clamped to the legal zone by the SAME rule the
			# legacy sim enforced sim-side (`Sp.deploy_zone` owns what is legal, not the board).
			var zone: Rect2 = Sp.deploy_zone(team_size, "A")
			var want: Vector2 = deploy_a[m]
			p = Vector2(clampf(want.x, zone.position.x, zone.position.x + zone.size.x),
				clampf(want.y, zone.position.y, zone.position.y + zone.size.y))
		var names: Array = []
		for mv in m.moveset:
			names.append(str((mv as Dictionary).get("name", "")))
		out.append({
			"id": ("a%02d" % slot) if side == "A" else ("b%02d" % slot),
			"team": side,
			"pos": p - off,
			"stats": m.stats,
			# `Sp.speed_of` is the arena's own scale-aware speed curve — the same one the legacy
			# sim moved bodies with, so the fight closes at the pace the board was sized for.
			"speed": Sp.speed_of(float(m.stats.get("DEX", 10.0))),
			"kit": KitLib.build(names, GameData.moves),
			"tactics": _new_sim_tactics(m, side),
		})
	return out


## THE ORDERS TRANSLATION. `tactics.gd`'s vocabulary is camelCase and mirrors `core.ts`; the
## tree's is snake_case. ⚠️ THIS IS WHERE THE POSITIONAL INTENT FINALLY BECOMES REAL — the
## deployment board has stored `positionalIntent` (hold/push/wings/dive/guard) and `guardedAlly`
## for months against a sim that read neither (`tactics.gd`'s own header says so). `combat_tree`
## takes exactly those five values, so the switch turns the eighth built-and-unreachable feature
## on by wiring rather than by writing anything new.
func _new_sim_tactics(m, side: String) -> Dictionary:
	var committed: Dictionary = TacticsScript.committed
	var plan: Dictionary = committed.get("planA" if side == "A" else "planB", {})
	var orders: Dictionary = committed.get("ordersA" if side == "A" else "ordersB", {})
	var own: Dictionary = orders.get(m, {})
	var t: Dictionary = {}

	var tp := str(own.get("targetPriority", plan.get("targetPriority", "")))
	match tp:
		"casters": t["target_priority"] = "casters"
		"tanks": t["target_priority"] = "tanks"
		# "manmark" has no live consumer (see the contract note above) — it degrades to the
		# documented team default rather than to a different-but-plausible-looking behaviour.
		_: t["target_priority"] = "weakest"

	var intent := str(own.get("positionalIntent", plan.get("positionalIntent", "")))
	t["positional"] = intent if intent in ["hold", "push", "wings", "dive", "guard"] else "push"
	if t["positional"] == "guard":
		var charge = own.get("guardedAlly")
		var ci: int = all_units.find(charge) if charge != null else -1
		if ci >= 0 and ci < team_a.size():
			t["guard_ally"] = "a%02d" % ci
		elif ci >= team_a.size():
			t["guard_ally"] = "b%02d" % (ci - team_a.size())
		else:
			# A guard with nobody to guard is a posture with no meaning — fall to holding the
			# line, which is what "stay near where you deployed" already means.
			t["positional"] = "hold"

	# `cautious` is `tactics.gd`'s compressed stand-in for the preserve axis; the tree's own
	# survival axis is `when_hurt`, and falling back IS what refusing to trade down looks like
	# on a field with positions. aggressive/balanced remain the engine default, as the UI says.
	t["when_hurt"] = "fall_back" if str(own.get("temperament", "balanced")) == "cautious" else "fight_on"
	# Mirror the flank so the two sides' wings do not converge on the same corner.
	t["wing_side"] = 1.0 if side == "A" else -1.0
	return t


## ── THE TRANSLATION ────────────────────────────────────────────────────────────────────────
## Pure re-keying of the new stream into the legacy contract. Every value below is READ from the
## stream; the only computed things are index-from-id, seconds-from-ticks, and the legacy state
## words `attack`/`stunned`, both of which the stream states as facts (a strike event with this
## unit as `from`; an `incapacitates` status in its own list) and neither of which is a guess
## about the fight.
func _adapt_result(raw: Dictionary) -> Dictionary:
	var off: Vector2 = ground_size * 0.5   # centre-frame -> corner-frame (see the ⚠️⚠️ above)
	var idx_of: Dictionary = {}
	for k in range(all_units.size()):
		var side := "A" if k < team_a.size() else "B"
		var slot: int = k if side == "A" else k - team_a.size()
		idx_of[("a%02d" % slot) if side == "A" else ("b%02d" % slot)] = k

	var raw_frames: Array = raw.get("frames", [])
	# ⚠️ PROVE THE ADDRESS SPACE, DO NOT ASSUME IT. `nodes[k]`, `all_units[k]` and every frame
	# record must share one index. The sim sorts by string id, so this holds only while the
	# zero-padded ids sort into roster order — an eleventh monster on a side ("a10" vs "a9")
	# is exactly the kind of thing that would break it silently, which is why it is padded AND
	# checked rather than either alone.
	if not raw_frames.is_empty():
		var first: Array = raw_frames[0].get("units", [])
		assert(first.size() == all_units.size(),
			"sim returned %d units for a roster of %d" % [first.size(), all_units.size()])
		for i in range(first.size()):
			assert(int(idx_of.get(str(first[i].get("id", "")), -1)) == i,
				"sim unit order does not match the roster order at index %d" % i)
			# ⚠️ AND PROVE THE FRAME. Corner-frame positions must land inside [0,W]x[0,H]; the
			# centre/corner mix-up above is invisible to every "did it run" check and produces a
			# fight rendered off the edge of the board, so it gets a tripwire of its own.
			var fp: Vector2 = (first[i].get("pos", Vector2.ZERO) as Vector2) + off
			assert(fp.x >= 0.0 and fp.x <= ground_size.x and fp.y >= 0.0 and fp.y <= ground_size.y,
				"unit %d deploys off the board at %s (ground %s)" % [i, fp, ground_size])
	var out_frames: Array = []
	var log: Array = [{"kind": "start", "t": 0.0}]
	var last_alive_a := team_a.size()
	var last_alive_b := team_b.size()

	for rf in raw_frames:
		var t: float = float(int(rf.get("tick", 0))) * NewSim.DT
		var events: Array = rf.get("events", [])
		# Who STRUCK this tick — the legacy `attack` state, taken from the event list rather
		# than derived from motion.
		var struck: Dictionary = {}
		for e in events:
			if str(e.get("kind", "")) in ["strike", "cast_done", "proj_hit", "miss", "cast_miss"]:
				struck[str(e.get("from", ""))] = true

		var units_out: Array = []
		var alive_a := 0
		var alive_b := 0
		for rec in (rf.get("units", []) as Array):
			var uid := str(rec.get("id", ""))
			var k: int = int(idx_of.get(uid, -1))
			var alive: bool = bool(rec.get("alive", true))
			if alive:
				if uid.begins_with("a"):
					alive_a += 1
				else:
					alive_b += 1
			var kinds: Array = []
			var incap := false
			for s in (rec.get("statuses", []) as Array):
				var kind := str((s as Dictionary).get("kind", ""))
				kinds.append(kind)
				if bool((GameData.field_status.get(kind, {}) as Dictionary).get("incapacitates", false)):
					incap = true
			var state := str(rec.get("state", "idle"))
			if alive:
				if incap:
					state = "stunned"
				elif state != "cast" and struck.has(uid):
					state = "attack"
			units_out.append({
				# centre-frame -> corner-frame; facing/move_dir are DIRECTIONS and never shift.
				"id": k, "pos": (rec.get("pos", Vector2.ZERO) as Vector2) + off,
				"facing": rec.get("facing", Vector2(1, 0)),
				"moveDir": rec.get("move_dir", Vector2.ZERO),
				# `weary` is not on the new stream at all (see the contract note) — emitted false
				# so the chip is honestly absent rather than randomly present.
				"weary": false,
				"castMove": str(rec.get("castMove", "")),
				"castFrac": float(rec.get("castFrac", 0.0)),
				"hp": float(rec.get("hp", 0)), "mp": float(rec.get("mp", 0)),
				"alive": alive, "state": state, "statuses": kinds,
				"targetId": -1,
				"intent": str(rec.get("intent", "")), "reason": str(rec.get("reason", "")),
			})
		last_alive_a = alive_a
		last_alive_b = alive_b

		var shots: Array = []
		# A projectile move emits `proj_launch` AND `cast_done` on the same tick — the damage is
		# committed at launch but ARRIVES later, so only the arrival (`proj_hit`) may draw an
		# impact. Without this the shot would flash twice: once in the shooter's face.
		var launched: Dictionary = {}
		for e in events:
			if str(e.get("kind", "")) == "proj_launch":
				launched["%s|%s" % [str(e.get("from", "")), str(e.get("move", ""))]] = true
		for e in events:
			var kind := str(e.get("kind", ""))
			var from_i: int = int(idx_of.get(str(e.get("from", "")), -1))
			var to_i: int = int(idx_of.get(str(e.get("to", "")), -1))
			match kind:
				"strike", "miss":
					shots.append({"fromId": from_i, "toId": to_i, "kind": "melee",
						"hit": kind == "strike", "dmg": int(e.get("dmg", 0)),
						"crit": bool(e.get("crit", false)), "move": "Attack", "arc": "front"})
				"cast_done", "proj_hit", "cast_miss":
					var mvn := str(e.get("move", ""))
					if kind == "cast_done" and launched.has("%s|%s" % [str(e.get("from", "")), mvn]):
						continue
					shots.append({"fromId": from_i, "toId": to_i,
						"kind": _shot_kind_of(mvn),
						"hit": kind != "cast_miss", "dmg": int(e.get("dmg", 0)),
						"crit": bool(e.get("crit", false)), "move": mvn, "arc": "front"})
			var le := _adapt_event(e, t)
			if not le.is_empty():
				log.append(le)

		var projs: Array = []
		for p in (rf.get("projectiles", []) as Array):
			var pd: Dictionary = p
			# The new stream carries no projectile id, so one is MINTED from the shot's own
			# identity (shooter + target + move) — stable across frames, which is all
			# `_find_projectile` needs to interpolate a streak between two frames.
			var pid: int = hash("%s>%s|%s" % [str(pd.get("from", "")), str(pd.get("target_id", "")),
				str(pd.get("move", ""))])
			projs.append({"id": pid, "from": (pd.get("pos", Vector2.ZERO) as Vector2) + off,
				"to": (pd.get("aim", pd.get("pos", Vector2.ZERO)) as Vector2) + off,
				"progress": 0.0,
				"kind": _shot_kind_of(str(pd.get("move", "")))})

		out_frames.append({"t": t, "units": units_out, "shots": shots, "projectiles": projs})

	var duration: float = float(int(raw.get("ticks", 0))) * NewSim.DT
	var winner := str(raw.get("winner", ""))
	if winner == "":
		winner = "draw"
	log.append({"kind": "end", "winner": winner, "duration": duration, "t": duration})
	_write_back_final(out_frames)
	return {"winner": winner, "duration": duration, "log": log,
		"survivorsA": last_alive_a, "survivorsB": last_alive_b,
		"groundSize": ground_size, "obstacles": _obstacles, "frames": out_frames,
		"decisionLogs": raw.get("decision_logs", {})}


## A move's CHANNEL is what the VFX and projectile art key off. It comes from the authored move
## (already loaded into `_move_by_name` for the ability-VFX cascade), never from a guess.
func _shot_kind_of(move_name: String) -> String:
	var mv: Dictionary = _move_by_name.get(move_name, {})
	return str(mv.get("channel", "melee"))


## Event → legacy log record. The log dispatch (`_log_event`) addresses monsters by SPECIES NAME,
## so ids are resolved through `all_units` here — the one place the two vocabularies meet.
func _adapt_event(e: Dictionary, t: float) -> Dictionary:
	var from_n := _name_of_sim_id(str(e.get("from", "")))
	var to_n := _name_of_sim_id(str(e.get("to", "")))
	match str(e.get("kind", "")):
		"strike":
			return {"kind": "hit", "attacker": from_n, "target": to_n, "move": "Attack",
				"dmg": int(e.get("dmg", 0)), "crit": bool(e.get("crit", false)), "t": t}
		"cast_done", "proj_hit":
			return {"kind": "hit", "attacker": from_n, "target": to_n,
				"move": str(e.get("move", "")), "dmg": int(e.get("dmg", 0)),
				"crit": bool(e.get("crit", false)), "t": t}
		"miss":
			return {"kind": "miss", "attacker": from_n, "target": to_n, "move": "Attack", "t": t}
		"cast_miss":
			return {"kind": "miss", "attacker": from_n, "target": to_n,
				"move": str(e.get("move", "")), "t": t}
		"status_applied":
			return {"kind": "status_apply", "unit": to_n, "status": str(e.get("status", "")), "t": t}
		"status_expire":
			return {"kind": "status_expire", "unit": to_n, "status": str(e.get("status", "")), "t": t}
		"heal":
			return {"kind": "heal", "caster": from_n, "unit": to_n, "move": str(e.get("move", "")),
				"amount": int(e.get("amount", 0)), "t": t}
		"buff":
			return {"kind": "buff", "caster": from_n, "unit": to_n,
				"move": str(e.get("move", "")), "t": t}
		"cleanse":
			return {"kind": "cleanse", "by": from_n, "unit": to_n, "move": str(e.get("move", "")),
				"broke": e.get("broke", []), "t": t}
		"interrupt":
			# ⚠️ The new `interrupt` event names the KICKER and the victim but not the cast it
			# denied. The log line says so rather than inventing a move name.
			return {"kind": "interrupt", "unit": to_n, "move": "its cast",
				"reason": "%s kicked it" % from_n, "t": t}
		"death":
			return {"kind": "death", "unit": _name_of_sim_id(str(e.get("id", ""))), "t": t}
	return {}


func _name_of_sim_id(sim_id: String) -> String:
	if sim_id == "":
		return "?"
	var slot: int = sim_id.substr(1).to_int()
	var k: int = slot if sim_id.begins_with("a") else team_a.size() + slot
	return str(all_units[k].species_name) if k >= 0 and k < all_units.size() else "?"


## ⚠️ THE NEW SIM DOES NOT TOUCH THE MONSTER OBJECTS — it works entirely on its own dicts, which
## is correct (injected state, nothing global) but leaves every `MonsterInstance.alive` reading
## true forever. `_skip()`'s topple loop, the report screen and the career all read those, so the
## final frame is written back once here. This is bookkeeping the OLD sim did as a side effect of
## mutating the roster; doing it explicitly is the honest version of the same thing.
func _write_back_final(out_frames: Array) -> void:
	if out_frames.is_empty():
		return
	for rec in (out_frames[out_frames.size() - 1].get("units", []) as Array):
		var k: int = int(rec.get("id", -1))
		if k < 0 or k >= all_units.size():
			continue
		var m = all_units[k]
		m.hp = maxf(0.0, float(rec.get("hp", 0.0)))
		m.mp = float(rec.get("mp", 0.0))
		m.alive = bool(rec.get("alive", false))


func _show_resolving(v: bool) -> void:
	if resolving_label != null:
		resolving_label.visible = v


func _update_mode_label() -> void:
	if mode_label == null:
		return
	if used_spatial:
		# ⚠️ Reports what is ON THE FIELD, not what the generator produced. With SHOW_OBSTACLES off
		# `_obstacles` is empty and the header said "124 obstacles" over an empty board — a HUD that
		# describes a world the player is not looking at is worse than no HUD.
		mode_label.text = "%s · %d frames · ground %d×%d · %d obstacles" % [
			_layout_name, frames.size(), int(ground_size.x), int(ground_size.y), _obstacles.size()]
	else:
		mode_label.text = "non-spatial fallback (spatial sim not present)"


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# WORLD
# ═══════════════════════════════════════════════════════════════════════════════════════════════

## Ground coordinates (origin at a corner, +y = "north") -> world (origin at board centre, X/Z).
func _to_world(p: Vector2) -> Vector3:
	return Vector3(
		(p.x - ground_size.x * 0.5) * WORLD_SCALE,
		0.0,
		(p.y - ground_size.y * 0.5) * WORLD_SCALE)


func _build_world() -> void:
	var bw := ground_size.x * WORLD_SCALE
	var bd := ground_size.y * WORLD_SCALE

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.06, 0.07, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.68, 0.70, 0.76)
	e.ambient_light_energy = 1.25
	e.fog_enabled = true
	e.fog_light_color = Color(0.32, 0.34, 0.40)
	e.fog_density = 0.004
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-56, -38, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	add_child(sun)

	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(bw, bd)
	floor_mesh.mesh = pm
	var fm := StandardMaterial3D.new()
	var gtex: Texture2D = Art.ground_for(league_name, _league_names())
	if gtex != null:
		fm.albedo_texture = gtex
		fm.uv1_scale = Vector3(bw / 6.0, bd / 6.0, 1.0)
	else:
		fm.albedo_color = Color(0.55, 0.50, 0.43)
	fm.roughness = 0.95
	floor_mesh.material_override = fm
	add_child(floor_mesh)

	_build_venue(bw, bd)
	_build_deploy_zones(bw, bd)
	if SHOW_OBSTACLES:
		_build_obstacles()
	_build_banners(bw, bd)

	camera = Camera3D.new()
	camera.fov = CAM_FOV
	add_child(camera)
	# ⚠️ NOT `Sp.leash_radius(...)`. That function was renamed to `engagement_radius` and
	# re-scoped to a LAYOUT helper for cover placement only — `spatial.gd`'s own header says it
	# "must never gate movement again", and using it here would re-couple the camera to the exact
	# concept that was just removed. The camera's initial and ongoing framing comes only from the
	# board's own size and, every frame after, from where the living units actually are
	# (`_camera_target()`) — never from a formula about where a fight is "supposed" to cluster.
	_cam_max_span = Vector2(bw, bd).length() * 0.5 * 1.05
	_cam_center = Vector3.ZERO
	_cam_span = _cam_max_span
	_apply_camera_now()


## One MultiMeshInstance3D for the 4 wall boxes and one for the 20 stand-tier boxes — instead of
## 24 individual `MeshInstance3D` nodes each with their own `material_override`.
## `docs/PERFORMANCE_BUDGETS.md` §5 names this exact pattern as "the single biggest current cost":
## same mesh, same material, only the transform differs per instance — a textbook MultiMesh case.
## THE DEPLOYMENT ZONES, drawn flat on the ground — the band each side actually spawns into, from
## `Spatial.deploy_positions`/`deploy_depth` rather than a shape invented here. With the obstacles
## off, these are the only landmarks on the field, and without landmarks "did they use the space?"
## is unanswerable: every position looks like every other position.
##
## ⚠️ TEAM COLOUR, NOT NEW COLOUR. `ART_BIBLE_GUILD_COLOURS.md` allows exactly three colour
## systems and forbids a fourth, so these take `Art.team_identity()`'s own hues at low alpha —
## they read as "this is A's ground" without competing with the status channel, which the bible
## reserves as the brightest thing in frame.
func _build_deploy_zones(bw: float, bd: float) -> void:
	var team_size: int = maxi(team_a.size(), team_b.size())
	var depth: float = Sp.deploy_depth(team_size) * WORLD_SCALE
	var sep: float = Sp.deploy_separation(team_size) * WORLD_SCALE
	for side in range(2):
		var dir := -1.0 if side == 0 else 1.0
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		# ⚠️ Sized from the SIM's own deploy band, not from a fraction of the board. The zone is
		# only useful as a landmark if it is where units actually spawn — a decorative rectangle
		# near the right area would make "did they hold their zone?" unanswerable.
		# ⚠️ THE WHOLE LEGAL ZONE, EDGE TO SEPARATION LINE (user call 2026-08-06). The thin strip
		# only marked the default spawn band; the deployment board lets a chip stand anywhere in
		# `Spatial.deploy_zone`, so the paint must cover exactly what the sim permits.
		var zone: Rect2 = Sp.deploy_zone(team_size, "A" if side == 0 else "B")
		pm.size = Vector2(zone.size.x * WORLD_SCALE, bd)
		mi.mesh = pm
		var m := StandardMaterial3D.new()
		var col: Color = Art.team_identity(side)["colour"]
		m.albedo_color = Color(col.r, col.g, col.b, 0.42)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = m
		# Lifted a hair off the floor so it does not z-fight with the ground texture.
		var zone2: Rect2 = Sp.deploy_zone(team_size, "A" if side == 0 else "B")
		var cx_w: float = (zone2.position.x + zone2.size.x * 0.5 - Sp.ground_size(team_size).x * 0.5) * WORLD_SCALE
		mi.position = Vector3(cx_w, 0.02, 0.0)
		add_child(mi)

	# The centre line — the thing both sides are walking toward, and the only way to see at a
	# glance which side has taken ground.
	var line := MeshInstance3D.new()
	var lm := PlaneMesh.new()
	lm.size = Vector2(0.6, bd * 0.88)
	line.mesh = lm
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(1, 1, 1, 0.22)
	lmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	line.material_override = lmat
	line.position = Vector3(0, 0.03, 0)
	add_child(line)


func _build_venue(bw: float, bd: float) -> void:
	var wall_mat := StandardMaterial3D.new()
	var wtex: Texture2D = Art.load_or_null("res://assets/arena/wall-timber.jpg")
	if wtex != null:
		wall_mat.albedo_texture = wtex
		wall_mat.uv1_scale = Vector3(bw / 5.0, 1.0, 1.0)
	else:
		wall_mat.albedo_color = Color(0.30, 0.24, 0.19)
	wall_mat.roughness = 0.9

	var wall_xforms: Array = [
		_box_xform(Vector3(0, WALL_H * 0.5, -bd * 0.5 - 0.4), Vector3(bw + 1.6, WALL_H, 0.8)),
		_box_xform(Vector3(0, WALL_H * 0.5, bd * 0.5 + 0.4), Vector3(bw + 1.6, WALL_H, 0.8)),
		_box_xform(Vector3(-bw * 0.5 - 0.4, WALL_H * 0.5, 0), Vector3(0.8, WALL_H, bd + 1.6)),
		_box_xform(Vector3(bw * 0.5 + 0.4, WALL_H * 0.5, 0), Vector3(0.8, WALL_H, bd + 1.6)),
	]
	add_child(_multimesh_boxes(wall_xforms, wall_mat))

	var stand_mat := StandardMaterial3D.new()
	var ctex: Texture2D = Art.load_or_null("res://assets/arena/stands-crowd.jpg")
	if ctex != null:
		stand_mat.albedo_texture = ctex
		stand_mat.uv1_scale = Vector3(bw / 8.0, 1.0, 1.0)
	else:
		stand_mat.albedo_color = Color(0.24, 0.21, 0.18)
	stand_mat.roughness = 0.95

	var stand_xforms: Array = []
	for tier in range(STAND_TIERS):
		var t := float(tier)
		var h := WALL_H + 0.8 + t * 0.8
		var out := 1.1 + t * 1.6
		stand_xforms.append(_box_xform(Vector3(0, h * 0.5, -bd * 0.5 - out), Vector3(bw + 2.0 + out * 2.0, h, 1.6)))
		stand_xforms.append(_box_xform(Vector3(0, h * 0.5, bd * 0.5 + out), Vector3(bw + 2.0 + out * 2.0, h, 1.6)))
		stand_xforms.append(_box_xform(Vector3(-bw * 0.5 - out, h * 0.5, 0), Vector3(1.6, h, bd + 2.0 + out * 2.0)))
		stand_xforms.append(_box_xform(Vector3(bw * 0.5 + out, h * 0.5, 0), Vector3(1.6, h, bd + 2.0 + out * 2.0)))
	add_child(_multimesh_boxes(stand_xforms, stand_mat))


## A handful of guild banners on the near wall — real dressing, not a grey box venue. Skipped
## entirely (not a placeholder colour) when the art hasn't generated yet; a missing banner is not
## worth a fallback rectangle the way a missing wall/ground texture is.
func _build_banners(bw: float, bd: float) -> void:
	var tex: Texture2D = Art.load_or_null("res://assets/arena/banner-guild.png")
	if tex == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var xs := [-bw * 0.28, 0.0, bw * 0.28]
	for x in xs:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1.6, 2.2)
		q.mesh = qm
		q.position = Vector3(x, WALL_H + 1.15, -bd * 0.5 - 0.42)
		q.material_override = mat
		add_child(q)


func _box_xform(pos: Vector3, box_size: Vector3) -> Transform3D:
	return Transform3D(Basis().scaled(box_size), pos)


## Fallback primitives get RIM LIGHTING (AD: "a perfect 90° edge catches no highlight... reads
## as a diagram of a box"). Rim is the cheap stand-in for bevels until every kind has a GLB —
## the edge catches light, so an undressed obstacle no longer reads cruder than its neighbour.
func _rim(mat: Material) -> Material:
	if mat is StandardMaterial3D:
		var m2 := (mat as StandardMaterial3D).duplicate()
		m2.rim_enabled = true
		m2.rim = 0.55
		m2.rim_tint = 0.6
		return m2
	return mat


func _multimesh_boxes(xforms: Array, mat: Material) -> MultiMeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = bm
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	return mmi


func _multimesh_cylinders(xforms: Array, mat: Material) -> MultiMeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5
	cm.bottom_radius = 0.5
	cm.height = 1.0
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cm
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	return mmi


## Obstacles grouped by `kind` — one MultiMeshInstance3D per kind present, instead of one node per
## piece. Count scales with ground AREA (`arena_layout.gd`), so this is where draw calls would
## otherwise grow with team size; grouped instancing keeps it flat at "number of kinds", not
## "number of pieces".
func _build_obstacles() -> void:
	var box_groups: Dictionary = {}     # kind -> Array[Transform3D]
	var cyl_groups: Dictionary = {}     # kind -> Array[Transform3D]  (the round kinds below)
	for o in _obstacles:
		var kind: String = str(o.get("kind", "crate"))
		var r: Rect2 = o["rect"]
		var grade: String = str(o.get("grade", "soft"))
		var centre := _to_world(r.position + r.size * 0.5)
		var w := maxf(r.size.x * WORLD_SCALE, 0.6)
		var d := maxf(r.size.y * WORLD_SCALE, 0.6)
		# Height carries the cover GRADE, so what a player sees matches what the sim applies:
		# blocking cover is tall enough to stop a shot, soft cover is knee-high.
		var h := 1.0
		if grade == "blocking":
			h = 3.2
		elif grade == "hard":
			h = 2.0
		var xf := Transform3D(Basis().scaled(Vector3(w, h, d)), centre + Vector3(0, h * 0.5, 0))
		if kind == "barrel" or kind == "boulder":
			if not cyl_groups.has(kind):
				cyl_groups[kind] = []
			cyl_groups[kind].append(xf)
		else:
			if not box_groups.has(kind):
				box_groups[kind] = []
			box_groups[kind].append(xf)

	# ⚠️ REAL MESHES FIRST, PRIMITIVES AS THE FALLBACK. A kind with no model on disk still renders
	# as a tinted box or cylinder exactly as before, so a missing file is a plainer arena rather
	# than an empty one.
	for kind in box_groups.keys():
		if not _try_prop_multimesh(kind, box_groups[kind]):
			add_child(_multimesh_boxes(box_groups[kind], _rim(_obstacle_material(kind))))
	for kind in cyl_groups.keys():
		if not _try_prop_multimesh(kind, cyl_groups[kind]):
			add_child(_multimesh_cylinders(cyl_groups[kind], _obstacle_material(kind)))


const PROP_DIR := "res://assets/models/obstacles/"

## One `MultiMeshInstance3D` per kind, drawing the CC0 prop instead of a primitive.
##
## ⚠️ THE SINGLE-MESH / SINGLE-MATERIAL RULE IS WHY THESE PARTICULAR PROPS WERE CHOSEN. A
## `MultiMesh` takes ONE mesh with ONE material, and obstacle count scales with ground area — so a
## multi-material prop does not merely look different, it forces a node per piece and grows draw
## calls with team size. 28 of the 70 CC0 models inspected failed that test
## (`docs/OBSTACLE_KIND_CANDIDATES.md`); every file here passed it.
##
## ⚠️ AND THE FIT IS PER-AXIS, WHICH IS A DELIBERATE TRADE. The sim's cover rect is authoritative:
## `Spatial.cover_between` tests that rectangle, and the grade is carried by height. Fitting the
## prop to it exactly means the player sees precisely the cover the sim applies — at the cost of
## stretching a prop whose proportions differ from its kind's footprint. The alternative, a
## uniform scale, looks better and LIES: a barrel drawn narrower than its rect gives cover from a
## spot that looks open. In a game the player cannot intervene in, being able to trust the picture
## outranks the picture being pretty.
func _try_prop_multimesh(kind: String, xforms: Array) -> bool:
	var path := PROP_DIR + kind + ".glb"
	if not ResourceLoader.exists(path):
		return false
	var scn := load(path) as PackedScene
	if scn == null:
		return false
	var inst: Node = scn.instantiate()
	var mi := _first_mesh(inst) as MeshInstance3D
	if mi == null or mi.mesh == null:
		inst.free()
		return false

	# Bounds in the INSTANCE's own space — the glTF importer parks its own scale between the scene
	# root and the mesh, and it differs per export, so the raw local AABB is in the wrong units.
	#
	# ⚠️ WALKED BY HAND, NOT VIA `global_transform`. This scene is never added to the tree — it is
	# instantiated only to harvest its mesh — and `global_transform` on a node outside the tree
	# returns identity while spamming "Condition !is_inside_tree() is true". Adding it to the tree
	# just to measure it would be a node built and freed per kind, per fight.
	var ab: AABB = _chain_from(inst, mi) * mi.get_aabb()
	var mesh: Mesh = mi.mesh
	var mat: Material = mi.get_active_material(0)
	inst.free()
	if ab.size.x <= 0.0001 or ab.size.y <= 0.0001 or ab.size.z <= 0.0001:
		return false

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		# `xf` already encodes the target box: basis scale is (w, h, d) and the origin sits at the
		# box's CENTRE. Convert that into "fit this prop's own bounds into that box".
		var xf: Transform3D = xforms[i]
		var want: Vector3 = xf.basis.get_scale()
		var s := Vector3(want.x / ab.size.x, want.y / ab.size.y, want.z / ab.size.z)
		# Re-seat on the ground: the prop's own minimum, scaled, is the offset from the box centre.
		var foot: float = xf.origin.y - want.y * 0.5
		var pos := Vector3(xf.origin.x, foot - ab.position.y * s.y, xf.origin.z)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(s), pos))

	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	if mat != null:
		node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(node)
	return true


## The accumulated local transform from `root` down to `node`, for a scene that is not in the
## tree. Multiplies parent-to-child so the result maps `node`'s local space into `root`'s.
static func _chain_from(root: Node, node: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _first_mesh(n: Node) -> Node:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _first_mesh(c)
		if r != null:
			return r
	return null


func _obstacle_material(kind: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var tex: Texture2D = Art.load_or_null(OBSTACLE_TEX.get(kind, "res://assets/arena/crate-wood.jpg"))
	if tex != null:
		mat.albedo_texture = tex
		mat.albedo_color = OBSTACLE_TINT.get(kind, Color(1, 1, 1))
	else:
		mat.albedo_color = OBSTACLE_TINT.get(kind, OBSTACLE_FALLBACK.get(kind, Color(0.5, 0.45, 0.35)))
	mat.roughness = 0.9
	return mat


func _league_names() -> Array:
	var career := get_node_or_null("/root/Career")
	if career == null:
		return Art.ARENA_LEAGUES
	var names: Array = []
	for l in career.leagues:
		names.append(l.get("name", ""))
	return names


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# CAMERA — follows the living units' own spread, never a static formula.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

## Bounding box of the currently-alive units (all units if none are alive yet/left), in world
## space, padded and clamped. This is the ONLY thing the camera reads to decide where to look —
## positions the frame stream already gave the renderer, nothing invented.
func _camera_target() -> Dictionary:
	if _cam_mode == CamMode.FREE:
		return {"center": _free_center, "span": _free_span}
	# ⚠️ Observation mode — frame the whole ground and never move.
	if _cam_mode == CamMode.ARENA:
		var bw := ground_size.x * WORLD_SCALE
		var bd := ground_size.y * WORLD_SCALE
		# The ground's half-depth is foreshortened by the camera pitch; its half-width is not. Take
		# whichever needs the wider frame so neither edge is cropped.
		# ⚠️ `span` is the half-extent that fills the VERTICAL fov, so a width cannot be compared
		# against it directly — it has to be divided by the aspect ratio first. Comparing them raw
		# over-sized the frame by the full 16:9, which is why the whole arena sat as a small slab
		# with empty margins above and below it.
		var aspect: float = maxf(0.1, get_viewport().get_visible_rect().size.aspect())
		var need_x: float = (bw * 0.5) / aspect
		var need_z: float = bd * 0.5 * sin(deg_to_rad(CAM_PITCH_DEG))
		return {"center": Vector3.ZERO, "span": maxf(need_x, need_z) * 1.04}

	var pts: Array = []
	for k in range(nodes.size()):
		if k >= all_units.size() or not all_units[k].alive:
			continue
		# TEAM mode: frame YOUR side (team A) — the fight from the owner's box seat. The enemy
		# enters frame exactly when it engages your line, which is when it matters.
		if _cam_mode == CamMode.TEAM and not (all_units[k] in team_a):
			continue
		pts.append((nodes[k]["holder"] as Node3D).position)
	if pts.is_empty():
		for k in range(nodes.size()):
			pts.append((nodes[k]["holder"] as Node3D).position)
	if pts.is_empty():
		return {"center": Vector3.ZERO, "span": _cam_max_span}

	var mn: Vector3 = pts[0]
	var mx: Vector3 = pts[0]
	for p in pts:
		mn.x = minf(mn.x, p.x); mn.z = minf(mn.z, p.z)
		mx.x = maxf(mx.x, p.x); mx.z = maxf(mx.z, p.z)
	var center := Vector3((mn.x + mx.x) * 0.5, 0.0, (mn.z + mx.z) * 0.5)
	# ⚠️ Bodies, not points — see the constants above. A creature standing on the edge of the pack
	# extends half a footprint further out than the position the sim reports for it, and its head
	# extends upward into screen space the ground box cannot see.
	var half_x := (mx.x - mn.x) * 0.5 + CAM_BODY_RADIUS
	var half_z := (mx.z - mn.z) * 0.5 + CAM_BODY_RADIUS
	var span := maxf(half_x, half_z) * CAM_PADDING + CAM_HEADROOM + CAM_HEIGHT_ALLOWANCE
	span = maxf(span, CAM_MIN_SPAN)
	span = minf(span, _cam_max_span)
	return {"center": center, "span": span}


## Places the camera at the CURRENT `_cam_center`/`_cam_span`, geometrically guaranteed to look
## exactly at `_cam_center` regardless of span: distance R is chosen so the span fills the FOV,
## then decomposed into height/depth by the fixed pitch, and `look_at` does the rest — no
## rotation-convention guesswork.
func _apply_camera_now() -> void:
	var theta := deg_to_rad(CAM_PITCH_DEG)
	var fov_half := deg_to_rad(camera.fov * 0.5)
	var r: float = _cam_span / tan(fov_half)
	var h: float = r * sin(theta)
	var d: float = r * cos(theta)
	camera.position = _cam_center + Vector3(0, h, d)
	camera.look_at(_cam_center, Vector3.UP)


func _update_camera(delta: float) -> void:
	if camera == null:
		return
	var target: Dictionary = _camera_target()
	var a := 1.0 - exp(-CAM_FOLLOW_RATE * delta)
	_cam_center = _cam_center.lerp(target["center"], a)
	_cam_span = lerpf(_cam_span, target["span"], a)
	_apply_camera_now()
	# Camera punch: a small decaying offset AFTER positioning, so the follow logic never fights
	# it. Pseudo-random from playback time — render-only, the sim knows nothing of it.
	if _shake > 0.004:
		var tphase := frame_pos * 12.7
		camera.position += Vector3(sin(tphase * 1.13), sin(tphase * 0.71) * 0.6, cos(tphase * 1.31)) \
			* _shake * UNIT_HEIGHT * 0.18
		_shake *= exp(-9.0 * delta)


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# UNITS
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _build_units() -> void:
	nodes.clear()
	_build_shadow_multimesh()
	for i in range(all_units.size()):
		var m = all_units[i]
		var side := "A" if i < team_a.size() else "B"
		m.side = side
		var holder := Node3D.new()
		add_child(holder)

		# ⚠️ THE RIGGED PATH IS TRIED FIRST, AND ITS ABSENCE IS NOT AN ERROR. The roster is 65
		# species and models arrive one at a time, so for most of this project's life MOST units
		# will fall through to the sprite below. `creature_rig.gd` presents the same
		# `setup`/`set_state`/`flinch` interface `creature_anim.gd` does, so everything downstream
		# — `_apply_frame`, the flinch on a landed shot, the death topple — drives either one
		# without knowing which it got.
		#
		# ⚠️ A rigged unit gets NO Sprite3D at all. Building both and hiding one would leave a
		# billboarded quad inside the holder that `_apply_frame` still writes to every tick, and
		# the first person to debug a facing bug would find two things claiming to be the body.
		var rig = CreatureRigScript.new()
		holder.add_child(rig)
		if rig.build(m.species_id, UNIT_HEIGHT):
			var rplate := _make_plate(m, side, i)
			plates_root.add_child(rplate)
			nodes.append({
				"holder": holder, "sprite": null, "rig": rig, "plate": rplate, "anim": rig,
				"hp_fill": rplate.get_meta("hp_fill"), "hp_text": rplate.get_meta("hp_text"),
				"mp_fill": rplate.get_meta("mp_fill"), "mp_text": rplate.get_meta("mp_text"), "cast_bg": rplate.get_meta("cast_bg"),
				"cast_fill": rplate.get_meta("cast_fill"), "cast_lbl": rplate.get_meta("cast_lbl"), "cast_icon": rplate.get_meta("cast_icon"),
				"status_row": rplate.get_meta("status_row"), "intent_lbl": rplate.get_meta("intent_lbl"),
				"border": rplate.get_meta("border"), "last_rec": {},
				"_status_sig": "", "_state_sig": "",
				"dead": false,
			})
			continue
		rig.queue_free()

		var spr := Sprite3D.new()
		var tex: Texture2D = Art.creature_texture(m.species_id)
		if tex != null:
			spr.texture = tex
			spr.pixel_size = UNIT_HEIGHT / float(tex.get_height())
		else:
			var ph := PlaceholderTexture2D.new()
			ph.size = Vector2(180, 380)
			spr.texture = ph
			spr.pixel_size = UNIT_HEIGHT / 380.0
			# ⚠️ `Art.team_identity(...)["colour"]`, not `Art.team_colour(...)` alone
			# (`docs/ACCESSIBILITY.md` §2, `arena_3d.gd:316` finding) — future-proofed so this
			# fallback tint is never the ONLY team tell if nameplates are ever made toggleable.
			spr.modulate = Art.team_identity(0 if side == "A" else 1)["colour"]
		spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		spr.shaded = false
		spr.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		spr.flip_h = (side == "B")
		spr.position = Vector3(0, UNIT_HEIGHT * 0.5, 0)
		holder.add_child(spr)

		# ⚠️ PROCEDURAL ANIMATION — see docs/MESHY_SPIKE_RESULT.md. Meshy's auto-rig is
		# HUMANOID-ONLY (it refused an avian with `422 Pose estimation failed`), and the roster is
		# 65 species across 13 body types, so skeletal animation cannot cover it. This poses the
		# whole body from the frame stream's own `state`/`facing` and works identically for every
		# body — including the ones no rig will ever fit.
		#
		# ⚠️ Drives the SPRITE, not the holder. The holder carries the unit's world POSITION,
		# which `_apply_frame` writes every tick from the sim; animating it would fight the sim
		# for the same transform and the unit would visibly stutter.
		var anim = CreatureAnimScript.new()
		holder.add_child(anim)
		anim.setup(spr)

		var plate := _make_plate(m, side, i)
		plates_root.add_child(plate)
		nodes.append({
			"holder": holder, "sprite": spr, "plate": plate, "anim": anim,
			"hp_fill": plate.get_meta("hp_fill"), "hp_text": plate.get_meta("hp_text"),
			"mp_fill": plate.get_meta("mp_fill"), "mp_text": plate.get_meta("mp_text"), "cast_bg": plate.get_meta("cast_bg"),
			"cast_fill": plate.get_meta("cast_fill"), "cast_lbl": plate.get_meta("cast_lbl"), "cast_icon": plate.get_meta("cast_icon"),
			"status_row": plate.get_meta("status_row"), "intent_lbl": plate.get_meta("intent_lbl"),
			"border": plate.get_meta("border"), "last_rec": {},
			"_status_sig": "", "_state_sig": "",
			"dead": false,
		})


## One MultiMeshInstance3D for every unit's ground shadow, per-instance COLOUR (not just
## transform) so a fallen unit's shadow dims along with its plate — `MultiMesh.use_colors`
## requires the material's `vertex_color_use_as_albedo` to actually read it.
func _build_shadow_multimesh() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(1.9, 1.2)
	var mat := StandardMaterial3D.new()
	var grad := GradientTexture2D.new()
	grad.fill = GradientTexture2D.FILL_RADIAL
	grad.fill_from = Vector2(0.5, 0.5)
	grad.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.55))
	g.set_color(1, Color(0, 0, 0, 0.0))
	grad.gradient = g
	grad.width = 64; grad.height = 64
	mat.albedo_texture = grad
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = q
	mm.instance_count = maxi(1, all_units.size())
	var flat_xf := Transform3D(Basis(Vector3(1, 0, 0), deg_to_rad(-90)), Vector3(0, 0.03, 0))
	for i in range(mm.instance_count):
		mm.set_instance_transform(i, flat_xf)
		mm.set_instance_color(i, Color(1, 1, 1, 1))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)
	shadow_mm = mm


## Team + badge + border + name/HP/status. Bigger text than the earlier pass on purpose —
## `docs/ACCESSIBILITY.md` §5/§8 flags 9px/8px as roughly HALF the 18px floor and asks for the fix
## BEFORE density gets worse, not after.
func _make_plate(m, side: String, idx: int) -> Control:
	var ident: Dictionary = Art.team_identity(0 if side == "A" else 1)
	# ⚠️ FULLY FRAMELESS (user direction 2026-08-06): every text element now carries its own
	# black outline, so the plate needs no card at all — the UI floats on the scene. The team
	# identity tell moves from the border to the badge glyph (kept, a11y load-bearing) and the
	# team-coloured HP bar edge below.
	var plate_bg := Color(0.085, 0.07, 0.055, 0.0)
	var border_col := _accessible_border(ident["colour"], plate_bg)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = plate_bg
	sb.border_color = border_col
	sb.set_border_width_all(0)   # frameless — the badge glyph and bar edge carry team identity
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 4; sb.content_margin_right = 4
	sb.content_margin_top = 2; sb.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", sb)
	# ⚠️ SIZED FOR THE PULLED-BACK CAMERA (2026-08-05). Plates are SCREEN-SPACE, so when the camera
	# moved from 58deg/40fov to 38deg/26fov the units shrank and the plates did not — five of them
	# stacked into an unreadable wall across the top of the frame, hiding the fight they annotate.
	# 148 -> 104 wide with smaller type.
	#
	# ⚠️ AND 104 WAS STILL TOO WIDE ONCE THE BOARD TRIPLED. The ground went 160x88 -> 352x194 and
	# the units spread properly, so the fight now occupies a QUARTER of the frame while ten plates
	# at 104px occupied most of the rest — the annotation was larger than the thing annotated.
	# 104 -> 82. ⚠️ THIS IS THE FLOOR: `docs/ACCESSIBILITY.md` sets the minimum readable type and
	# the 11px name below is at it. Any further reduction has to come from showing FEWER plates,
	# not smaller ones — which is what the quiet-unit fade below does instead.
	panel.custom_minimum_size = Vector2(82, 0)
	# Tier-2 disclosure — clicking a plate opens ITS callout (only one open at a time). Real
	# `Control` input, not a paint-only panel, so it is Tab/Enter reachable too (`_unhandled_input`
	# below handles the keyboard path per `docs/UX_LEGIBILITY.md` §10 / `docs/ACCESSIBILITY.md` #1).
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(func(ev): _on_plate_input(ev, idx))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	panel.add_child(col)

	# ── PLATER GRAMMAR (user direction 2026-08-06, after WoW's Plater addon): a compact dark
	# plate — tiny name, slim health bar with % inside, hair-thin mana bar, and a CAST BAR below
	# that appears only while casting, carrying the ability name (icons join it when the ability
	# icon set exists). The innate line and large chips are gone: minimalist is the spec, and the
	# innate is still one Tab away on the orders panel.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 3)
	col.add_child(head)
	var nm := Label.new()
	nm.text = "%s %s" % [ident["badge"], m.species_name]
	nm.add_theme_font_size_override("font_size", 18)
	nm.add_theme_color_override("font_color", Color(0.96, 0.96, 0.98))
	nm.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	nm.add_theme_constant_override("outline_size", 4)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(nm)
	var intent_lbl := Label.new()
	intent_lbl.text = ""
	intent_lbl.add_theme_font_size_override("font_size", 18)
	intent_lbl.add_theme_color_override("font_color", Color(0.88, 0.88, 0.92))
	intent_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	intent_lbl.add_theme_constant_override("outline_size", 4)
	head.add_child(intent_lbl)

	# The team RULE: with the border gone, this slim line under the name carries the team
	# COLOUR (the badge glyph carries the non-colour tell — both survive framelessness).
	var team_rule := ColorRect.new()
	team_rule.color = border_col
	team_rule.custom_minimum_size = Vector2(176, 3)
	col.add_child(team_rule)

	# bars live in one column so the death-hide collapses all of them together
	var bars := VBoxContainer.new()
	bars.add_theme_constant_override("separation", 1)
	col.add_child(bars)

	# ⚠️ TRUE BARS (user direction 2026-08-06): the troughs were PanelContainers, and containers
	# STRETCH children — the fill fought the layout instead of being a clean fraction of a fixed
	# trough. Each bar is now a plain Control (fixed size, no layout opinions) holding a
	# semi-transparent background and a left-anchored fill whose width IS the fraction:
	# full [==========] · half [=====/////] — the empty remainder always visible.
	var bar_bg := Control.new()
	bar_bg.custom_minimum_size = Vector2(176, 20)
	bars.add_child(bar_bg)
	var hp_trough := ColorRect.new()
	hp_trough.color = Color(0.05, 0.04, 0.03, 0.08)   # user-tuned 2026-08-06 (round 2): a ghost of a trough
	hp_trough.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar_bg.add_child(hp_trough)
	var fill := ColorRect.new()
	fill.color = Color(0.32, 0.76, 0.36)
	fill.position = Vector2(1, 1)
	fill.size = Vector2(174, 18)
	bar_bg.add_child(fill)
	var hp_text := Label.new()
	hp_text.text = ""
	hp_text.add_theme_font_size_override("font_size", 16)
	hp_text.add_theme_color_override("font_color", Color(1, 1, 1))
	# ⚠️ The outline is what makes the number readable — white on mid-green fails contrast at ANY
	# size; a 3px black outline reads over every fill colour and every HP state.
	hp_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hp_text.add_theme_constant_override("outline_size", 3)
	hp_text.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	hp_text.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hp_text.position = Vector2(-4, 0)
	bar_bg.add_child(hp_text)

	# mana: hair-thin, the caster's second resource always visible
	var mp_bg := Control.new()
	mp_bg.custom_minimum_size = Vector2(176, 12)
	bars.add_child(mp_bg)
	var mp_trough := ColorRect.new()
	mp_trough.color = Color(0.04, 0.05, 0.08, 0.08)
	mp_trough.set_anchors_preset(Control.PRESET_FULL_RECT)
	mp_bg.add_child(mp_trough)
	var mp_fill := ColorRect.new()
	mp_fill.color = Color(0.35, 0.55, 0.92)
	mp_fill.position = Vector2(1, 1)
	mp_fill.size = Vector2(174, 10)
	mp_bg.add_child(mp_fill)
	# ⚠️ The mana bar was 6px, colour-only, no text — the exact failure the HP bar had before its
	# fix, left on the sibling bar (accessibility audit #1). Same treatment: outlined % inside.
	var mp_text := Label.new()
	mp_text.text = ""
	mp_text.add_theme_font_size_override("font_size", 11)
	mp_text.add_theme_color_override("font_color", Color(1, 1, 1))
	mp_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	mp_text.add_theme_constant_override("outline_size", 3)
	mp_text.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	mp_text.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	mp_text.position = Vector2(-4, 0)
	mp_bg.add_child(mp_text)

	# ── the STATUS strip (user direction): a reserved slim slot between the resource bars and
	# the cast bar. It NEVER disappears — an always-present strip means statuses appear in a
	# stable place instead of reflowing the plate, which is what makes them scannable mid-fight.
	var status_strip := PanelContainer.new()
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = Color(0.04, 0.04, 0.05, 0.15)   # the status strip joins the transparency pass
	ssb.content_margin_left = 1; ssb.content_margin_right = 1
	ssb.content_margin_top = 0; ssb.content_margin_bottom = 0
	status_strip.add_theme_stylebox_override("panel", ssb)
	status_strip.custom_minimum_size = Vector2(176, 17)
	bars.add_child(status_strip)
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 2)
	status_strip.add_child(status_row)

	# cast bar BELOW the statuses (user direction); fills with castFrac, names the ability
	var cast_bg := Control.new()
	cast_bg.custom_minimum_size = Vector2(176, 19)
	cast_bg.visible = false
	bars.add_child(cast_bg)
	var cast_trough := ColorRect.new()
	cast_trough.color = Color(0.06, 0.04, 0.02, 0.08)
	cast_trough.set_anchors_preset(Control.PRESET_FULL_RECT)
	cast_bg.add_child(cast_trough)
	var cast_fill := ColorRect.new()
	cast_fill.color = Color(0.95, 0.68, 0.25)
	cast_fill.position = Vector2(1, 1)
	cast_fill.size = Vector2(0, 17)
	cast_bg.add_child(cast_fill)
	# The ability ICON — the slot this bar has carried since the Plater rework, now filled by
	# the generated 141-icon set (line glyph + stat tint + type badge).
	var cast_icon := TextureRect.new()
	cast_icon.custom_minimum_size = Vector2(19, 19)
	cast_icon.position = Vector2(1, 0)
	cast_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cast_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cast_bg.add_child(cast_icon)
	var cast_lbl := Label.new()
	cast_lbl.text = ""
	cast_lbl.add_theme_font_size_override("font_size", 16)
	cast_lbl.add_theme_color_override("font_color", Color(0.98, 0.94, 0.85))
	cast_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	cast_lbl.add_theme_constant_override("outline_size", 3)
	cast_lbl.position = Vector2(23, -1)
	cast_bg.add_child(cast_lbl)

	panel.set_meta("hp_fill", fill)
	panel.set_meta("hp_text", hp_text)
	panel.set_meta("mp_fill", mp_fill)
	panel.set_meta("mp_text", mp_text)
	panel.set_meta("cast_bg", cast_bg)
	panel.set_meta("cast_fill", cast_fill)
	panel.set_meta("cast_lbl", cast_lbl)
	panel.set_meta("cast_icon", cast_icon)
	panel.set_meta("status_row", status_row)
	panel.set_meta("intent_lbl", intent_lbl)
	panel.set_meta("border", sb)
	return panel


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# ACCESSIBILITY HELPERS — WCAG relative luminance / contrast, used only to keep team borders off
# the colour-alone floor (`docs/ACCESSIBILITY.md` §3 finding #6: iron-grey measured 2.60:1,
# below the 3:1 non-text floor; #9: three more pass with effectively no margin). Computed locally
# rather than editing `art.gd`'s `TEAM_COLOURS` — that table is not owned by this file/stream.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _srgb_to_linear(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


func _relative_luminance(c: Color) -> float:
	return 0.2126 * _srgb_to_linear(c.r) + 0.7152 * _srgb_to_linear(c.g) + 0.0722 * _srgb_to_linear(c.b)


func _contrast_ratio(a: Color, b: Color) -> float:
	var la := _relative_luminance(a) + 0.05
	var lb := _relative_luminance(b) + 0.05
	return maxf(la, lb) / minf(la, lb)


## Lightens `c` toward white just enough to clear a 3.5:1 margin against `bg` (WCAG's own floor is
## 3:1 for non-text UI — the extra 0.5 is the buffer `docs/ACCESSIBILITY.md` §3 asks for so a
## palette/blend-mode change doesn't tip a border back under the line). A colour that already
## clears the margin is returned unchanged.
func _accessible_border(c: Color, bg: Color) -> Color:
	var out := c
	var tries := 0
	while _contrast_ratio(out, bg) < 3.5 and tries < 30:
		out = out.lerp(Color(1, 1, 1), 0.08)
		tries += 1
	return out


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# TIER-2 DISCLOSURE — one unit's callout, click or Tab to open. `docs/UX_LEGIBILITY.md` §6 Tier 2
# / §11 item 1 ("the cheap interim slice, buildable now"): the Orders Summary (ORDER vs NATURE,
# using tactics.gd's own *_INFO copy verbatim — never a paraphrase) plus, when the sim populates
# them, the live `intent`/`reason` sentence.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _on_plate_input(ev: InputEvent, idx: int) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_select_unit(-1 if selected_idx == idx else idx)


func _select_unit(idx: int) -> void:
	selected_idx = idx
	for k in range(nodes.size()):
		var sb2: StyleBoxFlat = nodes[k]["border"]
		sb2.set_border_width_all(4 if k == idx else 2)
	if idx < 0:
		callout.visible = false
		return
	_refresh_callout(idx)
	callout.visible = true


func _refresh_callout(idx: int) -> void:
	if idx < 0 or idx >= all_units.size():
		return
	var m = all_units[idx]
	var rec: Dictionary = nodes[idx].get("last_rec", {})
	var ident: Dictionary = Art.team_identity(0 if m.side == "A" else 1)
	callout_title.text = "%s %s" % [ident["badge"], m.species_name]

	var lines: Array = []
	var hp_i := int(round(float(rec.get("hp", m.hp))))
	var mp_i := int(round(float(rec.get("mp", m.mp))))
	lines.append("HP %d / %d   MP %d / %d" % [hp_i, m.max_hp, mp_i, m.max_mp])

	var intent: String = str(rec.get("intent", ""))
	var reason: String = str(rec.get("reason", ""))
	lines.append("")
	if intent != "" or reason != "":
		if intent != "":
			lines.append(intent)
		if reason != "":
			lines.append(reason)
	else:
		# ⚠️ Honest about the gap rather than inventing a sentence — this sim build does not
		# populate `intent`/`reason` yet (`docs/BUILD_CONTRACT.md` §2, stream A mid-rewrite).
		lines.append("This build's simulation doesn't report a live intent yet.")

	lines.append("")
	lines.append("[b]Standing orders[/b]")
	for row in _orders_summary(m):
		lines.append("%s %s — %s" % [row["icon"], row["name"], row["tag"]])

	callout_body.text = "\n".join(lines)


## Reuses `tactics.gd`'s own *_INFO tables verbatim (`docs/UX_LEGIBILITY.md` §1 rule 1: "the
## vocabulary is not invented twice") to tag each axis ORDER (explicitly set, team plan or
## per-monster override) or ITS NATURE (absent, engine default) — exactly the distinction
## `tactics.gd`'s own doc comment says the data already supports.
func _orders_summary(m) -> Array:
	var committed: Dictionary = TacticsScript.committed
	var plan: Dictionary = committed.get("planA" if m.side == "A" else "planB", {})
	var orders: Dictionary = committed.get("ordersA" if m.side == "A" else "ordersB", {})
	var own: Dictionary = orders.get(m, {})
	var merged: Dictionary = plan.duplicate()
	for k in own:
		merged[k] = own[k]

	var out: Array = []

	var tp_has: bool = merged.has("targetPriority") and str(merged.get("targetPriority", "")) != ""
	var tp_info: Dictionary = TacticsScript.info_by_id(TacticsScript.TARGET_PRIORITY_INFO, merged.get("targetPriority", ""))
	if tp_info.is_empty():
		tp_info = TacticsScript.TARGET_PRIORITY_INFO[0]
	out.append({"icon": tp_info.get("icon", ""), "name": tp_info.get("name", ""), "tag": "your order" if tp_has else "its nature"})

	var temp_has: bool = own.has("temperament")
	var temp_val: String = str(merged.get("temperament", "balanced"))
	if temp_val == "":
		temp_val = "balanced"
	var temp_info: Dictionary = TacticsScript.info_by_id(TacticsScript.TEMPERAMENT_INFO, temp_val)
	out.append({"icon": temp_info.get("icon", ""), "name": temp_info.get("name", ""), "tag": "your order" if temp_has else "its nature"})

	var mana_has: bool = merged.has("manaPolicy")
	var mana_val: String = str(merged.get("manaPolicy", "normal"))
	if mana_val == "":
		mana_val = "normal"
	var mana_info: Dictionary = TacticsScript.info_by_id(TacticsScript.MANA_POLICY_INFO, mana_val)
	out.append({"icon": mana_info.get("icon", ""), "name": mana_info.get("name", ""), "tag": "your order" if mana_has else "its nature"})

	return out


func _unhandled_input(event: InputEvent) -> void:
	# ── FREE camera: hold LMB and drag to pan, wheel to zoom. First touch captures the current
	# framing so the hand-off is seamless; C returns to the auto modes. ──
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_panning = event.pressed
			if event.pressed and _cam_mode != CamMode.FREE:
				_free_center = _cam_center
				_free_span = _cam_span
				_cam_mode = CamMode.FREE
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if _cam_mode != CamMode.FREE:
				_free_center = _cam_center
				_free_span = _cam_span
				_cam_mode = CamMode.FREE
			var zf := 0.88 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.14
			_free_span = clampf(_free_span * zf, CAM_MIN_SPAN * 0.6, _cam_max_span * 1.2)
	elif event is InputEventMouseMotion and _panning and _cam_mode == CamMode.FREE:
		# Screen-space drag → ground-plane pan, scaled so a full-height drag crosses ~two spans.
		var vp_h: float = maxf(1.0, get_viewport().get_visible_rect().size.y)
		var k_pan: float = _free_span * 2.0 / vp_h
		var right: Vector3 = camera.global_transform.basis.x
		right.y = 0.0
		right = right.normalized()
		var fwd: Vector3 = -camera.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		_free_center += (-right * event.relative.x + fwd * event.relative.y) * k_pan
		var half_w: float = ground_size.x * WORLD_SCALE * 0.6
		var half_d: float = ground_size.y * WORLD_SCALE * 0.6
		_free_center.x = clampf(_free_center.x, -half_w, half_w)
		_free_center.z = clampf(_free_center.z, -half_d, half_d)

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			_cycle_selection(event.shift_pressed)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and selected_idx >= 0:
			_select_unit(-1)
			get_viewport().set_input_as_handled()
		# ⚠️ BOTH CAMERAS, BECAUSE NEITHER ONE IS RIGHT ON ITS OWN AND THAT IS MEASURED. The
		# whole-arena shot holds every unit in frame but puts a body at ~4% of frame height; the
		# follow shot reads a body at ~12-13% but loses the flanks. "See the whole fight" and "see
		# the creatures" are in genuine tension at 5v5 and one span cannot serve both, so this is a
		# key rather than a constant somebody has to pick.
		elif event.keycode == KEY_C:
			# Cycle TEAM → ACTION → ARENA → TEAM; from FREE, C returns home to TEAM.
			match _cam_mode:
				CamMode.TEAM: _cam_mode = CamMode.ACTION
				CamMode.ACTION: _cam_mode = CamMode.ARENA
				_: _cam_mode = CamMode.TEAM
			get_viewport().set_input_as_handled()
		# Slow the replay down to watch a specific exchange, or speed through the approach.
		elif event.keycode == KEY_BRACKETLEFT:
			speed = maxf(0.25, speed - 0.25)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_BRACKETRIGHT:
			speed = minf(4.0, speed + 0.25)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_SPACE:
			speed = 0.0 if speed > 0.0 else 1.0
			get_viewport().set_input_as_handled()


func _cycle_selection(reverse: bool) -> void:
	if nodes.is_empty():
		return
	var n := nodes.size()
	var start := selected_idx
	var step := -1 if reverse else 1
	for _i in range(n):
		start = (start + step + n) % n
		if start < all_units.size() and all_units[start].alive:
			_select_unit(start)
			return


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# PLAYBACK — interpolate the frame stream
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	if not playing:
		_update_plates()
		_update_camera(delta)
		return
	# ⚠️ Check for a frame stream BEFORE the opening hold, not after. The hold path called
	# `_apply_frame(0.0)`, which indexes `frames[0]` — so with the non-spatial fallback (no frame
	# stream at all) it crashed on the very first frame, before the guard below could catch it.
	if frames.is_empty():
		# Non-spatial fallback: no positions to replay. Units stay on their deploy marks and only
		# the log advances, which is honest about what this engine does and does not know.
		_drain_log(event_log.size())
		playing = false
		_finish()
		return

	opening_timer += delta * speed
	if opening_timer < OPENING_HOLD:
		_apply_frame(0.0)
		_update_plates()
		_update_camera(delta)
		return

	_update_innate_tells()
	_update_standing_hud()
	# Frames are one simulation tick apart, so advancing at `1 / DT` frames per second replays the
	# fight at true speed. ⚠️ Interpolating BETWEEN frames is what makes 10 Hz simulation look
	# smooth without the renderer inventing any motion of its own.
	# Hit-stop: _feel_slow dips on big hits and recovers in ~0.15s. It multiplies the PLAYBACK,
	# not `speed` — the user's chosen speed is never overwritten, the moment just lands heavier.
	_feel_slow = lerpf(_feel_slow, 1.0, 1.0 - exp(-14.0 * delta))
	frame_pos += delta * speed * 10.0 * _feel_slow
	if frame_pos >= float(frames.size() - 1):
		frame_pos = float(frames.size() - 1)
		_apply_frame(frame_pos)
		_drain_log(event_log.size())
		playing = false
		_finish()
		_update_camera(delta)
		return
	_apply_frame(frame_pos)
	_update_plates()
	_update_camera(delta)


func _apply_frame(fpos: float) -> void:
	var i := int(floor(fpos))
	var j: int = mini(i + 1, frames.size() - 1)
	var t: float = fpos - float(i)
	var fa: Dictionary = frames[i]
	var fb: Dictionary = frames[j]
	var ua: Array = fa.get("units", [])
	var ub: Array = fb.get("units", [])

	# Transition-only ticker entries (`docs/UX_LEGIBILITY.md` §1 rule 2) — checked once per NEW
	# discrete tick, never once per interpolated sub-frame, so a fast playback speed can't spam it.
	if i != _seen_tick:
		_seen_tick = i
		_check_intent_transitions(fa)

	for k in range(mini(nodes.size(), ua.size())):
		var rec: Dictionary = ua[k]
		var rec_b: Dictionary = ub[k] if k < ub.size() else rec
		var nd: Dictionary = nodes[k]
		nd["last_rec"] = rec
		var pa: Vector2 = rec.get("pos", Vector2.ZERO)
		var pb: Vector2 = rec_b.get("pos", pa)
		var world := _to_world(pa.lerp(pb, t))
		(nd["holder"] as Node3D).position = world

		var alive: bool = bool(rec.get("alive", true))
		if not alive and not nd["dead"]:
			_topple(k)
		# ⚠️ A dead unit keeps its NAME but loses its bar. An empty red trough sitting over a corpse
		# reads as "still fighting, nearly gone" — the opposite of what happened — and it competes
		# for attention with the units still alive, which is the whole point of plate declutter.
		# ⚠️ A dead monster loses its WHOLE plate (user call, 2026-08-06 — this hid only the HP row
		# at first). A corpse does not need a name tag: the plate exists to carry live reads
		# (HP, statuses, intent), and ten plates over five corpses is exactly the clutter the
		# declutter pass exists to prevent. The body + topple still say who fell, and the log
		# keeps the record.
		if not alive:
			(nd["plate"] as Control).visible = false

		if shadow_mm != null and k < shadow_mm.instance_count:
			shadow_mm.set_instance_transform(k, Transform3D(Basis(Vector3(1, 0, 0), deg_to_rad(-90)), world + Vector3(0, 0.03, 0)))
			shadow_mm.set_instance_color(k, Color(1, 1, 1, 0.35 if not alive else 1.0))

		var m = all_units[k]
		var hp: float = float(rec.get("hp", m.hp))
		var frac: float = 0.0 if m.max_hp <= 0 else clampf(hp / float(m.max_hp), 0.0, 1.0)
		var fill: ColorRect = nd["hp_fill"]
		fill.size = Vector2(174.0 * frac, 18)
		# mana — the hair-thin second bar (Plater grammar)
		var mfrac: float = 0.0 if m.max_mp <= 0 else clampf(float(rec.get("mp", 0.0)) / float(m.max_mp), 0.0, 1.0)
		(nd["mp_fill"] as ColorRect).size = Vector2(174.0 * mfrac, 10)
		(nd["mp_text"] as Label).text = "%d%%" % int(round(mfrac * 100.0))
		# cast bar — visible only while the sim says cast, filling with the windup
		var casting_b: bool = str(rec.get("state", "")) == "cast" and alive
		var flashing: bool = Time.get_ticks_msec() < int(nd.get("cast_flash_until", 0))
		(nd["cast_bg"] as Control).visible = casting_b or (flashing and alive)
		if casting_b:
			(nd["cast_fill"] as ColorRect).color = Color(0.95, 0.68, 0.25)   # restore after any flash
			# ⚠️ The bar MOVES with the cast (user direction): castFrac is lerped between the same
			# two frames positions interpolate between, so it glides at render rate instead of
			# stepping at the sim's 10Hz.
			var cf_a: float = float(rec.get("castFrac", 0.0))
			var cf_b: float = float(rec_b.get("castFrac", cf_a)) if str(rec_b.get("state", "")) == "cast" else cf_a
			(nd["cast_fill"] as ColorRect).size = Vector2(174.0 * clampf(lerpf(cf_a, cf_b, t), 0.0, 1.0), 17)
			(nd["cast_lbl"] as Label).text = str(rec.get("castMove", ""))
			var icon_mv: Dictionary = _move_by_name.get(str(rec.get("castMove", "")), {})
			var icon_path: String = "res://assets/icons/abilities/%s.png" % str(icon_mv.get("id", ""))
			(nd["cast_icon"] as TextureRect).texture = load(icon_path) if icon_mv.has("id") and ResourceLoader.exists(icon_path) else null
		if frac < 0.25:
			fill.color = Color(0.87, 0.24, 0.24)
		elif frac < 0.5:
			fill.color = Color(0.88, 0.70, 0.25)
		else:
			fill.color = Color(0.32, 0.76, 0.36)
		var hp_text: Label = nd["hp_text"]
		hp_text.text = "%d%%" % int(round(frac * 100.0))

		# Weary rides the status row as a pseudo-status — the care loop must be READABLE.
		var row_statuses: Array = (rec.get("statuses", []) as Array).duplicate()
		if bool(rec.get("weary", false)):
			row_statuses.append("weary")
		_sync_status_row(nd, row_statuses)
		_sync_intent_glyph(nd, str(rec.get("state", "idle")))

		# ⚠️ Feed the procedural animator the sim's OWN state and facing. The renderer derives
		# nothing here (docs/BUILD_CONTRACT.md §2) — both fields are already in the frame.
		# Cast telegraph: a rising channel-coloured glow while (and only while) the sim says this
		# unit is casting — the windup the interrupt game is played against, visible at any zoom.
		if vfx != null:
			var casting_now: bool = str(rec.get("state", "")) == "cast" and alive
			# ── AoE TELEGRAPH: while an allEnemies move winds up, its ACTUAL area sits on the
			# ground as a ring around the caster — the WoW grammar: you see the circle, you know
			# what is coming, and repositioning out of it is real counterplay the eye can verify.
			# Radius is the move's own authored reach (the same number the fan-out now enforces),
			# so the ring never lies about what it will hit. ──
			var tele_mv: Dictionary = _move_by_name.get(str(rec.get("castMove", "")), {})
			if casting_now and str(tele_mv.get("target", "")) == "allEnemies":
				_show_aoe_ring(k, Sp.reach_of(tele_mv, false), str(tele_mv.get("channel", "magic")))
			else:
				_hide_aoe_ring(k)
			if casting_now and not bool(nd.get("_was_casting", false)):
				# Cast START: one charge-ring play-through — the moment the windup begins is the
				# moment the interrupt window opens, and it deserves a beat of its own.
				vfx.flip((nd["holder"] as Node3D).position + Vector3(0, UNIT_HEIGHT * 0.5, 0),
					"charge", 5.0, Color(0.85, 0.70, 1.0), 0.5)
			nd["_was_casting"] = casting_now
			if casting_now:
				# ⚠️ CHANNEL-TRUE (UI team 2026-08-06): this hardcoded magic-violet for EVERY
				# caster — a melee windup telegraphed as a spell. Colour is a promise the player
				# banks reads on; the glow now speaks the casting move's own channel. Neutral
				# grey-white when the move is unknown (basics) — never a wrong colour.
				var glow_mv: Dictionary = _move_by_name.get(str(rec.get("castMove", "")), {})
				var glow_col: Color = vfx.CHANNEL_COLOUR.get(str(glow_mv.get("channel", "")), Color(0.85, 0.85, 0.9))
				vfx.cast_glow(k, nd["holder"], glow_col)
			else:
				vfx.end_cast_glow(k)

		var anim = nd.get("anim")
		if anim != null:
			var f = rec.get("facing", Vector2(0, 1))
			var md = rec.get("moveDir", Vector2.ZERO)
			anim.set_state(str(rec.get("state", "idle")), f if f is Vector2 else Vector2(0, 1),
				md if md is Vector2 else Vector2.ZERO)

	for shot in fa.get("shots", []):
		_draw_shot(shot)
		# A landed hit shakes its VICTIM — the exchange reads as two-sided rather than one unit
		# lunging into empty air.
		if bool(shot.get("hit", false)):
			var vid := int(shot.get("toId", -1))
			if vid >= 0 and vid < nodes.size():
				var va = nodes[vid].get("anim")
				if va != null:
					va.flinch()

	_sync_projectiles(fa, fb, t)

	# Keep the text log in step with the frame we're showing.
	var now_t: float = float(fa.get("t", 0.0))
	var upto := logged_upto
	while upto < event_log.size() and float(event_log[upto].get("t", 0.0)) <= now_t:
		upto += 1
	_drain_log(upto)

	if selected_idx >= 0:
		_refresh_callout(selected_idx)


## Rebuilds a unit's status-chip row only when the status list actually changed (cheap signature
## check) — avoids destroying/recreating `Control` children every tick for a unit whose statuses
## haven't moved, which is the common case.
func _sync_status_row(nd: Dictionary, statuses: Array) -> void:
	var sig: String = ",".join(statuses.map(func(s): return str(s)))
	if nd.get("_status_sig", "") == sig:
		return
	nd["_status_sig"] = sig
	var row: HBoxContainer = nd["status_row"]
	for c in row.get_children():
		c.queue_free()
	# Overflow cap (UX audit #6): a late-fight unit can carry 5+ statuses; uncapped chips clip
	# past the plate. Four visible + a neutral "+N" chip, matching the disclosure-tier idea.
	var shown: Array = statuses.slice(0, 4)
	if statuses.size() > 4:
		shown.append("+%d" % (statuses.size() - 4))
	for s in shown:
		var kind := str(s)
		var meta: Dictionary = STATUS_META.get(kind, {"abbr": kind.substr(0, 4).to_upper(), "color": Color(0.7, 0.7, 0.7)})
		var col: Color = meta.get("color", Color(0.7, 0.7, 0.7))
		var chip := PanelContainer.new()
		var csb := StyleBoxFlat.new()
		csb.bg_color = Color(col.r, col.g, col.b, 0.28)
		csb.border_color = col
		csb.set_border_width_all(1)
		csb.set_corner_radius_all(3)
		csb.content_margin_left = 2; csb.content_margin_right = 2
		csb.content_margin_top = 0; csb.content_margin_bottom = 0
		chip.add_theme_stylebox_override("panel", csb)
		var lbl := Label.new()
		lbl.text = str(meta.get("abbr", "?"))
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", col)
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		lbl.add_theme_constant_override("outline_size", 3)
		chip.add_child(lbl)
		row.add_child(chip)


func _sync_intent_glyph(nd: Dictionary, state: String) -> void:
	if nd.get("_state_sig", "") == state:
		return
	nd["_state_sig"] = state
	var lbl: Label = nd["intent_lbl"]
	lbl.text = "" if state == "dead" else str(STATE_GLYPH.get(state, ""))


## Transition-only intent/reason logging into the existing ticker (Tier 3,
## `docs/UX_LEGIBILITY.md` §6) — the cheap slice: no branch enum needed, just "did this unit's
## `intent` string change since the last tick we looked at". Silently does nothing while the sim
## doesn't populate `intent` (every entry is `""`), which is the correct degrade, not a bug.
func _check_intent_transitions(fa: Dictionary) -> void:
	for rec in fa.get("units", []):
		var uid: int = int(rec.get("id", -1))
		var intent: String = str(rec.get("intent", ""))
		if intent == "":
			continue
		if _last_intent.get(uid, "") == intent:
			continue
		_last_intent[uid] = intent
		var reason: String = str(rec.get("reason", ""))
		var txt := reason if reason != "" else intent
		log_view.append_text("[color=#9fb6d9]%s: %s[/color]\n" % [_unit_name(uid), txt])
		call_deferred("_snap_log")


func _unit_name(uid: int) -> String:
	if uid >= 0 and uid < all_units.size():
		return all_units[uid].species_name
	return "?"


func _draw_shot(shot: Dictionary) -> void:
	var from_id: int = int(shot.get("fromId", -1))
	var to_id: int = int(shot.get("toId", -1))
	if to_id < 0 or to_id >= nodes.size():
		return
	if bool(shot.get("hit", false)):
		_hit_flash(to_id)
		var crit: bool = bool(shot.get("crit", false))
		# ── impact burst, channel-coloured (never team-coloured — Guild Colours rule). Crit is
		# bigger and gains sparks: the payoff must read at fight speed, not only in the log. ──
		if vfx != null:
			# ── PLAY_ABILITY: the docs/VFX_ABILITY_MAP.md engine. The shot carries the move
			# NAME; the move dict carries everything the recipe cascade needs (name override →
			# line flavour → type/channel rules). The old channel-only block lives on inside
			# play_ability as the final fallback, so an unknown name still bursts. ──
			var vpos: Vector3 = (nodes[to_id]["holder"] as Node3D).position + Vector3(0, UNIT_HEIGHT * 0.5, 0)
			var cpos: Vector3 = vpos
			if from_id >= 0 and from_id < nodes.size():
				cpos = (nodes[from_id]["holder"] as Node3D).position + Vector3(0, UNIT_HEIGHT * 0.5, 0)
			var mv_d: Dictionary = _move_by_name.get(str(shot.get("move", "")), {})
			if mv_d.is_empty():
				mv_d = {"name": str(shot.get("move", "")), "type": "damage",
					"channel": str(shot.get("kind", "melee")), "target": "enemy"}
			# ── game feel: effect size scales with the WOUND, not the move. dmg as a fraction of
			# the victim's pool decides the oomph — a 5-damage poke on a wall stays a tick, the
			# same number on a dying wisp is a blow. Crits and heavy fractions also punch the
			# camera and pop the victim.
			var vic_hp := 1.0
			if to_id < all_units.size():
				vic_hp = maxf(1.0, float(all_units[to_id].max_hp))
			var frac: float = float(int(shot.get("dmg", 0))) / vic_hp
			var oomph: float = clampf(0.8 + frac * 2.5, 0.8, 2.0)
			vfx.play_ability(mv_d, cpos, vpos, crit, oomph)
			if crit or frac >= 0.18:
				_punch(0.45 if crit else 0.3, 0.3 if crit else 0.18)
				_scale_pop(to_id)

		var dmg_i: int = int(shot.get("dmg", 0))
		# ⚠️ Non-colour crit tell (`docs/ACCESSIBILITY.md` §4): crit vs. normal used to be
		# colour-only (gold vs. salmon, same size). A trailing "!" makes it readable without colour.
		#
		# ⚠️ AND THE SAME RULE FOR THE REAR BONUS. A backstab is a POSITIONAL read paying off, and
		# a player who cannot intervene has only the aftermath to learn from — so it says BACK in
		# words, not in a colour. Text, because facing is invisible at 4-13% of frame height.
		var arc := str(shot.get("arc", "front"))
		var label := ("%d!" % dmg_i) if crit else str(dmg_i)
		if arc == "rear":
			label = "%s BACK" % label
		# ⚠️ Damage numbers were a FOURTH colour system (gold/salmon/orange, mapping to nothing
		# the player had learned elsewhere). They now speak the channel palette — a magic hit's
		# number matches its burst — lightened for readability; crit keeps the "!" and a gold
		# LEAN (a modifier, not a base hue), rear keeps the BACK text.
		var num_col: Color = vfx.CHANNEL_COLOUR.get(str(shot.get("kind", "melee")), Color(0.9, 0.9, 0.9)) if vfx != null else Color(0.9, 0.9, 0.9)
		num_col = num_col.lerp(Color.WHITE, 0.35)
		if crit:
			num_col = num_col.lerp(Color(1.0, 0.84, 0.36), 0.5)
		_float_text(to_id, label, num_col)
	else:
		_float_text(to_id, "MISS", Color(0.78, 0.78, 0.84))
	# A tracer for anything not swung in melee, so ranged and magic read as reaching across.
	# ⚠️ NOT FOR FRIENDLY CASTS. The user spotted a gold "laser" spanning the arena — Larkessa
	# team-buffing a distant ally. Team coverage is formation-fraction by design (the deployment
	# board's aura/AoE trade), so the REACH is intended; the LINE was the lie — it reads as an
	# attack. Buff recipients are already marked by the aura_pulse ring, which is the grammar
	# built for exactly this. Attacks keep their tracers.
	var mv_t: Dictionary = _move_by_name.get(str(shot.get("move", "")), {})
	var friendly_cast: bool = str(mv_t.get("target", "enemy")) in ["self", "ally", "team"]
	if from_id >= 0 and from_id < nodes.size() and not friendly_cast:
		if str(shot.get("kind", "melee")) != "melee":
			_tracer((nodes[from_id]["holder"] as Node3D).position,
					(nodes[to_id]["holder"] as Node3D).position)
		elif bool(shot.get("hit", false)):
			# ⚠️ MELEE ATTRIBUTION (UX audit #4): in a 4-body scrum nothing pointed from attacker
			# to victim — the flinch and the number sat on the victim alone. A subdued flick
			# (dimmer, faster than a tracer — this is attribution, not reach) survives density.
			_tracer((nodes[from_id]["holder"] as Node3D).position,
					(nodes[to_id]["holder"] as Node3D).position, 0.35, 0.12)


func _tracer(a: Vector3, b: Vector3, alpha: float = 0.9, dur: float = 0.22) -> void:
	var im := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	# Craft pass: bright at the shooter, fading toward the mark — a line of equal weight reads
	# as a wall; a gradient reads as travel.
	st.set_color(Color(1.0, 0.92, 0.6, alpha))
	st.add_vertex(a + Vector3(0, UNIT_HEIGHT * 0.55, 0))
	st.set_color(Color(1.0, 0.92, 0.6, 0.15))
	st.add_vertex(b + Vector3(0, UNIT_HEIGHT * 0.55, 0))
	im.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	im.material_override = mat
	add_child(im)
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, dur / maxf(0.25, speed))
	tw.tween_callback(im.queue_free)


## In-flight aimed abilities (`docs/BUILD_CONTRACT.md` §2's new `projectiles` array) — drawn as a
## short streak that travels from `from` to `to` at `progress`. ⚠️ This is what makes a shot that
## MISSES because the target moved actually visible: the streak flies to `to` (where the target
## was aimed at) and the target may simply not be there anymore — no special-casing needed, the
## renderer just draws what the stream says. Guarded throughout: the current sim build emits no
## `projectiles` at all yet, so this is a no-op until stream A lands it.
func _sync_projectiles(fa: Dictionary, fb: Dictionary, t: float) -> void:
	var pa: Array = fa.get("projectiles", [])
	if pa.is_empty() and _projectile_nodes.is_empty():
		return
	var pb: Array = fb.get("projectiles", [])
	var seen: Dictionary = {}
	for proj in pa:
		var pid: int = int(proj.get("id", -1))
		var from_a: Vector2 = proj.get("from", Vector2.ZERO)
		var to_a: Vector2 = proj.get("to", from_a)
		var prog_a: float = clampf(float(proj.get("progress", 0.0)), 0.0, 1.0)
		var pos2: Vector2 = from_a.lerp(to_a, prog_a)
		var proj_b = _find_projectile(pb, pid)
		if proj_b != null:
			var from_b: Vector2 = proj_b.get("from", from_a)
			var to_b: Vector2 = proj_b.get("to", to_a)
			var prog_b: float = clampf(float(proj_b.get("progress", prog_a)), 0.0, 1.0)
			pos2 = pos2.lerp(from_b.lerp(to_b, prog_b), t)
		var dir2: Vector2 = to_a - from_a
		_update_projectile_node(pid, pos2, dir2, str(proj.get("kind", "ranged")))
		seen[pid] = true
	for pid in _projectile_nodes.keys():
		if not seen.has(pid):
			_projectile_nodes[pid].queue_free()
			_projectile_nodes.erase(pid)


func _find_projectile(arr: Array, pid: int):
	for p in arr:
		if int(p.get("id", -1)) == pid:
			return p
	return null


func _update_projectile_node(pid: int, pos2: Vector2, dir2: Vector2, kind: String) -> void:
	var mi: Node3D = _projectile_nodes.get(pid)
	if mi == null:
		# ⚠️ MAGIC IS A FIREBALL NOW — an animated flipbook billboard (Brackeys CC0 fire sheet,
		# looping) with an ember trail, replacing the grey box. Other channels keep the bolt
		# box: an arrow SHOULD read as a shaft, and one showpiece per channel beats four kinds
		# of fireworks nobody can tell apart. The trail is a child emitter, so it follows for
		# free and dies with the projectile node.
		if kind == "magic":
			var holder := Node3D.new()
			var quad := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(3.2, 3.2)
			# Craft pass 2026-08-06: the flame ANIMATES in flight — a fragment shader cycles the
			# 8x8 sheet on TIME (was a single frozen frame; the trail carried all the motion).
			# Billboarding is done in the vertex stage, the standard Godot snippet.
			var fsh := Shader.new()
			fsh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform sampler2D sheet : source_color;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	float f = mod(floor(TIME * 30.0), 64.0);
	vec2 cell = vec2(mod(f, 8.0), floor(f / 8.0));
	vec2 uv = (UV + cell) / 8.0;
	vec4 c = texture(sheet, uv);
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
"""
			var fmat := ShaderMaterial.new()
			fmat.shader = fsh
			var ft = load("res://assets/vfx/flipbooks/fire_01_8x8_clean.png")
			if ft != null:
				fmat.set_shader_parameter("sheet", ft)
			qm.material = fmat
			quad.mesh = qm
			holder.add_child(quad)
			var trail := GPUParticles3D.new()
			trail.amount = 20
			trail.lifetime = 0.5
			var tm := ParticleProcessMaterial.new()
			tm.direction = Vector3(0, 0, 0)
			tm.spread = 30.0
			tm.initial_velocity_min = 0.5
			tm.initial_velocity_max = 1.5
			tm.gravity = Vector3(0, 1.5, 0)
			tm.scale_min = 0.3
			tm.scale_max = 0.8
			tm.color = Color(1.0, 0.55, 0.2)
			trail.process_material = tm
			var tq := QuadMesh.new()
			tq.size = Vector2(0.9, 0.9)
			var tmat := StandardMaterial3D.new()
			tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			tmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			tmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			tmat.vertex_color_use_as_albedo = true
			var st = load("res://assets/vfx/kenney/spark.png")
			if st != null:
				tmat.albedo_texture = st
			tq.material = tmat
			trail.draw_pass_1 = tq
			holder.add_child(trail)
			# Quality tier: the fireball CARRIES ITS OWN LIGHT — the floor glows as it passes,
			# which is the difference between an object in the world and a sprite over it.
			var flight := OmniLight3D.new()
			flight.light_color = Color(1.0, 0.6, 0.25)
			flight.light_energy = 3.5
			flight.omni_range = 16.0
			flight.shadow_enabled = false
			holder.add_child(flight)
			mi = holder
		else:
			var box := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.35, 0.22, 1.3)
			box.mesh = bm
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = PROJECTILE_COLOUR.get(kind, Color(0.9, 0.9, 0.9))
			box.material_override = mat
			mi = box
		add_child(mi)
		_projectile_nodes[pid] = mi
	mi.position = _to_world(pos2) + Vector3(0, UNIT_HEIGHT * 0.55, 0)
	if dir2.length() > 0.001 and mi is MeshInstance3D:
		mi.rotation = Vector3(0, atan2(dir2.x, dir2.y), 0)


## Log events carry a unit NAME (the sim's own event vocabulary), the float-text helper wants the
## index into `all_units`. ⚠️ Names are not guaranteed unique — two Larkessa on one side is
## legal — so this returns the FIRST match and the float may land on the wrong twin. Accepted:
## the alternative is threading unit ids through every event, and the log line beside it always
## names the caster, so the information is not lost, only its anchor is approximate.
func _index_of_unit_named(nm: String) -> int:
	for i in range(all_units.size()):
		if str(all_units[i].species_name) == nm:
			return i
	return -1


var _float_recent := {}   # unit idx -> {t, n} — staggers same-moment floats (UX audit #3)

func _float_text(idx: int, text: String, col: Color) -> void:
	# Same-tick hits on one body used to spawn at the identical offset — a multi-hit or two
	# attackers turned the payoff numbers into one unreadable smear at exactly the moment the
	# player most wants to read them. Floats within 0.4s on the same unit now fan out.
	var now_ms := Time.get_ticks_msec()
	var rec_f: Dictionary = _float_recent.get(idx, {"t": 0, "n": 0})
	if now_ms - int(rec_f["t"]) < 400:
		rec_f["n"] = int(rec_f["n"]) + 1
	else:
		rec_f["n"] = 0
	rec_f["t"] = now_ms
	_float_recent[idx] = rec_f
	var fan: int = int(rec_f["n"])
	var lbl := Label3D.new()
	lbl.text = text
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 96
	lbl.outline_size = 30
	lbl.outline_modulate = Color(0, 0, 0, 0.9)
	lbl.modulate = col
	lbl.pixel_size = 0.0075
	lbl.no_depth_test = true
	add_child(lbl)
	# World-space fan: same-moment floats on one body step sideways then up a row (a Label3D
	# lives in world units, not pixels — ~1.7 units x is one digit-width at this camera).
	var fan_off := Vector3(float((fan % 3) - 1) * 1.7, float(fan / 3) * 1.3, 0)
	var start: Vector3 = (nodes[idx]["holder"] as Node3D).position + Vector3(0, UNIT_HEIGHT * 0.8, 0) + fan_off
	lbl.position = start
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position", start + Vector3(0, 2.4, 0), 0.8 / maxf(0.25, speed))
	tw.tween_property(lbl, "modulate:a", 0.0, 0.8 / maxf(0.25, speed))
	tw.chain().tween_callback(lbl.queue_free)


## The red flash on a landed hit. ⚠️ Two bodies, two mechanisms: a `Sprite3D` has `modulate`, a
## rigged `MeshInstance3D` does not — its colour lives on the material. Tinting is not optional
## polish here; without it a hit that deals damage has no tell on the BODY at all, only a floating
## number, and `docs/ACCESSIBILITY.md` counts the number as one channel rather than two.
func _hit_flash(idx: int) -> void:
	if idx < 0 or idx >= nodes.size():
		return
	var nd: Dictionary = nodes[idx]
	var spr = nd.get("sprite")
	if spr != null:
		var tw := create_tween()
		tw.tween_property(spr, "modulate", Color(1.7, 0.55, 0.55), 0.05)
		tw.tween_property(spr, "modulate", Color(1, 1, 1), 0.18)
		return
	var rig = nd.get("rig")
	if rig != null and rig.has_method("hit_flash"):
		rig.hit_flash()


var _aoe_rings := {}   # unit index -> MeshInstance3D (the AoE windup telegraph)
var _standing_lbl: Label = null

func _update_standing_hud() -> void:
	if _standing_lbl == null:
		_standing_lbl = Label.new()
		_standing_lbl.add_theme_font_size_override("font_size", 13)
		_standing_lbl.add_theme_color_override("font_color", Color(0.92, 0.92, 0.95))
		_standing_lbl.position = Vector2(get_viewport().get_visible_rect().size.x * 0.5 - 110, 46)
		add_child(_standing_lbl)
	var a_up := 0
	var b_up := 0
	for m in team_a:
		if m.alive: a_up += 1
	for m in team_b:
		if m.alive: b_up += 1
	_standing_lbl.text = "Team A  %d monster%s remaining\nTeam B  %d monster%s remaining" % [
		a_up, "" if a_up == 1 else "s", b_up, "" if b_up == 1 else "s"]
var _innate_rings := {}   # unit index -> MeshInstance3D (persistent innate-zone tells)

## INNATE ZONE TELLS — the care loop's spatial innates made visible. A zoner (auraEnemySlow)
## carries a faint slow-field ring at its reach; a territorial (homeGroundDR) gets a fixed ring
## at its STATION. Innate identity is static monster data — the same data the nameplate's innate
## line already shows — so the renderer computing it breaks no contract. Brace/charge arming
## glints still need sim-side frame flags; deferred with this note, not forgotten.
func _build_innate_tells() -> void:
	var InnatesL = load("res://scripts/innate_fx.gd")
	for k in range(all_units.size()):
		var m = all_units[k]
		var fx: Dictionary = InnatesL.compute(m, GameData.innate_effects)
		var ring: MeshInstance3D = null
		var col := Color(1, 1, 1)
		var radius := 0.0
		var follow := false
		if fx.has("auraEnemySlow"):
			col = Color(0.55, 0.62, 0.80, 0.20)   # cold blue-grey: the slow field
			radius = 18.0   # ~ a melee kit's reach; exact per-kit reach varies per move
			follow = true
		elif fx.has("homeGroundDR"):
			col = Color(0.72, 0.60, 0.35, 0.22)   # earthy: home ground
			radius = InnatesL.HOME_RADIUS
		if radius <= 0.0:
			continue
		ring = MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = radius - 0.4
		tor.outer_radius = radius
		tor.rings = 48
		ring.mesh = tor
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = col
		ring.material_override = mat
		ring.position = (nodes[k]["holder"] as Node3D).position + Vector3(0, 0.12, 0)
		add_child(ring)
		_innate_rings[k] = {"ring": ring, "follow": follow}


func _update_innate_tells() -> void:
	for k in _innate_rings:
		var rec: Dictionary = _innate_rings[k]
		var ring: MeshInstance3D = rec["ring"]
		var dead: bool = bool(nodes[k].get("dead", false))
		ring.visible = not dead
		if bool(rec["follow"]) and not dead:
			ring.position = (nodes[k]["holder"] as Node3D).position + Vector3(0, 0.12, 0)

# ── GAME FEEL (2026-08-06). All of it renderer-side and decaying — the sim never notices. ──
var _feel_slow := 1.0    # playback multiplier: dips on big hits (hit-stop), recovers fast
var _shake := 0.0        # camera punch magnitude, decays exponentially

## One call per impactful moment. `stop` dips playback (0.35 = strong hit-stop), `shake` kicks
## the camera. Both decay on their own — stacking punches extends, never accumulates runaway.
func _punch(stop: float, shake: float) -> void:
	_feel_slow = minf(_feel_slow, 1.0 - clampf(stop, 0.0, 0.85))
	_shake = maxf(_shake, shake)
	# The stands feel the shake too (user direction): any camera punch rolls a small per-model
	# cheer chance; deaths roll their own larger chance at the death event.
	if spectators != null:
		spectators.react(clampf(shake * 0.6, 0.08, 0.3))


## Victim scale-pop: a fast 1.0 → 1.12 → 1.0 on the holder. The body visibly TAKES the hit.
func _scale_pop(idx: int) -> void:
	if idx < 0 or idx >= nodes.size():
		return
	var h := nodes[idx]["holder"] as Node3D
	var tw := create_tween()
	tw.tween_property(h, "scale", Vector3.ONE * 1.12, 0.05)
	tw.tween_property(h, "scale", Vector3.ONE, 0.12)

func _show_aoe_ring(idx: int, radius: float, channel: String) -> void:
	var ring: MeshInstance3D = _aoe_rings.get(idx)
	if ring == null:
		ring = MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = maxf(0.5, radius - 0.6)
		tor.outer_radius = radius
		tor.rings = 48
		ring.mesh = tor
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var col: Color = vfx.CHANNEL_COLOUR.get(channel, Color(0.9, 0.6, 0.3)) if vfx != null else Color(0.9, 0.6, 0.3)
		mat.albedo_color = Color(col.r, col.g, col.b, 0.45)
		ring.material_override = mat
		add_child(ring)
		_aoe_rings[idx] = ring
	ring.position = (nodes[idx]["holder"] as Node3D).position + Vector3(0, 0.15, 0)
	ring.visible = true


func _hide_aoe_ring(idx: int) -> void:
	if _aoe_rings.has(idx):
		(_aoe_rings[idx] as MeshInstance3D).visible = false


func _topple(idx: int) -> void:
	if vfx != null and idx >= 0 and idx < nodes.size():
		vfx.burst((nodes[idx]["holder"] as Node3D).position + Vector3(0, UNIT_HEIGHT * 0.4, 0),
			"smoke", Color(0.55, 0.55, 0.60), 1.8, 16)
	var nd: Dictionary = nodes[idx]
	if nd["dead"]:
		return
	nd["dead"] = true
	(nd["plate"] as Control).modulate = Color(1, 1, 1, 0.4)
	if selected_idx == idx:
		_select_unit(-1)

	# ⚠️ A RIGGED UNIT MUST NOT BE TOPPLED BY THE RENDERER — it has a real death ANIMATION, and
	# rotating the body on top of it would fight the clip for the same transform. `set_state("dead")`
	# has already started that clip by the time this runs. The tween below exists only for the
	# sprite path, where there is no death motion and a topple is the only way a body reads as down.
	var spr = nd.get("sprite")
	if spr == null:
		return
	# ⚠️ Billboarding must be disabled first — a Y-billboard re-solves its orientation every frame
	# and would silently undo the topple, leaving the creature fading while still standing.
	spr.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	var side_sign := -1.0 if idx < team_a.size() else 1.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "rotation_degrees:z", 80.0 * side_sign, 0.4)
	tw.tween_property(spr, "position:y", UNIT_HEIGHT * 0.2, 0.4)
	tw.tween_property(spr, "modulate:a", 0.4, 0.45)
	if selected_idx == idx:
		_select_unit(-1)


## How loudly this unit's plate should read, 0.42 (quiet) .. 1.0 (full). Driven entirely by the
## frame stream's own fields — no renderer-side notion of "interesting", per `BUILD_CONTRACT.md`
## §2 ("the renderer derives nothing").
const PLATE_QUIET := 0.45
const PLATE_HURT_HP := 0.98      # anything below full HP has a story
const PLATE_DEAD := 0.32

func _plate_emphasis(idx: int, nd: Dictionary) -> float:
	var rec: Dictionary = nd.get("last_rec", {})
	if rec.is_empty():
		return 1.0
	if not bool(rec.get("alive", true)):
		return PLATE_DEAD
	# The selected unit is always at full emphasis — the player asked for it.
	if idx == selected_idx:
		return 1.0
	# Anything the sim says is NOT routine: hurt, under a status, or doing something.
	#
	# ⚠️ `maxHp` is NOT in the frame contract (`spatial_sim.gd:_record_frame` emits hp, mp, alive,
	# state, statuses, pos, facing, targetId, intent, reason — and no ceiling). It comes from the
	# unit's own static data, exactly as the HP bar at `_apply_frame` already does. That is not the
	# renderer deriving state; it is the renderer reading the roster.
	var mx: float = float(all_units[idx].max_hp) if idx < all_units.size() else 0.0
	if mx > 0.0 and float(rec.get("hp", mx)) / mx < PLATE_HURT_HP:
		return 1.0
	if not (rec.get("statuses", []) as Array).is_empty():
		return 1.0
	var st := str(rec.get("state", "idle"))
	if st == "attack" or st == "cast" or st == "stunned":
		return 1.0
	return PLATE_QUIET


func _update_plates() -> void:
	if camera == null:
		return
	# ⚠️ DECLUTTER PASS. Five plates in a scrum land on the same few screen pixels and stack into an
	# unreadable wall — the thing that hid the fight when the camera pulled back to 38 degrees.
	# Two rules, in this order:
	#   1. Sort by DEPTH so the nearest unit's plate is placed last and therefore drawn on top.
	#      A plate half-covered by a MORE distant unit's plate reads as a rendering fault.
	#   2. Nudge a plate UP whenever it would overlap one already placed this frame. Vertical, not
	#      horizontal, because a plate must stay above its own unit to be attributable at all —
	#      sliding it sideways breaks the one thing it is for.
	var placed: Array = []   # Rect2 of each plate already positioned this frame
	# ⚠️ STACK IN A STABLE ORDER, DRAW BY DEPTH — two different questions the old code answered
	# with one sort. Processing by camera distance made the lift order reshuffle every frame as
	# units moved, so clustered plates SWAPPED SLOTS constantly — the "hard to read when they are
	# together" the user saw. Placement now runs in fixed unit order (a scrum stacks into the
	# same column every frame); depth only decides z_index, so the nearest still draws on top.
	var order: Array = []
	for k in range(nodes.size()):
		var h := nodes[k]["holder"] as Node3D
		order.append({"k": k, "d": camera.global_position.distance_to(h.global_position)})
	var by_depth := order.duplicate()
	by_depth.sort_custom(func(a, b): return float(a["d"]) > float(b["d"]))
	for rank in range(by_depth.size()):
		(nodes[int(by_depth[rank]["k"])]["plate"] as Control).z_index = rank

	for entry in order:
		var k: int = int(entry["k"])
		var nd: Dictionary = nodes[k]
		var plate: Control = nd["plate"]
		# ⚠️ THE DEAD STAY UNPLATED. This pass sets `visible = true` on every plate it places, so
		# without this skip it silently resurrected the plate `_apply_frame` just hid — the
		# hide-and-reshow fight would be invisible in any headless probe and obvious on screen.
		if bool(nd.get("dead", false)) or not bool((nd.get("last_rec", {}) as Dictionary).get("alive", true)):
			plate.visible = false
			continue
		var world: Vector3 = (nd["holder"] as Node3D).global_position + Vector3(0, UNIT_HEIGHT + 0.7, 0)
		if camera.is_position_behind(world):
			plate.visible = false
			continue
		plate.visible = true
		var pos: Vector2 = camera.unproject_position(world) - Vector2(plate.size.x * 0.5, plate.size.y)

		# Lift until clear of everything already placed. Bounded: after PLATE_MAX_LIFT steps we
		# accept the overlap rather than launch a plate off the top of the screen, which would be
		# a worse failure than a slightly crowded corner.
		var rect := Rect2(pos, plate.size)
		var lifts := 0
		while lifts < PLATE_MAX_LIFT:
			var clash := false
			for r in placed:
				if rect.intersects(r as Rect2):
					clash = true
					break
			if not clash:
				break
			pos.y -= plate.size.y + PLATE_GAP
			rect = Rect2(pos, plate.size)
			lifts += 1

		# ⚠️ CLAMP INTO THE VIEWPORT. Lifting a plate to dodge an overlap can push it clean off the
		# top of the screen, which is a worse failure than the crowding it was avoiding — the unit
		# is then annotated by something the player cannot see. Observed at 1280x800 with five
		# units in a scrum: the nearest plate left the frame entirely.
		# ⚠️ QUIET UNITS RECEDE. Ten full-strength plates all shouting equally is why the annotation
		# read louder than the fight — and in an autobattler the player's attention is the ONLY
		# resource they have left, because they cannot intervene. A unit at full HP that is walking
		# is not news; a unit taking damage, casting, stunned or dying is.
		#
		# ⚠️ THIS DIMS, IT NEVER HIDES. Every plate stays on screen and stays legible — `CLAUDE.md`
		# makes legibility load-bearing, and a player who cannot find their own monster has been
		# failed worse than one reading a busy frame. This is emphasis, not disclosure.
		plate.modulate.a = _plate_emphasis(k, nd)

		var vp: Vector2 = get_viewport().get_visible_rect().size
		pos.x = clampf(pos.x, 4.0, maxf(4.0, vp.x - plate.size.x - 4.0))
		pos.y = clampf(pos.y, 4.0, maxf(4.0, vp.y - plate.size.y - 4.0))
		plate.position = pos
		# ⚠️ Record the CLAMPED rect, not the pre-clamp one — a plate pushed back down by the
		# viewport clamp occupies different pixels, and registering the wrong rect would let the
		# next plate overlap it anyway.
		placed.append(Rect2(pos, plate.size))
		# The lifted plate no longer sits on its unit's head, so it must still be attributable.
		# Fade it slightly as it climbs — a plate far from its unit reads as less certain, which
		# is honest, and the fade also stops a stack of lifted plates competing for attention.
		plate.modulate.a = 1.0 if lifts == 0 else maxf(0.55, 1.0 - 0.15 * float(lifts))


func _drain_log(upto: int) -> void:
	while logged_upto < upto and logged_upto < event_log.size():
		_log_event(event_log[logged_upto])
		logged_upto += 1


func _log_event(e: Dictionary) -> void:
	match e.get("kind", ""):
		"start":
			log_view.append_text("[color=#d9b957]The fight begins.[/color]\n")
		"hit":
			var col := "#ffcf5c" if e.get("crit", false) else "#e6e6ec"
			log_view.append_text("[color=%s]%s → %s: %s (%d)%s[/color]\n" % [col, e["attacker"], e["target"], e["move"], e["dmg"], "  CRIT" if e.get("crit", false) else ""])
		"miss":
			log_view.append_text("[color=#8a8a92]%s's %s missed %s[/color]\n" % [e["attacker"], e["move"], e["target"]])
		"status_apply":
			log_view.append_text("[color=#c98a3a]%s is now %s[/color]\n" % [e["unit"], e["status"]])
			# The two statuses that MOVE the fight get a float — a forced target and a launched
			# body are spatial events, and text in a side log does not read at fight speed.
			var stk := str(e.get("status", ""))
			if stk == "taunt" or stk == "knockback":
				var stid := _index_of_unit_named(str(e.get("unit", "")))
				if stid >= 0:
					_float_text(stid, "TAUNTED" if stk == "taunt" else "LAUNCHED",
						Color(0.92, 0.55, 0.30) if stk == "taunt" else Color(0.80, 0.60, 0.95))
					if vfx != null and stk == "knockback":
						vfx.burst((nodes[stid]["holder"] as Node3D).position + Vector3(0, 0.5, 0),
							"dust", Color(0.75, 0.68, 0.55), 1.5, 14)
		"status_expire":
			log_view.append_text("[color=#6f6f77]%s's %s wears off[/color]\n" % [e["unit"], e["status"]])
		"buff":
			log_view.append_text("[color=#7fd0a0]%s's %s aids %s[/color]\n" % [e["caster"], e["move"], e["unit"]])
			# THE BUFF GRAMMAR: ring under every affected monster, charge on the caster. The sim
			# emits one buff event PER AFFECTED UNIT, so a team buff rings exactly who it touched.
			if vfx != null:
				var bid := _index_of_unit_named(str(e.get("unit", "")))
				var bcid := _index_of_unit_named(str(e.get("caster", "")))
				if bid >= 0:
					var bmv: Dictionary = _move_by_name.get(str(e.get("move", "")), {})
					var bcaster: Vector3 = (nodes[bcid]["holder"] as Node3D).position if bcid >= 0 else (nodes[bid]["holder"] as Node3D).position
					vfx.play_ability(bmv if not bmv.is_empty() else {"name": "", "type": "buff", "channel": "support", "target": "ally"},
						bcaster + Vector3(0, UNIT_HEIGHT * 0.5, 0),
						(nodes[bid]["holder"] as Node3D).position, false)
		# ⚠️ heal and cleanse were MISSING from this dispatch, so the two effects fixed on
		# 2026-08-05 — friendly effects and healing, neither of which worked in either engine
		# before that day — would have landed invisibly. In a game the player only WATCHES, an
		# effect with no line in the log did not happen as far as they are concerned.
		"heal":
			var blocked: bool = bool(e.get("healblocked", false))
			log_view.append_text("[color=#7fd0a0]%s's %s heals %s for %d%s[/color]
" % [
				e["caster"], e["move"], e["unit"], int(e.get("amount", 0)),
				" (healblocked)" if blocked else ""])
			# ⚠️ Float it ON THE UNIT too, not only in the log. Damage already floats; a heal that
			# only ever appears as a line of text reads as bookkeeping rather than as something
			# that happened to a creature you are watching.
			var hid := _index_of_unit_named(str(e["unit"]))
			if hid >= 0:
				_float_text(hid, "+%d" % int(e.get("amount", 0)), Color(0.50, 0.82, 0.63))
				if vfx != null:
					vfx.heal_rise((nodes[hid]["holder"] as Node3D).position)
					vfx.aura_pulse((nodes[hid]["holder"] as Node3D).position, Color(0.50, 0.82, 0.63))
		"cleanse":
			# The most dramatic counter-play in the game: breaking hard control off a pinned ally.
			# Gold, because it is a save, not routine upkeep.
			var broke: Array = e.get("broke", [])
			log_view.append_text("[color=#d8b859]%s's %s frees %s from %s[/color]
" % [
				e["by"], e["move"], e["unit"], ", ".join(PackedStringArray(broke))])
			# Gold, and it says FREED rather than the status name — the player needs to read the
			# save at a glance, and which particular control broke is in the log line beside it.
			var cid := _index_of_unit_named(str(e["unit"]))
			if cid >= 0:
				_float_text(cid, "FREED", Color(0.85, 0.72, 0.35))
		# ── the 2026-08-06 mechanics — every one of these existed in the sim before it existed
		# on screen, and "an effect with no line in the log did not happen as far as the player
		# is concerned" (the heal/cleanse lesson, same file, one day earlier). ──
		"interrupt":
			log_view.append_text("[color=#ff8a5c]%s's %s is INTERRUPTED — %s[/color]\n" % [
				e.get("unit", "?"), e.get("move", "?"), e.get("reason", "")])
			var iid := _index_of_unit_named(str(e.get("unit", "")))
			if iid >= 0:
				_float_text(iid, "INTERRUPTED", Color(1.0, 0.54, 0.36))
				if vfx != null:
					vfx.burst((nodes[iid]["holder"] as Node3D).position + Vector3(0, UNIT_HEIGHT * 0.7, 0),
						"twirl", Color(1.0, 0.54, 0.36), 1.1, 10)
				# ⚠️ THE PLATER INTERRUPT FLASH: the cast bar does not vanish — it fills grey,
				# says "Interrupted", holds ~0.7s, THEN goes. A bar that silently disappears is
				# ambiguous (finished? cancelled?); the grey flash is the unambiguous "denied".
				var ind: Dictionary = nodes[iid]
				ind["cast_flash_until"] = Time.get_ticks_msec() + 700
				(ind["cast_fill"] as ColorRect).color = Color(0.55, 0.55, 0.60)
				(ind["cast_fill"] as ColorRect).size = Vector2(174.0, 17)
				(ind["cast_lbl"] as Label).text = "Interrupted"
		"cast_steady":
			log_view.append_text("[color=#d8b859]%s shrugs off the interrupt — %s continues[/color]\n" % [
				e.get("unit", "?"), e.get("move", "?")])
			var sid := _index_of_unit_named(str(e.get("unit", "")))
			if sid >= 0:
				_float_text(sid, "STEADY", Color(0.85, 0.72, 0.35))
				if vfx != null:
					vfx.burst((nodes[sid]["holder"] as Node3D).position + Vector3(0, 0.4, 0),
						"circle", Color(0.85, 0.72, 0.35), 1.4, 6)
		"detonate":
			log_view.append_text("[color=#ff9f45]%s[/color]\n" % e.get("reason", "a status detonates"))
			var did := _index_of_unit_named(str(e.get("unit", "")))
			if did >= 0:
				_float_text(did, "DETONATED", Color(1.0, 0.62, 0.27))
				if vfx != null:
					var dpos: Vector3 = (nodes[did]["holder"] as Node3D).position + Vector3(0, UNIT_HEIGHT * 0.5, 0)
					vfx.burst(dpos, "flare", Color(1.0, 0.62, 0.27), 1.8, 14)
					vfx.burst(dpos, "scorch", Color(0.9, 0.45, 0.2), 1.2, 6)
		"contagion":
			log_view.append_text("[color=#8fbf6a]☣ %s[/color]\n" % e.get("reason", "a status spreads"))
			var cgid := _index_of_unit_named(str(e.get("unit", "")))
			if cgid >= 0:
				_float_text(cgid, "INFECTED", Color(0.56, 0.75, 0.42))
				if vfx != null:
					vfx.burst((nodes[cgid]["holder"] as Node3D).position + Vector3(0, UNIT_HEIGHT * 0.5, 0),
						"smoke", Color(0.56, 0.75, 0.42), 1.2, 12)
		"death":
			log_view.append_text("[color=#ff5f5f]%s falls![/color]\n" % e["unit"])
			_punch(0.55, 0.45)
	call_deferred("_snap_log")


func _snap_log() -> void:
	var bar := log_scroll.get_v_scroll_bar()
	if bar != null:
		log_scroll.scroll_vertical = int(bar.max_value)


func _finish() -> void:
	var w: String = result.get("winner", "draw")
	banner_title.text = "Your team wins!" if w == "A" else ("The rival wins." if w == "B" else "Draw.")
	banner_sub.text = "%d vs %d standing — %.1fs" % [
		result.get("survivorsA", 0), result.get("survivorsB", 0), result.get("duration", 0.0)]
	banner.visible = true
	var ReportScript = load("res://scripts/ui/report_ui.gd")
	ReportScript.hand_off(result, team_a, team_b)
	_offer_cup_continuation(w == "A")


## If this fight was fought as part of a live cup run (`CupRun`), record the round's outcome and
## offer the player a way forward — another round's tactics screen, or, once every round is
## fought, the cup's final result (`tournament.tscn`, which pays the purse and applies promotion
## via `CupRun.finish() -> Career.apply_tournament_outcome()`). Standalone fights (no cup active)
## are untouched — same "See the report"/"Back to the Stable" pair as always.
func _offer_cup_continuation(won: bool) -> void:
	var cup := get_node_or_null("/root/CupRun")
	if cup == null or not cup.active:
		return
	cup.record_round_result(won)
	var cont := Button.new()
	cont.custom_minimum_size = Vector2(0, 36)
	if cup.is_finished():
		cont.text = "See cup results  →"
		cont.pressed.connect(func():
			cup.finish()
			get_tree().change_scene_to_file("res://scenes/tournament.tscn"))
	else:
		cont.text = "Next round (%d of %d)  →" % [cup.current_round + 1, cup.rival_count]
		cont.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/tactics.tscn"))
	banner_box.add_child(cont)


func _skip() -> void:
	if not frames.is_empty():
		frame_pos = float(frames.size() - 1)
		_apply_frame(frame_pos)
	_drain_log(event_log.size())
	for k in range(nodes.size()):
		if not all_units[k].alive:
			_topple(k)
	playing = false
	_finish()


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# OVERLAY
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _build_overlay() -> void:
	overlay = CanvasLayer.new()
	add_child(overlay)
	plates_root = Control.new()
	plates_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plates_root.anchor_right = 1; plates_root.anchor_bottom = 1
	overlay.add_child(plates_root)

	var ui := Control.new()
	ui.anchor_right = 1; ui.anchor_bottom = 1
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(ui)

	var header := Label.new()
	header.position = Vector2(20, 12)
	header.text = "%s League" % league_name
	header.add_theme_font_size_override("font_size", 22)
	header.add_theme_color_override("font_color", Color(0.87, 0.74, 0.36))
	ui.add_child(header)

	# Say plainly which engine produced what is on screen — a viewer should never have to guess
	# whether they are watching the real simulation or the non-spatial fallback. Populated by
	# `_update_mode_label()` once the (now async) fight has actually resolved — built here only as
	# a placeholder so the label exists for that later call.
	mode_label = Label.new()
	mode_label.position = Vector2(20, 42)
	mode_label.add_theme_font_size_override("font_size", 11)
	mode_label.add_theme_color_override("font_color", Color(0.55, 0.58, 0.64))
	mode_label.text = "resolving…"
	ui.add_child(mode_label)

	resolving_label = Label.new()
	resolving_label.anchor_right = 1; resolving_label.anchor_bottom = 1
	resolving_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	resolving_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	resolving_label.text = "Resolving the fight…"
	resolving_label.add_theme_font_size_override("font_size", 22)
	resolving_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.90))
	resolving_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resolving_label.visible = false
	ui.add_child(resolving_label)

	var hint := Label.new()
	hint.position = Vector2(20, 60)
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.50, 0.53, 0.60))
	# ⚠️ Every control this screen has, stated on this screen. The camera toggle and the replay
	# speed keys exist because neither camera and no single speed is right for every moment — a
	# tension that is measured, not a preference — and a control the player cannot discover is the
	# same as one that does not exist.
	hint.text = "Tab / click a nameplate for its orders · Esc close · C camera (Team/Action/Arena) · drag to pan, wheel to zoom · Space pause · [ ] speed"
	ui.add_child(hint)

	callout = PanelContainer.new()
	callout.visible = false
	callout.custom_minimum_size = Vector2(300, 0)
	callout.position = Vector2(20, 84)
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(0.04, 0.04, 0.06, 0.96)
	csb.border_color = Color(0.87, 0.74, 0.36)
	csb.set_border_width_all(2)
	csb.set_corner_radius_all(6)
	csb.content_margin_left = 12; csb.content_margin_right = 12
	csb.content_margin_top = 10; csb.content_margin_bottom = 10
	callout.add_theme_stylebox_override("panel", csb)
	callout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(callout)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 4)
	callout.add_child(cv)
	callout_title = Label.new()
	callout_title.add_theme_font_size_override("font_size", 18)
	callout_title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.97))
	cv.add_child(callout_title)
	callout_body = RichTextLabel.new()
	callout_body.bbcode_enabled = true
	callout_body.fit_content = true
	callout_body.custom_minimum_size = Vector2(280, 0)
	callout_body.add_theme_font_size_override("normal_font_size", 14)
	callout_body.add_theme_color_override("default_color", Color(0.90, 0.90, 0.93))
	cv.add_child(callout_body)

	var strip := HBoxContainer.new()
	strip.anchor_top = 1.0; strip.anchor_bottom = 1.0
	strip.anchor_left = 0.0; strip.anchor_right = 1.0
	strip.offset_top = -132; strip.offset_left = 16; strip.offset_right = -16; strip.offset_bottom = -12
	strip.add_theme_constant_override("separation", 12)
	ui.add_child(strip)

	var log_panel := PanelContainer.new()
	log_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lsb := StyleBoxFlat.new()
	lsb.bg_color = Color(0.04, 0.04, 0.06, 0.82)
	lsb.set_corner_radius_all(5)
	lsb.content_margin_left = 10; lsb.content_margin_right = 10
	lsb.content_margin_top = 6; lsb.content_margin_bottom = 6
	log_panel.add_theme_stylebox_override("panel", lsb)
	strip.add_child(log_panel)
	log_scroll = ScrollContainer.new()
	log_panel.add_child(log_scroll)
	log_view = RichTextLabel.new()
	log_view.bbcode_enabled = true
	log_view.fit_content = true
	log_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_scroll.add_child(log_view)

	var ctrl := VBoxContainer.new()
	ctrl.custom_minimum_size = Vector2(230, 0)
	ctrl.add_theme_constant_override("separation", 5)
	strip.add_child(ctrl)
	var speeds := HBoxContainer.new()
	speeds.add_theme_constant_override("separation", 4)
	ctrl.add_child(speeds)
	for s in SPEED_OPTIONS:
		var b := Button.new()
		b.text = ("%.1fx" % s) if s < 1.0 else ("%dx" % int(s))
		b.custom_minimum_size = Vector2(50, 28)
		b.pressed.connect(func(): speed = s)
		speeds.add_child(b)
	var skip := Button.new()
	skip.text = "Skip to result"
	skip.pressed.connect(_skip)
	ctrl.add_child(skip)
	var back := Button.new()
	back.text = "Back to the Stable"
	back.pressed.connect(func():
		var cup := get_node_or_null("/root/CupRun")
		if cup != null and cup.active:
			cup.cancel()
		get_tree().change_scene_to_file("res://scenes/stable.tscn"))
	ctrl.add_child(back)

	banner = PanelContainer.new()
	banner.anchor_left = 0.30; banner.anchor_right = 0.70
	banner.anchor_top = 0.34; banner.anchor_bottom = 0.34
	banner.offset_bottom = 140
	var bsb2 := StyleBoxFlat.new()
	bsb2.bg_color = Color(0.05, 0.05, 0.07, 0.94)
	bsb2.border_color = Color(0.87, 0.74, 0.36)
	bsb2.set_border_width_all(2)
	bsb2.set_corner_radius_all(8)
	bsb2.content_margin_top = 14; bsb2.content_margin_bottom = 14
	banner.add_theme_stylebox_override("panel", bsb2)
	banner.visible = false
	ui.add_child(banner)
	var bv := VBoxContainer.new()
	banner.add_child(bv)
	banner_box = bv
	banner_title = Label.new()
	banner_title.add_theme_font_size_override("font_size", 28)
	banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(banner_title)
	banner_sub = Label.new()
	banner_sub.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(banner_sub)
	var rb := Button.new()
	rb.text = "See the report  →"
	rb.custom_minimum_size = Vector2(0, 36)
	rb.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/report.tscn"))
	bv.add_child(rb)
