// The 45 species (§8.2 / §8.3): stats, lifespans, innate abilities.
// 30 base (6 body types × 5) + 15 exclusive (Draconic/Abyssal/Mythical).
import { BodyType, STATS, Stat, Stats, Species } from './core'

const s = (STR: number, DEX: number, CON: number, WIS: number, INT: number, CHA: number) => ({ STR, DEX, CON, WIS, INT, CHA })

export const SPECIES: Species[] = [
  // --- Mammal (STR / CON) ---
  { id: 'kongrath', name: 'Gruulk', body: 'Mammal', naturalClass: 'Warrior', base: s(42, 20, 34, 12, 10, 16), lifespan: 4, flavour: 'A green-hided, blue-crested colossus, quiet until the first hit lands; his opening blow is a landslide.',
    trainingProfile: {},
    innate: [{ name: 'Chest Beat', desc: '+50% damage on its first hit.' }, { name: 'Rising Fury', desc: '+5% damage.' }] },
  { id: 'aegisox', name: 'Terrock', body: 'Mammal', naturalClass: 'Tank', base: s(30, 14, 44, 16, 10, 14), lifespan: 6, flavour: 'A squared boulder of a giant, tan as quarry stone. It stands where it plants itself, and nothing moves it.',
    trainingProfile: { major: 'CON', flaw: 'DEX' },
    innate: [{ name: 'Ironclad', desc: 'Reduces damage taken by 2 per hit.' }, { name: 'Immovable', desc: 'Incoming debuffs are 25% weaker.' }] },
  { id: 'maneleo', name: 'Manegold', body: 'Mammal', naturalClass: 'Captain', base: s(40, 22, 26, 12, 12, 30), lifespan: 4, flavour: 'A tawny-gold shag-beast whose hood of fur falls like a mane; leads from the front and roars like it.',
    trainingProfile: { major: 'CHA', flaw: 'CON' },
    innate: [{ name: 'Rallying Roar', desc: 'Team: +5% damage.' }, { name: 'Pride', desc: '+8% damage.' }] },
  { id: 'grivvel', name: 'Grynt', body: 'Mammal', naturalClass: 'Rogue', base: s(34, 40, 22, 12, 10, 14), lifespan: 4, flavour: 'A wiry green scrapper, short-tempered and shorter; already picking the next fight.',
    trainingProfile: { major: 'DEX', flaw: 'CHA' },
    innate: [{ name: 'Rend', desc: '+8% critical hit chance.' }, { name: 'Frenzy', desc: '+25% damage while below 30% HP.' }] },
  { id: 'ursath', name: 'Frostmaul', body: 'Mammal', naturalClass: 'Warrior', base: s(40, 14, 38, 14, 10, 12), lifespan: 5, flavour: 'A blue-white shag-armed mauler woken from a long sleep; honest work, honestly enjoyed.',
    trainingProfile: { major: 'WIS', flaw: 'INT' },
    innate: [{ name: 'Thick Hide', desc: 'Reduces damage taken by 3 per hit.' }, { name: 'Maul', desc: 'Ignores 15% of enemy mitigation.' }] },

  // --- Avian (DEX / WIS) ---
  { id: 'pinguox', name: 'Capling', body: 'Avian', naturalClass: 'Ranger', base: s(20, 44, 18, 24, 28, 12), lifespan: 4, flavour: 'A small teal cap-headed diver, cheerfully unbothered by anything above its weight class.',
    // No flaw (user spec 2026-07-24): DEX is already this species' highest base
    // stat, so a DEX flaw would fight its own class identity — major only.
    trainingProfile: { major: 'CON' },
    innate: [{ name: 'Dive Bomb', desc: '+60% damage on its first hit.' }, { name: 'Keen Eye', desc: '+8% accuracy.' }] },
  { id: 'strixil', name: 'Aeristra', body: 'Avian', naturalClass: 'Sage', base: s(10, 22, 16, 42, 32, 14), lifespan: 5, flavour: 'A pale-blue floater that keeps the old roost\'s memory; it drifts, watches, remembers.',
    trainingProfile: { major: 'INT', flaw: 'STR' },
    innate: [{ name: 'Wellspring', desc: '10% chance to cast a skill twice.' }, { name: 'Silent Wisdom', desc: '+4 mana regen/turn.' }] },
  { id: 'balaenix', name: 'Azurefin', body: 'Avian', naturalClass: 'Rogue', base: s(28, 44, 18, 20, 16, 14), lifespan: 4, flavour: 'A deep-blue drifter with pale fins like sails; patient, silent, and sudden.',
    trainingProfile: { major: 'STR', flaw: 'CHA' },
    innate: [{ name: 'Ambush Strike', desc: '+40% damage on its first hit. +4% accuracy.' }, { name: 'Statue Stance', desc: '+10% damage while above 70% HP.' }] },
  { id: 'corvaan', name: 'Cobalon', body: 'Avian', naturalClass: 'Wizard', base: s(12, 26, 16, 30, 40, 16), lifespan: 4, flavour: 'A cobalt bird-thing with scholarly brows and a stolen spellbook of tricks.',
    trainingProfile: {},
    innate: [{ name: 'Arcane Bolt', desc: '+10% magic damage.' }, { name: 'Hex', desc: 'Enemies: -4% accuracy. Enemies: -1 mana regen/turn.' }] },
  { id: 'larkessa', name: 'Rosewing', body: 'Avian', naturalClass: 'Bard', base: s(12, 34, 14, 22, 16, 42), lifespan: 4, flavour: 'A rose-tinted songwing whose voice once guided the lost home; now it fills stadiums.',
    trainingProfile: { major: 'CHA', flaw: 'INT' },
    innate: [{ name: 'Song of Valor', desc: 'Team: +4% damage.' }, { name: 'Encore', desc: '25% chance its buffs last an extra round.' }] },

  // --- Marsupial (CHA / DEX) ---
  { id: 'bruxaroo', name: 'Mosshorn', body: 'Marsupial', naturalClass: 'Captain', base: s(40, 28, 26, 12, 10, 34), lifespan: 4, flavour: 'A green, long-limbed brawler crowned with mossy horns; swings first and grins after.',
    trainingProfile: { major: 'STR', flaw: 'INT' },
    innate: [{ name: 'Haymaker', desc: '+35% damage on its first hit.' }, { name: 'Southpaw', desc: 'Ignores 12% of enemy mitigation.' }] },
  { id: 'koalio', name: 'Slumbra', body: 'Marsupial', naturalClass: 'Orator', base: s(12, 20, 18, 30, 14, 44), lifespan: 5, flavour: 'A grey-blue climber, calm to the point of sleep; it would rather lull you than strike you.',
    trainingProfile: { major: 'CON', flaw: 'STR' },
    innate: [{ name: 'Drowsy Aura', desc: 'Enemies: -3% accuracy.' }, { name: 'Soothing Words', desc: 'Team: +3 HP regen/turn.' }] },
  { id: 'quokkade', name: 'Tannik', body: 'Marsupial', naturalClass: 'Bard', base: s(12, 36, 14, 22, 14, 40), lifespan: 4, flavour: 'A small warm-tan critter, relentlessly cheerful; fights for the crowd and the picnic after.',
    trainingProfile: {},
    innate: [{ name: 'Cheer', desc: 'Team: +4% dodge chance.' }, { name: 'Quickstep', desc: '+6% dodge chance.' }] },
  { id: 'sylvaglide', name: 'Leafwisp', body: 'Marsupial', naturalClass: 'Ranger', base: s(12, 42, 12, 24, 28, 26), lifespan: 4, flavour: 'A leaf-green wisp that rides draughts nobody else can feel; ambush by understatement.',
    // No flaw (user spec 2026-07-24): same reasoning as Pinguox — DEX is
    // already its highest base stat, so no DEX flaw is authored.
    trainingProfile: { major: 'WIS' },
    innate: [{ name: 'Glide Strike', desc: '+30% damage on its first hit.' }, { name: 'Aerial', desc: '+7% dodge chance.' }] },
  { id: 'tazzik', name: 'Razzhorn', body: 'Marsupial', naturalClass: 'Rogue', base: s(34, 40, 24, 12, 12, 20), lifespan: 4, flavour: 'A small dark-red demon of pure appetite; every venue it visits learns to pack early.',
    trainingProfile: { major: 'DEX', flaw: 'CON' },
    innate: [{ name: 'Devour', desc: 'Heals 30% of damage dealt as HP.' }, { name: 'Whirlwind', desc: '+7% critical hit chance.' }] },

  // --- Aquatic (WIS / INT) ---
  { id: 'maelurk', name: 'Oozehorn', body: 'Aquatic', naturalClass: 'Wizard', base: s(12, 22, 18, 32, 44, 14), lifespan: 4, flavour: 'A horned green ooze that waits in its own puddle; curiosity with an undertow.',
    trainingProfile: {},
    innate: [{ name: 'Ink Cloud', desc: 'Enemies: -5% accuracy.' }, { name: 'Tentacle Barrage', desc: '8% chance to cast a skill twice.' }] },
  { id: 'nautilux', name: 'Coralux', body: 'Aquatic', naturalClass: 'Spellshield', base: s(14, 12, 42, 32, 20, 12), lifespan: 5, flavour: 'A shell-orange drifter of a thousand tides; slow, deep pride and an unbroken guard.',
    trainingProfile: { major: 'CON', flaw: 'STR' },
    innate: [{ name: 'Ward', desc: 'Starts battle with a 25 HP shield.' }, { name: 'Spiral Shell', desc: 'Reduces damage taken by 2 per hit. +2% dodge chance.' }] },
  { id: 'carcharun', name: 'Gravemaw', body: 'Aquatic', naturalClass: 'Sage', base: s(12, 16, 24, 44, 30, 14), lifespan: 6, flavour: 'A slab-shouldered slate beast whose jaw opens wider than it should. The oldest bruiser on the Circuit.',
    trainingProfile: { major: 'STR', flaw: 'CHA' },
    innate: [{ name: 'Tidal Wisdom', desc: '+2 mana regen/turn. +2 HP regen/turn.' }, { name: 'Weathered Hide', desc: 'Reduces damage taken by 2 per hit. Incoming debuffs are 10% weaker.' }] },
  { id: 'mantaris', name: 'Veilfin', body: 'Aquatic', naturalClass: 'Ranger', base: s(14, 42, 18, 22, 32, 12), lifespan: 4, flavour: 'A soft-violet glider of the open water; a showman hooked on the hush before the sweep.',
    trainingProfile: { major: 'DEX', flaw: 'CON' },
    innate: [{ name: 'Wing Current', desc: '+10% dodge chance.' }, { name: 'Current Rider', desc: '+6% critical hit chance. +2% accuracy.' }] },
  { id: 'lanterix', name: 'Lumigel', body: 'Aquatic', naturalClass: 'Spellsword', base: s(20, 14, 36, 24, 40, 12), lifespan: 5, flavour: 'A soft pink glow-blob from true darkness; it carries its own light into the ring.',
    trainingProfile: { major: 'WIS', flaw: 'DEX' },
    innate: [{ name: 'Spellblade', desc: '+12% magic damage.' }, { name: 'Abyssal Glow', desc: '+3 mana regen/turn.' }] },

  // --- Insectoid — chitinous, tireless; covers WIS/DEX training weaknesses ---
  { id: 'scarabrute', name: 'Scarabron', body: 'Insectoid', naturalClass: 'Tank', base: s(36, 16, 44, 8, 14, 12), lifespan: 5, flavour: 'A bronze-shelled juggernaut; a dam-keeper\'s patience in an armoured scuttle.',
    trainingProfile: {},
    innate: [{ name: 'Chitin Plate', desc: 'Reduces damage taken by 1 per hit. Starts battle with a 12 HP shield.' }, { name: 'Burrow', desc: '+4% dodge chance.' }] },
  { id: 'mantevoke', name: 'Bristleye', body: 'Insectoid', naturalClass: 'Rogue', base: s(34, 42, 18, 8, 20, 12), lifespan: 4, flavour: 'A green orb bristling with white thorns around one unblinking eye; a temple guardian\'s patience.',
    trainingProfile: { major: 'STR', flaw: 'INT' },
    innate: [{ name: 'Ambush', desc: '+70% damage on its first hit.' }, { name: 'Serrated Claws', desc: 'Ignores 18% of enemy mitigation.' }] },
  { id: 'arachnyx', name: 'Pincerax', body: 'Insectoid', naturalClass: 'Wizard', base: s(14, 8, 16, 32, 40, 20), lifespan: 4, flavour: 'A scarlet-shelled scuttler, all claws and armour plate, that boxes with both pincers at once.',
    trainingProfile: { major: 'WIS', flaw: 'DEX' },
    innate: [{ name: 'Web Trap', desc: '+5% dodge chance. Enemies: -3% dodge chance.' }, { name: 'Venom Fang', desc: '12% chance to Poison on every hit.' }] },
  { id: 'vespera', name: 'Vesperon', body: 'Insectoid', naturalClass: 'Orator', base: s(12, 8, 26, 34, 18, 44), lifespan: 5, flavour: 'A yellow-and-black songwing with a sting in the chorus.',
    trainingProfile: { major: 'CHA', flaw: 'STR' },
    innate: [{ name: 'Hive Command', desc: '30% chance its debuffs last an extra round.' }, { name: 'Royal Jelly', desc: 'Team: +2 HP regen/turn.' }] },
  { id: 'odonatra', name: 'Duskdart', body: 'Insectoid', naturalClass: 'Ranger', base: s(14, 44, 16, 22, 30, 8), lifespan: 4, flavour: 'A dusk-cyan skimmer, all speed and shimmer, that strikes between wingbeats.',
    trainingProfile: { major: 'DEX', flaw: 'WIS' },
    innate: [{ name: 'Skim Dart', desc: '+25% damage on its first hit.' }, { name: 'Compound Eyes', desc: '+11% accuracy.' }] },

  // --- Reptilian — slow, patient, cold-blooded; covers DEX/WIS training weaknesses ---
  { id: 'crocmaw', name: 'Mirejaw', body: 'Reptilian', naturalClass: 'Warrior', base: s(44, 10, 38, 20, 12, 14), lifespan: 6, flavour: 'An olive-drab saurian, low and patient as a bog, with a bite that ends arguments.',
    trainingProfile: { major: 'STR', flaw: 'WIS' },
    innate: [{ name: 'Death Roll', desc: '+25% damage to enemies below 30% HP.' }, { name: 'Armored Scales', desc: 'Reduces damage taken by 1 per hit. +1 HP regen/turn.' }] },
  { id: 'iguanor', name: 'Regalor', body: 'Reptilian', naturalClass: 'Captain', base: s(42, 10, 26, 14, 12, 34), lifespan: 4, flavour: 'A gold-and-ivory grandee with a collar of ceremonial fur; fights like etiquette with claws.',
    trainingProfile: { major: 'INT', flaw: 'CON' },
    innate: [{ name: 'Sun Basking', desc: '+3 HP regen/turn.' }, { name: 'Crest Display', desc: '10% chance to Blind on every hit.' }] },
  { id: 'serpwyn', name: 'Sandsaur', body: 'Reptilian', naturalClass: 'Sage', base: s(16, 22, 14, 42, 30, 8), lifespan: 5, flavour: 'A sand-yellow saurian, long and low; it moves like heat-haze.',
    trainingProfile: { major: 'WIS', flaw: 'STR' },
    innate: [{ name: 'Cold Blood', desc: 'Incoming debuffs are 20% weaker.' }, { name: 'Hypnotic Gaze', desc: '+7% accuracy.' }] },
  { id: 'geckari', name: 'Emberimp', body: 'Reptilian', naturalClass: 'Rogue', base: s(30, 40, 18, 8, 16, 20), lifespan: 4, flavour: 'A small ember-orange clinger that scales sheer walls and tests patience alike.',
    trainingProfile: {},
    innate: [{ name: 'Wall Runner', desc: '+6% dodge chance. +2% accuracy.' }, { name: 'Tail Drop', desc: '+10% critical hit chance.' }] },
  { id: 'tortavos', name: 'Mosscap', body: 'Reptilian', naturalClass: 'Spellshield', base: s(8, 12, 44, 36, 22, 14), lifespan: 6, flavour: 'A moss-green domed elder; it carries its house, its history and its patience in one shell.',
    trainingProfile: { major: 'CON', flaw: 'INT' },
    innate: [{ name: 'Shell Ward', desc: 'Starts battle with an 18 HP shield.' }, { name: 'Inner Calm', desc: '+2 mana regen/turn.' }] },

  // --- Draconic (STR / WIS, weakness CHA) — Iron rank exclusive (Special License) ---
  // Body minor WIS (arcane heritage). Authored aptitudes v0.85.
  { id: 'pyraxon', name: 'Pyrodrake', body: 'Draconic', naturalClass: 'Warrior', base: s(42, 20, 36, 20, 16, 10), lifespan: 8, flavour: 'An ember-red dragon that banks the arena in heat; the first row learns to lean back.',
    trainingProfile: { major: 'STR', flaw: 'DEX' }, // heavy-hitting brute, too ponderous to dodge
    innate: [{ name: 'Flame Aura', desc: '8% chance to Burn on every hit.' }, { name: 'Draconic Pride', desc: '+6% damage.' }] },
  { id: 'frostwyren', name: 'Glacidrake', body: 'Draconic', naturalClass: 'Wizard', base: s(22, 22, 20, 30, 44, 6), lifespan: 8, flavour: 'A drake glazed in glacier-blue; frost gathers on the rails when it enters.',
    trainingProfile: { major: 'INT', flaw: 'DEX' }, // still, deliberate spellcaster
    innate: [{ name: 'Blizzard', desc: '6% chance to Stun on every hit.' }, { name: 'Glacial Wisdom', desc: '+2 mana regen/turn. Reduces damage taken by 1 per hit.' }] },
  { id: 'stormlerath', name: 'Voltdrake', body: 'Draconic', naturalClass: 'Ranger', base: s(26, 38, 20, 22, 32, 6), lifespan: 7, flavour: 'A storm-violet dragon; thunder arrives a heartbeat after every wingbeat.',
    trainingProfile: { major: 'DEX', flaw: 'CON' }, // swift striker, glassy
    innate: [{ name: 'Overload', desc: '+7% damage.' }, { name: 'Dodge Storm', desc: '+6% dodge chance. +3% critical hit chance.' }] },
  { id: 'verdantdrake', name: 'Verdrake', body: 'Draconic', naturalClass: 'Sage', base: s(20, 18, 26, 40, 32, 8), lifespan: 9, flavour: 'A verdant-green dragon; the forest\'s answer to a siege.',
    trainingProfile: { major: 'CON', flaw: 'STR' }, // rooted guardian — sturdy, not aggressive (WIS minor carries its Sage side)
    innate: [{ name: 'Life Bloom', desc: 'Team: +2 HP regen/turn. Team: +1 mana regen/turn.' }, { name: 'Root Grasp', desc: 'Enemies: -3% dodge chance. Enemies: -2% accuracy.' }] },
  { id: 'voidmaw', name: 'Voidfiend', body: 'Draconic', naturalClass: 'Wizard', base: s(22, 26, 20, 32, 38, 6), lifespan: 7, flavour: 'A blue-black horned devourer; the mouth is a promise.',
    trainingProfile: { major: 'INT', flaw: 'CON' }, // cosmic caster, survives on Void Pulse lifesteal, not bulk
    innate: [{ name: 'Void Pulse', desc: 'Heals 10% of damage dealt as HP.' }, { name: 'Entropy', desc: 'Enemies: -5% damage dealt.' }] },

  // --- Abyssal (INT / DEX, weakness CON) — Iron rank exclusive (Special License) ---
  // Body minor INT (eldritch intellect). Authored aptitudes v0.85.
  { id: 'tenebrae', name: 'Duskgeist', body: 'Abyssal', naturalClass: 'Rogue', base: s(32, 42, 14, 22, 24, 10), lifespan: 7, flavour: 'A bat-eared shade in deep violet; the light around it gives up early.',
    trainingProfile: { major: 'DEX', flaw: 'CON' }, // hit-and-run assassin, can't turn tanky
    innate: [{ name: 'Cloak of Shadow', desc: '+8% dodge chance.' }, { name: 'Silent Strike', desc: '+40% damage on its first hit. +5% critical hit chance.' }] },
  { id: 'abyssomancer', name: 'Skulgeist', body: 'Abyssal', naturalClass: 'Wizard', base: s(16, 30, 12, 34, 40, 12), lifespan: 8, flavour: 'A drifting night-purple shroud with a bone-white skull for a face; the abyss looks out through its sockets.',
    trainingProfile: { major: 'INT', flaw: 'CON' }, // pure glass-cannon caster
    innate: [{ name: 'Rift Magic', desc: '6% chance to cast a skill twice.' }, { name: 'Mana Theft', desc: 'Steals mana equal to 20% of damage dealt.' }] },
  { id: 'lurkerss', name: 'Morgrel', body: 'Abyssal', naturalClass: 'Sage', base: s(14, 30, 14, 38, 34, 14), lifespan: 8, flavour: 'A green shambler that should not still be moving, and moves anyway; patiently, endlessly.',
    trainingProfile: { major: 'WIS', flaw: 'STR' }, // support-sage, never a fighter (INT minor deepens its casting)
    innate: [{ name: 'Psychic Aura', desc: 'Team: +3% dodge chance. Team: +1 mana regen/turn.' }, { name: 'Ancient Knowing', desc: '+5% dodge chance.' }] },
  { id: 'chrono-leviathan', name: 'Chronotide', body: 'Abyssal', naturalClass: 'Sage', base: s(16, 30, 12, 40, 38, 8), lifespan: 10, flavour: 'An aged-teal titan of the deep whose tentacles move a half-second out of time.',
    trainingProfile: { major: 'WIS', flaw: 'DEX' }, // ancient, ponderous healer — slow but sustains via Age Reversal
    innate: [{ name: 'Temporal Distortion', desc: 'Team: +1 mana regen/turn. Enemies: -4% dodge chance.' }, { name: 'Age Reversal', desc: 'Heals 15% of damage dealt as HP.' }] },
  { id: 'cephalumbra', name: 'Umbratide', body: 'Abyssal', naturalClass: 'Rogue', base: s(32, 46, 12, 20, 24, 10), lifespan: 7, flavour: 'A shadow-violet tentacled thing that pools like ink and strikes from its own darkness.',
    trainingProfile: { major: 'DEX', flaw: 'CON' }, // ghost-swift glass phantom
    innate: [{ name: 'Phase Shift', desc: '+9% dodge chance.' }, { name: 'Whip Strike', desc: 'Ignores 10% of enemy mitigation.' }] },

  // --- Mythical (5 unique archetypes) — Platinum rank exclusive (Elite License) ---
  // Body minor CHA (legendary presence). Authored aptitudes v0.85.
  { id: 'titanrex', name: 'Titanus', body: 'Mythical', naturalClass: 'Warrior', base: s(60, 16, 50, 12, 12, 8), lifespan: 9, flavour: 'The apex bulk of the old world in grey-green plate; the ground files a complaint.',
    trainingProfile: { major: 'STR' }, // legendary — no true weak stat
    innate: [{ name: 'Prehistoric Roar', desc: '+20% damage on its first hit.' }, { name: 'Unstoppable', desc: 'Reduces damage taken by 1 per hit. Incoming debuffs are 15% weaker.' }] },
  { id: 'stellarion', name: 'Stellith', body: 'Mythical', naturalClass: 'Ranger', base: s(10, 52, 10, 32, 44, 10), lifespan: 8, flavour: 'A star-pale visitor with a crown of horns; it watches the way the night sky watches.',
    trainingProfile: { major: 'DEX' }, // legendary — no true weak stat
    innate: [{ name: 'Stellar Shot', desc: '+9% critical hit chance.' }, { name: 'Cosmic Precision', desc: '+10% accuracy.' }] },
  { id: 'wisdomkeeper', name: 'Maskelder', body: 'Mythical', naturalClass: 'Sage', base: s(12, 18, 20, 56, 44, 8), lifespan: 10, flavour: 'A masked elder in ritual paint; the mask is older than the league it fights in.',
    trainingProfile: { major: 'WIS' }, // legendary — no true weak stat
    innate: [{ name: 'Foresight', desc: 'Team: +5% dodge chance.' }, { name: 'Truth\'s Word', desc: 'Reduces damage taken by 1 per hit. Every 3rd round, automatically shrugs off one debuff on itself.' }] },
  { id: 'archmage-aleph', name: 'Magivex', body: 'Mythical', naturalClass: 'Wizard', base: s(8, 20, 14, 40, 58, 18), lifespan: 8, flavour: 'A green-skinned conjurer under a crooked violet hat, first of the old order of arena mages.',
    trainingProfile: { major: 'INT' }, // legendary — no true weak stat
    innate: [{ name: 'Spell Echo', desc: '12% chance to cast a skill twice.' }, { name: 'Arcane Mastery', desc: '+5 mana regen/turn.' }] },
  { id: 'harmonybringer', name: 'Aurelith', body: 'Mythical', naturalClass: 'Bard', base: s(10, 40, 28, 16, 10, 54), lifespan: 9, flavour: 'A radiant gold floater trailing light like a hymn; the crowd hushes when it rises.',
    trainingProfile: { major: 'CHA' }, // legendary — no true weak stat
    innate: [{ name: 'Unison', desc: 'Team: reduces damage taken by 2 per hit.' }, { name: 'Aegis Bond', desc: 'Reduces damage taken by 2 per hit. +2 HP regen/turn.' }] },

  // --- Saurian (5) — FUSION class: Mammal + Reptilian (FUSION_DESIGN.md). Only
  // obtained by fusing a Mammal-body and a Reptilian-body legacy. Dual-major
  // training (two +20% stats per species); the +10% minor / −10% flaw is rolled
  // PER MONSTER at fusion time (Career.bonusMinor/bonusFlaw), not authored here.
  { id: 'grendscale', name: 'Gillbrute', body: 'Saurian', naturalClass: 'Warrior', base: s(40, 18, 36, 12, 10, 14), lifespan: 6, flavour: 'A heavy green bruiser with a gilled, sea-cold stare; half the ocean\'s menace on two legs.',
    trainingProfile: {},
    innate: [{ name: 'Scaled Hide', desc: 'Reduces damage taken by 2 per hit.' }, { name: 'Primal Roar', desc: 'Enemies: -4% damage dealt.' }] },
  { id: 'vipramane', name: 'Venimp', body: 'Saurian', naturalClass: 'Rogue', base: s(30, 38, 20, 12, 14, 12), lifespan: 6, flavour: 'A venom-green sprite; small, quick, and deeply unfair.',
    trainingProfile: {},
    innate: [{ name: 'Serpent\'s Strike', desc: '+35% damage on its first hit. +4% critical hit chance.' }, { name: 'Mane Bristle', desc: '+7% dodge chance.' }] },
  { id: 'thornhide', name: 'Mossbrist', body: 'Saurian', naturalClass: 'Tank', base: s(28, 12, 44, 18, 10, 12), lifespan: 6, flavour: 'A moss-brown bristle-orb; walking into it is the whole argument.',
    trainingProfile: {},
    innate: [{ name: 'Thornplate', desc: 'Enters battle with a 16-point protective ward.' }, { name: 'Ironscale', desc: 'Reduces damage taken by 3 per hit.' }] },
  { id: 'runewyrm', name: 'Runeflight', body: 'Saurian', naturalClass: 'Sage', base: s(16, 16, 20, 36, 32, 12), lifespan: 6, flavour: 'A rune-violet flier; sigils flicker along its wings when it casts.',
    trainingProfile: {},
    innate: [{ name: 'Runic Wisdom', desc: '+2 mana regen/turn.' }, { name: 'Petrifying Gaze', desc: '8% chance to Stun on every hit.' }] },
  { id: 'basilroar', name: 'Embersaur', body: 'Saurian', naturalClass: 'Orator', base: s(22, 18, 20, 26, 12, 34), lifespan: 6, flavour: 'A rust-red saurian whose bellow shakes dust from the stands.',
    trainingProfile: {},
    innate: [{ name: 'Dread Bellow', desc: 'Enemies: -5% accuracy.' }, { name: 'Rally Cry', desc: 'Team: +5% damage.' }] },

  // --- Tempestine (5) — FUSION class: Avian + Aquatic. Feather-and-fin storm
  // creatures. Aptitude-neutral shells (trainingProfile {}) — training is
  // inherited per-monster at fusion. See FUSION_DESIGN.md.
  { id: 'thunderoc', name: 'Stormtalon', body: 'Tempestine', naturalClass: 'Ranger', base: s(24, 38, 16, 12, 26, 10), lifespan: 6, flavour: 'A storm-gold terror of the high thermals; the sky\'s opinion, delivered.',
    trainingProfile: {},
    innate: [{ name: 'Chain Lightning', desc: '8% chance to Stun on every hit.' }, { name: 'Storm Dive', desc: '+35% damage on its first hit.' }] },
  { id: 'galewing', name: 'Galecrest', body: 'Tempestine', naturalClass: 'Rogue', base: s(30, 36, 18, 14, 14, 14), lifespan: 6, flavour: 'A storm-cyan flier that rides its own gusts; the crest snaps like a banner in wind.',
    trainingProfile: {},
    innate: [{ name: 'Wind Veil', desc: '+8% dodge chance.' }, { name: 'Squall', desc: 'Enemies: -3% accuracy.' }] },
  { id: 'tidecaller', name: 'Tidegale', body: 'Tempestine', naturalClass: 'Spellshield', base: s(16, 16, 34, 30, 18, 14), lifespan: 6, flavour: 'A sea-green caller of currents; the tide listens, eventually.',
    trainingProfile: {},
    innate: [{ name: 'Tidal Grace', desc: 'Team: +2 HP regen/turn.' }, { name: 'Deluge', desc: 'Team: +1 mana regen/turn.' }] },
  { id: 'maelstrom', name: 'Vortiqua', body: 'Tempestine', naturalClass: 'Wizard', base: s(14, 20, 16, 30, 38, 10), lifespan: 6, flavour: 'A deep-blue tentacled spiral; the water remembers everywhere it has been.',
    trainingProfile: {},
    innate: [{ name: 'Overcharge', desc: '+7% damage.' }, { name: 'Static Field', desc: '6% chance to cast a skill twice.' }] },
  { id: 'brinehowl', name: 'Brinefiend', body: 'Tempestine', naturalClass: 'Orator', base: s(22, 16, 20, 26, 12, 32), lifespan: 6, flavour: 'A teal-skinned horror from the deep trenches; its howl carries the cold of the sea floor.',
    trainingProfile: {},
    innate: [{ name: 'Gale Cry', desc: 'Enemies: -5% accuracy.' }, { name: 'Rally Squall', desc: 'Team: +5% damage.' }] },

  // --- Broodkin (5) — FUSION class: Marsupial + Insectoid. Pouch-and-chitin
  // brood-carriers. Aptitude-neutral shells; training inherited at fusion.
  { id: 'chitinhop', name: 'Jadewing', body: 'Broodkin', naturalClass: 'Tank', base: s(30, 14, 42, 12, 14, 12), lifespan: 6, flavour: 'A jade-shelled skipper that bounces between blows on quick glassy wings.',
    trainingProfile: {},
    innate: [{ name: 'Carapace', desc: 'Reduces damage taken by 3 per hit.' }, { name: 'Dig In', desc: 'Enters battle with a 14-point protective ward.' }] },
  { id: 'broodmother', name: 'Broodclaw', body: 'Broodkin', naturalClass: 'Sage', base: s(14, 14, 22, 34, 32, 14), lifespan: 6, flavour: 'A plum-shelled matriarch, claws raised over the swarm she carries with her.',
    trainingProfile: {},
    innate: [{ name: 'Brood Tend', desc: 'Team: +2 HP regen/turn.' }, { name: 'Hive Mind', desc: 'Team: +1 mana regen/turn.' }] },
  { id: 'mantiskin', name: 'Huskthorn', body: 'Broodkin', naturalClass: 'Rogue', base: s(32, 36, 18, 12, 16, 10), lifespan: 6, flavour: 'A burnt-orange husk bristling with dried thorns; what it lost in colour it kept in edge.',
    trainingProfile: {},
    innate: [{ name: 'Ambush Fold', desc: '+40% damage on its first hit.' }, { name: 'Blade Arms', desc: '+5% critical hit chance.' }] },
  { id: 'resinback', name: 'Amberling', body: 'Broodkin', naturalClass: 'Spellshield', base: s(24, 12, 38, 26, 14, 12), lifespan: 6, flavour: 'A stone-jointed golem sealed in old amber resin; the carapace remembers the river it held.',
    trainingProfile: {},
    innate: [{ name: 'Resin Plate', desc: 'Reduces damage taken by 2 per hit.' }, { name: 'Amber Set', desc: 'Incoming debuffs are 15% weaker.' }] },
  { id: 'swarmherd', name: 'Swarmel', body: 'Broodkin', naturalClass: 'Bard', base: s(18, 26, 20, 14, 22, 28), lifespan: 6, flavour: 'A green mass that is many things agreeing to be one thing, most of the time.',
    trainingProfile: {},
    innate: [{ name: 'Command Swarm', desc: 'Team: +4% damage.' }, { name: 'Disorient', desc: 'Enemies: -4% dodge chance.' }] },

  // --- Primeval (v0.88, PRESTIGE fusion: Mythical + Draconic/Abyssal) ---
  // First-age titans — the pinnacle fusion line. Aptitude-neutral shells like
  // all fusion bodies (majors are INHERITED per-monster at fusion time).
  { id: 'aeonrex', name: 'Magnos', body: 'Primeval', naturalClass: 'Warrior', base: s(48, 16, 38, 12, 10, 14), lifespan: 8, flavour: 'The elder giant, amber-bright and slow as geology. Every step lands like a verdict.',
    trainingProfile: {},
    innate: [{ name: 'Dawn Fury', desc: '+8% damage.' }, { name: 'Unbroken Age', desc: 'Reduces damage taken by 2 per hit. Incoming debuffs are 20% weaker.' }] },
  { id: 'stellavore', name: 'Vorastra', body: 'Primeval', naturalClass: 'Ranger', base: s(12, 46, 10, 24, 38, 12), lifespan: 8, flavour: 'A devourer in magenta and olive; the horns curl like galaxies going wrong.',
    trainingProfile: {},
    innate: [{ name: 'Starving Aim', desc: '+10% critical hit chance.' }, { name: 'Light Drinker', desc: 'Heals 12% of damage dealt as HP.' }] },
  { id: 'chronoshell', name: 'Bronzecap', body: 'Primeval', naturalClass: 'Spellshield', base: s(24, 10, 46, 34, 16, 12), lifespan: 8, flavour: 'A bronze-domed elder, crowned and unhurried; it has outlasted every clock it was measured against.',
    trainingProfile: {},
    innate: [{ name: 'Era Shell', desc: 'Enters battle with a 20-point protective ward.' }, { name: 'Time Dilation', desc: 'Team: +1 mana regen/turn. Enemies: -4% dodge chance.' }] },
  { id: 'originmage', name: 'Ossari', body: 'Primeval', naturalClass: 'Wizard', base: s(8, 18, 12, 38, 50, 18), lifespan: 8, flavour: 'The first mage, reduced to bone and unwilling to stop; the robes went, the craft stayed.',
    trainingProfile: {},
    innate: [{ name: 'First Spell', desc: '10% chance to cast a skill twice.' }, { name: 'Wellspring Eternal', desc: '+4 mana regen/turn.' }] },
  { id: 'worldsong', name: 'Songlume', body: 'Primeval', naturalClass: 'Bard', base: s(10, 38, 26, 14, 12, 48), lifespan: 8, flavour: 'An ivory radiance in the shape of a spirit; the song given shape, glowing from within.',
    trainingProfile: {},
    innate: [{ name: 'Genesis Chord', desc: 'Team: +5% damage.' }, { name: 'Ending Verse', desc: 'Team: reduces damage taken by 2 per hit.' }] },
]

