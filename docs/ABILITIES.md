# The Ability Pool

> **Generated — do not hand-edit.** `npx tsx tools/genabilities.ts` rewrites this
> file from `src/moves.ts`. It went stale once by being written by hand; a
> reference maintained alongside 141 authored moves will always lose that race.

**141 abilities** across six stats and **18 lines**. A line is a group to
draw from, not a track you commit to — `CLASS_LINES` gives a class affinity for three
of them, and `chooseLoadout` multiplies affine moves by 1.35 so off-line picks stay
reachable.

Reading the numbers:

- **pwr** is the MID-POINT of a damage range, not a fixed number; **±** is the spread.
- **scale** is `statScale` — damage is `pwr × (1 + stat × scale)`, so a high-scaling
  move rewards training the stat rather than just having the move.
- **mp** prices EFFECTIVENESS, not power. `Blood Price` is cheap because it is paid
  for in blood.
- **rng** is field reach in world units (the arena is 40 × 22).
- **cd (s)** is recharge in SECONDS — the field engine reads it directly.
  `battle.ts` still counts rounds and divides by `SECONDS_PER_TURN`; nothing
  authors turns any more.
- AoE damage is judged at THREE targets, never one — `aoeFalloff` is
  −5%/extra target, floored at 40%, so three bodies is ×2.70 of a single hit.
- **Bold** keywords are HARD control (they take an action away).

## Which lines a class draws from

| class | lines |
|---|---|
| Tank | Guardian · Warden · Warcry |
| Warrior | Duelist · Bloodrage · Bulwark |
| Rogue | Assassin · Venomcraft · Duelist |
| Ranger | Volley · Assassin · Elementalist |
| Sage | Mender · Siphon · Hexer |
| Wizard | Hexer · Elementalist · Arcanist · Disruptor |
| Spellsword | Arcanist · Elementalist · Bulwark |
| Spellshield | Guardian · Bulwark · Warden · Mender |
| Captain | Captain · Warcry · Duelist |
| Orator | Demagogue · Enchanter · Captain · Disruptor |
| Bard | Captain · Enchanter · Demagogue · Volley |
| Evoker | Elementalist · Arcanist · Volley |
| Skirmisher | Bloodrage · Duelist · Assassin |
| Stalker | Assassin · Venomcraft · Siphon |
| Swashbuckler | Volley · Assassin · Demagogue |
| Shaman | Mender · Disruptor · Guardian |
| Mystic | Mender · Siphon · Venomcraft |
| Herald | Captain · Demagogue · Warcry |

## STR

24 abilities · lines: Bloodrage · Duelist · Warcry

### Bloodrage

| lv | ability | type | pwr | ± | scale | mp | cd (s) | acc | rng | keywords |
|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| 40 | **Scrap** | damage/melee | 13 | ±15% | 1/320 | 4 | 1.3 | 95 | 3 | — |
| 120 | **Enrage** | buff/support | — | — | — | 14 | 6.5 | 100 | 2.8 | atk + |
| 240 | **Blood Price** | damage/melee | 36 | ±20% | 1/240 | 10 | 3.9 | 90 | 2.8 | recoil |
| 380 | **Reckless Slam** | damage/melee | 58 | ±25% | 1/205 | 26 | 5.2 | 85 | 2.6 | recoil, move |
| 540 | **Last Stand** | buff/support | — | — | — | 30 | 9.1 | 100 | 2.8 | atk +, def + |
| 700 | **Blood Fury** | damage/melee | 42 | ±30% | 1/153 | 24 | 3.9 | 88 | 2.7 | hp scaling |
| 920 | **Titanfall** | damage/melee | 117 | ±25% | 1/130 | 52 | 7.8 | 80 | 2.5 | pierce, recoil, move, push |

- **Scrap** — A cheap, scrappy swing — what you throw while the rage builds.
- **Enrage** — Works itself into a fury: +20% damage for 3 rounds.
- **Blood Price** — Swung with everything, including what it costs you. Cheap in mana because it is paid for in blood.
- **Reckless Slam** — A scorching, reckless haymaker; it burns the arm that throws it.
- **Last Stand** — Digs in and stops retreating: +30% damage and +10 mitigation for 3 rounds.
- **Blood Fury** — Feeble while it is still whole, and terrifying once it is not — this blow feeds on its own wounds.
- **Titanfall** — Colossal blow that partly ignores defence; 15% recoil.

### Duelist

