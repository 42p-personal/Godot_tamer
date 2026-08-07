// THE 50 SIGNATURE SKILLS (v0.91) — the moves a monster EARNS at the Signature
// Rite, one per body type list. Design rationale and the full balance audit live
// in docs/SIGNATURE_DESIGN.md; this file is the data.
//
// ─── How the lists are keyed ────────────────────────────────────────────────
// Six base bodies get 6 apiece. Draconic and Abyssal SHARE one list of 8 (they
// are the two Special-licence bodies — siblings, and sharing means a Primeval's
// pool is identical whichever recipe made it, so nothing has to record which two
// creatures were fused). Mythical gets 6. Fusion bodies author NOTHING: they
// resolve to their recipe's two parent lists, so every fusion picks from 12 —
// except Primeval, which picks from 14.
//
//   Saurian     = Mammal 6    + Reptilian 6   = 12
//   Tempestine  = Avian 6     + Aquatic 6     = 12
//   Broodkin    = Marsupial 6 + Insectoid 6   = 12
//   Primeval    = Mythical 6  + prestige 8    = 14
//
// ─── The balance rule these numbers obey ────────────────────────────────────
// A signature may exceed a POOL ceiling on ONE axis by ~15-20%, and must sit at
// or under the pool on every other axis. Signatures are strong-and-EARLY — a
// Silver winner wielding something the pool only offers at learnLevel 920 — not
// strictly better. 37 numbers were cut in the audit for breaching this on two or
// three axes at once. Before changing any value here, read the ceiling table in
// docs/SIGNATURE_DESIGN.md.
//
// ⚠️ UNITS ARE NOT UNIFORM, and getting one wrong fails SILENTLY:
//     atkBuff / atkDebuff / pierce / execute  →  FRACTIONS (0.2 = 20%)
//     dodgeBuff / accBuff / accDebuff / defBuff →  PERCENTAGE POINTS (14 = +14%)
//     regenBuff / hpRegenBuff / thorns / ward / guard → flat values
// `accBuff: 0.15` compiles, runs, and does nothing measurable. validate.ts now
// guards this.
//
// ─── The three combo roles ──────────────────────────────────────────────────
// Every combo works POOL-ONLY; a signature never gates one, it upgrades an axis
// of it — breadth, chance, multiplier, or contagion.
//   setter   — sets a status better than the pool (AoE, or a higher %)
//   payoff   — cashes a status harder than the pool (bigger mult, or row-wide)
//   spreader — propagates a status, which no pool move but three can do
// A body's setter and payoff never pair with EACH OTHER (you can only ever hold
// one signature) — each pairs with a move from the 90-move pool.
import { BodyType, Move } from './core'

// Authored shape of one signature. `id` is synthesised from the list key + index
// so it can never collide with a pool move id.
export type SignatureDef = Omit<Move, 'id' | 'learnLevel'>

const def = (m: SignatureDef): SignatureDef => m

