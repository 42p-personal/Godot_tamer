## THE ASSET REGISTRY — one place that knows where every image lives.
##
## ⚠️ THIS IS A CONTRACT BETWEEN PARALLEL WORKSTREAMS. The art streams write files to these
## exact paths; the UI streams read them through these exact functions. Neither side hardcodes
## a path. If an asset is missing, `load_or_null` returns null and callers draw their documented
## fallback — the game must RUN with zero art present and degrade visibly, never crash, because
## art generation is slow and the systems work cannot block on it.
##
## Naming convention (both streams must honour it exactly):
##   creature  ->  res://assets/creatures/<species_id>.png   — side-on full body, transparent
##   backdrop  ->  res://assets/arenas/<league_slug>-backdrop.jpg — painterly venue, 1400x788
##   ground    ->  res://assets/arenas/<league_slug>-ground.jpg   — seamless tile, square
##   title     ->  res://assets/ui/title.jpg
##
## `league_slug` is the league name lowercased with spaces -> hyphens: "Tamers Apex" ->
## "tamers-apex". `league_slug_for()` is the single source of that transform.
extends Node

const CREATURE_DIR := "res://assets/creatures/"
const ARENA_DIR := "res://assets/arenas/"
const UI_DIR := "res://assets/ui/"
const AREA_DIR := "res://assets/areas/"

## Which leagues have authored arena art. A league not listed here falls back to the nearest
## listed one BELOW it (see `backdrop_for`), so the ladder is always playable while art lands.
##
## ⚠️ ALL ELEVEN ARE NOW PAINTED (widened 2026-08-08). This list said five for as long as five
## were painted, and it was correct then. The venue-textures pass generated ground + backdrop art
## for the missing six (Copper, Tin, Iron, Gold, Masters, Tamer Elite) and `_probe_venue_art.gd`
## confirms all 39 files load at real size — but NOBODY WIDENED THE GATE, so every one of those
## six kept borrowing a humbler league's venue and the new art was unreachable from the game.
##
## ⚠️ THIS IS THE PROJECT'S SIGNATURE FAILURE, CAUGHT ONCE MORE: content authored, priced and
## verified, then never reached because a list upstream of it still described the old world. The
## art probe passing is NOT evidence the art is in the game — it proves the files load, and a
## file that loads into a code path nobody calls is still not content. If a future pass adds a
## twelfth league's art, this constant is the second half of that job.
const ARENA_LEAGUES := [
	"Wood", "Copper", "Tin", "Bronze", "Iron", "Silver",
	"Gold", "Platinum", "Masters", "Tamer Elite", "Tamers Apex",
]

## The playable roster for this build — 12 species chosen for BODY and ROLE spread, not for
## power. ⚠️ Deliberately not all 65: twelve fully-realised creatures beat sixty-five
## placeholders, and the class system is emergent so these twelve still reach most classes
## through training.
const ROSTER := [
	"aegisox", "arachnyx", "balaenix", "bruxaroo",
	"corvaan", "crocmaw", "grivvel", "iguanor",
	"kongrath", "larkessa", "mantevoke", "nautilux",
	"pinguox", "pyraxon", "scarabrute", "strixil",
	"tazzik", "tenebrae", "titanrex", "ursath",
]

var _cache: Dictionary = {}