| lv | ability | type | pwr | ± | scale | mp | cd (s) | acc | rng | keywords |
|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| 90 | **Power Strike** | damage/melee | 24 | ±10% | 1/295 | 16 | 2.6 | 90 | 3.5 | recoil, move |
| 200 | **Sunder** | debuff/melee | 15 | ±10% | 1/253 | 14 | 3.9 | 90 | 3.6 | def − |
| 260 | **Riposte** | buff/support | — | — | — | 18 | 5.2 | 100 | 3.4 | thorns, def + |
| 300 | **Headbutt** | damage/melee | 30 | ±15% | 1/223 | 16 | 3.9 | 90 | 3.4 | **stun** |
| 330 | **Bonebreaker** | damage/melee | 35 | ±15% | 1/216 | 22 | 5.2 | 85 | 3.3 | vulnerable, def − |
| 360 | **Twist the Knife** | damage/melee | 35 | ±20% | 1/209 | 16 | 3.9 | 92 | 3.4 | detonate |
| 480 | **Rend** | damage/melee | 31 | ±15% | 1/185 | 18 | 3.9 | 85 | 3.4 | bleed |
| 780 | **Bloodletter** | damage/melee | 17 | ±35% | 1/144 | 30 | 6.5 | 85 | 3.6 | multi-hit, detonate |
| 850 | **Executioner** | damage/melee | 59 | ±10% | 1/136 | 28 | 5.2 | 90 | 3 | execute, detonate, move, backstab |

- **Power Strike** — A heavy, committed blow, thrown exactly where it was aimed.
- **Sunder** — Splits the guard rather than the body: −12 mitigation for 3 rounds. The setup STR never had.
- **Riposte** — Takes the blow to answer it: returns 10 damage on every hit for 2 rounds.
- **Headbutt** — Short, ugly, and it rings their bell.
- **Bonebreaker** — Shatters defence and leaves them open — the opener Executioner is waiting on.
- **Twist the Knife** — Finds the wound someone else already opened, and worsens it.
- **Rend** — Opens a wound that keeps opening. Bleed here; Bonebreaker handles armour.
- **Bloodletter** — A weak flurry, 3–5 strikes — unless the target is Bleeding, and then it drinks the wound.
- **Executioner** — The closing blow: brutal against the weakened, and devastating against the Vulnerable.

### Warcry

| lv | ability | type | pwr | ± | scale | mp | cd (s) | acc | rng | keywords |
|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| 40 | **Guard** | buff/support | — | — | — | 6 | 3.9 | 100 | 6.5 | guard |
| 160 | **Cleave** | damage/melee | 28 | ±20% | 1/267 | 22 | 3.9 | 85 | 4.9 | cone AoE |
| 220 | **Intimidate** | debuff/voice | — | — | — | 20 | 6.5 | 95 | 5.5 | **fear**, atk −, circle AoE |
| 400 | **Challenge** | debuff/voice | — | — | — | 16 | 5.2 | 100 | 6.5 | taunt, atk − |
| 560 | **Bracer** | buff/support | — | — | — | 20 | 5.2 | 100 | 6.5 | guard |
| 600 | **Whirlwind** | damage/melee | 47 | ±20% | 1/166 | 34 | 5.2 | 88 | 4.9 | circle AoE |
| 650 | **Earthshaker** | damage/melee | 61 | ±25% | 1/159 | 40 | 6.5 | 80 | 4.9 | **stun**, circle AoE, push, slow |
| 820 | **Warlord's Roar** | buff/support | — | — | — | 44 | 7.8 | 100 | 6.5 | atk +, acc + |

- **Guard** — Brace against the next hits.
- **Cleave** — A horizontal sweep through everything in front of it — weak into one body, brutal into three.
- **Intimidate** — A roar with a body behind it: the nearest of them break and run.
- **Challenge** — Singles one out and dares it. It comes for you, and it swings softer for the insult.
- **Bracer** — A hard defensive set — Guard is the cheap answer, this is the committed one.
- **Whirlwind** — Spins through everything within reach. Pure volume, no rider.
- **Earthshaker** — A shockwave that fells whatever is standing near it.
- **Warlord's Roar** — STR's one team buff, and of course it is a shout: the whole line hits harder and truer for 3 rounds.

## DEX

24 abilities · lines: Assassin · Venomcraft · Volley

### Assassin

| lv | ability | type | pwr | ± | scale | mp | cd (s) | acc | rng | keywords |
|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| 120 | **Shadowstep** | damage/ranged | 42 | ±15% | 1/282 | 16 | 5.2 | 92 | 2.8 | move, backstab |
| 200 | **Ambush** | damage/ranged | 39 | ±20% | 1/253 | 18 | 3.9 | 92 | 2.8 | first strike |
| 300 | **Vanish** | buff/support | — | — | — | 22 | 7.8 | 100 | 2.8 | dodge +, fade |
| 340 | **Smoke Bomb** | debuff/ranged | — | — | — | 20 | 6.5 | 100 | 2.4 | blind, acc −, circle AoE, fade |
| 420 | **Hamstring** | damage/ranged | 47 | ±15% | 1/196 | 16 | 3.9 | 90 | 2.7 | root |
| 600 | **Throat Cut** | damage/ranged | 74 | ±10% | 1/166 | 30 | 6.5 | 90 | 2.5 | **silence** |
| 850 | **Heartseeker** | damage/ranged | 36 | ±30% | 1/136 | 26 | 5.2 | 92 | 2.8 | multi-hit, execute |

