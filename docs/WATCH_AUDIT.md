# The Watch Audit — what a viewer can and cannot tell

**2026-08-09.** The first playtest record in this repository. `docs/OUTSTANDING.md` §3 has said for
months that the biggest unchecked assumption in the project is whether the sim is actually fun to
watch, and that there is not one playtest record in the repo. This is that record.

**Method.** `monster-tamer/scripts/_probe_watch.gd` drives the **real production watch path** —
title screen → `watch.gd` → `arena3d.tscn` → `scripts/ui/arena_3d.gd` — plays a 5v5 at true speed
with a real window (never `--headless`; the dummy renderer saves black rectangles and would have
"passed"), captures a PNG strip every 2 sim-seconds, and measures the viewer's experience every
engine frame. Three layouts × two stat levels. The frames were then looked at.

```
P:/Godot_v4.7.1-stable_win64.exe --path . res://scenes/_probe_watch.tscn -- four_pillar 0.35 0
                                                                            layout  train  cam(0 TEAM/1 ACTION/2 ARENA)
```

Captures land in `%APPDATA%/Godot/app_userdata/Monster Tamer/watch_*.png`.

---

## 0. The honest answer to the honest question

**No. It is not fun to watch, and the reason is structural, not cosmetic.**

Every fight measured has exactly the same shape:

| | four_pillar t0.35 | central_mass t0.80 | lanes t0.60 |
|---|---|---|---|
| fight length | 22.6s | 24.0s | 21.7s |
| **first damage** | **t=9.9s (44%)** | **t=9.6s (40%)** | **t=9.5s (44%)** |
| first death | t=10.5s (46%) | t=10.6s (44%) | t=10.4s (48%) |
| seconds with no log line at all | 22% | 29% | 27% |
| busiest second | **24 lines** | 18 lines | 18 lines |

**Forty per cent of every fight is a silent walk**, during which the only events are two monsters
buffing themselves in identical repeated lines. Then everything that will ever happen happens
inside a ten-second scrum at a density of eighteen to twenty-four log lines per second. There is
no middle. A viewer is bored, then overwhelmed, then it is over.

And the ten-second scrum is a **shapeless pile**. Look at
`watch_four_pillar_t35_06_t012.0.png`: eight bodies of eight different colours overlapping inside a
350×250-pixel heap in the middle of an otherwise empty brown board, with eight identical white
`10`s floating over them and three nameplates collided into an illegible run of text at the top of
the frame (`RazzhornTitanus-`). You cannot tell which body is on which side, who is hitting whom,
or what any ability is. The only legible account of the fight on that screen is the 11-pixel text
log in the bottom-left corner — which is to say **the fight is currently readable only by reading,
and the 3D scene is decoration over a text log.**

That is the finding. Everything below is why, ranked by what would change it.

---

## 1. ⚠️ ONE FIELD CAUSES THREE OF THE FOUR WORST SYMPTOMS

`arena_3d.gd:_write_back_final()` stamps the fight's **final** state onto the `MonsterInstance`
objects — inside `_adapt_result()`, i.e. **before playback begins**. Its own doc comment explains
why the write-back exists (the new sim never touches the monster objects, and the report and career
read them afterwards) and it is right about that. It is wrong about *when*. From frame zero of the
replay, `all_units[k].alive` is the answer to the fight, and three separate systems read it:

**a. The scoreboard spoils the result and is wrong for the entire fight.**
`_update_standing_hud()` counts `m.alive`. Measured: **the standing HUD disagrees with the frame on
screen in 100% of frames** (799/800, 771/772, 696/697 across the three runs — the one agreeing
frame is the last one). At t=8.0s, with all ten monsters alive and at full health, the HUD reads
*"Team A 2 monsters remaining / Team B 0 monsters remaining."* See
`watch_four_pillar_t35_04_t008.0.png`. **The only squad-level readout in the game announces the
winner before the first blow and lies continuously until the end.** This is the direct answer to
question 1 — can you tell who is winning — and the answer is that the one instrument built to tell
you is inverted.