// ─── MAMMAL — STR / melee ───────────────────────────────────────────────────
// Body minor STR, resist water, weak air. Bio: displacement and renewed purpose.
// All six are melee so every mammal drives them off the stat it trains at +10%.
// Statuses limited to STR's own three: bleed, stun, vulnerable.
const MAMMAL: SignatureDef[] = [
  def({ name: 'Highroad Charge', stat: 'STR', type: 'damage', channel: 'melee', target: 'enemy', cooldown: 6.5, accuracy: 92, power: 55, status: { kind: 'stun', chance: 25, duration: 1 }, effects: { pierce: 0.35 }, desc: 'The mountain road taken at a dead run; 25% chance to stun.' }),
  // Fire is STR's one fire attack: the controlled burn that takes the range back.
  def({ name: 'Reclaim the Range', stat: 'STR', type: 'damage', channel: 'melee', target: 'allEnemies', cooldown: 6.5, accuracy: 88, power: 42, status: { kind: 'vulnerable', chance: 40, duration: 3 }, desc: 'Burns the encroaching brush back; 40% chance to leave each foe Vulnerable.' }),
  // SETTER. Scatters, so it can bleed several foes at once and reach the back
  // line — cashed by pool Bloodletter (x2.5) or Deadeye (x1.5).
  def({ name: "Hunter's Seam", stat: 'STR', type: 'damage', channel: 'melee', target: 'enemy', cooldown: 6.5, accuracy: 92, power: 24, status: { kind: 'bleed', chance: 55, duration: 3 }, effects: { hits: [2, 3], randomTargets: true }, desc: 'Two or three ripping strikes across whoever is in reach; 55% chance to open a bleed on each.' }),
  def({ name: 'Rising Fury', stat: 'STR', type: 'buff', channel: 'support', target: 'self', cooldown: 6.5, accuracy: 100, power: 0, effects: { atkBuff: 0.35, hpRegenBuff: 6, duration: 4 }, desc: 'The longer it goes on, the worse it gets: +35% damage and +6 HP/turn for 4 rounds.' }),
  def({ name: 'The Weight of Years', stat: 'STR', type: 'damage', channel: 'melee', target: 'enemy', cooldown: 6.5, accuracy: 90, power: 55, effects: { recoil: 0.12, maxHpDmg: 0.04 }, desc: 'Everything it has, and it costs: heavy recoil, and extra damage scaled off the target’s own bulk.' }),
  // PAYOFF, row-wide rather than bigger — pool Bloodletter already cashes bleed
  // at x2.5 on ONE target, so this wins on breadth instead.
  def({ name: 'Throatline', stat: 'STR', type: 'damage', channel: 'melee', target: 'frontRow', cooldown: 6.5, accuracy: 92, power: 42, effects: { execute: 0.35, bonusVsStatus: { kind: 'bleed', mult: 1.6, consume: true } }, desc: 'Finishes what the bleeding started, right across the enemy front line.' }),
]

// ─── AVIAN — WIS / support ──────────────────────────────────────────────────
// Body minor WIS, resist air, weak water. Bio: scattered by scarcity, finding
// the way home. WIS is the only stat that heals ALLIES and carries the party
// cleanse; statuses limited to WIS's two, doom and silence.
const AVIAN: SignatureDef[] = [
  // PAYOFF — set by pool Field of Doom (28%). Pool's Mind Crush cashes at x1.6.
  def({ name: "Stormrider's Dive", stat: 'WIS', type: 'damage', channel: 'support', target: 'enemy', cooldown: 6.5, accuracy: 92, power: 53, effects: { bonusVsStatus: { kind: 'doom', mult: 2.0, consume: true } }, desc: 'Falls out of the sky onto a marked target; doubles down on anything already doomed.' }),
  def({ name: 'Wingbreaker', stat: 'WIS', type: 'damage', channel: 'support', target: 'backRow', cooldown: 6.5, accuracy: 90, power: 42, effects: { accDebuff: 12, duration: 3 }, desc: 'Strikes clean over the front line at whoever shelters behind it, and leaves them swinging wide.' }),
  // SETTER — the only AoE silence in the game (pool Silencing Spike is single).
  def({ name: 'The Windless Hour', stat: 'WIS', type: 'damage', channel: 'support', target: 'allEnemies', cooldown: 7.8, accuracy: 88, power: 37, status: { kind: 'silence', chance: 30, duration: 2 }, effects: { manaBurn: 20 }, desc: 'The air goes dead still; 30% chance to silence each foe, and burns 20 MP.' }),
  // SPREADER — omits `kind`, so the omen carries whatever the victim holds.
  def({ name: 'Carrion Omen', stat: 'WIS', type: 'damage', channel: 'support', target: 'enemy', cooldown: 7.8, accuracy: 92, power: 42, status: { kind: 'doom', chance: 35, duration: 4 }, effects: { spreadStatus: { targets: 2, chance: 45 } }, desc: 'Marks one for the end — and what it carries passes to two more of the flock.' }),
  def({ name: 'Called Home', stat: 'WIS', type: 'buff', channel: 'support', target: 'team', cooldown: 7.8, accuracy: 100, power: 28, effects: { cleanse: true }, desc: 'The whole flock answers: 30 HP restored to each ally and every ailment cleared.' }),
  def({ name: 'The Long Migration', stat: 'WIS', type: 'buff', channel: 'support', target: 'team', cooldown: 7.8, accuracy: 100, power: 0, effects: { regenBuff: 4, hpRegenBuff: 5, accBuff: 14, duration: 4 }, desc: 'The flight that sustains them: +4 mana, +5 HP per turn and +14% accuracy, team-wide, for 4 rounds.' }),
]