- **Shadowstep** — Steps through the shadow behind them. The only reliable way past a front line.
- **Ambush** — Devastating on someone who has not swung yet — worthless once they have seen you.
- **Vanish** — Gone. Attackers lose interest and swing at whoever is left.
- **Smoke Bomb** — Blinds everything close and covers the exit — the setup Ambush wants.
- **Hamstring** — Cuts the leg out from under them. They keep fighting; they stop leaving.
- **Throat Cut** — Quiet, precise, and it ends the casting. What the Assassin line exists to do.
- **Heartseeker** — Two or three finding strikes, lethal against anything already failing.

### Venomcraft

| lv | ability | type | pwr | ± | scale | mp | cd (s) | acc | rng | keywords |
|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| 90 | **Piercing Shot** | damage/ranged | 17 | ±20% | 1/295 | 14 | 2.6 | 90 | 9 | poison, multi-hit, contagion |
| 180 | **Toxin Stack** | damage/ranged | 27 | ±15% | 1/260 | 10 | 2.6 | 92 | 8.9 | poison |
| 220 | **Fester** | damage/ranged | 28 | ±20% | 1/246 | 8 | 2.6 | 92 | 9.2 | detonate |
| 280 | **Twin Fangs** | damage/ranged | 17 | ±25% | 1/229 | 14 | 2.6 | 90 | 9 | bleed, multi-hit |
| 400 | **Paralytic Dart** | damage/ranged | 53 | ±15% | 1/200 | 22 | 5.2 | 90 | 8.3 | **stun** |
| 560 | **Virulence** | damage/ranged | 52 | ±20% | 1/172 | 20 | 6.5 | 90 | 8.4 | detonate |
| 740 | **Plague Shot** | damage/ranged | 45 | ±20% | 1/148 | 34 | 6.5 | 85 | 7.2 | poison, contagion, circle AoE |

- **Piercing Shot** — One or two venom-tipped shots, and the venom may pass to a neighbour.
- **Toxin Stack** — A cheap second dose. Poison is the point; the dart barely matters.
- **Fester** — Digs at a poisoned wound until the venom does the rest.
- **Twin Fangs** — Two quick shots that open a wound — bleed here, poison everywhere else in the line.
- **Paralytic Dart** — DEX's one hard control: a neurotoxin that drops them where they stand.
- **Virulence** — Feeble on clean blood, ruinous on poisoned — the payoff the whole line builds toward.
- **Plague Shot** — Poison that jumps between bodies. It rewards an enemy that stands together.

### Volley

| lv | ability | type | pwr | ± | scale | mp | cd (s) | acc | rng | keywords |
|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| 40 | **Sling** | damage/ranged | 13 | ±30% | 1/320 | 5 | 1.3 | 95 | 11 | multi-hit |
| 40 | **Sidestep** | buff/support | — | — | — | 8 | 5.2 | 100 | 10.5 | dodge + |
| 160 | **Acrobatics** | buff/support | — | — | — | 12 | 5.2 | 100 | 10.5 | dodge + |
| 240 | **Focus Aim** | buff/support | — | — | — | 14 | 6.5 | 100 | 10.5 | acc + |
| 330 | **Pin Down** | damage/ranged | 40 | ±15% | 1/216 | 18 | 3.9 | 88 | 10 | pull, root |
| 470 | **Gambler's Volley** | damage/ranged | 10 | ±50% | 1/187 | 20 | 3.9 | 85 | 11 | multi-hit |
| 500 | **Ricochet** | damage/ranged | 34 | ±30% | 1/181 | 26 | 5.2 | 88 | 8.9 | multi-hit, circle AoE |
| 650 | **Rain of Arrows** | damage/ranged | 52 | ±25% | 1/159 | 34 | 6.5 | 85 | 8.4 | circle AoE, push |
| 680 | **Pinning Volley** | damage/ranged | 48 | ±20% | 1/155 | 32 | 6.5 | 88 | 8.5 | circle AoE, root |
| 920 | **Deadeye** | damage/ranged | 131 | ±5% | 1/130 | 44 | 7.8 | 95 | 9.2 | — |

- **Sling** — One or two quick shots. Cheap enough to throw all day.
- **Sidestep** — Footwork. Small, cheap, and always available.
- **Acrobatics** — A tumbling, weaving burst — almost untouchable, but only for a moment.
- **Focus Aim** — Steadies the breathing. The gambler choosing, briefly, not to gamble.
- **Pin Down** — Suppressing fire that drags them out of position and holds them there.
- **Gambler's Volley** — Everything in the quiver, all at once, aimed roughly. Anywhere from a scratch to a slaughter.
- **Ricochet** — One shot, several bodies. It bounces, and it does not much care whose.
- **Rain of Arrows** — A bombardment onto a chosen patch of ground — it punishes standing together.
- **Pinning Volley** — Nails several of them to the spot at once.
- **Deadeye** — One shot. It goes exactly where it was sent.

