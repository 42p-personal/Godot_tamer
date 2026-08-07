// Golden battle regressions + determinism. The goldens pin the engine's exact
// behavior for four seeded matchups (captured 2026-07-25, after the guard-
// persistence / element-aware-AI / firstStrike-valuation / heal-sorting fixes
// and the maxMana WIS+INT/2 blend). ANY intentional engine change will move
// these — recapture with a fresh run and update the table deliberately; an
// UNINTENTIONAL diff here is a regression.
// ═══════════════════════════════════════════════════════════════════════════
// ⚠️ FROZEN 2026-08-01. These values are a REGRESSION DETECTOR again, not a
// changelog.
//
// They moved roughly ten times in a single day during the ability rework and the
// balance pass — pool reprices, a cooldown unit conversion, a tactics wave, the
// 6v6 removal. A fixture that is recaptured every commit detects nothing; it just
// records what happened. The pool is stable now (141 moves, sweep 48/48), so this
// is the moment to stop.
//
// THE RULE FROM HERE:
//   1. A golden moving is a QUESTION, not a chore. Answer it before touching this
//      file — "which change did that, and did I mean it?"
//   2. If the answer is a deliberate content or engine change, recapture and write
//      the REASON on the fixture, one ⚠️ line. Every entry below already carries
//      its history; keep that unbroken.
//   3. If you cannot name the cause, DO NOT RECAPTURE. Twice today a golden moved
//      for a reason that turned out to be a real bug — a loadout picker fed the
//      wrong unit, and a free attack silently made 30% faster. Both would have
//      been papered over by a recapture, and the second was found only because a
//      plausible-sounding float explanation was tested and REFUTED.
//   4. `npx tsx tools/regold.ts` prints current values. It is a convenience for
//      step 2, never permission to skip step 1.
// ═══════════════════════════════════════════════════════════════════════════

import { describe, expect, it } from 'vitest'
import { simulateTeamBattle } from './battle'
import { generateMonster } from './monster'

const team = (seeds: string[], train: number) => seeds.map((s) => generateMonster(s, { train }))

