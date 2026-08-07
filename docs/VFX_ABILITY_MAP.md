# VFX Ability Map — every ability, its animation

Generated 2026-08-06 from `data.json` (141 moves) — regenerate with `python scratchpad/gen_vfx_map.py` after pool changes. Recipes reference the real asset inventory:

## The animation vocabulary

| recipe | status | what it is |
|---|---|---|
| `fireball` | HAVE | fire-sheet projectile + ember trail -> animated explosion on impact |
| `explosion` | HAVE | animated explosion flipbook at the victim |
| `slash` | HAVE | amber slash flash at the victim |
| `bolt` | HAVE | steel bolt projectile -> star impact burst |
| `big_hit` | HAVE | big-hit flash sheet (heavy/crit tier) |
| `fire_ring` | HAVE | expanding fire ring on the ground (AoE tell) |
| `electric_ring` | HAVE | electric ring around the victim (control tell) |
| `charge_ring` | HAVE | charge sheet on the caster at windup start |
| `aura_pulse` | BUILD | circle-sprite ring pulses under EVERY affected ally ~1s + charge on caster (the buff grammar) |
| `heal_rise` | BUILD | green sparks rising over the target + soft glow |
| `debuff_drip` | BUILD | tinted smoke sinking onto the victim + twirl on the caster |
| `venom_spit` | BUILD | green bolt -> sickly smoke burst (poison tint) |
| `smoke_veil` | HAVE | wispy smoke sheet enveloping the target |
| `lightstreaks` | NEW | light-streak sheet (predrawn, in repo) — beams/volleys |
| `blood_hit` | NEW | blood-impact sheet (predrawn, in repo) — bleed/execute hits |
| `frost_veil` | NEW | cloud sheet tinted ice-white — chill/sleep effects |
| `dust_shock` | HAVE | dust shockwave at ground level (knockback/stomp) |
| `spark_storm` | HAVE | gold spark fountain (crit/energy) |
| `scorch_mark` | HAVE | scorch decal burst (burn aftermath) |
| `ward_dome` | BUILD | circle sprite scaled up around target, fading (shield/ward) |
| `siphon_thread` | BUILD | particle stream victim -> caster (drain grammar) |

**HAVE** = asset shipped in `assets/vfx/` today · **BUILD** = procedural from the existing emitter pool (no new assets) · **NEW** = one more sheet copied from the `Potential animations/` folder already in the repo. Nothing external.

## The buff grammar (user direction 2026-08-06)

> *"for buffs we can be more creative, a temporary aura around all of the affected monsters for a second with an animation on the caster."*

Every buff row below uses `aura_pulse`: the caster plays the charge sheet, and a channel-coloured ring pulses under **every** affected monster for ~1s — so a team buff is READABLE as exactly who it touched, which is the legibility rule doing its job on the support tier.


## Arcanist (INT) — 9 moves

| ability | type | channel | target | animation |
|---|---|---|---|---|
| Spark | damage | magic | enemy | fireball -> explosion |
| Phase Step | buff | support | self | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Mirror Image | buff | support | self | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Static Chain | damage | magic | allEnemies | fire_ring + explosion per body (tint: orange) |
| Mana Leech | damage | magic | enemy | fireball -> explosion |
| Unmake | debuff | magic | enemy | debuff_drip |
| Displace | damage | magic | enemy | fireball -> explosion |
| Void Lance | damage | magic | enemy | fireball -> explosion |
| Arcane Overload | damage | magic | enemy | fireball -> explosion |

## Assassin (DEX) — 7 moves

| ability | type | channel | target | animation |
|---|---|---|---|---|
| Shadowstep | damage | ranged | enemy | shadow flash: dark smoke_veil + slash at the victim (a knife, never a bolt) |
| Ambush | damage | ranged | enemy | shadow flash: dark smoke_veil + slash at the victim (a knife, never a bolt) |
| Vanish | buff | support | self | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Smoke Bomb | debuff | ranged | allEnemies | debuff_drip on every victim + twirl on caster (tint: grey) |
| Hamstring | damage | ranged | enemy | shadow flash: dark smoke_veil + slash at the victim (a knife, never a bolt) |
| Throat Cut | damage | ranged | enemy | shadow flash: dark smoke_veil + slash at the victim (a knife, never a bolt) (tint: pale blue) |
| Heartseeker | damage | ranged | enemy | shadow flash: dark smoke_veil + slash at the victim (a knife, never a bolt) |

## Bloodrage (STR) — 7 moves

| ability | type | channel | target | animation |
|---|---|---|---|---|
| Scrap | damage | melee | enemy | slash flash |
| Enrage | buff | support | self | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Blood Price | damage | melee | enemy | blood_hit on the CASTER first, then slash on victim (the cost read) |
| Reckless Slam | damage | melee | enemy | slash flash |
| Last Stand | buff | support | self | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Blood Fury | damage | melee | enemy | slash flash |
| Titanfall | damage | melee | enemy | big_hit + dust_shock |

## Bulwark (CON) — 8 moves

