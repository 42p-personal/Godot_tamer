# World of Warcraft Arena — every map, and how it lays out its cover

**2026-08-05.** Researched on the studio owner's direction: *"look at world of warcraft arena, this
is what our game play is going to be based around... a list of all of the world of warcraft arena
maps past and present and how they lay their obstacles out, this will form the basis of how we do
our own."*

⚠️ **READ §4 BEFORE COPYING ANY OF THIS.** WoW Arena is a real-time, player-controlled game and
ours is a zero-intervention autobattler. Most of what a WoW pillar is *for* is a reflex skill our
player is never allowed to perform. The **shapes** transfer; the **purpose** has to be re-derived.

---

## 1. The full roster — 16 active, 1 removed

| # | Arena | Added | Zone | Cover layout |
|---|---|---|---|---|
| 1 | **Circle of Blood** / Blade's Edge | TBC (2.0) | Blade's Edge Mountains | Rectangular. A **bridge spans the middle**; a **pit with two pillars beneath it**; two side platforms reached by ropes from the bridge. The only map where cover and elevation are the same feature. |
| 2 | **Ring of Trials** / Nagrand | TBC (2.0) | Nagrand | Large circular room. **Four pillars, equidistant, forming a square** around an open centre. The canonical symmetric layout. |
| 3 | **Ruins of Lordaeron** | TBC (2.0) | Tirisfal Glades | Rectangular courtyard, **two large blocks/tombs flanking the centre**, teams start behind gates at opposite ends. |
| 4 | **Dalaran Arena** (Sewers) | WotLK (3.1) | Dalaran Underbelly | Square floor with a **raised central square**, stairs up its edges, **crates on the raised edges as persistent LOS blocks**, plus a **water pipe in the centre that intermittently blocks LOS**. The first map with a *timed* blocker. |
| 5 | **Ring of Valor** ⚠️ **REMOVED** | WotLK (3.2) | Orgrimmar | Oval. **Four circular platforms that rise and lower two at a time**, blocking movement and LOS when raised. Originally also had **moving pillars, spike traps and intermittent fire walls**. Removed in 5.1 — the wiki cites bugs; the arena became the Brawler's Guild. |
| 6 | **Tol'viron Arena** | MoP (5.1) | Uldum | Explicitly *"based on the simplistic Nagrand Arena — the only difference is art style and the direction of the pillars."* Sources disagree between three and four pillars; the disagreement itself is the point (see §3). |
| 7 | **The Tiger's Peak** | MoP (5.3) | Kun-Lai Summit | **Two statues acting as pillars**, plus **two raised platforms flanking the centre**, each reached by stairs on its outer side. Verticality as the main LOS tool. |
| 8 | **Ashamane's Fall** | Legion | Val'sharah | Circular. **Two square pillars and one rectangular pillar in a triangular formation** — deliberately *not* symmetric in count. |
| 9 | **Black Rook Hold Arena** | Legion | Val'sharah | **A single central statue as the only pillar**, on a slightly raised circular platform. The minimal case: one blocker, dead centre. |
| 10 | **Hook Point** | BfA | Boralus | **Two close-together pillars and one long wall with multiple gaps.** The only map whose main feature is a *wall with holes* rather than free-standing pillars. |
| 11 | **The Mugambala** | BfA | Zuldazar | **Three separate wide-open areas with minimal pillars.** Notoriously disliked — a standing "Remove Mugambala" thread on the official forums. |
| 12 | **The Robodrome** | BfA (8.2) | Mechagon | Mechanical arena, symmetric blockers. |
| 13 | **Empyrean Domain** | Shadowlands | Bastion | Symmetric, open. |
| 14 | **Maldraxxus Coliseum** | Shadowlands | Maldraxxus | Classic coliseum, symmetric. |
| 15 | **Enigma Crucible** | Shadowlands (9.2) | Zereth Mortis | ⚠️ **The design note is the valuable part.** The original concept had **a switch at the centre that reconfigured the central pillars** — creating cover for your team or denying it to the enemy. **Cut during testing "due to pathing and line-of-sight issues."** |
| 16 | **Nokhudon Proving Grounds** | Dragonflight | Ohn'ahran Plains | Added as the DF S1 map; Blizzard's own framing describes maps by *size* and *LOS placement* (see §2). |
| 17 | **Cage of Carnage** | The War Within | Undermine | Newest addition. |