const GOLDENS = [
  {
    name: '1v1-low', a: ['gold-a1'], b: ['gold-b1'], train: 150,
    // ⚠️ Recaptured for LINE AFFINITY (src/lines.ts) — every monster in the game
    // re-drafted its loadout, so all four goldens moved at once. This is the
    // intended blast radius: the picker now draws from the three lines that
    // express a monster's class instead of ranking all 100 moves globally.
    // Prior: 221/160 (v0.852 prestige base-stat bump). A now survives on 9 HP —
    // a low-training fight that got much closer, because both sides draft along
    // their lines instead of both grabbing the same globally-best moves.
    // ⚠️ Recaptured for the STR POOL REWORK (15 -> 23 moves, three lines). Power
    // Strike lost ~20% (it was the game's damage ceiling at lvl 90) and Titanfall
    // 68 -> 62, so every STR monster hits differently.
    // ⚠️ Recaptured for the DEX POOL REWORK (16 -> 24 moves, three lines).
    // ⚠️ Recaptured for the CON POOL REWORK (18 -> 23 moves, three lines).
    // ⚠️ Recaptured for the DAMAGE TIERING pass: STR/DEX/INT are the damage stats
    // and CON/WIS/CHA are not, so per-stat power multipliers split them into two
    // clear tiers, plus a wider stat-scale band. Every monster hits differently.
    // ⚠️ Recaptured for the DRAFT fix (chooseLoadout:expectedOutput no longer
    // divides by cooldown and now scales by the move's OWN stat). Every golden
    // team re-drafted, so all four moved at once — expected, not a regression.
    // ⚠️ These pin the TURN engine, which tamerengine will replace at M7; they
    // are kept green so a real regression in the SHIPPED game still shows up,
    // but their movement is no longer treated as signal about the new engine.
    // ⚠️ Recaptured for the SUPERLINEAR CON term in maxHp (40 + CON*2 + CON^2/1600).
    // Shared by both engines, so all seven goldens moved together — intended.
    // ⚠️ Recaptured for BAKING DAMAGE_MULT 0.92 into the 141 authored powers. A
    // REAL 8% damage cut in THIS engine: the dial lived in tamerengine's
    // `strike()` and battle.ts never applied it, so one pool was running at two
    // damage levels. It now runs at one. Holds under an unrounded bake, so this
    // is the cut itself, not the integer rounding that moved the field goldens.
    winner: 'A', events: 227, logLines: 168,
    finals: [
      { side: 'A', slot: 0, hp: 110, mana: 3, wasKOd: false },
      { side: 'B', slot: 0, hp: 0, mana: 1, wasKOd: true },
    ],
  },
  {
    name: '1v1-high', a: ['gold-a2'], b: ['gold-b2'], train: 1800,
    // Recaptured for the P4 loadout-ranking pass (chooseLoadout now ranks damage
    // by power/cooldown — a RATE — instead of damage-per-cast). Winner held at B.
    // 74 -> 147 events: both monsters swapped a big slow move for sustained ones,
    // so more casts land per fight. B ends on 146 mana rather than 673, which is
    // the same story from the other side — it is actually spending its bar now.
    // ⚠️ Recaptured for LINE AFFINITY (src/lines.ts) — every monster in the game
    // re-drafted its loadout, so all four goldens moved at once. This is the
    // intended blast radius: the picker now draws from the three lines that
    // express a monster's class instead of ranking all 100 moves globally.
    // 147 -> 73 events: both monsters now draft along their own lines and the
    // fight resolves in half the time it took with globally-ranked kits.
    // ⚠️ Recaptured for the DAMAGE TIERING pass: STR/DEX/INT are the damage stats
    // and CON/WIS/CHA are not, so per-stat power multipliers split them into two
    // clear tiers, plus a wider stat-scale band. Every monster hits differently.
    // ⚠️ Recaptured for the DRAFT fix (chooseLoadout:expectedOutput no longer
    // divides by cooldown and now scales by the move's OWN stat). Every golden
    // team re-drafted, so all four moved at once — expected, not a regression.
    // ⚠️ These pin the TURN engine, which tamerengine will replace at M7; they
    // are kept green so a real regression in the SHIPPED game still shows up,
    // but their movement is no longer treated as signal about the new engine.
    // ⚠️ Recaptured for the PROGRESSION SLOPE pass — every damage move's power
    // now scales with its learnLevel (x1.00 at lv40 -> x1.95 damage stats /
    // x1.55 support stats at lv920), so every team's kit hits harder and the
    // goldens move together. Deliberate, not a regression.
    // ⚠️ Recaptured for the ELEMENT REMOVAL — body-type resist/weak no longer
    // multiplies damage, so every fight involving a resisted or super-effective
    // move resolves differently. Deliberate; elements are gone from the game.
    // ⚠️ Recaptured for the DIRECT HEALS — Mending Surge (WIS) and Second Wind
    // (CHA) grew the pool 137 -> 139, so chooseLoadout re-drafted. Only this
    // golden moved: the other three field no WIS/CHA primary and never see them.
    // ⚠️ Recaptured for the SUPERLINEAR CON term in maxHp (40 + CON*2 + CON^2/1600).
    // Shared by both engines, so all seven goldens moved together — intended.
    // ⚠️ Recaptured for the two EARLY DETONATORS (Fester lv220, Twist the Knife
    // lv360). A pool addition re-drafts every kit, and these two are drafted at
    // exactly the training levels the goldens sit at.
    // ⚠️ Recaptured for the BALANCE SWEEP pass (tools/pool.ts): 15 authored
    // values changed across 12 moves, four of them EARLY OUTLIERS cut rather than
    // raising the later moves they were beating. Deliberate content change.
    // ⚠️ Recaptured for BAKING DAMAGE_MULT 0.92 into the 141 authored powers. A
    // REAL 8% damage cut in THIS engine: the dial lived in tamerengine's
    // `strike()` and battle.ts never applied it, so one pool was running at two
    // damage levels. It now runs at one. Holds under an unrounded bake, so this
    // is the cut itself, not the integer rounding that moved the field goldens.
    // ⚠️ Recaptured for the POOL-AUDIT reprices: Fester cd 3.9->2.6, Colossus Crash
    // 31->26, Mana Leech 44->34, Arcane Overload 129->168. A content change
    // re-drafts kits at exactly these training levels. The FIELD goldens did not
    // move, which is the explicit-loadout pinning working: none of the four is in
    // one of their named kits.
    winner: 'A', events: 264, logLines: 207,
    finals: [
      { side: 'A', slot: 0, hp: 79, mana: 507, wasKOd: false },
      { side: 'B', slot: 0, hp: 0, mana: 0, wasKOd: true },
    ],
  },
  {
    name: '2v2-mid', a: ['gold-a3', 'gold-a4'], b: ['gold-b3', 'gold-b4'], train: 700,
    // recaptured v0.91: the AI now understands multi-target reach and contagion,
    // so it ranks moves it used to undervalue. A wins FASTER and CLEANER — 126 →
    // 58 events, and slot 0 survives where it used to be KO'd. Better play, not
    // a balance change. Prior capture, v0.852: 126/93 (prestige base-stat bump).
    // Recaptured again for the play-quality pass (lethality, ranked support):
    // 58 -> 52 events. Fights keep getting shorter as the AI gets better.
    // Recaptured for the P4 floor pass: 12 damage moves that sat BELOW the free
    // attack were lifted above it, and Heartseeker's 137.8-DPS outlier was cut.
    // 52 -> 70 events. Winner HELD at A and both its monsters still survive —
    // the fight is longer because the losing side's spells now do real damage
    // instead of being worse than swinging. Prior: 58 -> 52 (play quality).
    // Recaptured again for the P4 loadout-ranking pass: 70 -> 91 events, winner
    // still A with both monsters alive. Same cause as 1v1-high — rate-ranked kits
    // fire more often.
    // ⚠️ Recaptured for LINE AFFINITY (src/lines.ts) — every monster in the game
    // re-drafted its loadout, so all four goldens moved at once. This is the
    // intended blast radius: the picker now draws from the three lines that
    // express a monster's class instead of ranking all 100 moves globally.
    // ⚠️ Recaptured for the WIS POOL REWORK (16 -> 22 moves, three lines).
    // Winner flipped A -> B. WIS gained real damage this pass (4 -> 9 moves incl.
    // a capstone hit), so a side with a WIS monster stops being purely passive.
    // ⚠️ Recaptured for the DAMAGE TIERING pass: STR/DEX/INT are the damage stats
    // and CON/WIS/CHA are not, so per-stat power multipliers split them into two
    // clear tiers, plus a wider stat-scale band. Every monster hits differently.
    // ⚠️ Recaptured for the DRAFT fix (chooseLoadout:expectedOutput no longer
    // divides by cooldown and now scales by the move's OWN stat). Every golden
    // team re-drafted, so all four moved at once — expected, not a regression.
    // ⚠️ These pin the TURN engine, which tamerengine will replace at M7; they
    // are kept green so a real regression in the SHIPPED game still shows up,
    // but their movement is no longer treated as signal about the new engine.
    // ⚠️ Recaptured for the PROGRESSION SLOPE pass — every damage move's power
    // now scales with its learnLevel (x1.00 at lv40 -> x1.95 damage stats /
    // x1.55 support stats at lv920), so every team's kit hits harder and the
    // goldens move together. Deliberate, not a regression.
    // ⚠️ Recaptured for the ELEMENT REMOVAL — body-type resist/weak no longer
    // multiplies damage, so every fight involving a resisted or super-effective
    // move resolves differently. Deliberate; elements are gone from the game.
    // ⚠️ Recaptured for the REACHABILITY repricing — Tranquility lv430 -> 320. It
    // was a mid-line Mender heal above WIS's p90 (355), so nobody could learn it;
    // now a WIS monster drafts it and the fight runs longer (79 -> 107 events).
    // ⚠️ Recaptured for the SUPERLINEAR CON term in maxHp (40 + CON*2 + CON^2/1600).
    // Shared by both engines, so all seven goldens moved together — intended.
    // ⚠️ Recaptured for the two EARLY DETONATORS (Fester lv220, Twist the Knife
    // lv360). A pool addition re-drafts every kit, and these two are drafted at
    // exactly the training levels the goldens sit at.
    // ⚠️ A2 NOW DIES AND A STILL WINS — 2v2-mid went from a clean 2-0 to a trade.
    // That is the sweep working: the four early-outlier cuts removed the free
    // damage a lv90 move was handing every kit at this training level.
    // ⚠️ Recaptured for the BALANCE SWEEP pass (tools/pool.ts): 15 authored
    // values changed across 12 moves, four of them EARLY OUTLIERS cut rather than
    // raising the later moves they were beating. Deliberate content change.
    // ⚠️ Recaptured for BAKING DAMAGE_MULT 0.92 into the 141 authored powers. A
    // REAL 8% damage cut in THIS engine: the dial lived in tamerengine's
    // `strike()` and battle.ts never applied it, so one pool was running at two
    // damage levels. It now runs at one. Holds under an unrounded bake, so this
    // is the cut itself, not the integer rounding that moved the field goldens.
    // ⚠️ AND A0 NOW SURVIVES — back to a clean 2-0 from the trade the balance
    // sweep produced. Less damage in the air means the trade no longer happens.
    // ⚠️ Recaptured for the POOL-AUDIT reprices: Fester cd 3.9->2.6, Colossus Crash
    // 31->26, Mana Leech 44->34, Arcane Overload 129->168. A content change
    // re-drafts kits at exactly these training levels. The FIELD goldens did not
    // move, which is the explicit-loadout pinning working: none of the four is in
    // one of their named kits.
    winner: 'A', events: 98, logLines: 75,
    finals: [
      { side: 'A', slot: 0, hp: 107, mana: 509, wasKOd: false },
      { side: 'A', slot: 1, hp: 154, mana: 244, wasKOd: false },
      { side: 'B', slot: 0, hp: 0, mana: 243, wasKOd: true },
      { side: 'B', slot: 1, hp: 0, mana: 327, wasKOd: true },
    ],
  },
  {
    // exercises the round-35 sudden-death path — now DECISIVE (was a full-wipe
    // draw). Recaptured 2026-07-22 after the %-of-max-HP sudden-death rework
    // (flat chip → % chip), CON coefficient trims, and WIS spell-power — the
    // clock now resolves a winner instead of wiping both.
    name: '3v3-high', a: ['gold-a5', 'gold-a6', 'gold-a7'], b: ['gold-b5', 'gold-b6', 'gold-b7'], train: 2000,
    // ⚠️ recaptured v0.91 (THIRD move this cycle) — WINNER FLIPPED A → B, after the
    // AI learned multi-target reach. Both sides got the same upgrade; B's kit
    // (gold-b5 Archmage-Aleph runs Inferno) simply gains more from an AI that
    // finally ranks a 3-target sweep above a single hit of the same face power.
    // A 3v3 decided by one AoE caster flipping is a fair outcome, not a
    // regression — the long-haul sim was re-run and the economy held.
    // Prior captures: AoE-falloff 419/314; live-formation 376/274; v0.89 349/254.
    // ⚠️ Recaptured for the guardian-taunt pass, and the winner flipped BACK to A.
    // Not noise: side A fields TWO Tortavos, both carrying Bulwark's Challenge.
    // Taunts previously fired only for a monster explicitly flagged `protect`, so
    // those tanks sat on the move while teammates died. Letting a guardian cover
    // any endangered ally is precisely the kit this unlocks — a tank-heavy team
    // getting its tanks back is the change working, not a coin landing differently.
    // Captures this cycle: B 347 (play-quality) <- B 404 (AoE-aware AI) <-
    // A 419 (AoE falloff) <- A 376 (live formation) <- A 349 (v0.89 league curve).
    // ⚠️ recaptured for the P3 class-kit gap fixes (the ABILITY POOL moved, not the
    // engine): the pool grew 90 -> 100, CON's buffs were retargeted self -> team,
    // and the loadout's buff fallback stopped rejecting team buffs. All three
    // change what these monsters LEARN and EQUIP, so a different fight is the
    // expected outcome. Winner HELD at A — the fight just runs longer and
    // bloodier (406 -> 440 events) because team buffs and control now get cast,
    // and A's slot 0 no longer survives it. This was the ONLY golden of the 12
    // that moved, which is the reassuring part: a pool change of that size
    // touching one fight means the other 11 kits were left intact.
    // ⚠️ Recaptured AGAIN for the P4 floor pass — WINNER FLIPPED A -> B, and this
    // one is explicable rather than noise: B fields gold-b5 Archmage-Aleph, an
    // INT caster, and INT was the pool worst hit by the floor bug (7 of its 15
    // damage moves ranked below the free attack). Lifting them is a direct buff
    // to exactly this monster, so the side built around it wins. A 3v3 decided by
    // the caster whose spells stopped being worse than punching is the fix
    // working. Now 5 of 6 monsters die — a decisive fight, not a grind.
    // ⚠️ Recaptured for the P4 loadout-ranking pass — winner flipped BACK to A, and
    // decisively (416 -> 333 events, A keeps two monsters on 1077 and 1348 HP).
    // This golden has now moved on three consecutive ability changes, which is
    // what a 3v3 between two near-equal high-training teams does: it is the most
    // sensitive fight in the set, not an unstable engine. The other three goldens
    // held their winner across all three passes.
    // ⚠️ Recaptured for LINE AFFINITY (src/lines.ts) — every monster in the game
    // re-drafted its loadout, so all four goldens moved at once. This is the
    // intended blast radius: the picker now draws from the three lines that
    // express a monster's class instead of ranking all 100 moves globally.
    // Winner flipped back to A and this time it is a 3-0 SWEEP — all three of A's
    // monsters survive. A tank-heavy side getting coherent tank kits is exactly
    // what affinity is for, so a decisive result here reads as the fix working.
    // ⚠️ Recaptured for the STR POOL REWORK (15 -> 23 moves, three lines). Power
    // Strike lost ~20% (it was the game's damage ceiling at lvl 90) and Titanfall
    // 68 -> 62, so every STR monster hits differently.
    // A still wins but it is no longer a free sweep — slot 0 dies and the other two
    // finish on roughly half the HP they used to. A less lopsided fight.
    // ⚠️ Recaptured for the CON POOL REWORK (18 -> 23 moves, three lines).
    // ⚠️ Winner flipped A -> B and it is now a 5-of-6 wipe with ONE survivor on 135 HP.
    // Side A fields two Tortavos (CON) — the stat whose buff count came down and
    // whose damage went up this pass — so a tank-heavy side losing its cushion is
    // the change doing exactly what it was aimed at, not noise.
    // ⚠️ Recaptured for the WIS POOL REWORK (16 -> 22 moves, three lines).
    // ⚠️ NOW A FULL-WIPE DRAW — the exact state this golden was once tuned OUT of.
    // Deliberately NOT treated as a WIS over-tune, because the broader evidence
    // says otherwise: the class-diverse field sweep IMPROVED to 10/12 at train 850,
    // a train-2000 sweep resolves 9/12, and healing is only 2.4% of all damage
    // dealt. One matchup at train 2000 stalling into round-35 chip is this fight
    // being the most sensitive in the set (it exists to exercise sudden death),
    // not the pool being broken. ⚠️ RE-CHECK once INT and CHA are reworked — if it
    // is still a draw with the pool complete, that IS a real signal.
    // ⚠️ Recaptured for the INT POOL REWORK (20 -> 22 moves, three lines).
    // ⚠️ Recaptured for the DAMAGE TIERING pass: STR/DEX/INT are the damage stats
    // and CON/WIS/CHA are not, so per-stat power multipliers split them into two
    // clear tiers, plus a wider stat-scale band. Every monster hits differently.
    // ⚠️ THE DRAW IS GONE — A wins decisively with a survivor on 590 HP. I flagged
    // the previous full-wipe draw to be re-checked once the pool was complete, and
    // this is that re-check: it was the half-transitioned pool, not WIS sustain.
    // ⚠️ Recaptured for the DRAFT fix (chooseLoadout:expectedOutput no longer
    // divides by cooldown and now scales by the move's OWN stat). Every golden
    // team re-drafted, so all four moved at once — expected, not a regression.
    // ⚠️ These pin the TURN engine, which tamerengine will replace at M7; they
    // are kept green so a real regression in the SHIPPED game still shows up,
    // but their movement is no longer treated as signal about the new engine.
    // ⚠️ Now a CLEAN 3-0 SWEEP with all three of A alive — it was a full-wipe
    // draw. Coherent kits (each monster drafting moves its own stat drives)
    // beat incoherent ones decisively; that is the draft fix showing up.
    // ⚠️ Recaptured for the PROGRESSION SLOPE pass — every damage move's power
    // now scales with its learnLevel (x1.00 at lv40 -> x1.95 damage stats /
    // x1.55 support stats at lv920), so every team's kit hits harder and the
    // goldens move together. Deliberate, not a regression.
    // ⚠️ Recaptured for the ELEMENT REMOVAL — body-type resist/weak no longer
    // multiplies damage, so every fight involving a resisted or super-effective
    // move resolves differently. Deliberate; elements are gone from the game.
    // ⚠️ Recaptured for the SUPERLINEAR CON term in maxHp (40 + CON*2 + CON^2/1600).
    // Shared by both engines, so all seven goldens moved together — intended.
    // ⚠️ Recaptured for the CLASS_LINES coverage pass — Wizard/Spellshield/Orator/
    // Bard each gained their primary stat's missing line, so those kits re-draft.
    // ⚠️ THE WINNER FLIPPED, A -> B, on a two-move pool addition. That is the
    // loudest a golden gets, and it is the honest consequence of adding content a
    // train-2000 kit will draft: both sides re-drafted and B's came out ahead. If a
    // future change flips it back, that is a NEW question, not a return to normal.
    // ⚠️ Recaptured for the two EARLY DETONATORS (Fester lv220, Twist the Knife
    // lv360). A pool addition re-drafts every kit, and these two are drafted at
    // exactly the training levels the goldens sit at.
    // ⚠️ Recaptured for BAKING DAMAGE_MULT 0.92 into the 141 authored powers. A
    // REAL 8% damage cut in THIS engine: the dial lived in tamerengine's
    // `strike()` and battle.ts never applied it, so one pool was running at two
    // damage levels. It now runs at one. Holds under an unrounded bake, so this
    // is the cut itself, not the integer rounding that moved the field goldens.
    // ⚠️ THE WINNER FLIPS B → A, and this fixture is the one that runs to the
    // round-35 sudden-death clock — the state most sensitive to total damage in
    // the air, which is exactly what moved. A flip here is expected from an 8%
    // cut, not a surprise; five of six still die.
    // ⚠️ Recaptured for the POOL-AUDIT reprices: Fester cd 3.9->2.6, Colossus Crash
    // 31->26, Mana Leech 44->34, Arcane Overload 129->168. A content change
    // re-drafts kits at exactly these training levels. The FIELD goldens did not
    // move, which is the explicit-loadout pinning working: none of the four is in
    // one of their named kits.
    // ⚠️ Recaptured for the SPATIAL-INNATE batch (2026-08-06): 33 innates whose names were
    // spatial identities (Ambush, Statue Stance, Immovable...) traded their legacy arithmetic
    // effects for spatial fields this engine cannot express — dormant here BY DESIGN, live on
    // the Godot field engine. A → draw, and it is explicable: A's last survivor previously
    // held on 266 HP, and the batch stripped firstHitMult/dodge riders both sides were using —
    // with less burst everywhere the mutual grind now kills all six. The 1v1/2v2 fixtures moved
    // by exactly one log line each, so the pool's centre of mass barely shifted; this fight is
    // (documented above) the most sensitive in the set.
    winner: 'draw', events: 489, logLines: 400,
    finals: [
      { side: 'A', slot: 0, hp: 0, mana: 716, wasKOd: true },
      { side: 'A', slot: 1, hp: 0, mana: 223, wasKOd: true },
      { side: 'A', slot: 2, hp: 0, mana: 756, wasKOd: true },
      { side: 'B', slot: 0, hp: 0, mana: 747, wasKOd: true },
      { side: 'B', slot: 1, hp: 0, mana: 766, wasKOd: true },
      { side: 'B', slot: 2, hp: 0, mana: 91, wasKOd: true },
    ],
  },
] as const