// ─── MARSUPIAL — CHA / voice ────────────────────────────────────────────────
// Body minor CHA, resist earth, weak fire. Bio: the itinerant fair. CHA's rule
// is party buffs on your side, party-wide debuffs on theirs.
const MARSUPIAL: SignatureDef[] = [
  def({ name: 'The Vanishing Act', stat: 'CHA', type: 'buff', channel: 'voice', target: 'team', cooldown: 6.5, accuracy: 100, power: 0, effects: { dodgeBuff: 16, accBuff: 14, duration: 4 }, desc: 'A troupe nobody can pin down: +16% dodge and +14% accuracy, team-wide, for 4 rounds.' }),
  // SETTER — pool Screech sets fear at 20%; cashed by pool Siren's Call.
  def({ name: "Barker's Cry", stat: 'CHA', type: 'damage', channel: 'voice', target: 'allEnemies', cooldown: 6.5, accuracy: 88, power: 39, status: { kind: 'fear', chance: 28, duration: 2 }, desc: 'Works the crowd against them; 28% chance to put fear through the whole enemy line.' }),
  // PAYOFF. ⚠️ CONSUMES the fear and immediately re-applies it — a NON-consuming
  // version would be inert, because fear lasts 2 rounds and this is cd5, so the
  // status always expires before the move comes off cooldown.
  def({ name: 'The Long Con', stat: 'CHA', type: 'damage', channel: 'voice', target: 'enemy', cooldown: 6.5, accuracy: 90, power: 52, status: { kind: 'fear', chance: 55, duration: 2 }, effects: { bonusVsStatus: { kind: 'fear', mult: 1.8, consume: true } }, desc: 'Breaks their nerve to cash it in — then puts it right back.' }),
  // SPREADER. Blind is a modifier rather than a hijack, so it can safely carry.
  def({ name: 'Carnival of Errors', stat: 'CHA', type: 'damage', channel: 'voice', target: 'enemy', cooldown: 7.8, accuracy: 90, power: 42, status: { kind: 'blind', chance: 50, duration: 3 }, effects: { spreadStatus: { targets: 1, chance: 30 } }, desc: 'Misdirection that catches: 50% to blind, and the confusion passes to a neighbour.' }),
  def({ name: 'Ashfall Elegy', stat: 'CHA', type: 'damage', channel: 'voice', target: 'allEnemies', cooldown: 6.5, accuracy: 88, power: 35, status: { kind: 'healblock', chance: 24, duration: 3 }, desc: 'A dirge for everything the fires took; 24% chance to stop each foe healing.' }),
  def({ name: 'The Grand Parade', stat: 'CHA', type: 'buff', channel: 'voice', target: 'team', cooldown: 7.8, accuracy: 100, power: 0, status: { kind: 'haste', chance: 100, duration: 2 }, effects: { atkBuff: 0.22, hpRegenBuff: 5, duration: 4 }, desc: 'The whole company marching in step: +22% damage, +5 HP/turn, and the team moves first.' }),
]