---

## 2. Blizzard's own stated taxonomy

When they introduced **map pools** in Dragonflight, Blizzard described how they divide the roster.
This is the most useful sentence in the whole research pass, because it is the designers' own
vocabulary rather than a player's:

> maps are sorted by **map size (large and small)** and **line-of-sight placement — symmetrical
> pillars, Z-axis, or other variants**

And the goal:

> an ideal Arena is one where **the better team wins consistently**; on a balanced map the
> designers **eliminate randomness as much as possible**

⚠️ **That second quote is the one that should change our generator.** Our arenas are *procedurally
placed* — pieces are sampled into an annulus with a seeded rng. WoW's are **hand-authored
compositions where every pillar was placed by a person**. Blizzard's stated aim is to remove
randomness from the map; ours currently introduces it.

---

## 3. The patterns, ranked by how often they recur

**A. Two-to-four blockers. Never twenty.** Every arena above uses between **one** (Black Rook
Hold) and **four** (Nagrand, Ring of Valor) primary LOS blockers. Not one uses a scatter of small
props. ⚠️ Our generator currently produces **24 pieces, 6 of them LOS-blocking** — an order of
magnitude more objects, each individually less important.

**B. Symmetry is near-universal, and it is rotational or mirrored.** Nagrand's four-pillar square,
Lordaeron's paired tombs, Tiger's Peak's paired platforms. This matches what `ARENA_DESIGN.md`
already enforces (180° mirrored pairs) — that decision is independently confirmed.

**C. The centre is contested, and the cover is usually near it.** Nagrand's pillars ring an open
middle; Dalaran's raised square *is* the middle; Black Rook Hold's statue is dead centre. Cover
sits where the fight will be, not scattered to the edges.

**D. Three distinct blocker archetypes, and they are not interchangeable:**
- **Free-standing pillar** — blocks from one angle, walkable around. Nagrand, Tol'viron, Ashamane's.
- **Wall with gaps** — blocks a *line*, forces a choice of gap. Hook Point.
- **Elevation** — blocks by height rather than footprint. Blade's Edge bridge/pit, Tiger's Peak
  platforms, Dalaran's raised square.

**E. Two maps put cover on a TIMER, and one of them was deleted.** Dalaran's water pipe still
works. Ring of Valor's rising platforms, moving pillars, spike traps and fire walls were removed
outright. ⚠️ **The most dynamic arena WoW ever shipped is the one that no longer exists.**