// --- Body-type average stat profiles (§8.4) ---
// Computed from the species data above so they can never drift from it. Every
// species deviates from its body average — that deviation is its "signature".
export const BODY_AVERAGES: Record<BodyType, Stats> = (() => {
  const out = {} as Record<BodyType, Stats>
  const bodies = [...new Set(SPECIES.map((sp) => sp.body))]
  for (const body of bodies) {
    const members = SPECIES.filter((sp) => sp.body === body)
    const avg = {} as Stats
    for (const k of STATS) avg[k] = Math.round(members.reduce((sum, sp) => sum + sp.base[k], 0) / members.length)
    out[body] = avg
  }
  return out
})()

// A species' stat signature: which stats sit notably above / below its body-type
// average. Returns up to two of each (deviation ≥ 4 counts as notable).
export function bodySignature(base: Stats, body: BodyType): { above: Stat[]; below: Stat[] } {
  const avg = BODY_AVERAGES[body]
  const deltas = STATS.map((st) => ({ st, d: base[st] - avg[st] }))
  const above = deltas.filter((x) => x.d >= 4).sort((a, b) => b.d - a.d).slice(0, 2).map((x) => x.st)
  const below = deltas.filter((x) => x.d <= -4).sort((a, b) => a.d - b.d).slice(0, 2).map((x) => x.st)
  return { above, below }
}

export const SPECIES_BY_ID: Record<string, Species> = Object.fromEntries(SPECIES.map((sp) => [sp.id, sp]))