**b. The camera follows the eventual survivors, not the fight.**
`_camera_target()` skips units where `not all_units[k].alive`, so it frames only the monsters that
will still be standing at the end — from the first frame. Measured: **65–79% of living units are in
frame on average**; a third of the fight happens off-screen. And it collapses the camera modes:
TEAM and ACTION produced *byte-identical* framing numbers (166px mean unit height, 66% on-screen,
2.64% body coverage) because with team B's survivors at zero, "all living units" and "living team A
units" are the same two monsters. **Pressing `C` to switch from TEAM to ACTION currently does
nothing.**

**c. `_skip()` topples the wrong bodies**, for the same reason — it is toppling by final state
rather than by the frame it stopped on. (Cosmetic; listed for completeness.)

**The fix is timing, not content.** Keep the write-back, move it to `_finish()`, and have the three
readers take aliveness from the frame the player is looking at. This is the highest
value-per-line change available in the whole watch layer.

---

## 2. THE NAMEPLATE — the only HP surface there is, and it is unattributable

Measured across the three fights, every engine frame:

- **52–69% of plates are orphaned** — lifted more than one body-height away from the head they
  annotate. The declutter stacker pushes them up until they clear each other, and at that point
  nothing connects a plate to a creature.
- **1.8–4.1 overlapping plate pairs per frame**, so the declutter does not even succeed.
- **Plates occupy 6.2% of the frame against 2.6% for the bodies — 2.4× more screen than the fight
  they annotate.** In ARENA camera mode the ratio is **34×**.

`watch_four_pillar_t35_00_t000.0.png` (deploy) is the clearest case: ten plates stacked in two
columns in the upper third of the screen, and the monsters they belong to are twenty-pixel specks
elsewhere. `..._06_t012.0.png` shows three plates overlapping into a single unreadable smear.

The file's own comments record two previous rounds of shrinking the plate (148→104→82px) and end
with *"THIS IS THE FLOOR… any further reduction has to come from showing FEWER plates."* That
conclusion is correct and was not carried out. The plate is currently trying to be, simultaneously,
a squad HP readout, a per-monster identity tag, a cast bar and an intent label — at a camera
distance where a monster is 165 pixels tall and there are ten of them.

---

## 3. THE CAMERA IS AVERAGING, NOT FILMING

The brief's claim is confirmed and is worse than stated, because the ground is also far too large
for the fight it holds.

- Ground: **440 × 246 world units = 108,416 sq units.**
- The fight's actual footprint: **~140 × 70, a mean of 16–18% of the ground**, and during the scrum
  a small fraction of that.
- ARENA mode, which is the only mode that keeps everyone on screen (100%), renders a monster at
  **43 px — 3.6% of frame height — with the bodies covering 0.18% of the frame.**
  `watch_four_pillar_t35_cam2_06_t012.0.png` is the whole ten-monster battle as a single
  100×60-pixel smudge at the centre of a 1920×1200 image. Each individual nameplate on that frame is
  larger than the entire battle.

So the camera offers a choice between *"see everything, at ant scale"* and *"see two thirds of it."*
Neither is filming. The venue/ground split `CLAUDE.md` insists on has not been applied here: the
ground is sized like a venue.

---

## 4. WHICH SILENT EVENT KINDS ACTUALLY MATTER — ranked, and two of the brief's ten refuted

The brief listed ten kinds with zero references in `arena_3d.gd`. That grep is misleading, because
`arena_3d.gd` **translates** sim kinds into a legacy vocabulary in `_adapt_event()` before
presenting them, and presents two more through the frame stream rather than through events. The
audit re-ran the same fight to count raw kinds and checked each one against how it is actually
presented. Confirmed silent, ranked by what it costs the viewer:

**1. `taunted` — and the code that looks like it handles this is dead.**
A forced target change is the single most important thing a tank does and the single most
inexplicable thing a viewer can see: a monster turns around and attacks someone else for no visible
reason. `arena_3d._log_event` floats "TAUNTED" when a `status_apply` arrives with
`status == "taunt"` — but `taunt` is not a `fieldStatus` (it is not in `data.json`'s fifteen), the
sim stores it as `tgt["taunt"]` and emits its own `taunted` event, and it **never** emits
`status_applied` for it. That branch cannot fire. A mass taunt currently has no float, no log line,
no line to the taunter, and no sound. Fired twice in the sample fight.

**2. `aoe` — the sim wrote the contract and the renderer never signed it.**
`sim.gd:1585` carries this comment above the emit: *"⚠️ THE BURST MUST BE VISIBLE OR IT IS NOT A
MECHANIC… The renderer draws this ring; it derives nothing — centre, radius and count come from
here."* The event carries `centre`, `radius`, `targets` and `falloff`. Nothing in `arena_3d.gd`
reads it. `_show_aoe_ring()` exists but is driven from `_apply_frame` as a *telegraph* during a
cast, from the move's authored reach — the **impact**, the moment three bodies get caught, has no
presentation. The entire "AoE is weak into one body and strong into three" design is invisible.

**3. `fizzle` — the ambiguity the interrupt fix already proved is unacceptable.**
When an interrupt lands, the cast bar deliberately fills grey and says "Interrupted" for 0.7s,
because *"a bar that silently disappears is ambiguous (finished? cancelled?)"*. A `fizzle` — no
target left, or no mana — makes the bar silently disappear. Same ambiguity, same fix needed
(grey + "No target"). Fired three times.

**4. `debuff` — an asymmetry the player will read as a rule.**
`buff` has a full presentation grammar (ring under the target, charge on the caster, green log
line). `debuff` has nothing. So a viewer watches their team visibly grow stronger and never once
sees the enemy weakened, which teaches a false lesson about what the kits do. Fired five times.

**REFUTED — these two are presented, just not through the event path:**
- `cast_start` is presented by the **nameplate cast bar**, driven from the frame stream's
  `castMove`/`castFrac`. Visible in `..._END.png` as "◉ Body Slam" under Terrock.
- `proj_launch` is presented by the **projectile bodies**, drawn from the frame stream's
  `projectiles` array.

**UNRANKABLE — never fired, and that is its own finding.** `heal`, `cleanse`, `interrupt`,
`thorns`, `ward_soak`, `status_tick`, `status_break` and `proj_fizzle` all fired **zero** times in
every fight measured. `COMBAT_SPATIAL_LOG.md` recorded this exact lesson on 2026-08-08 — *"a demo
roster that cannot produce a mechanic is a demo that hides it"* — and fixed it for
`scripts/sim/_watch_sim.gd`, the **dev** scene, which fields a real composition (tank with taunt and
thorns, healer with mend and cleanse, caster with an AoE, kicker, diver). **The production watch
path did not inherit that fix.** `watch.gd`'s ten species draft their kits from their movesets, and
the ten kits that resulted are all damage and self-buffs:

```
Gruulk    Brace, Sunder, Enrage, Scrap, Power Strike
Terrock   Taunt, Seize, Barbed Carapace, Body Slam, Guard, Steady Vigil
Cobalon   Cinderburst, Phase Step, Silencing Spike, Fracturing Stones, Spark, Frost Shard
Azurefin  Sunder, Shadowstep, Ambush, Power Strike, Enrage, Blood Price
Grynt     Ambush, Power Strike, Piercing Shot, Sunder, Fester, Shadowstep
Mirejaw   Sunder, Riposte, Scrap, Brace, Enrage, Power Strike
Titanus   Sunder, Brace, Scrap, Blood Price, Power Strike, Riposte
Rosewing  Grand Mockery, Captivate, Rallying Song, Acrobatics, Anthem of Iron, Inspire
Regalor   Spark, Rime Bind, Phase Step, Cinderburst, Ember, Guard
Razzhorn  Ambush, Fester, Twin Fangs, Toxin Stack, Piercing Shot, Sunder
```

Not one heal. Terrock carries `Taunt` and `Barbed Carapace` and produced two `taunted` events and
zero `thorns`. Four rounds of support-layer work are invisible on the path the player takes.

---

## 5. ⚠️ THE FIGHT IS SILENT. THE ENTIRE AUDIO LAYER IS UNREACHABLE FROM THE GAME.

`scripts/audio/battle_audio.gd` (473 lines) and `scripts/audio/cues.gd` (225 lines) are a complete,
procedurally-synthesised battle mixer: per-cue gain/priority/cap/cooldown tables, a ducking meter,
positional voices, status separation by pitch, replay-speed pitch scaling, crowd swells, and an
`on_event()` that handles **every one of the 22 sim event kinds** — including an `aoe` cue whose
gain scales with the number of bodies caught.

**Nothing in the game calls it.**

```
$ grep -rn "battle_audio" --include=*.gd --include=*.tscn .
  scripts/sim/_watch_sim.gd:127     ← the DEV scene
  scripts/audio/_probe_audio.gd:15  ← its own probe
  (nothing else)
$ grep -n "Audio" scripts/ui/arena_3d.gd
  (nothing)
```

`arena_3d.gd` contains no `AudioStreamPlayer`, no reference to the audio scripts, and no sound of
any kind. **The production 5v5 — the thing behind the "Watch a Battle" button — plays in total
silence.** This is the project's signature failure at full size: authored, priced, documented,
mixed, and it does not exist for the player.

It is also the *cheapest* fix for the density problem in §0. Twenty-four log lines in one second is
unreadable because the eye is serial; the ear is parallel. A layered mix is how a real autobattler
lets you feel five simultaneous exchanges without reading any of them.

⚠️ **One integration note:** `battle_audio.on_event()` takes **raw sim events** (`ward_soak`,
`taunted`, `aoe`…). `arena_3d._adapt_result()` currently discards the raw stream, keeping only the
twelve kinds `_adapt_event()` recognises. Wiring audio therefore requires keeping the raw per-frame
event array alongside the adapted log — which is the same prerequisite as fixing §4.

---

## 6. THE SQUAD IS NOT THE UNIT OF ATTENTION

`FUN_ADDITIONS.md` says it must be. It is not, and there is nothing on screen that is about a squad:

- The scoreboard is a survivor count, in the wrong units (*"Team A"* / *"Team B"*, not the guild or
  team names the rest of the game uses) — and it is wrong (§1a).
- There is **no aggregate team HP, no momentum indicator, no line showing which side is ahead**.
  Ten individual HP bars is not a squad read; it is ten reads the viewer must integrate themselves
  while eight bodies overlap.
- There is no formation read after deploy. The deploy frame shows a legible blue line and a red
  line; four seconds later they are a queue of individuals walking, and after that a pile.
- The live intent ticker at the bottom of the deploy frame reads, five times identically:
  `Gruulk: target: b02 (weakest)` / `Terrock: target: b02 (weakest)` / `Cobalon: target: b02
  (weakest)` … Five lines that say one thing. **That one thing — "the whole squad is focusing the
  same monster" — is genuinely interesting and is exactly a squad-level fact**, and it is presented
  as five identical individual lines that scroll past. It also leaks the raw sim id `b02` to the
  player.

---

## 7. THE POST-FIGHT READ ANSWERS "WHAT HAPPENED", NOT "WAS MY READ RIGHT"

`watch_four_pillar_t35_cam0_REPORT.png`. The report screen is the most legible surface in the whole
watch path and it is close to good. Per-monster rows with damage dealt/taken, a biggest-hit line, a
turning-point sentence, and a per-monster decision log behind a disclosure triangle. But:

- **It speaks in sim ids.** *"21.5s — finishing b00"*, *"11.0s — bulling through b01 to b04"*,
  *"13.5s — target: b01 (weakest)"*, and the turning-point sentence itself: *"Azurefin brought down
  Rosewing at 10.5s — bulling through a03 to a02 and the fight never came back level."* The player
  never sees `a03` anywhere else in the game. `UX_LEGIBILITY.md` §1 rule 1 says the vocabulary is
  never invented twice; this is the vocabulary being invented a third time, in machine keys.
- **Nothing grades the read.** The player committed a target priority and a positional intent before
  the fight; the report never says whether it worked. `FUN_ADDITIONS.md`'s ✓/✗ claim-grading — the
  thing that makes "preparation is the skill" land — is absent.
- **No timeline.** There is no shape to the fight: no HP-over-time, no marker of when it tipped, no
  way to answer "when did I lose this" other than reading the turning-point sentence.

---

## 8. What this audit verified and what it refuted, from the brief

| brief's claim | verdict |
|---|---|
| Ten event kinds are not presented by `arena_3d.gd` | **Partly refuted.** `cast_start` and `proj_launch` *are* presented, through the frame stream (cast bar, projectile bodies). Eight are genuinely silent; four of those never fire with the demo roster. |
| The log claims this was already fixed — check which | **Resolved.** Both are true of *different files*. The 2026-08-08 fix landed in `scripts/sim/_watch_sim.gd`, the dev scene, together with its real composition roster. `arena_3d.gd` — the production path — never received it. Neither the fix nor the roster. |
| The camera fits all living units, so a spread fight reads as a distant blob | **Confirmed and compounded.** It fits all *finally*-living units, so it follows the eventual survivors from frame 0, and TEAM/ACTION are consequently identical. |
| `C` cycles TEAM/ACTION/ARENA/FREE | **Confirmed present, but TEAM and ACTION are currently the same shot** (§1b). |
| No rewind or scrub | **Confirmed** — and given that first blood lands at 46% and the fight resolves in the following ten seconds, a viewer who looks away once has missed the match. |
| `arena_3d.gd` is 4,582 lines and is essentially the whole thing | **Confirmed.** |

**One unreproduced observation, flagged not diagnosed:** across seven runs of the identical command,
six produced a 226-tick fight and one produced 217/185. Six consecutive runs since have been
identical. Determinism is a contract, so this is recorded rather than dismissed; it may be an
artefact of this probe re-running the sim a second time to count raw kinds (a second navmesh bake in
the same process).

**Not a bug, and it cost me ten minutes — recorded so it costs nobody else any:** every capture in
this audit shows a tutorial card ("Recruit your first monster") over the arena. That is
probe-induced. `TutorialOverlay` is an autoload and `arena3d` is in its `MUTED_SCENES` list; the
mute keys off `get_tree().current_scene`, and this probe embeds the arena as a child instead of
making it the current scene. The real watch path mutes it correctly.

---

## 9. Instructions for the three builders

### Builder 1 — camera and presentation

In priority order. Each is measurable with `_probe_watch.gd` as it stands.

1. **Move `_write_back_final()` out of `_adapt_result()` into `_finish()`**, and change
   `_update_standing_hud()`, `_camera_target()` and `_skip()` to read aliveness from the frame being
   displayed (`frames[int(frame_pos)].units[k].alive`) instead of `all_units[k].alive`. Target: the
   probe's *"standing HUD disagrees"* figure goes from 100% to 0%, and TEAM/ACTION stop producing
   identical framing numbers.
2. **Present the four silent kinds that matter**, in this order: `taunted` (a float on the victim
   *and* a visible line to the taunter — this is the one that explains otherwise inexplicable
   behaviour), `aoe` (a ground ring at `centre`/`radius` on impact, sized by `targets` — the event
   already carries all three; the sim's own comment is the spec), `fizzle` (grey the cast bar and
   say why, exactly as `interrupt` already does), `debuff` (mirror the existing buff grammar).
   ⚠️ This requires keeping the raw per-frame event array through `_adapt_result()`; do that once,
   because Builder 2 needs the same thing.
   ⚠️ And delete or fix the dead `status == "taunt"` branch in `_log_event` — leaving code that
   looks like it handles taunt is how this stayed invisible.
3. **Stop the fight from being a shapeless scrum.** Two candidates, in order of expected return:
   a **team-tinted ground ring or rim light under every unit** (the team tell must be *on the body*,
   not on a detached plate — this is what makes `..._t012.0.png` unreadable), and **damage numbers
   that aggregate per victim per beat** rather than eight identical `10`s.
4. **Show fewer plates, not smaller ones.** The file already reached this conclusion. Candidate:
   full plate for the selected/leading unit and for anyone below ~35% HP; a bare HP pip on the body
   for everyone else. Target: orphan rate under 20%, zero overlapping pairs, plate area below body
   area.
5. **Re-open the ground size.** 440×246 for a fight that uses 140×70 is a venue masquerading as a
   ground. Shrinking the ground is a bigger legibility win than any camera change, and it is cheap —
   but it is a *balance* input (`Sp.ground_size`), so it goes through the balance discipline, not
   through the renderer.

### Builder 2 — audio

1. **Wire `battle_audio.gd` into `arena_3d.gd`.** It is done already, correctly, in
   `scripts/sim/_watch_sim.gd` lines 127–131 (create, `add_child`), 786 (`on_event(e, cpos, apos)`
   per event), 950 (`crowd_swell`), 1146–1147 (`set_speed`/`set_muted` from the playback controls).
   Copy that integration. It is an optional dependency there and must stay one here — a failed
   render leaves the node inert and the fight silent, which is the game we already have.
2. It needs **raw sim events**, not the adapted log. Coordinate with Builder 1's change; do not
   build a second event path.
3. Once it is in, **the mix is the thing to judge, not the wiring**. `battle_audio.gd`'s own comment
   is right: *"changing a `db` without looking at `prio`/`cap`/`cd` is how a cue sheet turns into
   noise."* Judge it against the density measured here — the busiest second carries 18–24 events.
4. **The approach is 40% of the fight and currently silent in both senses.** Crowd bed, footfall,
   and a rising pre-contact swell are the cheapest fix available for the dead-air half of §0, and
   audio can carry that stretch without the renderer needing anything new to show.

### Builder 3 — the post-fight read

1. **Never print a sim id.** `b00`, `a03`, `b01 to b04` appear in the decision log, the per-monster
   lines and the turning-point sentence. Resolve every id to the species name the plates already
   use. This is a small change and it is the difference between a report and a debug dump.
2. **Grade the read.** The committed plan is available (`Tactics.committed`'s `planA`/`ordersA`).
   For each axis the player set, say plainly whether it happened: *"You ordered Hunt the casters —
   Grynt reached their caster at 12.4s ✓"* / *"…never got past their tank ✗"*. This is the payoff
   the whole "commit, then observe" loop is built for and it does not exist.
3. **Give the fight a shape.** One horizontal timeline: both teams' aggregate HP, deaths marked, the
   turning point marked. It answers "when did I lose this" in one glance, which ten rows of
   dealt/took cannot.
4. **A rewind or scrub belongs to this builder, not to the camera.** First blood lands at 46% and
   the match resolves in the next ten seconds; there is currently no way to re-watch the exchange
   you just missed, and adding one to a replay that is already a frame array is cheap.

### Before any of it — the roster

⚠️ **Fix `watch.gd`'s roster first, or none of the above can be judged.** Half the presentation work
of the last four rounds cannot appear on the production path because the ten monsters that fight
there cannot produce heals, cleanses, interrupts, thorns, wards or DoT ticks. `_watch_sim.gd`
already has the composition that does. This is the same lesson `COMBAT_SPATIAL_LOG.md` recorded on
2026-08-08, and the roster — not the renderer — is the fix. `_probe_watch.gd` prints the kinds each
fight produced and the ten kits that produced them; that print is the tripwire.

---

## 10. The capture set

All under `%APPDATA%/Godot/app_userdata/Monster Tamer/`.

| file | what it shows |
|---|---|
| `watch_four_pillar_t35_cam0_00_t000.0.png` | deploy — ten plates stacked in the top third, monsters as specks |
| `..._04_t008.0.png` | the approach — enemy entirely off-frame, HUD reads "Team A 2 / Team B 0" with all ten alive |
| `..._06_t012.0.png` | **the scrum** — eight overlapping bodies, eight identical `10`s, three collided nameplates |
| `..._10_t020.0.png` | the endgame — a corpse reads well; the plates still float free |
| `watch_four_pillar_t35_cam2_06_t012.0.png` | **ARENA mode** — the whole battle as a 100×60px smudge in a 1920×1200 frame |
| `watch_four_pillar_t35_cam0_END.png` | the winner banner (clean and readable — the one unqualified success) |
| `watch_four_pillar_t35_cam0_REPORT.png` | the report, speaking in `a03`/`b00` |
