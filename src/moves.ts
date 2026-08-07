// The 90-skill shared learned-move pool (§7.5): 15 per stat, each with an explicit
// learn level and mechanical effects (core.ts:MoveEffects — pierce, multi-hit,
// execute, recoil, lifesteal, mana warfare, wards, ROUND-LIMITED buffs/debuffs —
// nothing lasts "for the fight" anymore, everything expires and can be refreshed).
// Big effects are balanced by MP cost (monster.ts:manaCost) and long cooldowns.
//
// Design philosophy per stat (user spec 2026-07-20) — each pool has a distinct
// identity so the stat itself, not just flavour text, determines playstyle:
//   STR: highest raw hits, some recoil (capped 15%), SELF buffs only,
//        one Fire-elemental attack, one Earth-elemental attack
//   DEX: poison + precision, heavy on multi-hit, SELF buffs only,
//        one Air-elemental attack, one Water-elemental attack
//   CON: the ONLY stat that grants shields (ward) or armour (defBuff); taunts
//        (forces targeting — inert until team battles exist); some self-heal;
//        very few party buffs; self-cleanse
//   WIS: heavy mana regen/mana burn; some healing reaches allies, not just
//        self; a few buffs; one party-wide cleanse
//   INT: all four elements represented; mix of AoE and single-target;
//        NO buffs, NO healing — pure elemental damage
//   CHA: party buffs on the user's side, party-wide debuffs on the enemy side
// Values are first-pass and meant for tuning.
//
// Synergy revamp (user spec 2026-07-25, level 120+ ONLY — 40/90 never touched):
// every stat gained setup->payoff combos via bonusVsStatus, most self-contained
// within the stat's own 12 post-90 moves (STR bleed setter+payoff, INT burn
// setter+payoff, WIS doom setter+early-cash, CHA fear setter+payoff), some
// cross-stat (DEX bleed setter/payoff mirrors STR's). AoE-status and "big"
// full-hijack statuses (sleep/charm/doom/silence/fear) were deliberately kept
// LOW probability (15-30%) per that spec; single-target "smaller" statuses
// (bleed/vulnerable) stayed moderate (30-50%). Thunderclap (INT) introduces
// firstStrikeMult — bonus damage if the caster acted before the target this
// round, rewarding speed investment (DEX/haste/knockback) without being a
// status. CON's Bulwark's Challenge (mass taunt, target allEnemies) + Barbed
// Carapace (thorns) is the flagship team-fight combo: force the whole enemy
// side onto one tank, then punish every hit.
import { Move, Stat, StatusKind } from './core'
import { LINE_OF } from './lines'

type Row = Omit<Move, 'id' | 'stat'>