// ─── AQUATIC — INT / magic ──────────────────────────────────────────────────
// Body minor INT, resist fire, weak earth. Bio: the deep stirs. INT's pool rule
// is ALL FOUR ELEMENTS, no buffs and no healing — so this is the only body whose
// six are all offensive. Statuses limited to INT's three: burn, vulnerable, stun.
const AQUATIC: SignatureDef[] = [
  def({ name: 'Trenchfall', stat: 'INT', type: 'damage', channel: 'magic', target: 'enemy', cooldown: 6.5, accuracy: 92, power: 55, effects: { pierce: 0.3 }, desc: 'The weight of the whole water column, dropped on one target.' }),
  def({ name: 'Ancient Cold', stat: 'INT', type: 'damage', channel: 'magic', target: 'allEnemies', cooldown: 6.5, accuracy: 88, power: 39, status: { kind: 'vulnerable', chance: 40, duration: 3 }, desc: 'Cold older than the leagues; 40% chance to leave each foe Vulnerable.' }),
  // SPREADER — burn catching through water is the vent field, not a contradiction.
  def({ name: 'The Boiling Vent', stat: 'INT', type: 'damage', channel: 'magic', target: 'enemy', cooldown: 7.8, accuracy: 90, power: 48, status: { kind: 'burn', chance: 48, duration: 3 }, effects: { spreadStatus: { kind: 'burn', targets: 1, chance: 30 } }, desc: 'Superheated water from the seafloor; the scald spreads.' }),
  // The game's ONLY AoE stun, so pinned BELOW the pool's single-target 30%.
  def({ name: 'Trenchbed Collapse', stat: 'INT', type: 'damage', channel: 'magic', target: 'allEnemies', cooldown: 7.8, accuracy: 85, power: 35, status: { kind: 'stun', chance: 20, duration: 1 }, desc: 'The floor gives way beneath the whole line; 20% chance to stun each.' }),
  // PAYOFF — pool Cinderburst cashes burn at x1.5.
  def({ name: 'The Surfacing', stat: 'INT', type: 'damage', channel: 'magic', target: 'enemy', cooldown: 6.5, accuracy: 92, power: 52, effects: { bonusVsStatus: { kind: 'burn', mult: 2.0, consume: true } }, desc: 'Breaches after generations below; doubles down on anything already burning.' }),
  def({ name: 'Abyssal Pressure', stat: 'INT', type: 'damage', channel: 'magic', target: 'enemy', cooldown: 6.5, accuracy: 92, power: 44, effects: { maxHpDmg: 0.05, pierce: 0.25 }, desc: 'Crushing depth — it hurts the largest bodies hardest.' }),
]

// ─── INSECTOID — CON ────────────────────────────────────────────────────────
// Body minor CON, resist earth, weak water. Bio: an old order declining as a new
// one rises. CON is the ONLY stat granting ward/defBuff/taunt, and its only
// status is knockback — nothing in the game cashes knockback, so the payoff role
// falls to vulnerable (set by STR, DEX and INT alike).
// This is the one body whose OFFENCE IS FUELLED BY ITS DEFENCE.
const INSECTOID: SignatureDef[] = [
  def({ name: 'Chitin Bulwark', stat: 'CON', type: 'buff', channel: 'support', target: 'self', cooldown: 6.5, accuracy: 100, power: 0, effects: { ward: 42, thorns: 7, defBuff: 6, duration: 4 }, desc: 'Layers on shell: a 42-point shield, 7 thorns and +6 armour for 4 rounds.' }),
  // Spends ward set by pool Bastion (25) or Fortify (40) — or Nautilux's innate.
  def({ name: 'Shatterguard', stat: 'CON', type: 'damage', channel: 'melee', target: 'enemy', cooldown: 6.5, accuracy: 90, power: 42, effects: { consumeWard: 0.02 }, desc: 'Drives its own shield into the blow — the bigger the shell, the worse the hit.' }),
  // Spends thorns set by pool Barbed Carapace (6).
  def({ name: 'Barbfall', stat: 'CON', type: 'damage', channel: 'melee', target: 'frontRow', cooldown: 6.5, accuracy: 88, power: 35, effects: { consumeThorns: 0.05 }, desc: 'Rips its barbs free and rakes them across the enemy front line.' }),
  def({ name: 'Unbroken', stat: 'CON', type: 'damage', channel: 'melee', target: 'enemy', cooldown: 6.5, accuracy: 90, power: 48, status: { kind: 'knockback', chance: 40, duration: 2 }, effects: { hpScale: { atFull: 1.7, atEmpty: 0.6 } }, desc: 'A fortress hits hardest while its walls still stand.' }),
  def({ name: 'The Hive Answers', stat: 'CON', type: 'debuff', channel: 'support', target: 'allEnemies', cooldown: 7.8, accuracy: 100, power: 0, effects: { tauntForce: true, guard: 23, thorns: 7, duration: 3 }, desc: 'Pulls the entire enemy line onto itself, braced behind 23 guard and 7 thorns.' }),
  def({ name: 'Long Succession', stat: 'CON', type: 'buff', channel: 'support', target: 'self', cooldown: 7.8, accuracy: 100, power: 55, effects: { cleanse: true, hpRegenBuff: 5, duration: 3 }, desc: 'The hive endures: 60 HP restored, every ailment cleared, +5 HP/turn.' }),
]