| ability | type | channel | target | animation |
|---|---|---|---|---|
| Brace | buff | support | self | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Bastion | buff | support | self | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Overrun | damage | melee | enemy | dust trail during the charge run + big_hit on collision |
| Shell Slam | damage | melee | enemy | slash flash |
| Fortify | buff | support | team | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Retaliate | buff | support | self | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Vital Surge | buff | support | self | heal_rise + aura_pulse on every affected |
| Colossus Crash | damage | melee | enemy | slash flash |

## Captain (CHA) — 10 moves

| ability | type | channel | target | animation |
|---|---|---|---|---|
| Rallying Song | buff | support | team | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Bravura | buff | support | self | ward_dome (gold) + aura_pulse |
| Anthem of Iron | buff | support | team | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Inspire | buff | support | ally | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Battle Hymn | buff | support | team | aura_pulse (caster charge_ring -> 1s ring under every affected) (tint: white-gold) |
| Second Wind | buff | support | team | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Standing Ovation | buff | support | team | heal_rise + aura_pulse on every affected |
| Fanfare | buff | support | team | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Hymn of Shields | buff | support | team | ward_dome on every ally (aura_pulse grammar) + charge on caster |
| Triumph | buff | support | team | aura_pulse (caster charge_ring -> 1s ring under every affected) |

## Demagogue (CHA) — 8 moves

| ability | type | channel | target | animation |
|---|---|---|---|---|
| Grand Mockery | debuff | voice | allEnemies | debuff_drip on every victim + twirl on caster (tint: ash) |
| Captivate | damage | voice | enemy | expanding circle ring at victim |
| Crowd Surge | debuff | voice | allEnemies | debuff_drip on every victim + twirl on caster |
| Demoralize | debuff | voice | allEnemies | debuff_drip on every victim + twirl on caster |
| Dirge | debuff | voice | allEnemies | debuff_drip on every victim + twirl on caster (tint: ash) |
| Siren's Call | damage | voice | enemy | expanding circle ring at victim |
| Showstopper | damage | voice | enemy | expanding circle ring at victim |
| Crescendo | damage | voice | allEnemies | expanding circle ring + debuff_drip |

## Disruptor (WIS) — 8 moves

| ability | type | channel | target | animation |
|---|---|---|---|---|
| Silencing Spike | damage | support | enemy | slash flash (tint: pale blue) |
| Wither | damage | support | enemy | slash flash |
| Null Field | control | support | self | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Enfeeble | debuff | support | enemy | debuff_drip |
| Hush | control | support | enemy | electric_ring on victim + charge_ring on caster (tint: pale blue) |
| Field of Doom | debuff | support | enemy | debuff_drip (tint: black-violet) |
| Dread Whisper | debuff | support | enemy | debuff_drip (tint: violet) |
| Mind Crush | damage | support | enemy | slash flash |

## Duelist (STR) — 9 moves

| ability | type | channel | target | animation |
|---|---|---|---|---|
| Power Strike | damage | melee | enemy | slash flash |
| Sunder | debuff | melee | enemy | debuff_drip |
| Riposte | buff | support | self | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Headbutt | damage | melee | enemy | slash flash (tint: gold) |
| Bonebreaker | damage | melee | enemy | slash flash (tint: orange) |
| Twist the Knife | damage | melee | enemy | blood_hit + DETONATED float (already wired) |
| Rend | damage | melee | enemy | slash flash (tint: dark red) |
| Bloodletter | damage | melee | enemy | blood_hit (large) |
| Executioner | damage | melee | enemy | big_hit + blood_hit (execute tier) |

## Elementalist (INT) — 7 moves

| ability | type | channel | target | animation |
|---|---|---|---|---|
| Frost Shard | damage | magic | enemy | fireball -> explosion |
| Rime Bind | damage | magic | enemy | fireball -> explosion |
| Frost Nova | damage | magic | allEnemies | fire_ring + explosion per body |
| Firewall | control | magic | self | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Inferno | damage | magic | allEnemies | fire_ring + explosion per body struck |
| Seismic Crush | damage | magic | allEnemies | fire_ring + explosion per body (tint: gold) |
| World Ender | damage | magic | allEnemies | fire_ring + explosion per body |

## Enchanter (CHA) — 6 moves

| ability | type | channel | target | animation |
|---|---|---|---|---|
| Discord | damage | voice | enemy | expanding circle ring at victim (tint: grey) |
| Screech | damage | voice | allEnemies | expanding circle ring + debuff_drip (tint: violet) |
| Sonic Boom | damage | voice | enemy | expanding circle ring (BUILD: scaled circle sprite) + dust_shock |
| Lullaby | control | voice | enemy | aura_pulse (lavender) drifting NOTES-like circles over victims |
| Cacophony | damage | voice | allEnemies | expanding circle ring + debuff_drip (tint: rose) |
| Mass Hysteria | control | voice | allEnemies | debuff_drip (violet) on every victim + twirl storm on caster |

## Guardian (CON) — 6 moves

