# Meshy spike — result

**2026-08-05.** Ran the pipeline validation `ART_BIBLE_LOWPOLY.md` §4 asks for, against the
studio owner's own Meshy API key. **Everything below was executed, not estimated.**

## Verdict: the pipeline works, with one hard limit that shapes the whole roster plan

| §4's question | answer |
|---|---|
| Rigged output, or must rigging be authored? | **Rigged — but only for humanoid-shaped creatures.** See the limit below. |
| Does the rig come with usable ANIMATION? | ⚠️ **NO from `/v1/rigging` — that clip is a BIND POSE** (1 keyframe per sampler). **YES from `/v1/animations`**, a separate endpoint with a preset action library: real motion, 3 credits each. Corrected below. |
| Does it honour a poly budget? | **Yes.** Asked for 1,200 tris, got **1,235**. Inside `ART_BIBLE_LOWPOLY.md`'s 700–1,500 band with no decimation step. |
| Consistent enough across runs? | **Promising** — 2 of 2 faithful to their source portraits. ⚠️ Not proven at roster scale; 2 is not 20. |
| Can one skeleton retarget across bodies? | ⚠️ **NO — see below.** |

## What it produced

**Image-to-3D from our EXISTING painterly portraits**, so designs are preserved rather than
reinvented. `kongrath.png` (185×512) → a 1,235-tri textured model in **100 seconds**.

⚠️ **The sporting identity survived the conversion intact** — white singlet, red team sash, hand
wraps, boot wraps. That is `ART_BIBLE_GUILD_COLOURS.md`'s "athlete dressed for the ring, not for
war" arriving for free, because it was already in the 2D art the model was built from. This is the
strongest argument for image-to-3D over text-to-3D: **the art direction is carried by the input.**

## ⚠️ THE HARD LIMIT: auto-rigging is HUMANOID-ONLY

- `kongrath` (biped mammal) → rigged fine. **24-joint Armature, 1 animation clip, 72 channels**,
  5 credits, 20 seconds. ⚠️ **Its "1 animation clip, 72 channels" is a BIND POSE, not motion** —
  1 keyframe per sampler, verified by parsing the GLB. An earlier draft of this document reported
  it as if it were animation. It is the rig's rest position. Bone names are the standard humanoid set — `Hips`, `Spine`, `LeftUpLeg`,
  `LeftFoot`, `LeftShoulder`, `LeftArm` — so Godot's humanoid retargeting applies.
- `larkessa` (avian) → **`422 Pose estimation failed, please provide a valid model`**. Retried
  three times, including with a `height_meters` hint. **Structural, not transient.**

**Why this matters more than it first looks:** the roster is **65 species across 13 body types**
(Mammal, Avian, Marsupial, Aquatic, Insectoid, Reptilian, Draconic, Abyssal, Mythical + 4 fusion).
Meshy's rig does humanoid pose estimation, so **only the roughly-bipedal-with-arms bodies can be
auto-rigged at all.** Birds, fish and insects cannot.

⚠️ **This is the answer §4 said would force a reconsideration** — not of the meshes, which are
good, but of the assumption that one skeleton covers the roster. It does not.

## Options, honestly costed

1. **Animate only what auto-rigs; static meshes for the rest.** Cheapest. ⚠️ But an arena where
   the mammals move and the birds are statues is worse than one where nothing moves — inconsistency
   reads as a bug, uniformity reads as a style.
2. **Hand-rig the non-humanoids.** Correct results, real labour, and no Blender is installed
   (`import bpy` fails) — this is a tooling decision as much as an art one.
3. **Procedural/tween animation instead of skeletal.** Squash, lean, hop, recoil driven from the
   frame stream's existing `state` and `facing`. ⚠️ At 20–40px — the size a creature actually
   occupies at the approved camera — this may be indistinguishable from skeletal animation, and it
   works identically for every body type. **Recommended to try before committing to (2).**
4. **Restrict future designs to humanoid silhouettes.** ⚠️ Rejected — it would gut the bestiary's
   variety, and `CLAUDE.md` is explicit that a species must never be locked out of a role.

## Cost

**65 credits** for 2 models + 1 rig, from a 3,211 balance. ≈30 per model, 5 per rig. **The full
20-creature painted roster is roughly 700 credits** — comfortably affordable.

## ⚠️ Two traps for whoever picks this up

- **Godot does not import a dropped-in `.glb` on its own.** `load()` returns null and the scene
  renders empty with only a `No loader found` error. Run
  `Godot --headless --path . --import` first. `--editor --quit-after` does NOT do it.
- **`Camera3D.look_at()` requires the node to be in the tree.** `add_child()` first, or it errors
  and silently keeps its default orientation — which looks exactly like "the models failed to load".

## ⚠️ CORRECTION: Meshy DOES produce real animation — via a different endpoint

`POST /openapi/v1/animations` takes `rig_task_id` + `action_id` (an integer into a preset action
library) and returns genuine skeletal motion. **Verified**: `action_id: 92` on the kongrath rig
produced `Double_Combo_Attack` — **86 keyframes over 2.87s across 72 channels**, in 16 seconds for
**3 credits**.

So the animation story is a THREE-step pipeline, not two:

| step | endpoint | cost | output |
|---|---|---|---|
| 1. mesh | `/v1/image-to-3d` | ~30 | 1,235-tri textured model |
| 2. rig | `/v1/rigging` | 5 | 24-joint skeleton + a **bind pose** |
| 3. animate | `/v1/animations` | 3 each | **real motion**, per action |

⚠️ **The humanoid-only limit still applies**, because step 3 needs step 2, and step 2 refuses
non-humanoid bodies. Animation does not rescue the birds, fish and insects — it only makes the
creatures that DO rig substantially better than procedural.

⚠️ **This strengthens the hybrid recommendation rather than replacing it.** Procedural remains the
floor that covers all 65 species; skeletal-plus-library is now a much stronger ceiling for the
subset that rigs, since the animations are authored motion rather than something hand-built.

**Unmapped:** the full action-library catalogue. `action_id 92` is the only one confirmed, taken
from the API docs' own example. The states this game needs — idle, advance, attack, stunned, death
— need their ids identified before this is production-usable.

## What was NOT tested

- Consistency across a full roster (2 samples only)
- Whether the generated animation clip is actually usable, or just a bind-pose idle
- Retargeting a shared animation set across two different rigged creatures
- Performance with 10 of these on screen at once

---

# ⚠️ DECIDED 2026-08-05: HYBRID. Bipeds rig; true animals stay procedural.

The humanoid-only limit turned out to be a **humanoid-SHAPED** limit, and an A-posed avian rigged
in 40 seconds for 5 credits. ⚠️ **But it rigged because the model was built as a bird-PERSON** —
humanoid torso, human legs, arms and wings — not because pose estimation learned avian anatomy.

Both rigs return the **identical 24-joint standard humanoid skeleton, 24 of 24 bone names shared**,
so one animation library retargets across every creature that is built as a biped.

**The studio owner chose HYBRID:**

| body plan | animation |
|---|---|
| Mammal, Reptilian, Draconic, Abyssal, Mythical, Marsupial — built as upright athletes | **skeletal**, one shared 9-clip library |
| Aquatic, Insectoid — genuinely non-humanoid, keep real anatomy | **procedural** (`creature_anim.gd`) |

⚠️ **THE COST OF THIS CHOICE, STATED PLAINLY, BECAUSE IT WILL BE FELT BEFORE IT IS SEEN:** two
animation systems, and a **visible seam**. Some creatures move richly — limbs, weight, follow-through
— and others only squash, lean and lunge. The studio owner accepted this knowingly. ⚠️ The failure
mode to watch for is that **inconsistency reads as a bug where uniformity reads as a style**: if the
seam becomes obvious in a live 5v5, the honest response is to move the whole roster to one system,
not to keep patching the gap.

**Mitigations worth building before that happens:**
1. **Match the procedural timings to the skeletal clips' rhythm** — if a procedural attack lunges on
   the same beat a skeletal attack swings, the two read as one language even at different fidelity.
2. **Keep the camera honest.** At 20–40px the gap is far smaller than it looks in a close-up; judge
   the seam at arena distance, never in the model viewer.
3. **Prefer procedural where it is INDISTINGUISHABLE** — a fish has no limbs to swing, so nothing is
   being given up for an aquatic body. The seam only matters where a creature visibly *could* have
   moved a limb and did not.

---

# Follow-up: procedural animation prototype

**Built and run the same day**, because auto-rigging being humanoid-only made this the deciding
question rather than a nice-to-have.

`monster-tamer/scripts/ui/creature_anim.gd` — poses a creature from the frame stream's existing
`state` and `facing`, with no skeleton anywhere. `scenes/_proto_anim.tscn` cycles both spike models
through all seven states at the real arena camera (38°, 26 fov).

## Result: it works, and it works for BOTH body types

| state | how it reads |
|---|---|
| `idle` / `cast` | breathing rise + volume-preserving squash; cast adds a lift and stills |
| `advance` / `retreat` | stride bob, forward lean vs backward lean |
| `attack` | lunge along `facing`, out fast and back slow, overlaid on the state pose |
| `stunned` | tilt, sink, and **no breathing** — stillness is the tell |
| `dead` | topple to 88° with a sink and squash |

⚠️ **THE PROOF IS THAT BOTH MODELS BEHAVE IDENTICALLY.** `kongrath` auto-rigs; `larkessa` was
REFUSED by pose estimation. They topple, lunge and tilt the same way, because none of it touches a
skeleton. **That removes the humanoid-only limit as a blocker on the roster.**

## ⚠️ What this honestly is NOT

**Whole-body transform is not skeletal animation.** A gorilla that *swings its arm* looks better
than a gorilla that *slides forward*. Limbs do not move here, and nothing in this prototype
pretends otherwise.

The bet is that at **20–40px** — the size a creature actually occupies under the approved camera —
the difference does not resolve, while the difference between *animated* and *statue* very much
does. ⚠️ **That bet is not yet proven.** These screenshots are stills at a closer framing than the
real arena, and motion quality cannot be judged from a still. **Judge it in a live fight before
committing.**

## Recommendation

**Use procedural as the baseline for all 65 species**, and treat Meshy's auto-rig as an *upgrade*
applied only where it succeeds — the two systems compose, since `creature_anim.gd` drives the
holder and a skeletal clip drives the mesh inside it.

That ordering matters: procedural-first gives a roster that is uniformly animated on day one,
and skeletal-where-available makes some creatures better without making any of them worse. The
reverse order gives an arena where mammals move and birds are statues.