## CON

23 abilities · lines: Warden · Guardian · Bulwark

### Warden

| lv | ability | type | pwr | ± | scale | mp | cd (s) | acc | rng | keywords |
|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| 140 | **Body Slam** | damage/melee | 17 | ±20% | 1/274 | 14 | 2.6 | 90 | 3 | **knockback**, move, push |
| 160 | **Seize** | damage/melee | 26 | ±15% | 1/267 | 14 | 3.9 | 90 | 3 | pull, root |
| 240 | **Shield Wall** | control/support | — | — | — | 30 | 7.8 | 100 | 3 | guard, zone |
| 300 | **Quagmire Stomp** | damage/melee | 21 | ±20% | 1/223 | 30 | 6.5 | 85 | 2.5 | **knockback**, circle AoE, slow |
| 380 | **Barricade** | control/support | — | — | — | 26 | 7.8 | 100 | 3 | def +, zone |
| 460 | **Tremor** | damage/melee | 17 | ±20% | 1/189 | 28 | 5.2 | 88 | 2.5 | circle AoE, slow |
| 520 | **Zone of Control** | control/support | — | — | — | 28 | 6.5 | 100 | 3 | thorns, zone |
| 620 | **Crushing Grip** | damage/melee | 31 | ±15% | 1/163 | 26 | 5.2 | 90 | 2.7 | root |
| 700 | **Earthen Grasp** | damage/melee | 23 | ±15% | 1/153 | 36 | 7.8 | 85 | 2.5 | circle AoE, root |

- **Body Slam** — Throws its bulk into them and sends them reeling.
- **Seize** — Clamps on and hauls them in. They can still fight; they cannot leave.
- **Shield Wall** — Plants a wall and holds it: +14 mitigation, and the ground around it becomes a slog.
- **Quagmire Stomp** — Churns the footing out from under the whole line.
- **Barricade** — Throws up cover and settles in behind it — the crossing in front becomes slow and costly.
- **Tremor** — The ground shudders. Everything nearby is slowed and staggered.
- **Zone of Control** — Nothing moves well beside it, and everything that tries gets clipped.
- **Crushing Grip** — Takes hold and squeezes. It is not going anywhere while this lasts.
- **Earthen Grasp** — Stone closes on every ankle in reach. The Warden capstone: nobody leaves.

### Guardian

| lv | ability | type | pwr | ± | scale | mp | cd (s) | acc | rng | keywords |
|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| 90 | **Taunt** | debuff/support | — | — | — | 10 | 5.2 | 100 | 4.5 | atk −, taunt |
| 120 | **Barbed Carapace** | buff/support | — | — | — | 24 | 6.5 | 100 | 6 | def +, thorns |
| 200 | **Steady Vigil** | buff/support | 18 | ±15% | 1/253 | 18 | 5.2 | 100 | 6 | hp regen |
| 340 | **Interpose** | buff/support | — | — | — | 24 | 6.5 | 100 | 6 | ward, def + |
| 650 | **Bulwark's Challenge** | debuff/support | — | — | — | 40 | 7.8 | 100 | 3.8 | guard, taunt, circle AoE |
| 760 | **Aegis of the Fallen** | buff/support | — | — | — | 48 | 9.1 | 100 | 6 | ward, def + |

- **Taunt** — Enrages one of them into coming for you, and swinging softer for it.
- **Barbed Carapace** — The whole line bristles: +4 mitigation and 6 damage returned on every hit.
- **Steady Vigil** — Stands over a wounded ally: heals, then keeps healing.
- **Interpose** — Steps in front of an ally: a 34 HP shield and +8 mitigation, put where it is needed rather than kept.
- **Bulwark's Challenge** — Plants its feet and roars: massive guard, and the WHOLE enemy team comes for it.
- **Aegis of the Fallen** — A shield over every ally at once — 45 HP of absorb each, and armour under it.

### Bulwark

| lv | ability | type | pwr | ± | scale | mp | cd (s) | acc | rng | keywords |
|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| 40 | **Brace** | buff/support | — | — | — | 5 | 2.6 | 100 | 3 | guard |
| 240 | **Bastion** | buff/support | — | — | — | 16 | 5.2 | 100 | 3 | ward |
| 280 | **Overrun** | damage/melee | 22 | ±20% | 1/229 | 18 | 3.9 | 88 | 3 | **knockback**, move, push |
| 380 | **Shell Slam** | damage/melee | 26 | ±20% | 1/205 | 22 | 3.9 | 85 | 2.9 | recoil, hp scaling |
| 430 | **Fortify** | buff/support | — | — | — | 44 | 6.5 | 100 | 4.1 | ward |
| 600 | **Retaliate** | buff/support | — | — | — | 22 | 5.2 | 100 | 3 | thorns, def + |
| 780 | **Vital Surge** | buff/support | 46 | ±15% | 1/144 | 34 | 7.8 | 100 | 2.6 | cleanse |
| 850 | **Colossus Crash** | damage/melee | 26 | ±20% | 1/136 | 32 | 6.5 | 85 | 2.7 | guard, %max HP, spend ward, move, push |