| ability | type | channel | target | animation |
|---|---|---|---|---|
| Taunt | debuff | support | enemy | electric_ring (orange) on caster + TAUNTED float (already wired) |
| Barbed Carapace | buff | support | team | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Steady Vigil | buff | support | ally | heal_rise + aura_pulse on every affected |
| Interpose | buff | support | ally | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Bulwark's Challenge | debuff | support | allEnemies | fire_ring (orange, defensive ring) + TAUNTED floats |
| Aegis of the Fallen | buff | support | team | aura_pulse (caster charge_ring -> 1s ring under every affected) |

## Hexer (INT) — 7 moves

| ability | type | channel | target | animation |
|---|---|---|---|---|
| Ember | damage | magic | enemy | fireball -> explosion (tint: ember orange) |
| Fracturing Stones | damage | magic | enemy | fireball -> explosion (tint: orange) |
| Cinderburst | damage | magic | enemy | explosion + scorch_mark (detonate tell already fires) |
| Sap Will | debuff | magic | enemy | debuff_drip |
| Arcane Bomb | damage | magic | enemy | fireball -> explosion |
| Curse of Ruin | debuff | magic | enemy | debuff_drip |
| Detonate | damage | magic | allEnemies | explosion (large) + scorch_mark |

## Mender (WIS) — 7 moves

| ability | type | channel | target | animation |
|---|---|---|---|---|
| Mend | buff | support | ally | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Clarity | buff | support | ally | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Renewal | buff | support | ally | heal_rise + aura_pulse on every affected |
| Mending Surge | buff | support | ally | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Tranquility | buff | support | ally | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Rebuke | damage | support | enemy | slash flash |
| Ward Against Ruin | buff | support | team | aura_pulse (caster charge_ring -> 1s ring under every affected) |

## Siphon (WIS) — 8 moves

| ability | type | channel | target | animation |
|---|---|---|---|---|
| Mana Sap | damage | support | enemy | siphon_thread |
| Mind Spike | damage | support | enemy | siphon_thread |
| Serenity | buff | support | self | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Attunement | buff | support | team | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Drain Spirit | damage | support | enemy | siphon_thread |
| Spirit Siphon | damage | support | enemy | siphon_thread |
| Judgement | damage | support | enemy | siphon_thread |
| Providence | buff | support | team | heal_rise + aura_pulse on every affected |

## Venomcraft (DEX) — 7 moves

| ability | type | channel | target | animation |
|---|---|---|---|---|
| Piercing Shot | damage | ranged | enemy | lightstreak that continues THROUGH the victim (pierce read) |
| Toxin Stack | damage | ranged | enemy | venom_spit (tint: sickly green) |
| Fester | damage | ranged | enemy | venom_spit |
| Twin Fangs | damage | ranged | enemy | venom_spit (tint: dark red) |
| Paralytic Dart | damage | ranged | enemy | venom_spit (tint: gold) |
| Virulence | damage | ranged | enemy | venom_spit |
| Plague Shot | damage | ranged | allEnemies | venom_spit + contagion smoke (already wired) on spread |

## Volley (DEX) — 10 moves

| ability | type | channel | target | animation |
|---|---|---|---|---|
| Sling | damage | ranged | enemy | 2x staggered bolts + spark bursts |
| Sidestep | buff | support | self | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Acrobatics | buff | support | self | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Focus Aim | buff | support | self | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Pin Down | damage | ranged | enemy | bolt -> star impact |
| Gambler's Volley | damage | ranged | enemy | THREE staggered bolts with spark bursts (variance read) |
| Ricochet | damage | ranged | allEnemies | 2x staggered bolts + spark bursts |
| Rain of Arrows | damage | ranged | allEnemies | bolt fan + star impacts |
| Pinning Volley | damage | ranged | allEnemies | bolt fan + star impacts |
| Deadeye | damage | ranged | enemy | single lightstreak beam + star impact (precision read) |

## Warcry (STR) — 8 moves

| ability | type | channel | target | animation |
|---|---|---|---|---|
| Guard | buff | support | self | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Cleave | damage | melee | allEnemies | slash flash |
| Intimidate | debuff | voice | allEnemies | debuff_drip on every victim + twirl on caster (tint: violet) |
| Challenge | debuff | voice | enemy | electric_ring (orange) + chest-beat charge sheet on caster |
| Bracer | buff | support | self | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Whirlwind | damage | melee | allEnemies | slash flash |
| Earthshaker | damage | melee | allEnemies | slash flash (tint: gold) |
| Warlord's Roar | buff | support | team | aura_pulse (caster charge_ring -> 1s ring under every affected) |

## Warden (CON) — 9 moves

| ability | type | channel | target | animation |
|---|---|---|---|---|
| Body Slam | damage | melee | enemy | dust_shock + big_hit (the LAUNCHED float already lands) |
| Seize | damage | melee | enemy | slash flash |
| Shield Wall | control | support | self | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Quagmire Stomp | damage | melee | allEnemies | dust_shock (mud-brown tint) + fire_ring recoloured earth |
| Barricade | control | support | self | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Tremor | damage | melee | allEnemies | slash flash |
| Zone of Control | control | support | self | aura_pulse (caster charge_ring -> 1s ring under every affected) |
| Crushing Grip | damage | melee | enemy | slash flash |
| Earthen Grasp | damage | melee | allEnemies | slash flash |
