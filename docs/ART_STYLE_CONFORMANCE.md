# The art style, and how to conform to it

> ⚠️ **SUPERSEDED FOR THE BATTLEFIELD, 2026-08-04 — see `ART_BIBLE_LOWPOLY.md`.** The user chose
> **low-poly 3D for the battlefield**, keeping painterly 2D for portraits, backdrops and UI. The
> argument that won it is in this file's own §5: the arena camera pulls out to 20–40px silhouettes,
> so painterly detail is paid for at the *High* cost band and then not seen.
>
> **This document remains authoritative for everything still 2D** — portraits, area art, arena
> backdrops, the title — and its palette discipline (§3) and identity test (§4) carry over to the
> models unchanged.

**2026-08-04.** Written after the user asked for *"a game art style for all of our sprites and
games, we need a style that we can conform to"*, citing MLC Studio's *Indie Developer's Guide to
Game Art Styles*.

---

## ⚠️ THE STYLE IS ALREADY CHOSEN. THE PROBLEM IS CONFORMANCE, NOT SELECTION.

The article surveys eight styles and asks *which one*. **That is not our open question.**
`ART_DIRECTION.md` answered it months ago, in one line:

> **A craftsman's yard after the day's work, lit by one warm working lamp.**

and `ART_THEME.md` ("Guild Colours") set the identity above it: **a sport built by hand, judged by
trade guilds, fought by athletes who dress for the ring, not for war.**

⚠️ **Re-picking a style now would throw away 30 battle sprites, 12 creature portraits, 5 arena
venues and a title screen that are already on disk and already consistent with each other.** Do
not reopen the choice. What is genuinely missing is a way to *check* that the next asset matches
the last one — and with generated art that is a much harder problem than picking a style.

### Where we land in the article's taxonomy

| axis | ours | article's cost band |
|---|---|---|
| Creatures | **Stylised 2D**, painterly illustration, transparent PNG, side/three-quarter | Hand-drawn: *High* |
| Arenas | **Stylised painterly** backdrops + tiling ground | — |
| Board | **Stylised 3D**, smooth-shaded, 2D sprites standing in a 3D space | Stylised 3D: *Medium* |
| Lighting | one warm key, cool sky bounce, deep shadow — an **HD-2D lens treatment** | — |

⚠️ **`ART_DIRECTION.md` explicitly forbids one of the article's styles: low-poly.** *"`flatShading`
is a low-poly STYLE and fights 'high definition'. Smooth by default."* The article treats low-poly
as a cheap win; for us it is a contradiction of the look.

⚠️ **And note the cost line the article would flag.** Hand-drawn/stylised illustration is its
*High* band, normally out of reach for a small team. **We can afford it only because the art is
generated, not drawn** (`ART_PIPELINE.md`). That is the trade we have actually made, and it moves
the difficulty from *cost per asset* to *consistency across assets*.

---

## The conformance spec — what every new asset must satisfy

Because assets are generated, **every image is a fresh roll of the dice.** A style guide written
for a human artist ("keep the line weight consistent") does not bind a generator. So this section
is written as **checkable rules**, in the order they are cheapest to check.

### 1. Format — mechanical, no judgement required

| asset | size | format | background |
|---|---|---|---|
| creature portrait | 320×320 | RGBA PNG | **transparent** |
| battle sprite | 128×128, 6 frames | RGBA PNG | **transparent** |
| arena backdrop | 1400×788 | JPEG | opaque |
| arena ground | square, seamless tile | JPEG | opaque |

⚠️ **The generator returns RGB, not RGBA** (`ART_PIPELINE.md` §Route B). Background removal is a
**post-process step, not a prompt instruction** — asking for "transparent background" produces a
white or checkerboard rectangle baked into the pixels. This has already caught people out.

### 2. Framing and pose — the rules that make a roster look like a roster

- **Full body, no crop.** Feet and tail inside the frame, small margin all round.
- **Side or three-quarter view**, facing left by convention; the renderer mirrors for the other team.
- **Neutral standing pose.** ⚠️ Not mid-action — an action pose reads as a specific move and fights
  every other animation the unit will ever play.
- **Even, flat-ish lighting on the creature itself.** ⚠️ The ARENA supplies the warm key; a sprite
  that arrives pre-lit from the left will contradict the arena lamp on half the boards.

### 3. Palette — the discipline that is load-bearing, not decorative

⚠️ **THREE COLOUR SYSTEMS SHARE THE SCREEN AND MUST NEVER COLLIDE** (`ART_THEME.md`):

| system | what it means | rule |
|---|---|---|
| **League material** | wood / bronze / silver / platinum — the venue | lives in the arena, never on a creature |
| **Team colour** | which guild this athlete plays for | **sash and frame only, never the body** |
| **Status / threat** | poison, burn, bleed, buff | **the brightest thing on screen** |

⚠️ **Saturated means something is HAPPENING; muted means this is WHO YOU ARE.** `art.gd`'s
`TEAM_COLOURS` are deliberately desaturated livery tones because the first cut of that palette was
pixel-for-pixel the hue set proposed for status effects — a collision nobody had cross-checked.
A creature painted in saturated red will read as *on fire* to a player mid-fight.

**So: creature bodies stay in natural, desaturated material colours.** Team identity is added by
the removable sash, not by the species.

### 4. The identity test — the one that actually matters

> **Does it look like an athlete dressed for a sporting fixture, or a monster dressed for war?**

`ART_THEME.md` is unambiguous: this is a **sport**. Straps, wraps, guards, a team sash. **No
weapons of war, no armour plate, no gore, no skulls.** A creature that looks like it is going to
kill something has failed, however well drawn.

### 5. Silhouette — the one that survives the camera

Per `ARENA_CAMERA_REFERENCE.md` the arena camera is pulling **out**, so a creature will often be a
20–40px silhouette. **Judge every new sprite at 40px tall before accepting it.** If two species are
indistinguishable at that size, the art has failed the game even if it is beautiful at 320px.

⚠️ This is why the **badge** (`art.gd:team_badge`) exists alongside the colour, and why colour
alone is never sufficient identification — `index % 8` makes team-colour collisions exact, not
merely likely, and a colourblind player loses the channel entirely.

---

## The acceptance checklist

Run this on every generated asset before it enters `assets/`. Anything that fails goes back to a
re-roll; **do not hand-fix an asset into compliance**, because the next one will fail the same way
and the prompt is what needs correcting.

- [ ] Correct dimensions and format; **alpha actually transparent** (check the pixels, not the prompt)
- [ ] Full body, neutral stance, side/three-quarter, facing left
- [ ] No baked directional lighting fighting the arena lamp
- [ ] Body colours natural and desaturated — **no saturated hue that could read as a status**
- [ ] Team identity carried by the sash only, and the sash is removable
- [ ] Sporting kit, not war gear — no weapons, plate, gore or skulls
- [ ] **Readable as a distinct silhouette at 40px**
- [ ] Sits beside the existing roster without looking like a different game

⚠️ **The last box is the real test and it cannot be automated.** Put the new sprite in a row with
five existing ones and look. Consistency across generated assets is the whole difficulty of this
pipeline, and it is judged by eye or not at all.