**F. The disliked maps are the open ones.** Mugambala ("three separate wide open areas with
minimal pillars") has a standing removal thread. Tol'viron is described as *"wide open with just
three small pillars, offering minimal LoS and maximum exposure."* Too little cover is a real
failure mode, not a safe default.

---

## 4. ⚠️ What does NOT transfer, and it is most of the point

**WoW Arena is a game of reflexes and ours forbids them.** The pillar's primary use in WoW is
*pillar-dancing* — a player physically running around a pillar to break an enemy cast, juke a
polymorph, or drop line of sight mid-global. `CLAUDE.md`'s first fixed point is that **the player
never intervenes in a fight**. So:

| in WoW a pillar is… | for us it must be… |
|---|---|
| a tool the PLAYER uses in the moment | a tactic the player **pre-commits** to, and then watches |
| rewarded by reaction speed | rewarded by having read the matchup correctly |
| a skill ceiling | a **legible** consequence of an order |

⚠️ **This is the same finding the combat team already recorded** (`docs/STUDIO_REPORT_2026-08-04.md`
§2): *"WoW Arena is real-time player-controlled; ours has no mid-fight input. So 'more like WoW
Arena' cannot mean its controls."* The map research confirms it from the other direction — the
maps are built to be *danced around*, and nobody in our game can dance.

**What that leaves, and it is still a lot:** the *shapes* are proven. Two-to-four large symmetric
blockers near a contested centre, in three archetypes, is a layout language with twenty years of
competitive validation behind it. We should take the vocabulary and re-purpose it for orders
rather than reflexes — a monster ordered to `hold` behind the left pillar is a pre-committed
version of the same decision.

---

## 5. What this says about our generator, concretely

Against `arena_layout.gd` as it stands today:

| WoW does | we do | verdict |
|---|---|---|
| 1–4 primary blockers | 6 blocking of 24 total pieces | ⚠️ **too many, each too small** |
| hand-authored placement | seeded random within an annulus | ⚠️ **the opposite of "eliminate randomness"** |
| symmetric (mirrored/rotational) | 180° mirrored pairs | ✅ **already right** |
| cover near the contested centre | annulus between tight/loose radii | ✅ **close to right** |
| pillar / wall-with-gaps / elevation | pillar and wall; **no elevation** | ⚠️ elevation is banned by `ARENA_DESIGN.md` ("NO ELEVATION — readability wins"). That ban is defensible and it costs us one of the three archetypes |
| a handful of authored maps, pooled | ~20 procedurally-varied grounds | open question |

**The single highest-value change suggested by this research:** stop scattering many small pieces
and author a small number of **named layouts** — a Nagrand-like four-pillar square, a Hook
Point-like wall-with-gaps, a Lordaeron-like paired-tombs — then vary them by material and palette
the way `CLAUDE.md` already plans for Platinum-and-above. That converts our arenas from *random*
to *composed*, which is what Blizzard says an arena is for.

⚠️ **And it directly answers the measurement that prompted this.** `docs/` records that
LOS-blocking cover is 0.909% of our ground and that cover-seeking measured as noise. Nagrand-style
authoring — four large pillars around the contested middle — puts blockers **where the fight
actually is** instead of sampling them into a ring, which is the cheapest way to make cover matter
without turning a sports ground into a maze.

---

## Sources

- [Arena — Warcraft Wiki](https://warcraft.wiki.gg/wiki/Arena) — the canonical roster
- [Dalaran Arena](https://wowpedia.fandom.com/wiki/Dalaran_Arena) · [Ring of Valor](https://warcraft.wiki.gg/wiki/Ring_of_Valor) · [Tol'viron](https://warcraft.wiki.gg/wiki/Tol%27viron_Arena) · [Enigma Crucible](https://warcraft.wiki.gg/wiki/Enigma_Crucible) · [Black Rook Hold](https://warcraft.wiki.gg/wiki/Black_Rook_Hold_Arena) · [Hook Point](https://warcraft.wiki.gg/wiki/Hook_Point_(arena)) · [Mugambala](https://warcraft.wiki.gg/wiki/Mugambala)
- [Nagrand Arena — Liquipedia](https://liquipedia.net/worldofwarcraft/Nagrand_Arena) · [Tiger's Peak — Liquipedia](https://liquipedia.net/worldofwarcraft/The_Tiger%27s_Peak)
- [Arena Map Pools and Rotation — Blizzard, via Blue Tracker](https://www.bluetracker.gg/wow/topic/us-en/1443472-arena-map-pools-and-rotation/) — the size / LOS-placement taxonomy
- [Blizzard Introduces Map Pools — Warcraft Tavern](https://www.warcrafttavern.com/wow/news/blizzard-introduces-map-pools-to-arena-queue-in-dragonflight/)
- [Remove Mugambala — official forums](https://us.forums.blizzard.com/en/wow/t/remove-mugambala/1675629)

⚠️ **Coverage is honest, not complete.** Layouts for **The Robodrome, Empyrean Domain, Maldraxxus
Coliseum, Nokhudon Proving Grounds and Cage of Carnage** are thin above — the wikis carry lore and
images but little written geometry, and I am not going to invent descriptions to fill a table. If
those five matter, the reliable source is in-game or map screenshots, not text.