// ─── REPTILIAN — DEX / ranged ───────────────────────────────────────────────
// Body minor DEX, resist fire, weak air. Bio: waiting, patient beyond reckoning,
// for a reason good enough to move. DEX's rule is poison and precision, heavy
// multi-hit, and SELF buffs only — never team buffs.
const REPTILIAN: SignatureDef[] = [
  def({ name: 'The Long Patience', stat: 'DEX', type: 'damage', channel: 'ranged', target: 'enemy', cooldown: 6.5, accuracy: 92, power: 55, effects: { hpScale: { atFull: 1.5, atEmpty: 0.75 }, pierce: 0.3 }, desc: 'Untouched and unhurried, it hits like nothing else — and fades as it takes damage.' }),
  // SPREADER — poison is damage-over-time, so it carries a wider spread safely.
  def({ name: 'Venom Bloom', stat: 'DEX', type: 'damage', channel: 'ranged', target: 'enemy', cooldown: 7.8, accuracy: 90, power: 40, status: { kind: 'poison', chance: 52, duration: 3 }, effects: { spreadStatus: { kind: 'poison', targets: 2, chance: 35 } }, desc: 'Venom that does not stay put; 52% to poison, and it passes to two more.' }),
  // SETTER — cashed by pool Deadeye (x1.5), or Bloodletter across stats.
  def({ name: 'Coil and Strike', stat: 'DEX', type: 'damage', channel: 'ranged', target: 'enemy', cooldown: 6.5, accuracy: 92, power: 22, status: { kind: 'bleed', chance: 45, duration: 3 }, effects: { hits: [2, 4], randomTargets: true }, desc: 'Two to four strikes from stillness, wherever they land.' }),
  def({ name: 'Sunward Basking', stat: 'DEX', type: 'buff', channel: 'support', target: 'self', cooldown: 6.5, accuracy: 100, power: 0, status: { kind: 'haste', chance: 100, duration: 2 }, effects: { dodgeBuff: 16, accBuff: 14, duration: 4 }, desc: 'Soaks up the heat and comes alive: +16% dodge, +14% accuracy, and moves first.' }),
  // PAYOFF — pool Deadeye cashes bleed at x1.5.
  def({ name: 'Ambush from Stillness', stat: 'DEX', type: 'damage', channel: 'ranged', target: 'enemy', cooldown: 6.5, accuracy: 92, power: 46, effects: { bonusVsStatus: { kind: 'bleed', mult: 2.1, consume: true }, execute: 0.3 }, desc: 'The strike it has been waiting the whole fight to make.' }),
  def({ name: 'Tailwhip Sweep', stat: 'DEX', type: 'damage', channel: 'ranged', target: 'frontRow', cooldown: 6.5, accuracy: 88, power: 37, status: { kind: 'knockback', chance: 46, duration: 2 }, desc: 'Takes the legs from the whole front line; 46% chance to drive each back.' }),
]

