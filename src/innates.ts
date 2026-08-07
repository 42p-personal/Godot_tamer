// SPECIES INNATE EFFECTS — the numeric data behind `Species.innate` (§8.3).
//
// ⚠️ RELOCATED FROM `battle.ts` (2026-08-03, `docs/INNATES_ON_FIELD.md` stage 1). This table
// used to live inside the turn engine (`battle.ts`) with nothing else able to reach it without
// importing a file marked LEGACY. It is shared game DATA — same category as `moves.ts` and
// `lines.ts` — not turn-engine logic, so it gets its own module and both `battle.ts` (the
// shipping turn engine) and `src/tamerengine/` (the field engine `data.json` travels to Godot
// in) import from here. Pure relocation: no field, no value, no key changed.
//
// Reworked wholesale on `3doverhal` (§8.3, 2026-07-25): every innate is a genuine passive that
// maps to a real mechanical number — no flavour-only entries left. Curated table by ability
// name. Only ONE of a species' two innates is active at a time (`Monster.activeInnate`) —
// balance rule from that: a self-only field must carry a HIGHER magnitude than its aura twin
// (auras include the owner, so at equal numbers the aura strictly dominates — see Quickstep 6 vs
// Cheer 4 for the pattern).
//
// ⚠️ EVERY SPECIES INNATE MUST HAVE AN ENTRY HERE, KEYED BY NAME. `validate.ts` enforces it
// (the name-key guard) — a rename in `species.ts` without a matching rename here silently
// detaches the effect, and nothing else catches that. See `docs/OUTSTANDING.md` §2.5 /
// `docs/TECHNICAL_ISSUES.md` §10 for the history: this is the same failure shape as a lineless
// move, at the same scale.
import { StatusKind } from './core'

export interface InnateEffect {
  flatDR?: number // flat damage reduction on every hit taken
  dodge?: number // bonus dodge %
  acc?: number // bonus accuracy %
  regen?: number // bonus mana regen per turn
  hpRegen?: number // bonus HP regen per turn (self)
  dmgMult?: number // multiplier on all damage dealt
  firstHitMult?: number // multiplier on this monster's first damaging hit
  lifesteal?: number // fraction of damage dealt returned as HP
  lowHpDmgMult?: number // extra damage multiplier while below 30% HP
  highHpDmgMult?: number // extra damage multiplier while above 70% HP
  crit?: number // bonus critical-hit % (stacks with DEX-derived critChance)
  pierce?: number // fraction of target mitigation ignored (stacks with STR pierce + skill pierce)
  echo?: number // bonus % chance a skill casts twice (stacks with INT-derived echoChance)
  magicDmgMult?: number // multiplier on damage from MAGIC-channel moves (was elemental, pre-removal)
  executeMult?: number // damage multiplier vs targets below 30% HP
  startWard?: number // begins every battle with an absorb shield of this many HP
  manaSteal?: number // fraction of damage dealt drained from the target's mana into own
  buffExtend?: number // % chance each of its cast buffs lasts +1 round (rolled on apply)
  debuffExtend?: number // % chance each of its inflicted debuffs lasts +1 round (rolled on apply)
  debuffResist?: number // % shaved off incoming debuff magnitudes (stacks with CHA-derived)
  statusOnHit?: { kind: StatusKind; chance: number; duration: number } | null // may inflict a status on every damaging hit