## Load a texture, returning null (not an error) when the file isn't there yet.
func load_or_null(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		_cache[path] = null
		return null
	var tex := load(path) as Texture2D
	_cache[path] = tex
	return tex


func league_slug_for(league_name: String) -> String:
	return league_name.to_lower().replace(" ", "-")


func creature_texture(species_id: String) -> Texture2D:
	return load_or_null(CREATURE_DIR + species_id + ".png")


## The arena art for a league, falling back DOWN the ladder to the nearest painted league.
## ⚠️ Falls back downward on purpose: an unpainted high league borrowing a humbler venue reads
## as "this venue hasn't been built yet", where borrowing a grander one would misrepresent the
## player's actual progress.
func _nearest_painted_league(league_name: String, all_leagues: Array) -> String:
	var idx := -1
	for i in range(all_leagues.size()):
		if all_leagues[i] == league_name:
			idx = i
			break
	if idx < 0:
		return ARENA_LEAGUES[0]
	for i in range(idx, -1, -1):
		if ARENA_LEAGUES.has(all_leagues[i]):
			return all_leagues[i]
	return ARENA_LEAGUES[0]


func backdrop_for(league_name: String, all_leagues: Array) -> Texture2D:
	var slug := league_slug_for(_nearest_painted_league(league_name, all_leagues))
	return load_or_null(ARENA_DIR + slug + "-backdrop.jpg")


func ground_for(league_name: String, all_leagues: Array) -> Texture2D:
	var slug := league_slug_for(_nearest_painted_league(league_name, all_leagues))
	return load_or_null(ARENA_DIR + slug + "-ground.jpg")


func title_texture() -> Texture2D:
	return load_or_null(UI_DIR + "title.jpg")


## Town/area backdrop art — `key` is the plain area name ("town", "market", "shop", "lab",
## "breeding", "halloffame", "stables"), matching the `area-<key>.jpg` files copied from the
## React build's `public/backgrounds/` (town_ui.gd / market_ui.gd). Same null-degrades-visibly
## contract as every other getter here — a screen missing its backdrop falls back to a plain
## panel, it never errors.
func area_texture(key: String) -> Texture2D:
	return load_or_null(AREA_DIR + "area-" + key + ".jpg")


## Deterministic team colour per side/team index — the Guild Colours identity channel.
## ⚠️ Team colour lives on FRAMES, SASHES and UI ACCENTS only, never on the creature's own body
## and never on an HP fill (docs/ART_THEME.md §"palette discipline": three colour systems that
## must never collide — league material, team colour, status/threat).
##
## ⚠️ THESE ARE DELIBERATELY LIVERY TONES, NOT ALARM TONES, AND THAT IS THE FIX FOR A REAL
## COLLISION. The first cut of this palette was saturated blue/red/gold/green/violet — which is
## pixel-for-pixel the hue set `ART_THEME.md` proposes for STATUS effects (buff/bleed/burn/
## poison/debuff). Nobody had cross-checked the two documents against each other, so a team's
## colour and a status's colour would have meant the same hue in the same frame. These are
## desaturated and darkened into cloth/enamel territory so that **saturated == something is
## happening to this creature; muted == this is who the creature plays for.** Status colours must
## stay the brighter of the two when they are authored.
const TEAM_COLOURS := [
	Color(0.20, 0.38, 0.62),  # slate blue     — guild livery, not "buff blue"
	Color(0.63, 0.26, 0.28),  # oxblood        — not "bleed red"
	Color(0.72, 0.58, 0.28),  # brass          — not "burn amber"
	Color(0.26, 0.46, 0.36),  # bottle green   — not "poison green"
	Color(0.45, 0.33, 0.55),  # plum           — not "debuff violet"
	Color(0.78, 0.78, 0.80),  # chalk white
	Color(0.35, 0.33, 0.31),  # iron grey
	Color(0.55, 0.40, 0.26),  # tan leather
]

## ⚠️ A SECOND, NON-COLOUR TELL IS A HARD REQUIREMENT, NOT A NICETY.
## `ART_THEME.md` already asked for one, on the grounds that two teams will eventually collide on
## a similar colour. Worse, `index % TEAM_COLOURS.size()` makes that collision EXACT rather than
## merely likely — every Nth team is the same swatch. A badge glyph paired with the colour keeps
## nameplates separable on collision AND for a colourblind player, who otherwise loses the team
## channel entirely. UI must draw BOTH; colour alone is never sufficient identification.
const TEAM_BADGES := ["◆", "▲", "●", "■", "★", "✦", "⬟", "✚"]

func team_colour(index: int) -> Color:
	return TEAM_COLOURS[index % TEAM_COLOURS.size()]

func team_badge(index: int) -> String:
	return TEAM_BADGES[index % TEAM_BADGES.size()]

## Colour + badge together, for any UI drawing a team identity. Prefer this over `team_colour`
## alone so the non-colour tell cannot be forgotten at a call site.
func team_identity(index: int) -> Dictionary:
	return {"colour": team_colour(index), "badge": team_badge(index)}


## ⚠️ SPECIES -> CC0 PACK MODEL. Our 65 species were authored long before any 3D existed, and the
## free set is 45 creatures that do not line up one-to-one with them. This maps the 20 species the
## arena actually fields today; anything unmapped falls through to the painted sprite, which is
## the whole reason `creature_rig.build()` returning false is a signal rather than an error.
##
## ⚠️ MATCHED ON BODY SHAPE AND ROLE, NOT ON NAME. A species' silhouette is what the player reads
## at 20-40px (`ART_BIBLE_LOWPOLY.md`), so a heavy bruiser needs a heavy silhouette and a flier
## needs wings — the creature's NAME is the least important part of the match. Where the pack has
## an evolved variant, the bigger species takes it.
## ⚠️ NO *_evolved VARIANTS (user rule 2026-08-06) — evolved models read as duplicate species
## in the gallery. Every slot uses a distinct base body or one of the new sweep additions
## (wolf/husky/fox/spider/fish).
const PACK_MODEL := {
	"aegisox":    "giant",  # the ox TANK reads as bulk, not livestock; tan tint splits from aeonrex
	"arachnyx":   "crab_enemy",         # many-legged, low, wide
	"balaenix":   "glub",  # the whale-bird, pale whale-blue
	"bruxaroo":   "monkroose",          # marsupial bounder
	"corvaan":    "birb",               # corvid
	"crocmaw":    "dino",               # long-jawed reptile
	"grivvel":    "goblin",             # small, wiry, mean
	"iguanor":    "alpaking",           # mid-size quadruped-ish reptile
	"kongrath":   "orc",                # the bruiser this whole spike was about
	"larkessa":   "armabee",            # small flier
	"mantevoke":  "green_spiky_blob",   # insectoid, spined
	"nautilux":   "squidle",            # cephalopod
	"pinguox":    "mushnub",            # squat, waddling
	"pyraxon":    "dragon",             # draconic
	"scarabrute": "crab_enemy",  # armoured many-legs; bronze = the scarab
	"strixil":    "hywirl",    # larger flier
	"tazzik":     "demon",              # devil
	"tenebrae":   "ghost",              # shadow
	"titanrex":   "enemy_large",   # mythical apex -> big fantasy beast (was dino - showcase dup with crocmaw)
	"ursath":     "yeti",               # heavy ursine
	# ── the remaining 45 (2026-08-06): every species now has a BODY. Reuse is deliberate —
	# 46 models over 65 species; shared bodies get per-instance tints later. Matched on
	# silhouette per the rule above, never on name.
	"maneleo": "yeti",  # the maned beast - shaggy biped, tawny-gold tint = the mane
	"koalio": "monkroose",  # round climber, grey-blue splits from bruxaroo
	"quokkade": "enemy_small",  # small cheerful hopper, warm tan
	"sylvaglide": "hywirl",  # the glider on the floater body, leaf-green
	"maelurk": "slime_enemy",
	"carcharun": "enemy_large",  # the shark BRUISER, slate splits from titanrex
	"mantaris": "glub",     # soft swimmer (was squidle x4)
	"lanterix": "pink_slime",
	"tidecaller": "glub",  # tidal amphibian on the aquatic blob
	"maelstrom": "squidle",
	"brinehowl": "blue_demon",  # deep-sea howler biped, brine-teal tint
	"cephalumbra": "squidle",
	"chrono-leviathan": "squidle",  # the leviathan joins the abyssal cephalopods, aged teal
	"vespera": "armabee",
	"odonatra": "armabee",
	"chitinhop": "armabee",  # insect hopper, jade splits the bee family further
	"broodmother": "crab_enemy",  # the brood queen, plum tint splits from arachnyx
	"mantiskin": "green_spiky_blob",
	"resinback": "goleling",  # armoured carapace -> golem, the original casting intent (was crab_enemy x3)
	"swarmherd": "green_blob",
	"serpwyn": "dino",
	"geckari": "enemy_small",  # small clinger, gecko-orange
	"tortavos": "mushroom_king",
	"vipramane": "enemy_small",   # small venomous striker (was dino x5)
	"basilroar": "dino",
	"grendscale": "orc_enemy",
	"thornhide": "green_spiky_blob",  # the spikes ARE the thorns; moss-brown tint
	"thunderoc": "enemy_flying",  # the great storm-bird, storm-gold tint
	"galewing": "birb",  # fantasy bird body, gale-cyan splits from corvaan
	"frostwyren": "dragon",
	"stormlerath": "dragon",
	"verdantdrake": "dragon",  # a drake wears the dragon; verdant tint splits it from ember/ice/storm
	"runewyrm": "enemy_flying",   # winged wyrm (was dragon x5)
	"voidmaw": "blue_demon",
	"abyssomancer": "ghost_skull",  # abyssal mage -> the skull ghost (was wizard x3)
	"lurkerss": "zombie",  # shambling abyssal lurker (was slime_enemy x2)
	"stellarion": "alien",
	"wisdomkeeper": "tribal",
	"archmage-aleph": "wizard",
	"harmonybringer": "hywirl",  # back to the radiant floater, gold tint
	"aeonrex": "giant",
	"stellavore": "alien",
	"chronoshell": "mushroom_king",
	"originmage": "skeleton",  # the FIRST mage, ancient -> lich read (was wizard x2)
	"worldsong": "ghost",  # the song given shape - ethereal, ivory tint splits from tenebrae
}


func pack_model_for(species_id: String) -> String:
	return str(PACK_MODEL.get(species_id, ""))


## ⚠️ SPECIES TINT IDENTITY (user direction 2026-08-06: "still too many duplicates").
## Every species that SHARES a model gets an authored tint so shared bodies stop reading as
## clones — pyraxon is ember-red, frostwyren ice-blue, stormlerath storm-violet on the one
## dragon body. AUTHORED per species, never random: a species must look the same in the
## gallery, the market and the arena. Multiplies the model's albedo, so keep components in
## ~0.55–1.15 — the palette texture carries the detail, the tint carries the identity.
## Species with a unique body are deliberately absent (WHITE = the model's own colours).
const SPECIES_TINT := {
	# fish: the three sea giants
	"balaenix":         Color(0.75, 0.85, 1.05),  # pale whale-blue
	"carcharun":        Color(0.70, 0.72, 0.78),  # shark slate-grey
	"chrono-leviathan": Color(0.55, 0.85, 0.80),  # abyssal teal
	# dino: croc / serpent / basilisk
	"crocmaw":          Color(0.45, 0.95, 0.50),  # swamp green - pushed hard, the dino base is pink
	"serpwyn":          Color(1.15, 1.05, 0.45),  # sand-yellow serpent
	"basilroar":        Color(1.15, 0.50, 0.40),  # rust-red basilisk
	# armabee: lark / wasp / dragonfly
	"larkessa":         Color(1.10, 0.75, 0.85),  # rose lark
	"vespera":          Color(1.10, 1.00, 0.60),  # wasp yellow
	"odonatra":         Color(0.60, 0.95, 1.05),  # dragonfly cyan
	# green_spiky_blob
	"mantevoke":        Color(0.80, 1.00, 0.70),  # mantis green
	"mantiskin":        Color(1.25, 0.55, 0.20),  # burnt-orange husk - the white SPIKES carry the tint, the green body barely can
	# squidle: nautilus / whirlpool / shadow
	"nautilux":         Color(1.05, 0.85, 0.65),  # nautilus shell-orange
	"maelstrom":        Color(0.55, 0.70, 1.05),  # deep whirlpool blue
	"cephalumbra":      Color(0.65, 0.55, 0.85),  # shadow violet
	# dragon: ember / ice / storm
	"pyraxon":          Color(1.10, 0.60, 0.50),  # ember red
	"frostwyren":       Color(0.65, 0.85, 1.10),  # ice blue
	"stormlerath":      Color(0.75, 0.65, 1.05),  # storm violet
	# frog
	"tidecaller":       Color(0.60, 0.90, 1.00),  # tidal blue
	"geckari":          Color(1.35, 0.55, 0.25),  # pushed hard - Emberimp must read EMBER on the dark-green base
	# mushroom_king
	"tortavos":         Color(0.85, 1.00, 0.75),  # mossy shell
	"chronoshell":      Color(1.00, 0.85, 0.60),  # aged bronze
	# alien
	"stellarion":       Color(0.80, 0.90, 1.10),  # starlight blue
	"stellavore":       Color(1.00, 0.65, 0.95),  # devourer magenta
	# recast six (user: real-animal bodies read as animals, not monsters)
	"verdantdrake": Color(0.50, 1.05, 0.50),  # verdant green drake
	"maneleo": Color(1.15, 0.92, 0.55),  # tawny lion-gold on the white yeti
	"harmonybringer": Color(1.15, 1.05, 0.70),  # radiant gold
	"aegisox": Color(1.00, 0.85, 0.62),  # tan ox-hide, splits from aeonrex
	"brinehowl": Color(0.60, 1.00, 0.95),  # brine teal on the blue demon
	"broodmother": Color(0.70, 0.55, 1.00),  # plum brood-queen, splits from arachnyx red
	# the no-animals purge (user 2026-08-06)
	"worldsong": Color(1.15, 1.10, 0.85),  # radiant ivory on the ghost
	"thornhide": Color(0.75, 0.65, 0.40),  # moss-brown bristle
	"sylvaglide": Color(0.70, 1.05, 0.60),  # leaf-green glider
	"thunderoc": Color(1.15, 1.05, 0.50),  # storm-gold
	"runewyrm": Color(0.70, 0.60, 0.95),  # rune-violet, splits from thunderoc on enemy_flying
	"galewing": Color(0.60, 0.95, 1.10),  # gale cyan on the birb
	"quokkade": Color(1.30, 0.95, 0.50),  # pushed - warm tan, not swamp green
	"koalio": Color(0.75, 0.80, 0.95),  # koala grey-blue
	"chitinhop": Color(0.60, 1.00, 0.60),  # jade chitin
	"scarabrute": Color(0.90, 0.75, 0.40),  # scarab bronze
	"mantaris": Color(0.85, 0.70, 1.00),  # soft violet, splits the glub trio
	"vipramane": Color(0.60, 1.00, 0.50),  # venom green on enemy_small
}


func species_tint(species_id: String) -> Color:
	return SPECIES_TINT.get(species_id, Color.WHITE)


## ⚠️ A multiply tint CANNOT BRIGHTEN A DARK BODY — worldsong's "radiant ivory" on the
## near-black ghost produced a pixel-identical twin of tenebrae. Species whose identity is
## LIGHT ON DARK glow instead: a soft authored emission in the tint's hue. Kept as its own
## short table because glow is a strong read ("something magical") and must stay rare.
const SPECIES_GLOW := {
	"worldsong": 0.55,   # the song given shape - the radiant primeval ghost
}


func species_glow(species_id: String) -> float:
	return float(SPECIES_GLOW.get(species_id, 0.0))