// ─── DRACONIC + ABYSSAL (SHARED, 8) ─────────────────────────────────────────
// The two Special-licence bodies share one list. They pull opposite ways —
// Draconic is WIS/support/fire, Abyssal is INT/magic/water — so the list is
// split 4 magic / 4 support and each body self-selects. Both elements appear so
// each gets one matching its own resist. All four statuses the two minors can
// reach are used: burn and vulnerable (INT), doom and silence (WIS).
const PRESTIGE_SHARED: SignatureDef[] = [
  def({ name: 'Elder Flame', stat: 'INT', type: 'damage', channel: 'magic', target: 'enemy', cooldown: 6.5, accuracy: 92, power: 55, status: { kind: 'burn', chance: 46, duration: 3 }, desc: 'Fire from before the leagues were drawn; 46% chance to set the target alight.' }),
  def({ name: 'Crushing Deep', stat: 'INT', type: 'damage', channel: 'magic', target: 'allEnemies', cooldown: 7.8, accuracy: 88, power: 39, effects: { displace: { toRow: 'back', chance: 40 } }, desc: 'Pressure that drives the whole enemy line backwards out of formation.' }),
  def({ name: 'Entropy Cascade', stat: 'INT', type: 'damage', channel: 'magic', target: 'enemy', cooldown: 7.8, accuracy: 90, power: 48, effects: { spreadStatus: { targets: 2, chance: 40 } }, desc: 'Whatever is wrong with them spreads to two more.' }),
  def({ name: 'Void Pulse', stat: 'INT', type: 'damage', channel: 'magic', target: 'allEnemies', cooldown: 6.5, accuracy: 88, power: 37, status: { kind: 'vulnerable', chance: 40, duration: 3 }, desc: 'A pulse of nothing at all; 40% chance to leave each foe Vulnerable.' }),
  def({ name: 'Ancient Knowing', stat: 'WIS', type: 'buff', channel: 'support', target: 'team', cooldown: 7.8, accuracy: 100, power: 28, effects: { cleanse: true }, desc: 'Knowledge older than injury: 30 HP to each ally and every ailment cleared.' }),
  def({ name: 'Aeons of Patience', stat: 'WIS', type: 'damage', channel: 'support', target: 'enemy', cooldown: 6.5, accuracy: 92, power: 52, effects: { bonusVsStatus: { kind: 'doom', mult: 2.0, consume: true } }, desc: 'It has waited longer than this fight; doubles down on anything already doomed.' }),
  def({ name: 'Deepwater Hymn', stat: 'WIS', type: 'damage', channel: 'support', target: 'backRow', cooldown: 6.5, accuracy: 90, power: 42, status: { kind: 'silence', chance: 29, duration: 2 }, effects: { manaBurn: 20 }, desc: 'Sung at the ranks behind the wall; 29% to silence, and burns 20 MP.' }),
  def({ name: 'Wyrmscale Aegis', stat: 'WIS', type: 'buff', channel: 'support', target: 'self', cooldown: 6.5, accuracy: 100, power: 0, effects: { defBuff: 8, thorns: 7, hpRegenBuff: 5, duration: 4 }, desc: 'Scales that have turned worse than this: +8 armour, 7 thorns, +5 HP/turn.' }),
]

// ─── MYTHICAL — CHA / voice ─────────────────────────────────────────────────
// Body minor CHA, resist air, weak earth. Four of the six are named for Mythical
// innates — the defining trait finally weaponised.
const MYTHICAL: SignatureDef[] = [
  def({ name: 'The Unison', stat: 'CHA', type: 'buff', channel: 'voice', target: 'team', cooldown: 7.8, accuracy: 100, power: 0, status: { kind: 'haste', chance: 100, duration: 2 }, effects: { atkBuff: 0.28, accBuff: 14, duration: 4 }, desc: 'One will across the whole team: +28% damage, +14% accuracy, and everyone moves first.' }),
  // SETTER — pool Screech sets fear at 20%; cashed by pool Siren's Call.
  def({ name: 'Prehistoric Roar', stat: 'CHA', type: 'damage', channel: 'voice', target: 'allEnemies', cooldown: 6.5, accuracy: 88, power: 42, status: { kind: 'fear', chance: 28, duration: 2 }, desc: 'A sound older than the circuit; 28% chance to break the whole enemy line.' }),
  def({ name: 'Aegis Bond', stat: 'CHA', type: 'buff', channel: 'voice', target: 'team', cooldown: 7.8, accuracy: 100, power: 0, effects: { thorns: 7, hpRegenBuff: 5, duration: 4 }, desc: 'Binds the team together: 7 thorns and +5 HP/turn for everyone, 4 rounds.' }),
  // PAYOFF — pool Siren's Call cashes fear at x1.5.
  def({ name: 'Cosmic Precision', stat: 'CHA', type: 'damage', channel: 'voice', target: 'enemy', cooldown: 6.5, accuracy: 95, power: 55, effects: { bonusVsStatus: { kind: 'fear', mult: 2.0, consume: true } }, desc: 'Finds the one gap that matters; doubles down on anything already afraid.' }),
  def({ name: 'Stellar Cascade', stat: 'CHA', type: 'damage', channel: 'voice', target: 'backRow', cooldown: 7.8, accuracy: 90, power: 42, effects: { displace: { toRow: 'front', chance: 45 } }, desc: 'Hauls whoever is hiding at the back out into the open.' }),
  def({ name: 'Unstoppable', stat: 'CHA', type: 'damage', channel: 'voice', target: 'enemy', cooldown: 6.5, accuracy: 92, power: 53, effects: { hpScale: { atFull: 1.6, atEmpty: 0.8 }, pierce: 0.3 }, desc: 'Nothing has stopped it yet, and it hits like it knows.' }),
]