  // ── SPATIAL INNATES (2026-08-06, user-approved slate) ──────────────────────
  // ⚠️ THESE FIELDS ARE LIVE ONLY ON THE GODOT FIELD ENGINE. The legacy turn engine
  // (`battle.ts`) has no space, no facing, no casts and no cover, so it cannot express them —
  // they are dormant there BY DESIGN, the reverse of the removed `element` field (which was
  // dormant on the engine being moved TO; these are live on the destination). Magnitudes were
  // deliberately pulled DOWN one notch by the user before authoring ("magnitudes too strong
  // overall") and are re-baseline starting points, not commitments.
  coverPierce?: number // fraction of the target's cover accuracy debuff ignored (0..1)
  openFieldDmg?: number // damage mult when NO cover of any grade lies between you and target
  rearArcBonus?: number // added to the standard rear-attack damage bonus (0.15 + this)
  rearArcDeg?: number // your OWN rear arc in degrees (standard 120 — smaller = harder to backstab)
  fleetfoot?: number // your backpedal speed mult (replaces the standard 0.60)
  chargeDmg?: number // mult on your first hit after closing 25+ units in a sustained run
  predatorDmg?: number // damage mult vs targets currently moving away from you
  braceDmg?: number // damage mult after standing still ~1s, until you next move
  castSteady?: number // % chance to shrug off a CONTROL interrupt (LOS breaks always land)
  windupMult?: number // multiplier on your cast windup times (<1 = faster)
  kbResist?: number // knockback distance mult (0.25 = pushed a quarter as far)
  duelDmg?: number // damage mult when nobody else is near you and your target (the side-duel)
  packDmg?: number // damage mult when an ally hit your target within the last second
  homeGroundDR?: number // flat DR while near your own deploy station
  homeGroundAcc?: number // bonus accuracy while near your own deploy station
  auraEnemySlow?: number // speed mult on enemies inside your reach (<1 = slower)

  // Team-wide auras (user spec 2026-07-25): apply to every LIVING ally each
  // round, including the owner — vanish the round after the owner falls.
  // Stack additively with each other and with the recipient's own self-only
  // fields above (aura dmgMult multiplies in).
  //
  // ⚠️ NOT YET WIRED ON `tamerengine` (`docs/INNATES_ON_FIELD.md` §2, Group K/L). Porting this
  // shape verbatim — global, unconditional, no range check — would reintroduce the exact
  // position-blindness bug the field engine already fixed once for cast team buffs
  // (`tamerengine/types.ts` `TEAM_AURA_RADIUS`). Needs a design decision before it is wired.
  auraFlatDR?: number
  auraDodge?: number
  auraRegen?: number
  auraHpRegen?: number
  auraDmgMult?: number

  // Enemy-facing debuff auras: apply to every LIVING enemy each round, same
  // living/vanish-on-death rule as team auras above, just the opposing side.
  //
  // ⚠️ SAME GAP AS THE TEAM AURAS ABOVE — not yet wired on `tamerengine`.
  enemyAccDebuff?: number
  enemyDodgeDebuff?: number
  enemyRegenDebuff?: number
  enemyDmgDebuff?: number
}