- **Brace** — Small, cheap, always there.
- **Bastion** — Raise a 25 HP absorb shield. Fortify is the version for everyone else.
- **Overrun** — Charges straight through: damage and a shove, paid for with momentum.
- **Shell Slam** — Hits hardest while the shell is whole, and fades as its own health fails.
- **Fortify** — A 40 HP absorb shield on every ally. Uncapped reach, priced in mana.
- **Retaliate** — Answers everything: 16 damage returned per hit for 2 rounds.
- **Vital Surge** — Shrugs it all off and knits shut. CON heals ITSELF; healing others is WIS.
- **Colossus Crash** — A crushing advance that braces after the blow; the bigger they are, the more it takes.

## WIS

23 abilities · lines: Disruptor · Mender · Siphon

### Disruptor

| lv | ability | type | pwr | ± | scale | mp | cd (s) | acc | rng | keywords |
|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| 200 | **Silencing Spike** | damage/support | 17 | ±15% | 1/253 | 18 | 2.6 | 90 | 6.2 | **silence**, mana burn |
| 300 | **Wither** | damage/support | 21 | ±15% | 1/223 | 20 | 5.2 | 90 | 6.2 | lifesteal, mana burn |
| 320 | **Null Field** | control/support | — | — | — | 34 | 7.8 | 100 | 7 | mp regen, zone |
| 330 | **Enfeeble** | debuff/support | — | — | — | 22 | 5.2 | 95 | 7 | atk −, acc − |
| 420 | **Hush** | control/support | — | — | — | 18 | 5.2 | 95 | 7 | **silence** |
| 540 | **Field of Doom** | debuff/support | — | — | — | 26 | 6.5 | 95 | 7 | doom, atk − |
| 700 | **Dread Whisper** | debuff/support | — | — | — | 28 | 6.5 | 95 | 7 | **fear** |
| 780 | **Mind Crush** | damage/support | 46 | ±15% | 1/144 | 34 | 6.5 | 85 | 6.2 | mana burn, detonate |

- **Silencing Spike** — A psychic jab that drinks 13 MP and can close the throat entirely.
- **Wither** — Saps them round on round and feeds you what it takes.
- **Null Field** — A patch of dead air. Nothing casts well inside it, including what walks in.
- **Enfeeble** — They hit softer and they miss more. The Disruptor pressure debuff.
- **Hush** — No damage, no flourish — just silence, reliably, for three rounds.
- **Field of Doom** — A dampening field, and a clock. Mind Crush knows what to do with the clock.
- **Dread Whisper** — WIS's one hard control: a word in the ear, and they run.
- **Mind Crush** — A heavy psychic blow that detonates their Doom early. The payoff.

### Mender

| lv | ability | type | pwr | ± | scale | mp | cd (s) | acc | rng | keywords |
|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| 40 | **Mend** | buff/support | 15 | ±15% | 1/320 | 8 | 3.9 | 100 | 8.2 | — |
| 120 | **Clarity** | buff/support | — | — | — | 12 | 3.9 | 100 | 8 | cleanse |
| 260 | **Renewal** | buff/support | 11 | ±15% | 1/234 | 18 | 5.2 | 100 | 8.5 | hp regen |
| 300 | **Mending Surge** | buff/support | 97 | ±15% | 1/223 | 34 | 7.8 | 100 | 8 | — |
| 320 | **Tranquility** | buff/support | 74 | ±15% | 1/218 | 26 | 6.5 | 100 | 7.3 | — |
| 560 | **Rebuke** | damage/support | 34 | ±20% | 1/172 | 24 | 5.2 | 90 | 7.2 | — |
| 650 | **Ward Against Ruin** | buff/support | 24 | ±15% | 1/159 | 34 | 9.1 | 100 | 8 | def +, mp regen |

- **Mend** — Soothing focus, given to somebody else. WIS is the only stat that can.
- **Clarity** — Clears an ally's head — confusion, charm, fear, all of it.
- **Renewal** — Not a burst but a tide: 8 HP a round for four rounds.
- **Mending Surge** — A flood of restoration into one body — the burst answer to burst.
- **Tranquility** — Deep restorative calm channelled into one ally.
- **Rebuke** — The healer answers back. A mender is not the same thing as a bystander.
- **Ward Against Ruin** — Hardens the whole team against what is coming — 8% less damage taken, and a little mending with it.