// The authored lists, by list key. Fusion bodies are NOT keys here — they resolve
// through FUSION_SOURCES below.
export const SIGNATURE_LISTS = {
  Mammal: MAMMAL,
  Avian: AVIAN,
  Marsupial: MARSUPIAL,
  Aquatic: AQUATIC,
  Insectoid: INSECTOID,
  Reptilian: REPTILIAN,
  Prestige: PRESTIGE_SHARED, // Draconic AND Abyssal both read this
  Mythical: MYTHICAL,
} as const
export type SignatureListKey = keyof typeof SIGNATURE_LISTS

// Which list(s) a body draws from. Draconic and Abyssal share 'Prestige'; the
// four fusion bodies inherit their recipe's two parent lists and author none.
const BODY_LISTS: Record<BodyType, SignatureListKey[]> = {
  Mammal: ['Mammal'],
  Avian: ['Avian'],
  Marsupial: ['Marsupial'],
  Aquatic: ['Aquatic'],
  Insectoid: ['Insectoid'],
  Reptilian: ['Reptilian'],
  Draconic: ['Prestige'],
  Abyssal: ['Prestige'],
  Mythical: ['Mythical'],
  Saurian: ['Mammal', 'Reptilian'],
  Tempestine: ['Avian', 'Aquatic'],
  Broodkin: ['Marsupial', 'Insectoid'],
  // Primeval is Mythical + Draconic/Abyssal. Because the two Special bodies share
  // one list, the pool is the same whichever recipe produced this monster — which
  // is exactly why nothing has to record the fused parents.
  Primeval: ['Mythical', 'Prestige'],
}

// Stable, collision-proof id: list key + index. Never overlaps a pool move id
// (those are `${STAT}-${n}`), so a persisted loadout entry is unambiguous.
export const signatureId = (key: SignatureListKey, index: number): string => `SIG-${key}-${index}`

const buildMove = (key: SignatureListKey, d: SignatureDef, i: number): Move => ({ ...d, id: signatureId(key, i), learnLevel: 0 })

// Every signature move a monster of this body may choose from at the Rite.
export function signatureChoicesFor(body: BodyType): Move[] {
  return (BODY_LISTS[body] ?? []).flatMap((key) => SIGNATURE_LISTS[key].map((d, i) => buildMove(key, d, i)))
}

// Resolve a stored signature id back to its Move (loadouts persist ids only).
export function signatureMoveById(id: string): Move | null {
  for (const key of Object.keys(SIGNATURE_LISTS) as SignatureListKey[]) {
    const list = SIGNATURE_LISTS[key]
    for (let i = 0; i < list.length; i++) if (signatureId(key, i) === id) return buildMove(key, list[i], i)
  }
  return null
}

// Flat list of every authored signature — used by validate.ts and the tests.
export const ALL_SIGNATURE_MOVES: Move[] = (Object.keys(SIGNATURE_LISTS) as SignatureListKey[])
  .flatMap((key) => SIGNATURE_LISTS[key].map((d, i) => buildMove(key, d, i)))