const POOLS: Record<Stat, Row[]> = {
  // ══ STR ══ executes · shouts · rages · dueling · heavy hitting · combos ══════
  // Three lines (src/lines.ts): BLOODRAGE spends HP as a resource · DUELIST sets up
  // and cashes in single targets · WARCRY is shouts — STR's hard CC arrives through
  // the voice, not the blade, which is what stops it overlapping CHA's damage.
  // ⚠️ mana is priced by EFFECTIVENESS, not derived from power: Blood Price costs
  // 10 MP for 30 power because you pay the rest in blood.
  // ⚠️ `variance` is the half-width of the damage range. A duellist lands where it
  // aimed (0.10); a berserker swinging wild does not (0.25-0.35).
  STR: [
    // ── Bloodrage — HP is the resource; you spend life and race the clock ──────
    { name: 'Scrap', learnLevel: 40, type: 'damage', channel: 'melee', target: 'enemy', cooldown: 1.3, accuracy: 95, power: 13, mana: 4, variance: 0.15, range: 3, desc: 'A cheap, scrappy swing — what you throw while the rage builds.' },
    { name: 'Enrage', learnLevel: 120, type: 'buff', channel: 'support', target: 'self', cooldown: 6.5, accuracy: 100, power: 0, mana: 14, effects: { atkBuff: 0.2, duration: 3 }, range: 2.8, desc: 'Works itself into a fury: +20% damage for 3 rounds.' },
    { name: 'Blood Price', learnLevel: 240, type: 'damage', channel: 'melee', target: 'enemy', cooldown: 3.9, accuracy: 90, power: 36, mana: 10, variance: 0.2, effects: { recoil: 0.1 }, range: 2.8, desc: 'Swung with everything, including what it costs you. Cheap in mana because it is paid for in blood.' },
    { name: 'Reckless Slam', learnLevel: 380, type: 'damage', channel: 'melee', target: 'enemy', cooldown: 5.2, accuracy: 85, power: 58, mana: 26, variance: 0.25, effects: { recoil: 0.1 }, range: 2.6, desc: 'A scorching, reckless haymaker; it burns the arm that throws it.' },
    { name: 'Last Stand', learnLevel: 540, type: 'buff', channel: 'support', target: 'self', cooldown: 9.1, accuracy: 100, power: 0, mana: 30, effects: { atkBuff: 0.3, defBuff: 10, duration: 3 }, range: 2.8, desc: 'Digs in and stops retreating: +30% damage and +10 mitigation for 3 rounds.' },
    // ⚠️ hpScale is the ONE effect that already reads the caster's remaining HP,
    // so Blood Fury is the line's payoff ATTACK rather than one more modifier —
    // half damage at full health, more than double on the edge of death.
    { name: 'Blood Fury', learnLevel: 700, type: 'damage', channel: 'melee', target: 'enemy', cooldown: 3.9, accuracy: 88, power: 42, mana: 24, variance: 0.3, effects: { hpScale: { atFull: 0.5, atEmpty: 2.1 } }, range: 2.7, desc: 'Feeble while it is still whole, and terrifying once it is not — this blow feeds on its own wounds.' },
    { name: 'Titanfall', learnLevel: 920, type: 'damage', channel: 'melee', target: 'enemy', cooldown: 7.8, accuracy: 80, power: 117, mana: 52, variance: 0.25, effects: { pierce: 0.3, recoil: 0.15 }, range: 2.5, desc: 'Colossal blow that partly ignores defence; 15% recoil.' },

    // ── Duelist — precision, armour-break, execute; STR's combo line ───────────
    // ⚠️ Power Strike was the game's damage CEILING at lvl 90, which is why nothing
    // above it ever felt like progress. Cut ~20% so the ladder above it can exist.
    { name: 'Power Strike', learnLevel: 90, type: 'damage', channel: 'melee', target: 'enemy', cooldown: 2.6, accuracy: 90, power: 24, mana: 16, variance: 0.1, effects: { recoil: 0.05 }, range: 3.5, desc: 'A heavy, committed blow, thrown exactly where it was aimed.' },
    { name: 'Sunder', learnLevel: 200, type: 'debuff', channel: 'melee', target: 'enemy', cooldown: 3.9, accuracy: 90, power: 15, mana: 14, variance: 0.1, effects: { defDebuff: 12, duration: 3 }, range: 3.6, desc: 'Splits the guard rather than the body: −12 mitigation for 3 rounds. The setup STR never had.' },
    { name: 'Riposte', learnLevel: 260, type: 'buff', channel: 'support', target: 'self', cooldown: 5.2, accuracy: 100, power: 0, mana: 18, effects: { thorns: 10, defBuff: 4, duration: 2 }, range: 3.4, desc: 'Takes the blow to answer it: returns 10 damage on every hit for 2 rounds.' },
    { name: 'Headbutt', learnLevel: 300, type: 'damage', channel: 'melee', target: 'enemy', cooldown: 3.9, accuracy: 90, power: 30, mana: 16, variance: 0.15, status: { kind: 'stun', chance: 30, duration: 1 }, range: 3.4, desc: 'Short, ugly, and it rings their bell.' },
    { name: 'Bonebreaker', learnLevel: 330, type: 'damage', channel: 'melee', target: 'enemy', cooldown: 5.2, accuracy: 85, power: 35, mana: 22, variance: 0.15, effects: { defDebuff: 8, duration: 3 }, status: { kind: 'vulnerable', chance: 45, duration: 2 }, range: 3.3, desc: 'Shatters defence and leaves them open — the opener Executioner is waiting on.' },
    { name: 'Rend', learnLevel: 480, type: 'damage', channel: 'melee', target: 'enemy', cooldown: 3.9, accuracy: 85, power: 31, mana: 18, variance: 0.15, status: { kind: 'bleed', chance: 55, duration: 3 }, range: 3.4, desc: 'Opens a wound that keeps opening. Bleed here; Bonebreaker handles armour.' },
    // ⚠️ THE EARLY DETONATOR FOR BLEED. Bloodletter (lv780) was the ONLY way to
    // cash a bleed, while bleed is applied from lv280 — a 500-level stretch where
    // the status is live and nothing in the game can collect on it. Weaker
    // multiplier than the capstone on purpose (x1.5 vs x2.5): this is the version
    // you combo with, not the one you build toward.
    // ⚠️ Deliberately EARLIER than STR's own bleed applier (Rend, lv480), so its
    // first partner is a DEX ally's Twin Fangs (lv280). Cross-stat by design —
    // the prime/detonate split is a TEAM decision before it is a solo one.
    { name: 'Twist the Knife', learnLevel: 360, type: 'damage', channel: 'melee', target: 'enemy', cooldown: 3.9, accuracy: 92, power: 35, mana: 16, variance: 0.2, effects: { bonusVsStatus: { kind: 'bleed', mult: 1.5, consume: true } }, range: 3.4, desc: 'Finds the wound someone else already opened, and worsens it.' },
    { name: 'Bloodletter', learnLevel: 780, type: 'damage', channel: 'melee', target: 'enemy', cooldown: 6.5, accuracy: 85, power: 17, mana: 30, variance: 0.35, effects: { hits: [3, 5], bonusVsStatus: { kind: 'bleed', mult: 2.5, consume: true } }, range: 3.6, desc: 'A weak flurry, 3–5 strikes — unless the target is Bleeding, and then it drinks the wound.' },
    { name: 'Executioner', learnLevel: 850, type: 'damage', channel: 'melee', target: 'enemy', cooldown: 5.2, accuracy: 90, power: 59, mana: 28, variance: 0.1, effects: { execute: 0.35, bonusVsStatus: { kind: 'vulnerable', mult: 1.8, consume: true } }, range: 3, desc: 'The closing blow: brutal against the weakened, and devastating against the Vulnerable.' },

    // ── Warcry — shouts. STR's hard CC comes through the voice ────────────────
    { name: 'Guard', learnLevel: 40, type: 'buff', channel: 'support', target: 'self', cooldown: 3.9, accuracy: 100, power: 0, mana: 6, effects: { guard: 8 }, range: 6.5, desc: 'Brace against the next hits.' },
    { name: 'Cleave', learnLevel: 160, type: 'damage', channel: 'melee', target: 'allEnemies', cooldown: 3.9, accuracy: 85, power: 28, mana: 22, variance: 0.2, range: 4.9, desc: 'A horizontal sweep through everything in front of it — weak into one body, brutal into three.' },
    { name: 'Intimidate', learnLevel: 220, type: 'debuff', channel: 'voice', target: 'allEnemies', cooldown: 6.5, accuracy: 95, power: 0, mana: 20, effects: { atkDebuff: 0.1, duration: 2 }, status: { kind: 'fear', chance: 35, duration: 2 }, range: 5.5, desc: 'A roar with a body behind it: the nearest of them break and run.' },
    { name: 'Challenge', learnLevel: 400, type: 'debuff', channel: 'voice', target: 'enemy', cooldown: 5.2, accuracy: 100, power: 0, mana: 16, effects: { tauntForce: true, atkDebuff: 0.12, duration: 3 }, range: 6.5, desc: 'Singles one out and dares it. It comes for you, and it swings softer for the insult.' },
    { name: 'Bracer', learnLevel: 560, type: 'buff', channel: 'support', target: 'self', cooldown: 5.2, accuracy: 100, power: 0, mana: 20, effects: { guard: 14 }, range: 6.5, desc: 'A hard defensive set — Guard is the cheap answer, this is the committed one.' },
    { name: 'Whirlwind', learnLevel: 600, type: 'damage', channel: 'melee', target: 'allEnemies', cooldown: 5.2, accuracy: 88, power: 47, mana: 34, variance: 0.2, range: 4.9, desc: 'Spins through everything within reach. Pure volume, no rider.' },
    { name: 'Earthshaker', learnLevel: 650, type: 'damage', channel: 'melee', target: 'allEnemies', cooldown: 6.5, accuracy: 80, power: 61, mana: 40, variance: 0.25, status: { kind: 'stun', chance: 30, duration: 1 }, range: 4.9, desc: 'A shockwave that fells whatever is standing near it.' },
    { name: "Warlord's Roar", learnLevel: 820, type: 'buff', channel: 'support', target: 'team', cooldown: 7.8, accuracy: 100, power: 0, mana: 44, effects: { atkBuff: 0.18, accBuff: 6, duration: 3 }, range: 6.5, desc: "STR's one team buff, and of course it is a shout: the whole line hits harder and truer for 3 rounds." },
  ],
  // ══ DEX ══ buildup · poisons · stealths · ranged · volleys · multishots ══════
  // ASSASSIN is stealth -> burst -> vanish, where each piece needs the one before
  // it. VENOMCRAFT builds poison up and then cashes it in. VOLLEY is volume and
  // variance — it owns the widest damage ranges in the game, which is DEX's
  // "gambler" identity expressed mechanically instead of in flavour text.
  DEX: [
    // ── Assassin — stealth, reach the back line, kill one thing, leave ────────
    { name: 'Shadowstep', learnLevel: 120, type: 'damage', channel: 'ranged', target: 'enemy', cooldown: 5.2, accuracy: 92, power: 42, mana: 16, variance: 0.15, range: 2.8, desc: 'Steps through the shadow behind them. The only reliable way past a front line.' },
    { name: 'Ambush', learnLevel: 200, type: 'damage', channel: 'ranged', target: 'enemy', cooldown: 3.9, accuracy: 92, power: 39, mana: 18, variance: 0.2, effects: { firstStrikeMult: 1.5 }, range: 2.8, desc: 'Devastating on someone who has not swung yet — worthless once they have seen you.' },
    { name: 'Vanish', learnLevel: 300, type: 'buff', channel: 'support', target: 'self', cooldown: 7.8, accuracy: 100, power: 0, mana: 22, effects: { dodgeBuff: 20, duration: 2 }, range: 2.8, desc: 'Gone. Attackers lose interest and swing at whoever is left.' },
    { name: 'Smoke Bomb', learnLevel: 340, type: 'debuff', channel: 'ranged', target: 'allEnemies', cooldown: 6.5, accuracy: 100, power: 0, mana: 20, effects: { accDebuff: 14, duration: 2 }, status: { kind: 'blind', chance: 50, duration: 2 }, range: 2.4, desc: 'Blinds everything close and covers the exit — the setup Ambush wants.' },
    { name: 'Hamstring', learnLevel: 420, type: 'damage', channel: 'ranged', target: 'enemy', cooldown: 3.9, accuracy: 90, power: 47, mana: 16, variance: 0.15, range: 2.7, desc: 'Cuts the leg out from under them. They keep fighting; they stop leaving.' },
    { name: 'Throat Cut', learnLevel: 600, type: 'damage', channel: 'ranged', target: 'enemy', cooldown: 6.5, accuracy: 90, power: 74, mana: 30, variance: 0.1, status: { kind: 'silence', chance: 55, duration: 2 }, range: 2.5, desc: 'Quiet, precise, and it ends the casting. What the Assassin line exists to do.' },
    { name: 'Heartseeker', learnLevel: 850, type: 'damage', channel: 'ranged', target: 'enemy', cooldown: 5.2, accuracy: 92, power: 36, mana: 26, variance: 0.3, effects: { hits: [2, 3], execute: 0.35 }, range: 2.8, desc: 'Two or three finding strikes, lethal against anything already failing.' },

    // ── Venomcraft — put poison on, keep it there, then detonate it ───────────
    { name: 'Piercing Shot', learnLevel: 90, type: 'damage', channel: 'ranged', target: 'enemy', cooldown: 2.6, accuracy: 90, power: 17, mana: 14, variance: 0.2, effects: { hits: [1, 2], spreadStatus: { kind: 'poison', targets: 1, chance: 20 } }, status: { kind: 'poison', chance: 45, duration: 3 }, range: 9, desc: 'One or two venom-tipped shots, and the venom may pass to a neighbour.' },
    { name: 'Toxin Stack', learnLevel: 180, type: 'damage', channel: 'ranged', target: 'enemy', cooldown: 2.6, accuracy: 92, power: 27, mana: 10, variance: 0.15, status: { kind: 'poison', chance: 70, duration: 4 }, range: 8.9, desc: 'A cheap second dose. Poison is the point; the dart barely matters.' },
    // ⚠️ THE EARLY DETONATOR FOR POISON, and the biggest hole in the combo game.
    // Poison is the MOST APPLIED status in the pool (1228 casts, 9.8% of all
    // casts at mid tier) and its only payoff was Virulence at lv560 — above what
    // a mid-game monster can learn at all. The status a player sees most was the
    // one they could never cash.
    // ⚠️ x1.5 against Virulence's x2.6, and it sits after both cheap appliers
    // (Piercing Shot lv90, Toxin Stack lv180) so Venomcraft can finally close its
    // own loop without waiting for Masters.
    { name: 'Fester', learnLevel: 220, type: 'damage', channel: 'ranged', target: 'enemy', cooldown: 2.6, accuracy: 92, power: 28, mana: 8, variance: 0.2, effects: { bonusVsStatus: { kind: 'poison', mult: 1.5, consume: true } }, range: 9.2, desc: 'Digs at a poisoned wound until the venom does the rest.' },
    { name: 'Twin Fangs', learnLevel: 280, type: 'damage', channel: 'ranged', target: 'enemy', cooldown: 2.6, accuracy: 90, power: 17, mana: 14, variance: 0.25, effects: { hits: [2, 2] }, status: { kind: 'bleed', chance: 35, duration: 3 }, range: 9, desc: 'Two quick shots that open a wound — bleed here, poison everywhere else in the line.' },
    { name: 'Paralytic Dart', learnLevel: 400, type: 'damage', channel: 'ranged', target: 'enemy', cooldown: 5.2, accuracy: 90, power: 53, mana: 22, variance: 0.15, status: { kind: 'stun', chance: 35, duration: 1 }, range: 8.3, desc: "DEX's one hard control: a neurotoxin that drops them where they stand." },
    { name: 'Virulence', learnLevel: 560, type: 'damage', channel: 'ranged', target: 'enemy', cooldown: 6.5, accuracy: 90, power: 52, mana: 20, variance: 0.2, effects: { bonusVsStatus: { kind: 'poison', mult: 2.6, consume: true } }, range: 8.4, desc: 'Feeble on clean blood, ruinous on poisoned — the payoff the whole line builds toward.' },
    { name: 'Plague Shot', learnLevel: 740, type: 'damage', channel: 'ranged', target: 'allEnemies', cooldown: 6.5, accuracy: 85, power: 45, mana: 34, variance: 0.2, effects: { spreadStatus: { kind: 'poison', targets: 2, chance: 40 } }, status: { kind: 'poison', chance: 55, duration: 4 }, range: 7.2, desc: 'Poison that jumps between bodies. It rewards an enemy that stands together.' },

    // ── Volley — volume and variance. The widest damage ranges in the game ────
    { name: 'Sling', learnLevel: 40, type: 'damage', channel: 'ranged', target: 'enemy', cooldown: 1.3, accuracy: 95, power: 13, mana: 5, variance: 0.3, effects: { hits: [1, 2] }, range: 11, desc: 'One or two quick shots. Cheap enough to throw all day.' },
    { name: 'Sidestep', learnLevel: 40, type: 'buff', channel: 'support', target: 'self', cooldown: 5.2, accuracy: 100, power: 0, mana: 8, effects: { dodgeBuff: 14, duration: 2 }, range: 10.5, desc: 'Footwork. Small, cheap, and always available.' },
    { name: 'Acrobatics', learnLevel: 160, type: 'buff', channel: 'support', target: 'self', cooldown: 5.2, accuracy: 100, power: 0, mana: 12, effects: { dodgeBuff: 30, duration: 1 }, range: 10.5, desc: 'A tumbling, weaving burst — almost untouchable, but only for a moment.' },
    { name: 'Focus Aim', learnLevel: 240, type: 'buff', channel: 'support', target: 'self', cooldown: 6.5, accuracy: 100, power: 0, mana: 14, effects: { accBuff: 18, duration: 3 }, range: 10.5, desc: 'Steadies the breathing. The gambler choosing, briefly, not to gamble.' },
    { name: 'Pin Down', learnLevel: 330, type: 'damage', channel: 'ranged', target: 'enemy', cooldown: 3.9, accuracy: 88, power: 40, mana: 18, variance: 0.15, range: 10, desc: 'Suppressing fire that drags them out of position and holds them there.' },
    // ⚠️ The widest range in the game — 1 to 6 hits AND a 0.5 spread on top. This
    // is the DEX identity as a single move: it can whiff or it can delete someone.
    { name: "Gambler's Volley", learnLevel: 470, type: 'damage', channel: 'ranged', target: 'enemy', cooldown: 3.9, accuracy: 85, power: 10, mana: 20, variance: 0.5, effects: { hits: [1, 6] }, range: 11, desc: 'Everything in the quiver, all at once, aimed roughly. Anywhere from a scratch to a slaughter.' },
    { name: 'Ricochet', learnLevel: 500, type: 'damage', channel: 'ranged', target: 'allEnemies', cooldown: 5.2, accuracy: 88, power: 34, mana: 26, variance: 0.3, effects: { hits: [1, 2] }, range: 8.9, desc: 'One shot, several bodies. It bounces, and it does not much care whose.' },
    { name: 'Rain of Arrows', learnLevel: 650, type: 'damage', channel: 'ranged', target: 'allEnemies', cooldown: 6.5, accuracy: 85, power: 52, mana: 34, variance: 0.25, range: 8.4, desc: 'A bombardment onto a chosen patch of ground — it punishes standing together.' },
    { name: 'Pinning Volley', learnLevel: 680, type: 'damage', channel: 'ranged', target: 'allEnemies', cooldown: 6.5, accuracy: 88, power: 48, mana: 32, variance: 0.2, range: 8.5, desc: 'Nails several of them to the spot at once.' },
    // ⚠️ The lowest variance in the game (0.05), and deliberately so: the capstone
    // marksman is where the gambler finally stops gambling.
    { name: 'Deadeye', learnLevel: 920, type: 'damage', channel: 'ranged', target: 'enemy', cooldown: 7.8, accuracy: 95, power: 131, mana: 44, variance: 0.05, range: 9.2, desc: 'One shot. It goes exactly where it was sent.' },
  ],
  // ══ CON ══ obstacles · mass taunt · redirecting damage · prevention · shields ═
  // WARDEN decides the geometry — zones, roots, ground you cannot cross. GUARDIAN
  // points its protection OUTWARD (taunt, cover an ally, team wards). BULWARK is
  // self-shielding and the conditional damage that comes with being unbroken.
  //
  // ⚠️ CON is a SUPPORT stat, not a damage stat: its 9 damage moves are nearly all
  // conditional on momentum, remaining HP, or holding someone in place.
  // ⚠️ Its buff count came DOWN this pass (12 -> 9) and its control went UP, per
  // the framework: buffs belong to CHA/WIS. CON protects; it does not empower.
  // ⚠️ CON is the only stat with NO hard CC by design — all ten of its control
  // effects are soft (roots, slows, shoves). Geometry, not lockout.
  CON: [
    // ── Warden — own the ground; nobody crosses, nobody leaves ───────────────
    { name: 'Body Slam', learnLevel: 140, type: 'damage', channel: 'melee', target: 'enemy', cooldown: 2.6, accuracy: 90, power: 17, mana: 14, variance: 0.2, status: { kind: 'knockback', chance: 45, duration: 2 }, range: 3, desc: 'Throws its bulk into them and sends them reeling.' },
    { name: 'Seize', learnLevel: 160, type: 'damage', channel: 'melee', target: 'enemy', cooldown: 3.9, accuracy: 90, power: 26, mana: 14, variance: 0.15, range: 3, desc: 'Clamps on and hauls them in. They can still fight; they cannot leave.' },
    { name: 'Shield Wall', learnLevel: 240, type: 'control', channel: 'support', target: 'self', cooldown: 7.8, accuracy: 100, power: 0, mana: 30, effects: { guard: 14 }, range: 3, desc: 'Plants a wall and holds it: +14 mitigation, and the ground around it becomes a slog.' },
    { name: 'Quagmire Stomp', learnLevel: 300, type: 'damage', channel: 'melee', target: 'allEnemies', cooldown: 6.5, accuracy: 85, power: 21, mana: 30, variance: 0.2, status: { kind: 'knockback', chance: 45, duration: 2 }, range: 2.5, desc: 'Churns the footing out from under the whole line.' },
    { name: 'Barricade', learnLevel: 380, type: 'control', channel: 'support', target: 'self', cooldown: 7.8, accuracy: 100, power: 0, mana: 26, effects: { defBuff: 8, duration: 3 }, range: 3, desc: 'Throws up cover and settles in behind it — the crossing in front becomes slow and costly.' },
    { name: 'Tremor', learnLevel: 460, type: 'damage', channel: 'melee', target: 'allEnemies', cooldown: 5.2, accuracy: 88, power: 17, mana: 28, variance: 0.2, range: 2.5, desc: 'The ground shudders. Everything nearby is slowed and staggered.' },
    { name: 'Zone of Control', learnLevel: 520, type: 'control', channel: 'support', target: 'self', cooldown: 6.5, accuracy: 100, power: 0, mana: 28, effects: { thorns: 6, duration: 4 }, range: 3, desc: 'Nothing moves well beside it, and everything that tries gets clipped.' },
    { name: 'Crushing Grip', learnLevel: 620, type: 'damage', channel: 'melee', target: 'enemy', cooldown: 5.2, accuracy: 90, power: 31, mana: 26, variance: 0.15, range: 2.7, desc: 'Takes hold and squeezes. It is not going anywhere while this lasts.' },
    { name: 'Earthen Grasp', learnLevel: 700, type: 'damage', channel: 'melee', target: 'allEnemies', cooldown: 7.8, accuracy: 85, power: 23, mana: 36, variance: 0.15, range: 2.5, desc: 'Stone closes on every ankle in reach. The Warden capstone: nobody leaves.' },

    // ── Guardian — protection pointed OUTWARD, at somebody else ──────────────
    { name: 'Taunt', learnLevel: 90, type: 'debuff', channel: 'support', target: 'enemy', cooldown: 5.2, accuracy: 100, power: 0, mana: 10, effects: { atkDebuff: 0.1, duration: 3, tauntForce: true }, range: 4.5, desc: 'Enrages one of them into coming for you, and swinging softer for it.' },
    { name: 'Barbed Carapace', learnLevel: 120, type: 'buff', channel: 'support', target: 'team', cooldown: 6.5, accuracy: 100, power: 0, mana: 24, effects: { defBuff: 4, thorns: 6, duration: 3 }, range: 6, desc: 'The whole line bristles: +4 mitigation and 6 damage returned on every hit.' },
    { name: 'Steady Vigil', learnLevel: 200, type: 'buff', channel: 'support', target: 'ally', cooldown: 5.2, accuracy: 100, power: 18, mana: 18, effects: { hpRegenBuff: 7, duration: 3 }, range: 6, desc: 'Stands over a wounded ally: heals, then keeps healing.' },
    { name: 'Interpose', learnLevel: 340, type: 'buff', channel: 'support', target: 'ally', cooldown: 6.5, accuracy: 100, power: 0, mana: 24, effects: { ward: 34, defBuff: 8, duration: 3 }, range: 6, desc: 'Steps in front of an ally: a 34 HP shield and +8 mitigation, put where it is needed rather than kept.' },
    { name: "Bulwark's Challenge", learnLevel: 650, type: 'debuff', channel: 'support', target: 'allEnemies', cooldown: 7.8, accuracy: 100, power: 0, mana: 40, effects: { guard: 20, tauntForce: true, duration: 2 }, range: 3.8, desc: 'Plants its feet and roars: massive guard, and the WHOLE enemy team comes for it.' },
    { name: 'Aegis of the Fallen', learnLevel: 760, type: 'buff', channel: 'support', target: 'team', cooldown: 9.1, accuracy: 100, power: 0, mana: 48, effects: { ward: 45, defBuff: 6, duration: 3 }, range: 6, desc: 'A shield over every ally at once — 45 HP of absorb each, and armour under it.' },

    // ── Bulwark — self-shielding, and damage conditional on being unbroken ───
    { name: 'Brace', learnLevel: 40, type: 'buff', channel: 'support', target: 'self', cooldown: 2.6, accuracy: 100, power: 0, mana: 5, effects: { guard: 6 }, range: 3, desc: 'Small, cheap, always there.' },
    { name: 'Bastion', learnLevel: 240, type: 'buff', channel: 'support', target: 'self', cooldown: 5.2, accuracy: 100, power: 0, mana: 16, effects: { ward: 25 }, range: 3, desc: 'Raise a 25 HP absorb shield. Fortify is the version for everyone else.' },
    { name: 'Overrun', learnLevel: 280, type: 'damage', channel: 'melee', target: 'enemy', cooldown: 3.9, accuracy: 88, power: 22, mana: 18, variance: 0.2, status: { kind: 'knockback', chance: 40, duration: 2 }, range: 3, desc: 'Charges straight through: damage and a shove, paid for with momentum.' },
    { name: 'Shell Slam', learnLevel: 380, type: 'damage', channel: 'melee', target: 'enemy', cooldown: 3.9, accuracy: 85, power: 26, mana: 22, variance: 0.2, effects: { recoil: 0.1, hpScale: { atFull: 1.4, atEmpty: 0.8 } }, range: 2.9, desc: 'Hits hardest while the shell is whole, and fades as its own health fails.' },
    { name: 'Fortify', learnLevel: 430, type: 'buff', channel: 'support', target: 'team', cooldown: 6.5, accuracy: 100, power: 0, mana: 44, effects: { ward: 40 }, range: 4.1, desc: 'A 40 HP absorb shield on every ally. Uncapped reach, priced in mana.' },
    { name: 'Retaliate', learnLevel: 600, type: 'buff', channel: 'support', target: 'self', cooldown: 5.2, accuracy: 100, power: 0, mana: 22, effects: { thorns: 16, defBuff: 6, duration: 2 }, range: 3, desc: 'Answers everything: 16 damage returned per hit for 2 rounds.' },
    { name: 'Vital Surge', learnLevel: 780, type: 'buff', channel: 'support', target: 'self', cooldown: 7.8, accuracy: 100, power: 46, mana: 34, effects: { cleanse: true }, range: 2.6, desc: 'Shrugs it all off and knits shut. CON heals ITSELF; healing others is WIS.' },
    { name: 'Colossus Crash', learnLevel: 850, type: 'damage', channel: 'melee', target: 'enemy', cooldown: 6.5, accuracy: 85, power: 26, mana: 32, variance: 0.2, effects: { guard: 10, maxHpDmg: 0.03, consumeWard: 0.015 }, range: 2.7, desc: 'A crushing advance that braces after the blow; the bigger they are, the more it takes.' },
  ],
  // ══ WIS ══ resource buffer & stealer · lifesteal · manasteal · THE healer ════
  // DISRUPTOR denies resources — silence, doom, mana burn, until the enemy simply
  // never casts. MENDER is the only real team healing in the game. SIPHON takes
  // what they have and keeps it.
  //
  // ⚠️ WIS is the ONLY stat that can heal ANOTHER monster. CON heals itself,
  // nobody else does at all. Mend and Clarity target an ALLY for that reason.
  // ⚠️ Its buffs came down and its damage went up this pass (4 -> 9): restoration
  // and denial are its identity, but it needed to be able to threaten something.
  WIS: [
    // ── Disruptor — resource denial; the enemy never gets to cast ────────────
    { name: 'Silencing Spike', learnLevel: 200, type: 'damage', channel: 'support', target: 'enemy', cooldown: 2.6, accuracy: 90, power: 17, mana: 18, variance: 0.15, effects: { manaBurn: 13 }, status: { kind: 'silence', chance: 30, duration: 2 }, range: 6.2, desc: 'A psychic jab that drinks 13 MP and can close the throat entirely.' },
    { name: 'Wither', learnLevel: 300, type: 'damage', channel: 'support', target: 'enemy', cooldown: 5.2, accuracy: 90, power: 21, mana: 20, variance: 0.15, effects: { lifesteal: 0.25, manaBurn: 10 }, range: 6.2, desc: 'Saps them round on round and feeds you what it takes.' },
    { name: 'Null Field', learnLevel: 320, type: 'control', channel: 'support', target: 'self', cooldown: 7.8, accuracy: 100, power: 0, mana: 34, effects: { regenBuff: 3, duration: 4 }, range: 7, desc: 'A patch of dead air. Nothing casts well inside it, including what walks in.' },
    { name: 'Enfeeble', learnLevel: 330, type: 'debuff', channel: 'support', target: 'enemy', cooldown: 5.2, accuracy: 95, power: 0, mana: 22, effects: { atkDebuff: 0.2, accDebuff: 12, duration: 3 }, range: 7, desc: 'They hit softer and they miss more. The Disruptor pressure debuff.' },
    { name: 'Hush', learnLevel: 420, type: 'control', channel: 'support', target: 'enemy', cooldown: 5.2, accuracy: 95, power: 0, mana: 18, status: { kind: 'silence', chance: 75, duration: 3 }, range: 7, desc: 'No damage, no flourish — just silence, reliably, for three rounds.' },
    { name: 'Field of Doom', learnLevel: 540, type: 'debuff', channel: 'support', target: 'enemy', cooldown: 6.5, accuracy: 95, power: 0, mana: 26, effects: { atkDebuff: 0.15, duration: 3 }, status: { kind: 'doom', chance: 32, duration: 4 }, range: 7, desc: 'A dampening field, and a clock. Mind Crush knows what to do with the clock.' },
    { name: 'Dread Whisper', learnLevel: 700, type: 'debuff', channel: 'support', target: 'enemy', cooldown: 6.5, accuracy: 95, power: 0, mana: 28, status: { kind: 'fear', chance: 60, duration: 2 }, range: 7, desc: "WIS's one hard control: a word in the ear, and they run." },
    { name: 'Mind Crush', learnLevel: 780, type: 'damage', channel: 'support', target: 'enemy', cooldown: 6.5, accuracy: 85, power: 46, mana: 34, variance: 0.15, effects: { manaBurn: 25, bonusVsStatus: { kind: 'doom', mult: 1.8, consume: true } }, range: 6.2, desc: 'A heavy psychic blow that detonates their Doom early. The payoff.' },

    // ── Mender — the only real team healing in the game ──────────────────────
    { name: 'Mend', learnLevel: 40, type: 'buff', channel: 'support', target: 'ally', cooldown: 3.9, accuracy: 100, power: 15, mana: 8, range: 8.2, desc: 'Soothing focus, given to somebody else. WIS is the only stat that can.' },
    { name: 'Clarity', learnLevel: 120, type: 'buff', channel: 'support', target: 'ally', cooldown: 3.9, accuracy: 100, power: 0, mana: 12, effects: { cleanse: true }, range: 8, desc: "Clears an ally's head — confusion, charm, fear, all of it." },
    { name: 'Renewal', learnLevel: 260, type: 'buff', channel: 'support', target: 'ally', cooldown: 5.2, accuracy: 100, power: 11, mana: 18, effects: { hpRegenBuff: 10, duration: 4 }, range: 8.5, desc: 'Not a burst but a tide: 8 HP a round for four rounds.' },
    { name: 'Tranquility', learnLevel: 320, type: 'buff', channel: 'support', target: 'ally', cooldown: 6.5, accuracy: 100, power: 74, mana: 26, range: 7.3, desc: 'Deep restorative calm channelled into one ally.' },
    { name: 'Rebuke', learnLevel: 560, type: 'damage', channel: 'support', target: 'enemy', cooldown: 5.2, accuracy: 90, power: 34, mana: 24, variance: 0.2, range: 7.2, desc: 'The healer answers back. A mender is not the same thing as a bystander.' },
    { name: 'Ward Against Ruin', learnLevel: 650, type: 'buff', channel: 'support', target: 'team', cooldown: 9.1, accuracy: 100, power: 24, mana: 34, effects: { defBuff: 8, regenBuff: 3, duration: 3 }, range: 8, desc: "Hardens the whole team against what is coming — 8% less damage taken, and a little mending with it." },

    // ── Siphon — take what they have, and keep it ────────────────────────────
    { name: 'Mana Sap', learnLevel: 90, type: 'damage', channel: 'support', target: 'enemy', cooldown: 2.6, accuracy: 92, power: 15, mana: 8, variance: 0.15, effects: { manaBurn: 14 }, range: 6.6, desc: 'Drinks 14 MP straight out of them. Once the worst move in the game; now a real theft.' },
    { name: 'Mind Spike', learnLevel: 140, type: 'damage', channel: 'support', target: 'enemy', cooldown: 2.6, accuracy: 92, power: 17, mana: 8, variance: 0.15, range: 6.5, desc: 'A cheap psychic jab — the filler WIS never had and could never afford.' },
    { name: 'Serenity', learnLevel: 160, type: 'buff', channel: 'support', target: 'self', cooldown: 6.5, accuracy: 100, power: 0, mana: 12, effects: { regenBuff: 4, dodgeBuff: 8, duration: 3 }, range: 6.5, desc: 'Calm flow. The one self-regen — the other three were the same move wearing hats.' },
    { name: 'Attunement', learnLevel: 240, type: 'buff', channel: 'support', target: 'team', cooldown: 5.2, accuracy: 100, power: 0, mana: 30, effects: { regenBuff: 4, duration: 3 }, range: 6.5, desc: "Links the team's focus: everyone regains mana faster. Distinct from Serenity by REACH." },
    { name: 'Drain Spirit', learnLevel: 380, type: 'damage', channel: 'support', target: 'enemy', cooldown: 5.2, accuracy: 88, power: 27, mana: 20, variance: 0.15, effects: { manaBurn: 15, lifesteal: 0.35 }, range: 6.1, desc: 'Takes both at once — their mana, and a share of their blood.' },
    { name: 'Spirit Siphon', learnLevel: 600, type: 'damage', channel: 'support', target: 'enemy', cooldown: 6.5, accuracy: 88, power: 40, mana: 30, variance: 0.2, effects: { manaBurn: 20, lifesteal: 0.4 }, range: 5.7, desc: 'Holds on and drains, HP and MP together, for as long as it lasts.' },
    { name: 'Judgement', learnLevel: 820, type: 'damage', channel: 'support', target: 'enemy', cooldown: 7.8, accuracy: 88, power: 60, mana: 38, variance: 0.2, range: 5.7, desc: 'A real capstone HIT rather than one more aura. WIS can end things too.' },
    // ⚠️ THE FIRST REAL DIRECT HEAL. `type: 'buff'` is not a hedge — there is no
    // 'heal' MoveType; the engine heals on `friendly && power > 0`, so `power` IS
    // the restored amount. Every existing restore pairs a token direct heal
    // (Renewal 8, Providence 12, Steady Vigil 20) with an hpRegenBuff, which is a
    // tide rather than a burst, and a tide cannot answer burst — it pays out
    // after the blow that would have killed you. This is the save.
    // Priced accordingly: the biggest single number WIS has, a 6s cooldown and
    // 34 MP, so it is one answer per fight rather than a wall.
    // ⚠️ learnLevel 300, NOT 400. PRICE THE UNLOCK AT WHAT THE CLASS ACTUALLY
    // TRAINS TO. WIS-primary monsters measure median 281 / p90 355, so 400 sat
    // ABOVE the ceiling: 1 of 51 support-class monsters could learn it and the
    // ability effectively did not exist. The drafting was never at fault — the
    // one monster that could learn it did draft it. 300 clears the median and
    // leaves it a real mid-game unlock. Renewal (260) is the peer that works.
    { name: 'Mending Surge', learnLevel: 300, type: 'buff', channel: 'support', target: 'ally', cooldown: 7.8, accuracy: 100, power: 97, mana: 34, range: 8.0, desc: 'A flood of restoration into one body — the burst answer to burst.' },
    { name: 'Providence', learnLevel: 850, type: 'buff', channel: 'support', target: 'team', cooldown: 9.1, accuracy: 100, power: 18, mana: 40, effects: { cleanse: true, hpRegenBuff: 10, duration: 3 }, range: 6.8, desc: 'Sees what is coming: clears the team and steadies it. Restoration — empowerment is CHA.' },
  ],
  // ══ INT ══ magic · elements · ground AoE + stun · frost root/slow · teleports ═
  // HEXER stacks statuses and then detonates them. ELEMENTALIST makes ground you
  // cannot stand on. ARCANIST moves things — itself, or them — and hits precisely.
  //
  // ⚠️ INT had SEVENTEEN damage moves and ZERO debuffs. It is a damage stat, but
  // the framework puts debuffs in CHA/WIS/INT, and a Wizard with nothing but bolts
  // has no way to play except "cast the biggest number". Now 3 debuffs and 2
  // controls, and the Hexer line has an actual loop.
  INT: [
    // ── Hexer — put it on, keep it on, then cash it in ───────────────────────
    { name: 'Ember', learnLevel: 40, type: 'damage', channel: 'magic', target: 'enemy', cooldown: 2.6, accuracy: 90, power: 14, mana: 6, variance: 0.2, status: { kind: 'burn', chance: 45, duration: 3 }, range: 7.9, desc: 'Minor fire, and it catches. The cheapest way to start a stack.' },
    { name: 'Fracturing Stones', learnLevel: 120, type: 'damage', channel: 'magic', target: 'enemy', cooldown: 2.6, accuracy: 90, power: 24, mana: 14, variance: 0.2, status: { kind: 'vulnerable', chance: 40, duration: 3 }, range: 7.5, desc: 'A stinging barrage that cracks the guard. The second stack type.' },
    { name: 'Cinderburst', learnLevel: 200, type: 'damage', channel: 'magic', target: 'enemy', cooldown: 3.9, accuracy: 88, power: 37, mana: 20, variance: 0.15, effects: { bonusVsStatus: { kind: 'burn', mult: 1.6, consume: true } }, range: 7, desc: 'Solid on its own, and it snuffs a Burn for far more. The first detonator.' },
    { name: 'Sap Will', learnLevel: 280, type: 'debuff', channel: 'magic', target: 'enemy', cooldown: 5.2, accuracy: 95, power: 0, mana: 18, effects: { atkDebuff: 0.22, duration: 3 }, range: 7.5, desc: 'Drains the will to strike: −22% damage for 3 rounds. INT could not do this at all before.' },
    { name: 'Arcane Bomb', learnLevel: 340, type: 'damage', channel: 'magic', target: 'enemy', cooldown: 5.2, accuracy: 88, power: 37, mana: 26, variance: 0.2, effects: { bonusVsStatus: { kind: 'vulnerable', mult: 1.7, consume: true } }, range: 6.6, desc: 'A charge left ticking on them — devastating on anything already cracked open.' },
    { name: 'Curse of Ruin', learnLevel: 480, type: 'debuff', channel: 'magic', target: 'enemy', cooldown: 6.5, accuracy: 95, power: 0, mana: 24, effects: { defDebuff: 14, duration: 3 }, range: 7.5, desc: 'Unpicks whatever is holding them together: −14 mitigation from EVERY source of damage.' },
    { name: 'Detonate', learnLevel: 700, type: 'damage', channel: 'magic', target: 'allEnemies', cooldown: 6.5, accuracy: 85, power: 51, mana: 38, variance: 0.25, effects: { bonusVsStatus: { kind: 'burn', mult: 2.0, consume: true } }, range: 5.6, desc: 'Sets off everything still burning, on everyone at once. The Hexer capstone.' },

    // ── Elementalist — ground you cannot stand on ────────────────────────────
    { name: 'Frost Shard', learnLevel: 90, type: 'damage', channel: 'magic', target: 'enemy', cooldown: 2.6, accuracy: 90, power: 23, mana: 12, variance: 0.2, range: 8.3, desc: 'An icy dart. The frost line opens here.' },
    { name: 'Rime Bind', learnLevel: 160, type: 'damage', channel: 'magic', target: 'enemy', cooldown: 3.9, accuracy: 90, power: 34, mana: 16, variance: 0.15, range: 8, desc: 'Ice climbs the legs and sets. It can still cast; it is going nowhere.' },
    { name: 'Frost Nova', learnLevel: 280, type: 'damage', channel: 'magic', target: 'allEnemies', cooldown: 5.2, accuracy: 85, power: 31, mana: 26, variance: 0.2, range: 6.9, desc: 'A ring of hoarfrost bursts outward — the anti-melee tool casters never had.' },
    { name: 'Firewall', learnLevel: 400, type: 'control', channel: 'magic', target: 'self', cooldown: 6.5, accuracy: 100, power: 0, mana: 30, range: 8, desc: 'A burning line laid across the ground. Not a hit — a place they should not walk.' },
    { name: 'Inferno', learnLevel: 430, type: 'damage', channel: 'magic', target: 'allEnemies', cooldown: 5.2, accuracy: 82, power: 44, mana: 32, variance: 0.25, status: { kind: 'burn', chance: 30, duration: 3 }, range: 6.6, desc: 'Fire across the whole position, and much of it keeps burning.' },
    { name: 'Seismic Crush', learnLevel: 560, type: 'damage', channel: 'magic', target: 'allEnemies', cooldown: 6.5, accuracy: 82, power: 53, mana: 38, variance: 0.25, status: { kind: 'stun', chance: 30, duration: 1 }, range: 6.3, desc: 'The ground itself comes up. Damage AND a stun on everything standing on it.' },
    { name: 'World Ender', learnLevel: 920, type: 'damage', channel: 'magic', target: 'allEnemies', cooldown: 9.1, accuracy: 78, power: 87, mana: 56, variance: 0.3, effects: { maxHpDmg: 0.02 }, range: 6, desc: 'The largest thing in the game, and it hurts the biggest of them most.' },

    // ── Arcanist — move things. Yourself, or them ────────────────────────────
    { name: 'Spark', learnLevel: 40, type: 'damage', channel: 'magic', target: 'enemy', cooldown: 1.3, accuracy: 95, power: 16, mana: 5, variance: 0.15, range: 7.4, desc: 'A small air bolt, cheap enough to throw between everything else.' },
    { name: 'Phase Step', learnLevel: 180, type: 'buff', channel: 'support', target: 'self', cooldown: 5.2, accuracy: 100, power: 0, mana: 14, effects: { dodgeBuff: 12, duration: 1 }, range: 7, desc: 'Steps out of the world and back a few paces away — through cover, if need be.' },
    { name: 'Mirror Image', learnLevel: 250, type: 'buff', channel: 'support', target: 'self', cooldown: 6.5, accuracy: 100, power: 0, mana: 20, effects: { dodgeBuff: 16, duration: 3 }, range: 7, desc: 'Shimmering duplicates. Attacks keep finding the wrong one.' },
    { name: 'Static Chain', learnLevel: 330, type: 'damage', channel: 'magic', target: 'allEnemies', cooldown: 5.2, accuracy: 85, power: 39, mana: 28, variance: 0.2, status: { kind: 'vulnerable', chance: 25, duration: 2 }, range: 6, desc: 'A bolt that leaps body to body along a line, weakening as it goes.' },
    { name: 'Mana Leech', learnLevel: 335, type: 'damage', channel: 'magic', target: 'enemy', cooldown: 3.9, accuracy: 88, power: 34, mana: 22, variance: 0.15, effects: { manaBurn: 14, lifesteal: 0.25 }, range: 6.9, desc: 'Siphons and steps away in the same motion. WIS steals better; this one escapes.' },
    { name: 'Unmake', learnLevel: 560, type: 'debuff', channel: 'magic', target: 'enemy', cooldown: 6.5, accuracy: 95, power: 0, mana: 26, effects: { consumeWard: 1, accDebuff: 12, duration: 3 }, range: 7, desc: 'Strips the shield off them and leaves their aim shaking.' },
    { name: 'Displace', learnLevel: 640, type: 'damage', channel: 'magic', target: 'enemy', cooldown: 5.2, accuracy: 90, power: 50, mana: 26, variance: 0.15, range: 6.8, desc: 'Teleports the TARGET — rips a diver out of your back line and pins it where it lands.' },
    { name: 'Void Lance', learnLevel: 780, type: 'damage', channel: 'magic', target: 'enemy', cooldown: 6.5, accuracy: 85, power: 89, mana: 38, variance: 0.1, effects: { pierce: 0.5 }, range: 6.2, desc: 'Pure void. Half of everything they are wearing simply does not apply.' },
    { name: 'Arcane Overload', learnLevel: 850, type: 'damage', channel: 'magic', target: 'enemy', cooldown: 7.8, accuracy: 85, power: 168, mana: 44, variance: 0.3, effects: { recoil: 0.15 }, range: 6.2, desc: 'Overchannelled past what the caster can hold. It burns them too.' },
  ],
  // ══ CHA ══ team buff/debuff · few attacks · denial and support · lots of CC ══
  // ENCHANTER is ACTION denial — charm, sleep, fear; the home of hard CC.
  // CAPTAIN is empowerment. DEMAGOGUE is team debuffs and morale.
  //
  // ⚠️ THE RULE THIS STAT SETTLES: CHA EMPOWERS, CON PROTECTS, WIS RESTORES.
  // CHA is the only stat in the game that makes an ally STRONGER — every atkBuff,
  // accBuff, haste and crit grant routes through here. CON's support is shields,
  // WIS's is healing. It had 5 buffs against CON's 12 before this pass, which for
  // the stat whose flagship is the Enchanter was simply backwards.
  // ⚠️ It carries the most hard CC in the game, and deliberately few attacks.
  CHA: [
    // ── Enchanter — action denial. Take the turn, not the hit points ─────────
    { name: 'Discord', learnLevel: 40, type: 'damage', channel: 'voice', target: 'enemy', cooldown: 2.6, accuracy: 90, power: 14, mana: 8, variance: 0.2, status: { kind: 'blind', chance: 50, duration: 3 }, range: 6.5, desc: 'A jarring note that leaves them swinging at afterimages.' },
    { name: 'Screech', learnLevel: 160, type: 'damage', channel: 'voice', target: 'allEnemies', cooldown: 3.9, accuracy: 85, power: 12, mana: 22, variance: 0.2, status: { kind: 'fear', chance: 30, duration: 2 }, range: 5.5, desc: 'A sound that routs. Hard control across a whole line.' },
    { name: 'Sonic Boom', learnLevel: 380, type: 'damage', channel: 'voice', target: 'enemy', cooldown: 5.2, accuracy: 85, power: 28, mana: 26, variance: 0.2, status: { kind: 'confusion', chance: 40, duration: 2 }, effects: { spreadStatus: { kind: 'confusion', targets: 1, chance: 30 } }, range: 5.7, desc: 'A heavy burst, and the disorientation carries to whoever stood too close.' },
    { name: 'Lullaby', learnLevel: 385, type: 'control', channel: 'voice', target: 'enemy', cooldown: 6.5, accuracy: 85, power: 0, mana: 24, status: { kind: 'sleep', chance: 60, duration: 3 }, effects: { spreadStatus: { kind: 'sleep', targets: 1, chance: 30 } }, range: 6.5, desc: 'Sings them to actual sleep — a free hit, but any damage wakes them. Drowsiness is catching.' },
    { name: 'Cacophony', learnLevel: 650, type: 'damage', channel: 'voice', target: 'allEnemies', cooldown: 6.5, accuracy: 82, power: 28, mana: 36, variance: 0.25, status: { kind: 'charm', chance: 22, duration: 2 }, range: 4.9, desc: 'A charmed foe turns on its own team. The best status in the game, and the rarest.' },
    { name: 'Mass Hysteria', learnLevel: 820, type: 'control', channel: 'voice', target: 'allEnemies', cooldown: 9.1, accuracy: 88, power: 0, mana: 52, status: { kind: 'fear', chance: 55, duration: 2 }, effects: { spreadStatus: { kind: 'confusion', targets: 2, chance: 40 } }, range: 5.5, desc: 'The whole enemy line breaks at once. The Enchanter capstone: nobody gets a turn.' },

    // ── Captain — empowerment. Nothing else in the game does this ────────────
    { name: 'Rallying Song', learnLevel: 90, type: 'buff', channel: 'support', target: 'team', cooldown: 5.2, accuracy: 100, power: 0, mana: 18, effects: { atkBuff: 0.12, duration: 3 }, range: 7.5, desc: 'A stirring tune: the whole team hits harder for 3 rounds.' },
    { name: 'Bravura', learnLevel: 140, type: 'buff', channel: 'support', target: 'self', cooldown: 5.2, accuracy: 100, power: 0, mana: 16, effects: { ward: 20, dodgeBuff: 10, duration: 3 }, range: 7.5, desc: 'Performs straight through the danger. The bard can look after itself.' },
    { name: 'Anthem of Iron', learnLevel: 180, type: 'buff', channel: 'support', target: 'team', cooldown: 6.5, accuracy: 100, power: 0, mana: 24, effects: { atkBuff: 0.1, defBuff: 6, duration: 3 }, range: 7.5, desc: 'Hit harder and hold together — attack and armour in one song.' },
    { name: 'Inspire', learnLevel: 260, type: 'buff', channel: 'support', target: 'ally', cooldown: 5.2, accuracy: 100, power: 0, mana: 16, effects: { atkBuff: 0.28, accBuff: 10, duration: 3 }, range: 7.5, desc: 'Everything poured into ONE ally. Focused, and cheaper than lifting everyone.' },
    { name: 'Battle Hymn', learnLevel: 300, type: 'buff', channel: 'support', target: 'team', cooldown: 6.5, accuracy: 100, power: 0, mana: 26, effects: { dodgeBuff: 8, regenBuff: 2, duration: 3 }, status: { kind: 'haste', chance: 100, duration: 2 }, range: 7.5, desc: 'A steadying anthem — and the whole team moves first.' },
    { name: 'Fanfare', learnLevel: 420, type: 'buff', channel: 'support', target: 'team', cooldown: 6.5, accuracy: 100, power: 0, mana: 32, effects: { accBuff: 16, duration: 3 }, range: 7.5, desc: 'Team accuracy, sharply. Nothing else in the game hands out aim like this.' },
    { name: 'Hymn of Shields', learnLevel: 470, type: 'buff', channel: 'support', target: 'team', cooldown: 7.8, accuracy: 100, power: 0, mana: 38, effects: { ward: 26, guard: 5, duration: 3 }, range: 7.5, desc: 'A hymn that armours everyone who can hear it, the singer included.' },
    // ⚠️ CHA HEALS THE WHOLE LINE, WEAKLY. Half of Mending Surge and spread over
    // everyone: a rally, not a mend. It reads as CHA because it pays for breadth
    // in per-head strength, which is the same trade the AoE damage rule makes —
    // weak into one body, strong into three.
    // ⚠️ THIS BENDS A STANDING RULE ("WIS is the ONLY stat that can heal another
    // monster"). `Standing Ovation` already bent it with a team hpRegenBuff, so
    // the rule was already describing an older pool than the one that shipped.
    // Kept deliberately weaker per target than anything in Mender so WIS remains
    // the stat you bring when you need someone SAVED.
    // ⚠️ learnLevel 340, NOT 480 — CHA-primary measures median 330 / p90 396, so
    // 480 was unlearnable by everyone. See Mending Surge above.
    { name: 'Second Wind', learnLevel: 340, type: 'buff', channel: 'support', target: 'team', cooldown: 11.7, accuracy: 100, power: 44, mana: 42, range: 7.5, desc: 'A cry that puts the whole line back on its feet — none of them fully.' },
    { name: 'Standing Ovation', learnLevel: 380, type: 'buff', channel: 'support', target: 'team', cooldown: 7.8, accuracy: 100, power: 0, mana: 42, effects: { atkBuff: 0.2, accBuff: 10, hpRegenBuff: 6, duration: 3 }, range: 7.5, desc: 'Feeds on applause and hands it straight back to the team.' },
    { name: 'Triumph', learnLevel: 880, type: 'buff', channel: 'support', target: 'team', cooldown: 10.4, accuracy: 100, power: 0, mana: 56, effects: { atkBuff: 0.32, accBuff: 14, dodgeBuff: 10, duration: 2 }, range: 7.5, desc: 'The empowerment capstone: everything at once, for two rounds only.' },

    // ── Demagogue — team debuffs and morale ──────────────────────────────────
    { name: 'Grand Mockery', learnLevel: 120, type: 'debuff', channel: 'voice', target: 'allEnemies', cooldown: 5.2, accuracy: 95, power: 0, mana: 22, effects: { atkDebuff: 0.14, duration: 3 }, status: { kind: 'healblock', chance: 25, duration: 2 }, range: 5.1, desc: "A cutting jeer: they hit softer, and some of them stop closing." },
    { name: 'Captivate', learnLevel: 200, type: 'damage', channel: 'voice', target: 'enemy', cooldown: 3.9, accuracy: 88, power: 17, mana: 14, variance: 0.2, effects: { lifesteal: 0.45 }, range: 6, desc: 'Feeds on adoration and gives nothing back.' },
    { name: 'Demoralize', learnLevel: 330, type: 'debuff', channel: 'voice', target: 'allEnemies', cooldown: 6.5, accuracy: 90, power: 0, mana: 30, effects: { atkDebuff: 0.24, duration: 3 }, range: 5.1, desc: 'Breaks the spirit outright. Deeper than Mockery, and that is the whole difference.' },
    { name: 'Crowd Surge', learnLevel: 320, type: 'debuff', channel: 'voice', target: 'allEnemies', cooldown: 5.2, accuracy: 90, power: 13, mana: 24, variance: 0.2, effects: { accDebuff: 10, duration: 2 }, range: 5.2, desc: 'Shoves the whole enemy line backwards. A DEFENSIVE use of a debuff stat.' },
    { name: 'Dirge', learnLevel: 520, type: 'debuff', channel: 'voice', target: 'allEnemies', cooldown: 7.8, accuracy: 95, power: 0, mana: 34, status: { kind: 'healblock', chance: 70, duration: 3 }, range: 5.1, desc: 'While it plays, nothing on that side closes a wound.' },
    { name: "Siren's Call", learnLevel: 780, type: 'damage', channel: 'voice', target: 'enemy', cooldown: 6.5, accuracy: 85, power: 26, mana: 32, variance: 0.2, effects: { manaBurn: 16, bonusVsStatus: { kind: 'fear', mult: 1.6, consume: true } }, range: 5.6, desc: 'An irresistible song that scatters focus — and shatters the courage of the Afraid.' },
    { name: 'Showstopper', learnLevel: 850, type: 'damage', channel: 'voice', target: 'enemy', cooldown: 6.5, accuracy: 88, power: 43, mana: 36, variance: 0.15, effects: { execute: 0.35 }, range: 5.3, desc: 'The closing number, and it closes them.' },
    { name: 'Crescendo', learnLevel: 920, type: 'damage', channel: 'voice', target: 'allEnemies', cooldown: 9.1, accuracy: 80, power: 52, mana: 50, variance: 0.25, range: 4.5, desc: 'A voice AoE finisher. CHA damage exists — it is just rare, and it is late.' },
  ],
}

export const ALL_MOVES: Move[] = (Object.keys(POOLS) as Stat[]).flatMap((stat) =>
  POOLS[stat].map((row, i) => ({
    ...row,
    id: `${stat}-${i}`,
    stat,
    // The line this move belongs to, from the single lookup in `lines.ts`. See
    // that file for why the pool needs lines at all — three separate waves of
    // authored content were silently unreachable without them.
    line: LINE_OF[row.name],
  })),
)

export const MOVES_BY_ID: Record<string, Move> = Object.fromEntries(ALL_MOVES.map((m) => [m.id, m]))

/**
 * Every status some move in the pool can CASH with a `bonusVsStatus` rider.
 *
 * ⚠️ DERIVED, NEVER HAND-LISTED. A hand-written list is a second source of truth
 * that silently rots the moment a payoff is added or repriced — and `comboRole`
 * reads this in three places (the UI gate, the primer's move bonus, the
 * detonator's target bias), so a stale copy would disagree with itself.
 */
export const CASHABLE_STATUSES: ReadonlySet<StatusKind> = new Set(
  ALL_MOVES.map((m) => m.effects?.bonusVsStatus?.kind).filter((k): k is StatusKind => !!k))