### Siphon

| lv | ability | type | pwr | ± | scale | mp | cd (s) | acc | rng | keywords |
|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| 90 | **Mana Sap** | damage/support | 15 | ±15% | 1/295 | 8 | 2.6 | 92 | 6.6 | mana burn |
| 140 | **Mind Spike** | damage/support | 17 | ±15% | 1/274 | 8 | 2.6 | 92 | 6.5 | — |
| 160 | **Serenity** | buff/support | — | — | — | 12 | 6.5 | 100 | 6.5 | mp regen, dodge + |
| 240 | **Attunement** | buff/support | — | — | — | 30 | 5.2 | 100 | 6.5 | mp regen |
| 380 | **Drain Spirit** | damage/support | 27 | ±15% | 1/205 | 20 | 5.2 | 88 | 6.1 | mana burn, lifesteal |
| 600 | **Spirit Siphon** | damage/support | 40 | ±20% | 1/166 | 30 | 6.5 | 88 | 5.7 | mana burn, lifesteal |
| 820 | **Judgement** | damage/support | 60 | ±20% | 1/139 | 38 | 7.8 | 88 | 5.7 | — |
| 850 | **Providence** | buff/support | 18 | ±15% | 1/136 | 40 | 9.1 | 100 | 6.8 | cleanse, hp regen |

- **Mana Sap** — Drinks 14 MP straight out of them. Once the worst move in the game; now a real theft.
- **Mind Spike** — A cheap psychic jab — the filler WIS never had and could never afford.
- **Serenity** — Calm flow. The one self-regen — the other three were the same move wearing hats.
- **Attunement** — Links the team's focus: everyone regains mana faster. Distinct from Serenity by REACH.
- **Drain Spirit** — Takes both at once — their mana, and a share of their blood.
- **Spirit Siphon** — Holds on and drains, HP and MP together, for as long as it lasts.
- **Judgement** — A real capstone HIT rather than one more aura. WIS can end things too.
- **Providence** — Sees what is coming: clears the team and steadies it. Restoration — empowerment is CHA.

## INT

23 abilities · lines: Hexer · Elementalist · Arcanist

### Hexer

| lv | ability | type | pwr | ± | scale | mp | cd (s) | acc | rng | keywords |
|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| 40 | **Ember** | damage/magic | 14 | ±20% | 1/320 | 6 | 2.6 | 90 | 7.9 | burn |
| 120 | **Fracturing Stones** | damage/magic | 24 | ±20% | 1/282 | 14 | 2.6 | 90 | 7.5 | vulnerable |
| 200 | **Cinderburst** | damage/magic | 37 | ±15% | 1/253 | 20 | 3.9 | 88 | 7 | detonate |
| 280 | **Sap Will** | debuff/magic | — | — | — | 18 | 5.2 | 95 | 7.5 | atk − |
| 340 | **Arcane Bomb** | damage/magic | 37 | ±20% | 1/214 | 26 | 5.2 | 88 | 6.6 | detonate, circle AoE |
| 480 | **Curse of Ruin** | debuff/magic | — | — | — | 24 | 6.5 | 95 | 7.5 | def − |
| 700 | **Detonate** | damage/magic | 51 | ±25% | 1/153 | 38 | 6.5 | 85 | 5.6 | detonate, circle AoE |

- **Ember** — Minor fire, and it catches. The cheapest way to start a stack.
- **Fracturing Stones** — A stinging barrage that cracks the guard. The second stack type.
- **Cinderburst** — Solid on its own, and it snuffs a Burn for far more. The first detonator.
- **Sap Will** — Drains the will to strike: −22% damage for 3 rounds. INT could not do this at all before.
- **Arcane Bomb** — A charge left ticking on them — devastating on anything already cracked open.
- **Curse of Ruin** — Unpicks whatever is holding them together: −14 mitigation from EVERY source of damage.
- **Detonate** — Sets off everything still burning, on everyone at once. The Hexer capstone.

### Elementalist

| lv | ability | type | pwr | ± | scale | mp | cd (s) | acc | rng | keywords |
|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| 90 | **Frost Shard** | damage/magic | 23 | ±20% | 1/295 | 12 | 2.6 | 90 | 8.3 | — |
| 160 | **Rime Bind** | damage/magic | 34 | ±15% | 1/267 | 16 | 3.9 | 90 | 8 | root |
| 280 | **Frost Nova** | damage/magic | 31 | ±20% | 1/229 | 26 | 5.2 | 85 | 6.9 | circle AoE, slow |
| 400 | **Firewall** | control/magic | — | — | — | 30 | 6.5 | 100 | 8 | zone |
| 430 | **Inferno** | damage/magic | 44 | ±25% | 1/194 | 32 | 5.2 | 82 | 6.6 | burn, circle AoE |
| 560 | **Seismic Crush** | damage/magic | 53 | ±25% | 1/172 | 38 | 6.5 | 82 | 6.3 | **stun**, circle AoE |
| 920 | **World Ender** | damage/magic | 87 | ±30% | 1/130 | 56 | 9.1 | 78 | 6 | %max HP, circle AoE |