// ⚠️ ALL FOUR RECAPTURED for the HEAL-DRAFT fix: chooseLoadout's damage-floor
// guard counted SLOTS rather than damage moves, so a combo pair locked the
// utility loop out and Sages drafted zero heals. Every kit with a support
// profile changed, so every golden moved at once — expected, not a regression.
describe('golden battles', () => {
  for (const g of GOLDENS) {
    it(g.name, () => {
      const r = simulateTeamBattle(team([...g.a], g.train), team([...g.b], g.train))
      expect(r.winner).toBe(g.winner)
      expect(r.events.length).toBe(g.events)
      expect(r.log.length).toBe(g.logLines)
      expect(r.finals).toEqual(g.finals)
    })
  }
})

describe('determinism', () => {
  it('identical inputs produce byte-identical battles', () => {
    const run = () => simulateTeamBattle(team(['det-a1', 'det-a2'], 900), team(['det-b1', 'det-b2'], 900))
    const r1 = run()
    const r2 = run()
    expect(r2.winner).toBe(r1.winner)
    expect(r2.log).toEqual(r1.log)
    expect(r2.events).toEqual(r1.events)
    expect(r2.finals).toEqual(r1.finals)
  })

  it('every battle ends with a winner and full finals coverage', () => {
    for (let i = 0; i < 10; i++) {
      const r = simulateTeamBattle(team([`end-a${i}`], 100 + i * 200), team([`end-b${i}`], 100 + i * 200))
      expect(['A', 'B', 'draw']).toContain(r.winner)
      expect(r.finals.length).toBe(2)
      expect(r.events[r.events.length - 1]?.kind).toBe('end')
    }
  })
})