// SPATIAL REASSIGNMENT BATCH (2026-08-06): 33 entries whose NAMES were already spatial
// identities trapped in arithmetic bodies (Ambush, Statue Stance, Immovable, Drowsy Aura,
// Time Dilation, Burrow...) now carry the new spatial fields. Their old numeric effects were
// REPLACED wholesale - the name is the identity, and a name that says "Ambush" while the number
// says "generic first-hit bonus" was the flavour-text lie the 2026-07-25 rework existed to end.
export const INNATE_EFFECTS: Record<string, InnateEffect> = {
  // --- Thematic redistribution (user spec 2026-07-25): crit → DEX majors then
  // Reptilians; pierce → STR majors then Mammals; mana regen → WIS then Avians;
  // magic-damage/echo → INT then Aquatics; auras → CHA majors then Marsupials;
  // flat-DR trimmed on the tournament-dominant CON tanks. ---

  // damage reduction (self) — every entry its own defensive texture (2026-07-25:
  // no two innates share a profile; clusters got distinct numbers/riders)
  'Thick Hide': { flatDR: 3 }, // the plain thickest hide in the game
  'Weathered Hide': { flatDR: 2, debuffResist: 10 }, // old scars — little gets under its skin
  'Spiral Shell': { flatDR: 2, dodge: 2 }, // the spiral deflects glancing blows
  'Statue Stance': { braceDmg: 1.15 },
  // CON-tank trim (2026-07-25 balance sweep: these species dominated at every level)
  Ironclad: { flatDR: 2 }, // the textbook plate
  Unstoppable: { kbResist: 0.25, flatDR: 1 }, // cannot be slowed or weakened
  'Chitin Plate': { flatDR: 1, startWard: 12 }, // the dam-keystone shell is already braced
  'Armored Scales': { flatDR: 1, hpRegen: 1 }, // crocodile wounds knit famously fast
  'Shell Ward': { startWard: 18 }, // the shell is raised before the bell
  // Aegis Bond outbids its aura twin Unison (auraFlatDR 2) — self-only must pay more (the bond also mends).
  'Aegis Bond': { flatDR: 2, hpRegen: 2 },
  // evasion (self) — pure-dodge ladder 4..10, no two alike; composites carry riders
  Quickstep: { dodge: 6 }, Aerial: { dodge: 7 }, 'Phase Shift': { dodge: 9 }, 'Wing Current': { dodge: 10 },
  'Dodge Storm': { dodge: 6, crit: 3 }, // storm-dancer: slip the blow, answer it
  'Cloak of Shadow': { dodge: 8 }, 'Ancient Knowing': { dodge: 5 },
  Burrow: { homeGroundDR: 2, homeGroundAcc: 8 }, 'Wall Runner': { dodge: 6, acc: 2 }, // impossible angles cut both ways
  // "Hard to reach" (self dodge) AND "foes arrive slowed" (enemy dodge debuff) — both halves of the description, one entry.
  'Web Trap': { homeGroundDR: 2, homeGroundAcc: 8, dodge: 2 },
  // accuracy (self) — 7/8/10/12 ladder
  'Keen Eye': { coverPierce: 0.6 }, 'Cosmic Precision': { coverPierce: 0.6, acc: 3 }, 'Compound Eyes': { rearArcDeg: 75 }, 'Hypnotic Gaze': { acc: 7 },
  // mana regen (self) — WIS majors and Avians; 2/3/4/5 ladder
  'Silent Wisdom': { castSteady: 50, regen: 2 }, 'Glacial Wisdom': { regen: 2, flatDR: 1 }, 'Arcane Mastery': { regen: 5 },
  'Inner Calm': { castSteady: 50 },
  'Abyssal Glow': { regen: 3 }, // its glow is its own wellspring — Lanterix, WIS major
  // HP regen (self) — Sun Basking was miscoded as mana regen; "recovers strength between blows" is HP.
  'Sun Basking': { hpRegen: 3 },
  // damage boosts (self, flat %) — thinned to a 1.05..1.08 ladder, one holder each
  'Rising Fury': { dmgMult: 1.05 }, 'Draconic Pride': { dmgMult: 1.06 }, Overload: { dmgMult: 1.07 },
  // Pride outbids its aura twin Rallying Roar (auraDmgMult 1.05).
  Pride: { dmgMult: 1.08 },
  // former exclusive "+X% damage" clones, re-textured (2026-07-25):
  'Flame Aura': { statusOnHit: { kind: 'burn', chance: 8, duration: 2 } }, // the aura itself scorches
  Blizzard: { statusOnHit: { kind: 'stun', chance: 6, duration: 1 } }, // frozen stiff
  'Whip Strike': { pierce: 0.1 }, // the whip wraps around shields
  'Void Pulse': { lifesteal: 0.1 }, // the void consumes
  'Rift Magic': { echo: 6 }, // a cast slips through the rift twice
  'Stellar Shot': { openFieldDmg: 1.15, crit: 3 }, // starlight finds the mark
  // critical hits — DEX majors (Grivvel/Tazzik/Mantaris) + Reptilian (Geckari); 6..10 ladder
  Rend: { crit: 8 }, Whirlwind: { crit: 7 }, 'Current Rider': { fleetfoot: 0.85, acc: 2 }, 'Tail Drop': { crit: 10 },
  // armour piercing — STR majors (Mantevoke/Bruxaroo) + Mammal (Ursath); serrated cuts deepest
  'Serrated Claws': { pierce: 0.18 }, Southpaw: { duelDmg: 1.15 }, Maul: { pierce: 0.15 },
  // magic mastery / double-cast — INT majors + Aquatics; echo 6/8/10/12 ladder
  'Arcane Bolt': { magicDmgMult: 1.1 }, Spellblade: { magicDmgMult: 1.12 },
  Wellspring: { echo: 10 }, 'Tentacle Barrage': { echo: 8 }, // eight arms — some casts come twice
  'Spell Echo': { echo: 12 }, // finally does what its name says
  // openers — bonus multiplier on this monster's first landed hit (self);
  // 1.2..1.7 ladder, the mantis's legendary strike at the top
  'Chest Beat': { duelDmg: 1.15, firstHitMult: 1.2 }, 'Dive Bomb': { chargeDmg: 1.18 }, 'Glide Strike': { predatorDmg: 1.12 },
  Haymaker: { firstHitMult: 1.35 }, 'Silent Strike': { rearArcBonus: 0.1, crit: 5 }, 'Prehistoric Roar': { firstHitMult: 1.2 },
  'Ambush Strike': { rearArcBonus: 0.1, acc: 4 }, // the patient strike does not miss
  Ambush: { rearArcBonus: 0.1, firstHitMult: 1.25 }, 'Skim Dart': { openFieldDmg: 1.15 },
  // sustain — lifesteal / mana steal (self)
  Devour: { lifesteal: 0.3 }, 'Age Reversal': { lifesteal: 0.15 }, 'Mana Theft': { manaSteal: 0.2 },
  // conditional damage windows
  Frenzy: { lowHpDmgMult: 1.25 }, // desperation — below 30% HP
  'Death Roll': { chargeDmg: 1.18, executeMult: 1.1 }, // finishes weakened prey — below 30% target HP
  // status-on-hit — venom in every bite, a dazzling crest flash
  'Venom Fang': { statusOnHit: { kind: 'poison', chance: 12, duration: 3 } },
  'Crest Display': { statusOnHit: { kind: 'blind', chance: 10, duration: 2 } },
  // buff/debuff duration extension — the song plays again; the queen's decree lingers
  Encore: { buffExtend: 25 }, 'Hive Command': { debuffExtend: 30 },
  // debuff resistance — the ox is the most unshakeable; the serpent close behind
  Immovable: { kbResist: 0.25, debuffResist: 10 }, 'Cold Blood': { debuffResist: 20 },
  // opening shield — the shell is already up when the bell rings
  Ward: { startWard: 25 },

  // Tidal Wisdom: SELF sustain now (was an aura — Carcharun is a STR-major
  // aquatic, off the CHA/Marsupial aura theme; the old shark keeps its own counsel).
  'Tidal Wisdom': { regen: 2, hpRegen: 2 },

  // --- Team-wide auras: apply to every LIVING ally each round, including the
  // owner. Reserved (user spec 2026-07-25) for CHA-major species (Maneleo,
  // Larkessa, Vespera) and Marsupials (Quokkade, Koalio) — plus the exclusive
  // species, which sit outside the training-theme system entirely. ---
  'Rallying Roar': { auraDmgMult: 1.05 },
  Cheer: { auraDodge: 4 }, Unison: { packDmg: 1.1, auraFlatDR: 1 },
  'Song of Valor': { auraDmgMult: 1.04 },
  'Psychic Aura': { auraDodge: 3, auraRegen: 1 }, // the mind shields and feeds the mind
  Foresight: { auraDodge: 5 },
  'Soothing Words': { auraHpRegen: 3 }, // the pool's strongest pure team-heal — the crooner's whole identity
  'Life Bloom': { auraHpRegen: 2, auraRegen: 1 }, // the bloom nourishes body and spirit
  'Royal Jelly': { auraHpRegen: 2 }, // the queen feeds the hive

  // --- Enemy-facing debuff auras: apply to every LIVING enemy each round.
  // Ink Cloud was miscoded as a SELF buff when its own description says it
  // weakens the enemy — fixed here. ---
  'Ink Cloud': { enemyAccDebuff: 5 },
  Hex: { enemyAccDebuff: 4, enemyRegenDebuff: 1 },
  // Dodge-debuffs are dead weight vs low-DEX foes (dodge has no floor at 0 and
  // hit chance past 100 is wasted), so Drowsy Aura moved to accuracy — drowsy
  // foes swing wide — and Root Grasp splits its value across both (balance
  // sweep 2026-07-25: these two were the pool's worst performers).
  'Drowsy Aura': { auraEnemySlow: 0.85 },
  'Root Grasp': { auraEnemySlow: 0.85, enemyAccDebuff: 2 }, Entropy: { enemyDmgDebuff: 0.05 },
  'Temporal Distortion': { enemyDodgeDebuff: 4, auraRegen: 1 },

  // Truth's Word: reworked into a genuine passive (see truthsWordCleanse), plus
  // a small always-on ward of conviction — the cleanse alone is worthless
  // against teams that carry no debuff moves.
  "Truth's Word": { flatDR: 1 },

  // --- Saurian (fusion class, v0.7) — Mammal+Reptilian chimeras ---
  'Scaled Hide': { flatDR: 2 }, // warm-blood bulk under cold-blood plate
  'Primal Roar': { enemyDmgDebuff: 0.04 }, // the roar takes the fight out of them
  "Serpent's Strike": { predatorDmg: 1.12, crit: 4 }, // the ambush lunge
  'Mane Bristle': { rearArcDeg: 75, dodge: 3 }, // the bristling mane reads the strike
  Thornplate: { startWard: 16 }, // the keeled plates are braced before the bell
  Ironscale: { flatDR: 3 }, // the heaviest plate a Saurian wears
  'Runic Wisdom': { regen: 2 }, // rune-lit scales feed the well
  'Petrifying Gaze': { statusOnHit: { kind: 'stun', chance: 8, duration: 1 } }, // the basilisk look
  'Dread Bellow': { enemyAccDebuff: 5 }, // foes flinch and swing wide
  'Rally Cry': { auraDmgMult: 1.05 }, // the war-bellow lifts the whole line

  // --- Tempestine (fusion class) — Avian+Aquatic storm creatures ---
  'Chain Lightning': { statusOnHit: { kind: 'stun', chance: 8, duration: 1 } },
  'Storm Dive': { chargeDmg: 1.18, acc: 3 },
  'Wind Veil': { fleetfoot: 0.85 },
  Squall: { enemyAccDebuff: 3 },
  'Tidal Grace': { auraHpRegen: 2 },
  Deluge: { auraRegen: 1 },
  Overcharge: { windupMult: 0.8, dmgMult: 1.03 },
  'Static Field': { echo: 6 },
  'Gale Cry': { enemyAccDebuff: 5 },
  'Rally Squall': { auraDmgMult: 1.05 },

  // --- Broodkin (fusion class) — Marsupial+Insectoid brood-carriers ---
  Carapace: { flatDR: 3 },
  'Dig In': { braceDmg: 1.15, flatDR: 1 },
  'Brood Tend': { auraHpRegen: 2 },
  'Hive Mind': { packDmg: 1.1 },
  'Ambush Fold': { firstHitMult: 1.4 },
  'Blade Arms': { crit: 5 },
  'Resin Plate': { flatDR: 2 },
  'Amber Set': { debuffResist: 15 },
  'Command Swarm': { packDmg: 1.1, auraDmgMult: 1.02 },
  Disorient: { enemyDodgeDebuff: 4 },

  // --- Primeval (v0.88, prestige fusion: Mythical + Draconic/Abyssal) ---
  'Dawn Fury': { dmgMult: 1.08 },
  'Unbroken Age': { flatDR: 2, debuffResist: 20 },
  'Starving Aim': { crit: 10 },
  'Light Drinker': { lifesteal: 0.12 },
  'Era Shell': { startWard: 20 },
  'Time Dilation': { windupMult: 0.8 },
  'First Spell': { echo: 10 },
  'Wellspring Eternal': { regen: 4 },
  'Genesis Chord': { auraDmgMult: 1.05 },
  'Ending Verse': { auraFlatDR: 2 },
}