- **Frost Shard** — An icy dart. The frost line opens here.
- **Rime Bind** — Ice climbs the legs and sets. It can still cast; it is going nowhere.
- **Frost Nova** — A ring of hoarfrost bursts outward — the anti-melee tool casters never had.
- **Firewall** — A burning line laid across the ground. Not a hit — a place they should not walk.
- **Inferno** — Fire across the whole position, and much of it keeps burning.
- **Seismic Crush** — The ground itself comes up. Damage AND a stun on everything standing on it.
- **World Ender** — The largest thing in the game, and it hurts the biggest of them most.

### Arcanist

| lv | ability | type | pwr | ± | scale | mp | cd (s) | acc | rng | keywords |
|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| 40 | **Spark** | damage/magic | 16 | ±15% | 1/320 | 5 | 1.3 | 95 | 7.4 | — |
| 180 | **Phase Step** | buff/support | — | — | — | 14 | 5.2 | 100 | 7 | dodge +, move |
| 250 | **Mirror Image** | buff/support | — | — | — | 20 | 6.5 | 100 | 7 | dodge + |
| 330 | **Static Chain** | damage/magic | 39 | ±20% | 1/216 | 28 | 5.2 | 85 | 6 | vulnerable, line AoE, slow |
| 335 | **Mana Leech** | damage/magic | 34 | ±15% | 1/215 | 22 | 3.9 | 88 | 6.9 | mana burn, lifesteal, move |
| 560 | **Unmake** | debuff/magic | — | — | — | 26 | 6.5 | 95 | 7 | spend ward, acc − |
| 640 | **Displace** | damage/magic | 50 | ±15% | 1/160 | 26 | 5.2 | 90 | 6.8 | move, push, root |
| 780 | **Void Lance** | damage/magic | 89 | ±10% | 1/144 | 38 | 6.5 | 85 | 6.2 | pierce, move, backstab |
| 850 | **Arcane Overload** | damage/magic | 168 | ±30% | 1/136 | 44 | 7.8 | 85 | 6.2 | recoil |

- **Spark** — A small air bolt, cheap enough to throw between everything else.
- **Phase Step** — Steps out of the world and back a few paces away — through cover, if need be.
- **Mirror Image** — Shimmering duplicates. Attacks keep finding the wrong one.
- **Static Chain** — A bolt that leaps body to body along a line, weakening as it goes.
- **Mana Leech** — Siphons and steps away in the same motion. WIS steals better; this one escapes.
- **Unmake** — Strips the shield off them and leaves their aim shaking.
- **Displace** — Teleports the TARGET — rips a diver out of your back line and pins it where it lands.
- **Void Lance** — Pure void. Half of everything they are wearing simply does not apply.
- **Arcane Overload** — Overchannelled past what the caster can hold. It burns them too.

## CHA

24 abilities · lines: Enchanter · Captain · Demagogue

### Enchanter

| lv | ability | type | pwr | ± | scale | mp | cd (s) | acc | rng | keywords |
|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| 40 | **Discord** | damage/voice | 14 | ±20% | 1/320 | 8 | 2.6 | 90 | 6.5 | blind |
| 160 | **Screech** | damage/voice | 12 | ±20% | 1/267 | 22 | 3.9 | 85 | 5.5 | **fear**, circle AoE |
| 380 | **Sonic Boom** | damage/voice | 28 | ±20% | 1/205 | 26 | 5.2 | 85 | 5.7 | **confusion**, contagion, push |
| 385 | **Lullaby** | control/voice | — | — | — | 24 | 6.5 | 85 | 6.5 | **sleep**, contagion, slow |
| 650 | **Cacophony** | damage/voice | 28 | ±25% | 1/159 | 36 | 6.5 | 82 | 4.9 | **charm**, circle AoE |
| 820 | **Mass Hysteria** | control/voice | — | — | — | 52 | 9.1 | 88 | 5.5 | **fear**, contagion, circle AoE |

- **Discord** — A jarring note that leaves them swinging at afterimages.
- **Screech** — A sound that routs. Hard control across a whole line.
- **Sonic Boom** — A heavy burst, and the disorientation carries to whoever stood too close.
- **Lullaby** — Sings them to actual sleep — a free hit, but any damage wakes them. Drowsiness is catching.
- **Cacophony** — A charmed foe turns on its own team. The best status in the game, and the rarest.
- **Mass Hysteria** — The whole enemy line breaks at once. The Enchanter capstone: nobody gets a turn.

### Captain

| lv | ability | type | pwr | ± | scale | mp | cd (s) | acc | rng | keywords |
|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| 90 | **Rallying Song** | buff/support | — | — | — | 18 | 5.2 | 100 | 7.5 | atk + |
| 140 | **Bravura** | buff/support | — | — | — | 16 | 5.2 | 100 | 7.5 | ward, dodge + |
| 180 | **Anthem of Iron** | buff/support | — | — | — | 24 | 6.5 | 100 | 7.5 | atk +, def + |
| 260 | **Inspire** | buff/support | — | — | — | 16 | 5.2 | 100 | 7.5 | atk +, acc + |
| 300 | **Battle Hymn** | buff/support | — | — | — | 26 | 6.5 | 100 | 7.5 | haste, dodge +, mp regen |
| 340 | **Second Wind** | buff/support | 44 | ±15% | 1/214 | 42 | 11.7 | 100 | 7.5 | — |
| 380 | **Standing Ovation** | buff/support | — | — | — | 42 | 7.8 | 100 | 7.5 | atk +, acc +, hp regen |
| 420 | **Fanfare** | buff/support | — | — | — | 32 | 6.5 | 100 | 7.5 | acc + |
| 470 | **Hymn of Shields** | buff/support | — | — | — | 38 | 7.8 | 100 | 7.5 | ward, guard |
| 880 | **Triumph** | buff/support | — | — | — | 56 | 10.4 | 100 | 7.5 | atk +, acc +, dodge + |

- **Rallying Song** — A stirring tune: the whole team hits harder for 3 rounds.
- **Bravura** — Performs straight through the danger. The bard can look after itself.
- **Anthem of Iron** — Hit harder and hold together — attack and armour in one song.
- **Inspire** — Everything poured into ONE ally. Focused, and cheaper than lifting everyone.
- **Battle Hymn** — A steadying anthem — and the whole team moves first.
- **Second Wind** — A cry that puts the whole line back on its feet — none of them fully.
- **Standing Ovation** — Feeds on applause and hands it straight back to the team.
- **Fanfare** — Team accuracy, sharply. Nothing else in the game hands out aim like this.
- **Hymn of Shields** — A hymn that armours everyone who can hear it, the singer included.
- **Triumph** — The empowerment capstone: everything at once, for two rounds only.

### Demagogue

| lv | ability | type | pwr | ± | scale | mp | cd (s) | acc | rng | keywords |
|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| 120 | **Grand Mockery** | debuff/voice | — | — | — | 22 | 5.2 | 95 | 5.1 | healblock, atk −, circle AoE |
| 200 | **Captivate** | damage/voice | 17 | ±20% | 1/253 | 14 | 3.9 | 88 | 6 | lifesteal, slow |
| 320 | **Crowd Surge** | debuff/voice | 13 | ±20% | 1/218 | 24 | 5.2 | 90 | 5.2 | acc −, circle AoE, push |
| 330 | **Demoralize** | debuff/voice | — | — | — | 30 | 6.5 | 90 | 5.1 | atk −, circle AoE |
| 520 | **Dirge** | debuff/voice | — | — | — | 34 | 7.8 | 95 | 5.1 | healblock, circle AoE |
| 780 | **Siren's Call** | damage/voice | 26 | ±20% | 1/144 | 32 | 6.5 | 85 | 5.6 | mana burn, detonate |
| 850 | **Showstopper** | damage/voice | 43 | ±15% | 1/136 | 36 | 6.5 | 88 | 5.3 | execute |
| 920 | **Crescendo** | damage/voice | 52 | ±25% | 1/130 | 50 | 9.1 | 80 | 4.5 | circle AoE |

- **Grand Mockery** — A cutting jeer: they hit softer, and some of them stop closing.
- **Captivate** — Feeds on adoration and gives nothing back.
- **Crowd Surge** — Shoves the whole enemy line backwards. A DEFENSIVE use of a debuff stat.
- **Demoralize** — Breaks the spirit outright. Deeper than Mockery, and that is the whole difference.
- **Dirge** — While it plays, nothing on that side closes a wound.
- **Siren's Call** — An irresistible song that scatters focus — and shatters the courage of the Afraid.
- **Showstopper** — The closing number, and it closes them.
- **Crescendo** — A voice AoE finisher. CHA damage exists — it is just rare, and it is late.

## Totals

| | count |
|---|---:|
| abilities | 141 |
| lines | 18 |
| hard control | 17 |
| area effects | 28 |
| damage moves | 77 |
| STR | 24 |
| DEX | 24 |
| CON | 23 |
| WIS | 23 |
| INT | 23 |
| CHA | 24 |

---

⚠️ **Elements are removed from the game.** Body types no longer carry a resist/weak
pair and no move carries an element. The INT line named *Elementalist* is unrelated
and stays. See `CLAUDE.md`.
