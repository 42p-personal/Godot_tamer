import { Dispatch, ReactNode, SetStateAction, useEffect, useMemo, useRef, useState } from 'react'
import {
  BODY_MINOR, BodyType, isFusionBody, isPrestigeBody, CC_INFO, COMBO_INFO, DEFAULT_TACTICS, FOODS, FoodDef, FoodTier, GAMEPLANS, INNATE_SECONDARY_LEVEL, LEAGUES, MANA_POLICY_INFO, MatchOrders, Monster, Move, PRESERVE_INFO, STATS, Stat,
  TARGET_PRIORITY_INFO, TEMPERAMENT_INFO, Tactics, classForStats,
  feedDelta, frontRowCount, happinessMultiplier, hashString, mulberry32, roleOfClass, rowOfSlot,
} from './core'
import { CASHABLE_STATUSES } from './moves'
import { generateMonster, manaCost, maxHp, maxMana, staminaDamageMult } from './monster'
import { BattleResult, simulateTeamBattle } from './battle'
import { analyzeBattle, battleAdvice } from './battleReport'
import { ArenaBattle } from './arena'
import { Sprite } from './Sprite'
import { SPECIES } from './species'
import { BIOS } from './bestiary'
import { ALL_DRILLS, BASIC_DRILLS, DIVERSE_DRILLS, DIVERSE_GAIN, Drill, EXTREME_COST, EXTREME_DRILLS, EXTREME_GAIN, INTENSIVE_DRILLS } from './drills'
import { signatureName } from './signature'
import { signatureChoicesFor } from './signatureMoves'
import {
  Career, EXTREME_DRILL_STAMINA, DIVERSE_DRILL_STAMINA, drillStamina, MAX_STAMINA, canRankUp, careerMonster, careerSpanYears, statCapFor,
  dateLabel, foodName, FORAGE_STAMINA_COST, FORAGE_HAPPINESS_COST, WILD_GEN1_CAP, previewWeekEffects, stageInfo, trainingProfileFor,
} from './game'
import {
  PANTRY_CONTRACT_COST, GRAND_LARDER_COST, ELITE_LICENSE_COST, ELITE_LICENSE_LEAGUE, EventMatch, EventStanding, GameState, PendingEvent, RIVAL_BAND_MIN, rivalBudgetMult, SPECIAL_LICENSE_COST, SPECIAL_LICENSE_LEAGUE,
  canBuySpecialLicense, canBuyEliteLicense, COACH_CAP_LIFT, wildCapFor,
  MARKET_BASE_SLOTS, MARKET_SLOTS_MAX, SCOUT_CHANCE, COACH_SURCHARGE, marketSlotCost, scoutCost, coachCost, coachLeague,
  buyMarketSlot, buyMarketScout, buyMarketCoach, setScoutPick, canBuyMarketCoach, coachVisible, speciesLicensed,
  COMFORT_ITEMS, EXTREME_MANUAL_COST, DIVERSE_MANUAL_COST, buyDiverseManual, BATTLE_ANALYST_COST, buyBattleAnalyst, Frozen, careerFromFrozen, BREED_COST, BREED_MAX_CHILDREN, applyStudBook, breed, breedPotentialV2, buyComfortItem, buyExtremeManual, studIncome, podiumsOf, champsOf, useTonic,
  WeekPlanEntry, advanceWeek, barnCost, buyPantryContract, buyGrandLarder, buyEliteLicense, buyMonster, foodDiscountFor, resolveEvent,
  buySpecialLicense, cancelSignUp, cupLore, eligibleForTournament, fusionRoom, gameplanForRivalTeam, generateRivalTeamsForTournament, goto, healAtInfirmary, infirmaryFee, leagueIndexOf, monthOfWeek,
  placementLabel, scoutFee, teamSizeForLeague, seatedRivalTeamIndex,
  trainerXpProgress, trainerBarnBonus, trainerLevel, trainerStipend, effectiveBarnCap, barnFull as barnFullOf, BREEDING_BONUS,
  buyLicense, cancelTrial, nextLicenseCost, startTrial, trialStatus, trialChampionMult, RIVAL_PERSONALITY_GAMEPLAN,
  fuse, fusionSpin, fusionRecipeFor, fusablePairIn, freezeToLab, thawFromLab, expandLab, labExpandCost, LAB_SLOTS_BASE, FUSION_COST,
  generateRival, newGame, offerMonster, renameMonster, rewardMultiplier, setActiveInnate, setLoadout, signUp, pendingCupIsThisWeek, isSignUpOpen,
  applyMarkToOpponent, buildEventPlayerTeam, finalizeCup, finalizeRite, finalizeTrial, roundRobinSchedule,
  riteStatus, riteEligible, riteRoster, startRite, cancelRite, riteChampionMult, claimSignature, SIGNATURE_RITE_LEVEL,
  tournamentCalendarFor, upgradeBarn, visibleLeagueCount, weekOfMonth, yearOfWeek,
} from './town'
import { AREA_BACKGROUND, AreaArtKey, TOWN_AREA_ART } from './areaArt'
import { APP_VERSION } from './version'

const STAT_COLOR: Record<Stat, string> = {
  STR: 'var(--str)', DEX: 'var(--dex)', CON: 'var(--con)',
  WIS: 'var(--wis)', INT: 'var(--int)', CHA: 'var(--cha)',
}

function StatBar({ stat, value, max }: { stat: Stat; value: number; max: number }) {
  return (
    <div className="stat">
      <span>{stat}</span>
      <span className="bar"><i style={{ width: `${Math.min(100, (value / max) * 100)}%`, background: STAT_COLOR[stat] }} /></span>
      <span className="v">{value}</span>
    </div>
  )
}


// Training-aptitude marks (2026-07-25): one uniform rendering used everywhere a
// species' growth profile is summarised, so it reads the same on the Market
// card, the Bestiary, and a monster card. Each mark is a coloured arrow + its
// stat, both tinted to that stat's colour. Major = ▲ (large up), minor = ▴
// (small up — a weaker buff), flaw = ▼ (down). The magnitude/word lives in the
// tooltip so the line stays a clean set of same-shaped, same-coloured marks.
const APT_MARK = {
  major: { glyph: '▲', cls: 'major', label: 'major aptitude · trains +20% faster' },
  minor: { glyph: '▴', cls: 'minor', label: 'minor aptitude · trains +10% faster' },
  flaw: { glyph: '▼', cls: 'flaw', label: 'training flaw · trains −20% slower' },
  flawSoft: { glyph: '▽', cls: 'flaw', label: 'minor flaw · trains only −5% slower' },
} as const
function AptMark({ kind, stat }: { kind: keyof typeof APT_MARK; stat: Stat }) {
  const a = APT_MARK[kind]
  return <span className={'aptmark ' + a.cls} style={{ color: STAT_COLOR[stat] }} title={`${stat} — ${a.label}`}>{a.glyph}&nbsp;{stat}</span>
}
// softFlaw: prestige bodies carry only a gentle −5% flaw (Mythical carry none).
function AptMarks({ prof, softFlaw }: { prof: { major?: Stat; minor: Stat; flaw?: Stat }; softFlaw?: boolean }) {
  return (
    <span className="aptmarks">
      {prof.major && <AptMark kind="major" stat={prof.major} />}
      {prof.minor !== prof.major && <AptMark kind="minor" stat={prof.minor} />}
      {prof.flaw && <AptMark kind={softFlaw ? 'flawSoft' : 'flaw'} stat={prof.flaw} />}
    </span>
  )
}

// Training aptitude — same metric the Ranch screen tags stats with, so this
// line always agrees with it.
function Signature({ m }: { m: Monster }) {
  return (
    <div className="meta sig">
      <AptMarks prof={trainingProfileFor(m.species)} softFlaw={isPrestigeBody(m.species.body)} />
      <span className="dim">training aptitude</span>
    </div>
  )
}

// Compact effect label for a food button (2026-07-25): the primary effect
// in-line (not tooltip-only), plus a muted `cost` line for the training foods'
// downside. Normal foods show the taste outcome for the current monster.
function foodEffectLabel(f: FoodDef, c: Career): { primary: string; cls: string; cost?: string } {
  if (f.tier === 'normal') {
    const d = feedDelta(f.id, c.favouriteFood, c.hatedFood)
    return d > 0 ? { primary: '♥ favourite · +1', cls: 'pos' } : d < 0 ? { primary: '✖ hated · −1', cls: 'neg' } : { primary: 'neutral', cls: 'dim' }
  }
  if (f.boostStats) return {
    primary: `${f.boostStats.join('·')} +${Math.round((f.boostMult ?? 0) * 100)}%`, cls: 'pos',
    cost: `−${Math.abs(f.happiness ?? 0)} happiness · ${f.stamina} stamina`,
  }
  if (f.rewardMult) return { primary: 'win cup → +50% reward', cls: 'gold' }
  if (f.stamina) return { primary: `+${f.stamina} stamina`, cls: 'pos' }
  if (f.happiness) return { primary: `+${f.happiness} happiness`, cls: 'pos' }
  return { primary: '', cls: 'dim' }
}

// HP → MP → Stamina → Happiness, in that order (user spec 2026-07-19) —
// shared between the feeding screen and the Ranch detail panel so the two
// never drift out of sync. Bars turn amber/red as condition worsens so an
// injured monster reads as injured at a glance, not as a hairline sliver.
const hpBarColor = (frac: number) =>
  frac < 0.25 ? '#ef5350' : frac < 0.6 ? '#ffb74d' : 'linear-gradient(90deg, #43a047, #7cb342)'
const mpBarColor = (frac: number) =>
  frac < 0.25 ? '#ffb74d' : 'linear-gradient(90deg, #1e88e5, #42a5f5)'
// Injured enough to warn about before a fight (also drives strip chips).
const isInjured = (c: Career) => c.hp < maxHp(c.stats) * 0.6 || (maxMana(c.stats) > 0 && c.mp < maxMana(c.stats) * 0.25)

function ConditionMeters({ hp, mp, stamina, happiness, stats }: {
  hp: number; mp: number; stamina: number; happiness: number; stats: Monster['stats']
}) {
  const hpMax = maxHp(stats)
  const mpMax = maxMana(stats)
  const hpFrac = Math.min(hp, hpMax) / hpMax
  const mpFrac = mpMax > 0 ? Math.min(mp, mpMax) / mpMax : 1
  return (
    <div className="detail-meters">
      <div className="meter"><label>HP {Math.min(hp, hpMax)}/{hpMax}{hpFrac < 0.25 ? ' 🩹' : ''}</label><div className="bar"><i style={{ width: `${Math.min(100, hpFrac * 100)}%`, background: hpBarColor(hpFrac) }} /></div></div>
      <div className="meter"><label>MP {Math.min(mp, mpMax)}/{mpMax}</label><div className="bar"><i style={{ width: `${mpFrac * 100}%`, background: mpBarColor(mpFrac) }} /></div></div>
      <div className="meter"><label>Stamina {stamina}/{MAX_STAMINA}</label><div className="bar"><i style={{ width: `${stamina}%`, background: 'var(--dex)' }} /></div></div>
      <div className="meter"><label>Happiness {happiness}/10</label><div className="bar"><i style={{ width: `${happiness * 10}%`, background: 'var(--cha)' }} /></div></div>
    </div>
  )
}

function MonsterCard({ m }: { m: Monster }) {
  const barMax = Math.max(100, ...STATS.map((k) => m.stats[k])) * 1.05
  return (
    <div>
      <div className="mhead">
        <Sprite species={m.species} />
        <div>
          <div className="name">{m.name}</div>
          <div className="meta">{m.species.name} · {m.species.body} · {m.sex === 'M' ? '♂' : '♀'}</div>
          <div className="meta">{m.species.flavour}</div>
          <Signature m={m} />
        </div>
      </div>

      <div className="badges">
        <span className="badge">{m.className}</span>
        <span className="badge">{m.league} league</span>
        <span className="badge">Career {m.species.lifespan}y</span>
      </div>

      <div className="afftaste">
        <span>Food preferences: <b className="up">♥ {m.favouriteFood}</b> · <b className="down">✖ {m.hatedFood}</b></span>
      </div>

      {STATS.map((k) => <StatBar key={k} stat={k} value={m.stats[k]} max={barMax} />)}

      <div className="section-title">Innate</div>
      {(() => {
        const a = m.species.innate[m.activeInnate] ?? m.species.innate[0]
        return <div className="ability" key={a.name}>{a.name} — <small>{a.desc}</small></div>
      })()}
      <div className="md dim">
        {m.innateUnlocked ? '2nd choice unlocked — edit abilities to switch.' : `2nd choice unlocks at ${INNATE_SECONDARY_LEVEL} in a stat.`}
      </div>

      <div className="section-title">Loadout (equipped {m.loadout.length} of {m.learned.length} learned)</div>
      <div className="moves">
        {m.loadout.length === 0 && <div className="md">No moves yet — train a stat past 40.</div>}
        {m.loadout.map((mv) => (
          <div className="move" key={mv.id}>
            <span className="lvl">{mv.stat} {mv.learnLevel}</span>
            <span className="mn">{mv.name}</span>
            <div className="md">{mv.desc} {mv.status ? `(${mv.status.kind})` : ''} · {manaCost(mv)} MP · cd {mv.cooldown} · acc {mv.accuracy}</div>
          </div>
        ))}
      </div>
    </div>
  )
}

// Scouting profile (user spec 2026-07-22, reference: the full MonsterCard
// layout) — same shape whether or not you've paid: identity (sprite, name,
// species, element) is always visible since it's plainly on display in the
// bracket already; class + loadout unlock at the 'basic' tier, stats unlock
// at 'full'. Whatever tier hasn't been bought renders as "??" text / a
// locked ">" bar instead of being omitted, so the card never reflows.
function ScoutReport({ m, tier }: { m: Monster; tier: 'basic' | 'full' | undefined }) {
  const knowsKit = tier === 'basic' || tier === 'full'
  const knowsStats = tier === 'full'
  const barMax = Math.max(100, ...STATS.map((k) => m.stats[k])) * 1.05
  return (
    <div className="scoutcard">
      <div className="mhead">
        <Sprite species={m.species} />
        <div>
          <div className="name">{m.name}</div>
          <div className="meta">{m.species.name} · {m.species.body} · {m.sex === 'M' ? '♂' : '♀'}</div>
          <div className="meta">{m.species.flavour}</div>
        </div>
      </div>

      <div className="badges">
        <span className={'badge' + (knowsKit ? '' : ' locked')}>{knowsKit ? m.className : '??'}</span>
        <span className="badge">{m.league} league</span>
        <span className="badge">Career {m.species.lifespan}y</span>
      </div>

      <div className="afftaste">
      </div>

      {STATS.map((k) => knowsStats
        ? <StatBar key={k} stat={k} value={m.stats[k]} max={barMax} />
        : (
          <div className="stat" key={k}>
            <span>{k}</span>
            <span className="bar locked">&gt;</span>
            <span className="v">??</span>
          </div>
        ))}

      <div className="section-title">Loadout</div>
      <div className="moves">
        {knowsKit ? m.loadout.map((mv) => (
          <div className="move" key={mv.id}>
            <span className="lvl">{mv.stat} {mv.learnLevel}</span>
            <span className="mn">{mv.name}</span>
            <div className="md">{mv.desc} {mv.status ? `(${mv.status.kind})` : ''} · {manaCost(mv)} MP · cd {mv.cooldown} · acc {mv.accuracy}</div>
          </div>
        )) : <div className="md dim">?? — pay to scout its class &amp; loadout.</div>}
      </div>
    </div>
  )
}

function Stable({ label, seed, setSeed, train, setTrain, happiness, setHappiness, m, onEditAbilities, onRemove }: {
  label: string; seed: string; setSeed: (s: string) => void
  train: number; setTrain: (n: number) => void
  happiness: number; setHappiness: (n: number) => void; m: Monster
  onEditAbilities: () => void; onRemove?: () => void
}) {
  const feedLocal = (food: (typeof FOODS)[number]['id']) =>
    setHappiness(Math.max(0, Math.min(10, happiness + feedDelta(food, m.favouriteFood, m.hatedFood))))
  return (
    <div className="card">
      <div className="controls">
        <input type="text" value={seed} placeholder="seed word…" onChange={(e) => setSeed(e.target.value)} />
        <button className="ghost" onClick={() => setSeed(label + '-' + Math.floor(mulberry32(hashString(seed + train))() * 1e6))}>🎲</button>
        {onRemove && <button className="ghost" title="remove fighter" onClick={onRemove}>✕</button>}
      </div>
      <div className="slider">
        <label><span>Training invested</span><span>{train} pts · {m.league}</span></label>
        <input type="range" min={0} max={2400} step={20} value={train} onChange={(e) => setTrain(Number(e.target.value))} />
      </div>
      <MonsterCard m={m} />
      <button className="detail-actionbtn" style={{ marginTop: 6 }} onClick={onEditAbilities}>⚔ Edit Abilities</button>
      <div className="feed">
        <div className="happyrow">
          <span>Happiness {happiness}/10</span>
          <span className="dim">battle dmg ×{happinessMultiplier(happiness).toFixed(2)}</span>
        </div>
        <div className="happybar"><i style={{ width: `${happiness * 10}%` }} /></div>
        <div className="foods">
          {FOODS.map((f) => {
            const d = feedDelta(f.id, m.favouriteFood, m.hatedFood)
            return (
              <button key={f.id} className="food" onClick={() => feedLocal(f.id)} title={`${f.price}g · ${d > 0 ? 'favourite (+1)' : d < 0 ? 'hated (−1)' : 'neutral'}`}>
                {f.name}{d > 0 ? ' ♥' : d < 0 ? ' ✖' : ''}
              </button>
            )
          })}
        </div>
      </div>
    </div>
  )
}

// Expandable codex of all species, grouped by body type. Exclusive body types
// stay locked (name only) until the matching breeding license is owned.
function Bestiary({ specialLicense, eliteLicense }: { specialLicense: boolean; eliteLicense: boolean }) {
  const groups: { bt: BodyType; locked: boolean; licenseName: string }[] = [
    { bt: 'Mammal', locked: false, licenseName: '' },
    { bt: 'Avian', locked: false, licenseName: '' },
    { bt: 'Marsupial', locked: false, licenseName: '' },
    { bt: 'Aquatic', locked: false, licenseName: '' },
    { bt: 'Insectoid', locked: false, licenseName: '' },
    { bt: 'Reptilian', locked: false, licenseName: '' },
    { bt: 'Draconic', locked: !specialLicense, licenseName: 'Special Breeding License' },
    { bt: 'Abyssal', locked: !specialLicense, licenseName: 'Special Breeding License' },
    { bt: 'Mythical', locked: !eliteLicense, licenseName: 'Elite Breeding License' },
  ]
  return (
    <details className="bestiary">
      <summary>📖 Bestiary — {SPECIES.length} monsters</summary>
      <div className="bestbody">
        {groups.map(({ bt, locked, licenseName }) => {
          const minor = BODY_MINOR[bt]
          return (
          <div className="bestgroup" key={bt}>
            <div className="bestgroup-h">
              {bt}{minor && <> · minor <span style={{ color: STAT_COLOR[minor] }}>{minor}</span></>}
                          </div>
            {locked
              ? <div className="dim bsmall">🔒 {SPECIES.filter((s) => s.body === bt).length} species — unlock with the {licenseName}.</div>
              : SPECIES.filter((s) => s.body === bt).map((s) => {
                const prof = trainingProfileFor(s)
                return (
                <details className="bestrow" key={s.id}>
                  <summary>
                    <Sprite species={s} size={36} />
                    <span className="bn">{s.name}</span>
                    <span className="dim">· {s.flavour}</span>
                    <span className="bsmall"><AptMarks prof={prof} softFlaw={isPrestigeBody(s.body)} /></span>
                  </summary>
                  <p className="bio">{BIOS[s.id] ?? s.flavour}</p>
                  <p className="dim bsmall">
                    Innate: {s.innate.map((a) => a.name).join(' · ')} · Career span {s.lifespan}y
                  </p>
                </details>
                )
              })}
          </div>
          )
        })}
      </div>
    </details>
  )
}

// The detailed transcript now lives INSIDE ArenaBattle (collapsible, appears
// once the replay finishes) — this is just the sandbox's clear button.
function BattleLog({ onClear }: { onClear: () => void }) {
  return (
    <div className="battlebar">
      <button className="ghost" onClick={onClear}>clear</button>
    </div>
  )
}

// A sandbox fighter's raising state — enough to regenerate its Monster
// deterministically. `loadout: null` means auto-pick (chooseLoadout inside
// generateMonster); a non-null array is a player-chosen override, same
// slot-swap mechanism as the Ranch's AbilitySelector.
interface FighterSlot { id: number; seed: string; train: number; happiness: number; loadout: string[] | null; activeInnate: number | null; tactics: Tactics | null }
const SANDBOX_MAX_TEAM = 6
const SEED_POOL_A = ['Kongrath', 'Wyna', 'Rex', 'Zeta', 'Ashen', 'Nova']
const SEED_POOL_B = ['Maelurk', 'Ashryn', 'Doom', 'Vex', 'Iris', 'Talon']

function buildSandboxMonster(f: FighterSlot): Monster {
  const m = generateMonster(f.seed, { train: f.train })
  if (f.loadout) {
    const picked = f.loadout.map((mid) => m.learned.find((mv) => mv.id === mid)).filter((mv): mv is Move => !!mv)
    if (picked.length) m.loadout = picked
  }
  if (f.activeInnate != null && (f.activeInnate !== 1 || m.innateUnlocked)) m.activeInnate = f.activeInnate
  if (f.tactics) m.tactics = f.tactics
  return m
}

function SandboxView() {
  const [teamA, setTeamA] = useState<FighterSlot[]>([{ id: 0, seed: SEED_POOL_A[0], train: 300, happiness: 5, loadout: null, activeInnate: null, tactics: null }])
  const [teamB, setTeamB] = useState<FighterSlot[]>([{ id: 1, seed: SEED_POOL_B[0], train: 300, happiness: 5, loadout: null, activeInnate: null, tactics: null }])
  const nextId = useRef(2)
  const [editing, setEditing] = useState<{ side: 'A' | 'B'; id: number } | null>(null)
  const [result, setResult] = useState<BattleResult | null>(null)
  const [battleKey, setBattleKey] = useState(0)

  const teamFor = (side: 'A' | 'B') => (side === 'A' ? teamA : teamB)
  const setTeamFor = (side: 'A' | 'B') => (side === 'A' ? setTeamA : setTeamB)

  const addFighter = (side: 'A' | 'B') => {
    const list = teamFor(side)
    if (list.length >= SANDBOX_MAX_TEAM) return
    const id = nextId.current++
    const pool = side === 'A' ? SEED_POOL_A : SEED_POOL_B
    const seed = pool[list.length] ?? `${side}-${id}`
    setTeamFor(side)((l) => [...l, { id, seed, train: 300, happiness: 5, loadout: null, activeInnate: null, tactics: null }])
    setResult(null) // roster shape changed — the old result no longer lines up
  }
  const removeFighter = (side: 'A' | 'B', id: number) => {
    setTeamFor(side)((l) => (l.length > 1 ? l.filter((f) => f.id !== id) : l))
    setResult(null)
  }
  const updateFighter = (side: 'A' | 'B', id: number, patch: Partial<FighterSlot>) => {
    setTeamFor(side)((l) => l.map((f) => (f.id === id ? { ...f, ...patch } : f)))
  }

  const monstersA = useMemo(() => teamA.map(buildSandboxMonster), [teamA])
  const monstersB = useMemo(() => teamB.map(buildSandboxMonster), [teamB])

  const runBattle = () => {
    setResult(simulateTeamBattle(monstersA, monstersB, teamA.map((f) => f.happiness), teamB.map((f) => f.happiness)))
    setBattleKey((k) => k + 1)
  }

  const editingFighter = editing ? teamFor(editing.side).find((f) => f.id === editing.id) : undefined
  const editingMonster = editingFighter ? buildSandboxMonster(editingFighter) : null

  if (editing && editingFighter && editingMonster) {
    return (
      <AbilitySelector
        m={editingMonster}
        name={editingMonster.name}
        onSetLoadout={(ids) => updateFighter(editing.side, editing.id, { loadout: ids.length ? ids : null })}
        onSetInnate={(index) => updateFighter(editing.side, editing.id, { activeInnate: index })}
        onSetTactics={(t) => updateFighter(editing.side, editing.id, { tactics: t })}
        showTactics
        onClose={() => setEditing(null)}
      />
    )
  }

  return (
    <>
      <p className="sub">Type a seed to generate a monster, invest training to unlock moves (2nd innate at 300), add fighters to build a team, edit abilities, then auto-battle. Same seeds → same monsters &amp; same fight.</p>

      <div className="arena">
        <div className="sandbox-team">
          {teamA.map((f, i) => (
            <Stable key={f.id} label={`A${f.id}`} seed={f.seed} setSeed={(s) => updateFighter('A', f.id, { seed: s })}
              train={f.train} setTrain={(n) => updateFighter('A', f.id, { train: n })}
              happiness={f.happiness} setHappiness={(n) => updateFighter('A', f.id, { happiness: n })}
              m={monstersA[i]}
              onEditAbilities={() => setEditing({ side: 'A', id: f.id })}
              onRemove={teamA.length > 1 ? () => removeFighter('A', f.id) : undefined}
            />
          ))}
          <button className="ghost addfighter" disabled={teamA.length >= SANDBOX_MAX_TEAM} onClick={() => addFighter('A')}>
            + Add Fighter ({teamA.length}/{SANDBOX_MAX_TEAM})
          </button>
        </div>
        <div className="vs">VS</div>
        <div className="sandbox-team">
          {teamB.map((f, i) => (
            <Stable key={f.id} label={`B${f.id}`} seed={f.seed} setSeed={(s) => updateFighter('B', f.id, { seed: s })}
              train={f.train} setTrain={(n) => updateFighter('B', f.id, { train: n })}
              happiness={f.happiness} setHappiness={(n) => updateFighter('B', f.id, { happiness: n })}
              m={monstersB[i]}
              onEditAbilities={() => setEditing({ side: 'B', id: f.id })}
              onRemove={teamB.length > 1 ? () => removeFighter('B', f.id) : undefined}
            />
          ))}
          <button className="ghost addfighter" disabled={teamB.length >= SANDBOX_MAX_TEAM} onClick={() => addFighter('B')}>
            + Add Fighter ({teamB.length}/{SANDBOX_MAX_TEAM})
          </button>
        </div>
      </div>

      <div className="battlebar">
        <button onClick={runBattle}>⚔️ Auto-Battle</button>
      </div>

      {result && (
        <div key={battleKey}>
          <ArenaBattle teamA={monstersA} teamB={monstersB} result={result} />
          <BattleLog onClear={() => setResult(null)} />
        </div>
      )}
    </>
  )
}

// The fusion spinning wheel (v0.7): cycles the class's species, decelerating to
// the pre-decided result — the "mad-science reveal" of a fusion.
function FusionWheel({ pool, result, onDone }: { pool: string[]; result: string; onDone: () => void }) {
  const [idx, setIdx] = useState(0)
  const [done, setDone] = useState(false)
  useEffect(() => {
    const resultIdx = Math.max(0, pool.indexOf(result))
    const total = pool.length * 3 + resultIdx // 3 full loops, then land on the result
    let cur = 0
    let timer: ReturnType<typeof setTimeout>
    const tick = () => {
      cur++
      setIdx(cur % pool.length)
      if (cur >= total) { setDone(true); return }
      timer = setTimeout(tick, 50 + Math.pow(cur / total, 3) * 380) // ease-out
    }
    timer = setTimeout(tick, 60)
    return () => clearTimeout(timer)
  }, [pool, result])
  const shown = SPECIES.find((s) => s.id === (done ? result : pool[idx]))
  if (!shown) return null
  return (
    <div className="wheel-overlay" onClick={done ? onDone : undefined}>
      <div className="wheel-card" onClick={(e) => e.stopPropagation()}>
        <div className="section-title">⚗️ Fusing…</div>
        <div className={'wheel-reel' + (done ? ' landed' : '')}>
          <Sprite species={shown} size={96} />
          <b>{shown.name}</b>
        </div>
        {done
          ? <><div className="up" style={{ textAlign: 'center' }}>A {shown.name}! ({shown.naturalClass})</div>
              <button className="enter" onClick={onDone}>Take it home →</button></>
          : <div className="dim" style={{ textAlign: 'center' }}>the chimera takes shape…</div>}
      </div>
    </div>
  )
}

// Full-bleed painted backdrop for a screen. `position: fixed` means it can be
// rendered from anywhere in the tree and still cover the viewport, so each view
// owns its own scene without lifting state up to App.
function AreaBackdrop({ scene }: { scene: AreaArtKey }) {
  return <div className="areabg" style={{ backgroundImage: `url(${AREA_BACKGROUND[scene]})` }} aria-hidden="true" />
}

// ============================ Town hub (§13) ============================
type TownArea = 'hub' | 'market' | 'shop' | 'breeding' | 'retirement' | 'lab'

// Market Scout (v0.77): pick a body type, then a species inside it, and each
// market slot gets a per-tier chance to come up as that monster. The upgraded
// scout opens a second pair, which may stay "Any" to put all the weight on the
// first. Prestige body types only appear once their licence is held — the
// engine also refuses an unlicensed pick, this just avoids dangling the bait.
function ScoutPair({ game, setGame, which, label }: {
  game: GameState; setGame: Dispatch<SetStateAction<GameState>>; which: 'A' | 'B'; label: string
}) {
  const picked = which === 'A' ? game.scoutPickA : game.scoutPickB
  const pickedSp = picked ? SPECIES.find((s) => s.id === picked) : undefined
  const [body, setBody] = useState<string>(pickedSp?.body ?? '')
  // Derived from SPECIES so it can never drift from the real roster: every
  // non-fusion body the player is actually licensed to be offered.
  const bodies = [...new Set(SPECIES.filter((s) => !isFusionBody(s.body)
    && speciesLicensed(s, game.specialLicense, game.eliteLicense)).map((s) => s.body))]
  const inBody = SPECIES.filter((s) => s.body === body)
  return (
    <div className="scoutpair">
      <span className="scoutpair-l">{label}</span>
      <select value={body} onChange={(e) => { setBody(e.target.value); setGame((g) => setScoutPick(g, which, null)) }}>
        <option value="">— any —</option>
        {bodies.map((b) => <option key={b} value={b}>{b}</option>)}
      </select>
      <select value={picked ?? ''} disabled={!body} onChange={(e) => setGame((g) => setScoutPick(g, which, e.target.value || null))}>
        <option value="">— any {body || 'monster'} —</option>
        {inBody.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
      </select>
    </div>
  )
}

function ScoutPanel({ game, setGame }: { game: GameState; setGame: Dispatch<SetStateAction<GameState>> }) {
  const tier = game.marketScout ?? 0
  if (tier < 1) return null
  const pct = Math.round(SCOUT_CHANCE[Math.min(2, tier)] * 100)
  return (
    <div className="scoutbox">
      <div className="scoutbox-h">🔎 Market Scout <span className="dim">· {pct}% per slot</span></div>
      <ScoutPair game={game} setGame={setGame} which="A" label="Looking for" />
      {tier >= 2 && <ScoutPair game={game} setGame={setGame} which="B" label="…and also" />}
      <div className="hint">Applies to next month's stock.</div>
    </div>
  )
}

function TownView({ game, setGame }: { game: GameState; setGame: Dispatch<SetStateAction<GameState>> }) {
  const [fuseA, setFuseA] = useState('')
  const [fuseB, setFuseB] = useState('')
  const [wheel, setWheel] = useState<{ result: string; pool: string[]; a: string; b: string } | null>(null)
  // The town is a navigable hub of locations. A fresh game (empty stable) opens
  // straight into the Market to buy a first monster; otherwise land on the hub.
  const [area, setArea] = useState<TownArea>(game.stable.length === 0 ? 'market' : 'hub')
  const barnFull = barnFullOf(game) // retirees live in the Hall of Fame, not the barn
  const active = game.stable.filter((c) => !c.retired)
  const retirees = game.stable.filter((c) => c.retired)
  // v0.77: the Lab freezer is the single preservation store — breeding AND fusion
  // both draw from it. The old stud farm (game.frozen) is migrated away on load.
  const frozenPool = game.labFrozen ?? []
  const studTotal = frozenPool.reduce((s, f) => s + studIncome(f), 0)

  // --- Guided first-run tutorial (v0.86) -----------------------------------
  // The 'buy'/'raise' beats are one-shot messages that DON'T advance the step
  // (the step advances by buying 2 / clicking Back to Town), so a local "seen"
  // set hides them after the player reads them; 'howto'/'final' advance the
  // persisted step on close, so they self-dismiss.
  const [tutSeen, setTutSeen] = useState<Set<string>>(() => new Set())
  const step = game.tutorialStep
  const closeGuided = () => setGame((g) => ({ ...g, tutorialStep: undefined, tutorialDismissed: true }))
  const tutModal =
    step === 'buy' && area === 'market' && !tutSeen.has('buy')
      ? { title: `Greetings ${game.trainerName},`, body: "Welcome to the bull pen. To begin with, you're going to need to purchase two monsters from the market here.", onClose: () => setTutSeen((s) => new Set(s).add('buy')) }
    : step === 'raise' && area === 'market' && !tutSeen.has('raise')
      ? { body: "Well now, you got the creatures — you best go and raise 'em.", onClose: () => setTutSeen((s) => new Set(s).add('raise')) }
    : step === 'howto' && area === 'hub'
      ? { body: "Well now, I'll tell you a bit about how it works here. The Lab is where you freeze your monsters for fusing and breeding — you breed them at the Breeding Ranch to keep their stats and raise their potential, while fusing makes a whole new creature. The Ranch Shop helps you upgrade your grandpa's old place, and the Hall of Fame is for all your retired fighters. The Market's pretty self-explanatory since we've just been there — but remember, it gets fresh stock each month. I'll be seeing ya!", onClose: () => setGame((g) => ({ ...g, tutorialStep: 'final' })) }
    : step === 'final' && area === 'hub'
      ? { body: 'Train your monsters, feed them well, and let them earn you riches in the circuits. Breed a dynasty from your champions before they retire, or buy fresh monsters to fuse and see what their power unlocks.', onClose: closeGuided }
    : null

  return (
    <>
      <AreaBackdrop scene={TOWN_AREA_ART[area] ?? 'town'} />
      {tutModal && <GrandpaModal title={tutModal.title} body={tutModal.body} onClose={tutModal.onClose} />}
      {/* The welcome overview belongs on the town map only — repeating the whole
          "how it works" block on every sub-area (Market/Shop/Lab/…) was just
          clutter (v0.81 UI audit). */}
      {area === 'hub' && !game.tutorialStep && game.tutorialEnabled && !game.tutorialDismissed && (
        <TutorialBanner onDismiss={() => setGame((g) => ({ ...g, tutorialDismissed: true }))} />
      )}
      <div className="townbar">
        <span>🪙 {game.gold}g</span>
        <span>🏠 Stable {active.length}/{effectiveBarnCap(game)}</span>
        <span>🧊 Preserved {frozenPool.length}/{game.labSlots ?? 2}</span>
        {game.pantryContract && <span className="up">🧺 Pantry</span>}
        {game.grandLarder && <span className="up">🏰 Larder</span>}
      </div>

      {area !== 'hub' && (
        <button
          className={'ghost townback' + (area === 'market' && step === 'buy' ? ' tut-block' : area === 'market' && step === 'raise' ? ' tut-go' : '')}
          disabled={area === 'market' && step === 'buy'}
          title={area === 'market' && step === 'buy' ? 'Buy two monsters first' : undefined}
          onClick={() => { if (step === 'raise') setGame((g) => ({ ...g, tutorialStep: 'howto' })); setArea('hub') }}
        >← Town</button>
      )}

      {/* ---- HUB: the town map, a grid of location buttons ---- */}
      {area === 'hub' && (
        <>
          <div className="townhub">
            <button className="hubbtn" onClick={() => setArea('market')}>
              <span className="hubicon">🛒</span><b>Market</b>
              <span className="dim">buy monsters &amp; heal at the infirmary</span>
            </button>
            <button className="hubbtn" onClick={() => setArea('shop')}>
              <span className="hubicon">🏗️</span><b>Ranch Shop</b>
              <span className="dim">licenses, barn, care upgrades &amp; contracts</span>
            </button>
            <button className={'hubbtn' + (step === 'final' ? ' tut-go' : '')} disabled={active.length === 0}
              title={active.length === 0 ? 'Buy a monster at the Market first' : undefined}
              onClick={() => setGame((g) => goto(g, 'ranch'))}>
              <span className="hubicon">🏟</span><b>Grandpa's Ranch</b>
              <span className="dim">{active.length === 0 ? 'empty — visit the Market' : `train your ${active.length} competitor${active.length === 1 ? '' : 's'}`}</span>
            </button>
            <button className="hubbtn" onClick={() => setArea('breeding')}>
              <span className="hubicon">🐎</span><b>Breeding Ranch</b>
              <span className="dim">{frozenPool.length === 0 ? 'freeze a monster to breed it' : `${frozenPool.length} preserved`}{studTotal > 0 ? ` · +${studTotal}g/wk` : ''}</span>
            </button>
            <button className="hubbtn" onClick={() => setArea('retirement')}>
              <span className="hubicon">🏛</span><b>Hall of Fame</b>
              <span className="dim">{retirees.length === 0 ? 'no honourees yet' : `${retirees.length} honoured`}</span>
            </button>
            <button className="hubbtn" onClick={() => setArea('lab')}>
              <span className="hubicon">🧪</span><b>Lab</b>
              <span className="dim">freeze &amp; fuse monsters</span>
            </button>
          </div>

          {/* Glanceable meta on the hub itself */}
          {(() => {
            const p = trainerXpProgress(game)
            const barn = trainerBarnBonus(game)
            return (
              <div className="card loc">
                <div className="loc-h"><span>🎓 Trainer — {game.trainerName}</span><span className="dim">Level {p.level}</span></div>
                <div className="xpbar"><div className="xpfill" style={{ width: `${Math.round((p.into / p.need) * 100)}%` }} /></div>
                <div className="dim" style={{ marginTop: 4 }}>
                  {p.into}/{p.need} XP to level {p.level + 1} · <b className="up">+{trainerStipend(game)}g/wk stipend</b>
                  {barn > 0 && <> · <b className="up">+{barn} barn slot{barn > 1 ? 's' : ''}</b></>}
                </div>
              </div>
            )
          })()}
          {game.rivals.length > 0 && (
            <div className="card loc">
              <div className="loc-h"><span>🥊 Rivals</span></div>
              {game.rivals.map((rv) => {
                const led = rv.wins > rv.losses, tied = rv.wins === rv.losses
                const record = rv.wins === 0 && rv.losses === 0 ? 'Not yet faced'
                  : tied ? `Even ${rv.wins}–${rv.losses}`
                    : led ? `You lead ${rv.wins}–${rv.losses}` : `${rv.name} leads ${rv.losses}–${rv.wins}`
                const trait = rv.personality === 'aggressive' ? 'hits hard and early'
                  : rv.personality === 'cagey' ? 'patient and defensive' : 'loves a big play'
                return (
                  <div className="shoprow" key={rv.id}>
                    <div>
                      <b>{rv.name}</b> <span className="dim">· {LEAGUES[rv.licenseIndex].name} · {trait}</span>
                      <div className={led ? 'up' : tied ? 'dim' : 'down'}>{record}</div>
                    </div>
                  </div>
                )
              })}
            </div>
          )}
        </>
      )}

      {/* ---- HALL OF FAME: finished careers, honours only, unlimited room ---- */}
      {area === 'retirement' && (
        <div className="townmap">
          <div className="card loc">
            <TipBanner game={game} setGame={setGame} id="hof">
              🏛 Retired careers rest here for their records only — preserve a monster at the Lab
              <b> before</b> it ages out, or its bloodline is closed for good.
            </TipBanner>
            <div className="loc-h"><span>🏛 Hall of Fame</span><span className="dim">{retirees.length} honoured · unlimited room</span></div>
            <div className="dim" style={{ marginBottom: 6 }}>Every monster who finished a career rests here with its record — honours only, no further breeding.</div>
            {retirees.length === 0 && <div className="dim">Empty — monsters are honoured here when their career span ends.</div>}
            {[...retirees]
              .sort((a, b) => b.tournamentHistory.filter((h) => h.placement === 1).length - a.tournamentHistory.filter((h) => h.placement === 1).length
                || b.tournamentHistory.filter((h) => h.placement <= 3).length - a.tournamentHistory.filter((h) => h.placement <= 3).length)
              .map((c) => {
                const podiums = c.tournamentHistory.filter((h) => h.placement <= 3).length
                const champs = c.tournamentHistory.filter((h) => h.placement === 1).length
                const best = Math.max(...STATS.map((k) => c.stats[k]))
                return (
                  <div className="shoprow" key={c.id}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                      <Sprite species={c.species} size={32} stage="Retiree" />
                      <div>
                        <b>{c.name}</b> <span className="dim">· {c.species.name} · {classForStats(c.stats)}</span>
                        <div className="dim">🏅 {podiums} podium{podiums === 1 ? '' : 's'} · 🏆 {champs} · peak {best}</div>
                      </div>
                    </div>
                    <span className="dim" style={{ fontSize: 11 }}>honoured</span>
                  </div>
                )
              })}
          </div>
        </div>
      )}

      {/* ---- BREEDING RANCH: the stud farm + breeding ---- */}
      {area === 'breeding' && (
        <div className="townmap">
          <div className="card loc">
            <TipBanner game={game} setGame={setGame} id="breeding">
              🐎 Breed two preserved monsters for a child with a stat head start and a higher training
              ceiling than either parent.
            </TipBanner>
            <div className="loc-h"><span>🐎 Breeding Ranch</span><span className="dim">{frozenPool.length} preserved at the Lab</span></div>
            <div className="hint">Breeding stock lives in the 🧪 Lab freezer — freeze a monster before its career ends, or its line is closed.</div>
            <div className="section-title">Breeding stock</div>
            <div className="labrows">
              {frozenPool.length === 0 && <div className="dim">Nothing preserved — freeze a monster at the Lab while it is still competing.</div>}
              {frozenPool.map((f) => (
                <div className="labrow" key={f.id}>
                  <Sprite species={f.species} size={28} stage="Retiree" />
                  <span className="bn">{f.name}{f.studBook ? ' 📕' : ''}</span>
                  <span className="dim">
                    {f.species.name} · 🏅{podiumsOf(f)} 🏆{champsOf(f)} · {BREED_MAX_CHILDREN - (f.breedCount ?? 0)} breed{BREED_MAX_CHILDREN - (f.breedCount ?? 0) === 1 ? '' : 's'} left
                    {f.studBook ? ` · stud +${studIncome(f)}g/wk` : ''}
                  </span>
                  {(game.studBooks ?? 0) > 0 && !f.studBook && (
                    <button className="ghost" title="Assign a Stud Book — weekly fees from this legacy's record"
                      onClick={() => setGame((g) => applyStudBook(g, f.id))}>📕 Stud</button>
                  )}
                </div>
              ))}
            </div>
            <div className="section-title">Breed (two preserved monsters parent a child)</div>
            <div className="fuserow">
              <select value={fuseA} onChange={(e) => setFuseA(e.target.value)}>
                <option value="">— parent A (frame) —</option>
                {frozenPool.filter((f) => (f.breedCount ?? 0) < BREED_MAX_CHILDREN).map((f) => <option key={f.id} value={f.id}>{f.name} ({f.species.name})</option>)}
              </select>
              <select value={fuseB} onChange={(e) => setFuseB(e.target.value)}>
                <option value="">— parent B (heritage) —</option>
                {frozenPool.filter((f) => (f.breedCount ?? 0) < BREED_MAX_CHILDREN).map((f) => <option key={f.id} value={f.id}>{f.name} ({f.species.name})</option>)}
              </select>
              <button
                className="rankup"
                disabled={!fuseA || !fuseB || fuseA === fuseB || game.gold < BREED_COST || !fusionRoom(game)}
                onClick={() => { setGame((g) => breed(g, fuseA, fuseB)); setFuseA(''); setFuseB('') }}
              >
                Breed · {BREED_COST}g
              </button>
            </div>
            {fuseA && fuseB && fuseA !== fuseB && (() => {
              const a = frozenPool.find((f) => f.id === fuseA)!
              const b = frozenPool.find((f) => f.id === fuseB)!
              const pot = breedPotentialV2(a, b)
              return <div className="hint">Child: {a.species.name} · Gen {Math.max(a.generation ?? 1, b.generation ?? 1) + 1} · potential ×{pot.toFixed(2)} {'★'.repeat(Math.max(0, Math.round((pot - 1) / 0.05)))}</div>
            })()}
            <div className="hint">Each preserved monster can parent {BREED_MAX_CHILDREN} children. Decorated parents pass on higher <b>potential</b>.</div>
          </div>
        </div>
      )}

      {/* ---- LAB: freezer (stasis) + fusion (v0.7) ---- */}
      {area === 'lab' && (() => {
        const frozen = game.labFrozen ?? []
        // Fusion can pull from the active stable OR the freezer (v0.73).
        const fusable = [...game.stable.filter((c) => !c.retired), ...frozen]
        const frozenIds = new Set(frozen.map((f) => f.id))
        const spin = fuseA && fuseB && fuseA !== fuseB ? fusionSpin(game, fuseA, fuseB) : null
        const bodyOf = (id: string) => fusable.find((m) => m.id === id)?.species.body
        const validPair = fuseA && fuseB && fuseA !== fuseB && !!fusionRecipeFor(bodyOf(fuseA)!, bodyOf(fuseB)!)
        return (
        <div className="townmap">
          <div className="card loc">
            <div className="loc-h"><span>🧪 Lab · Freezer</span><span className="dim">{frozen.length}/{game.labSlots} slots</span></div>
            <div className="warnnote">⚠️ A fused monster's stats do not carry over — fusion always starts fresh. To preserve a dynasty through stats, use the <b>Breeding Ranch</b>.</div>
            {/* Fusion nudge (v0.89): holding a valid pair is easy to miss, and the
                cost is easy to never quite have spare — so say both out loud. */}
            {(() => {
              const pair = fusablePairIn(game)
              if (!pair) return null
              const short = FUSION_COST - game.gold
              return (
                <div className={short > 0 ? 'hint' : 'tipbanner'}>
                  ⚗️ <b>{pair.a.name}</b> + <b>{pair.b.name}</b> can be fused into a <b>{pair.label}</b>
                  {short > 0
                    ? <> — save <b>{short}g</b> more to afford it (fusion costs {FUSION_COST}g). Both parents must still be alive.</>
                    : <> — you can afford it now ({FUSION_COST}g). Fuse before either ages out.</>}
                </div>
              )
            })()}
            <div className="dim" style={{ marginBottom: 6 }}>
              The freezer preserves a monster's genome — it is the <b>only</b> route to breeding
              and fusion. Freeze it while it is still competing: once a career ends it retires to
              the Hall of Fame and the line is closed.
            </div>
            <div className="hint">
              ⚗️ Fusion pairs: Mammal + Reptilian → Saurian · Avian + Aquatic → Tempestine · Marsupial + Insectoid → Broodkin · Mythical + Draconic/Abyssal → <b>Primeval</b> (1.25× potential)
            </div>
            {/* Freeze an active monster in */}
            <div className="section-title">Freeze into stasis</div>
            <div className="labrows">
              {game.stable.filter((c) => !c.retired).length === 0 && <div className="dim">No active monsters to freeze.</div>}
              {game.stable.filter((c) => !c.retired).map((c) => (
                <div className="labrow" key={c.id}>
                  <Sprite species={c.species} size={28} stage="Teen" />
                  <span className="bn">{c.name}</span>
                  <span className="dim">{c.species.name} · {c.species.body}</span>
                  <button className="ghost" disabled={frozen.length >= game.labSlots}
                    title={frozen.length >= game.labSlots ? 'Freezer full — expand it' : 'Freeze (pauses aging)'}
                    onClick={() => setGame((g) => freezeToLab(g, c.id))}>❄️ Freeze</button>
                </div>
              ))}
            </div>
            {/* Frozen monsters */}
            <div className="section-title">In the freezer</div>
            <div className="labrows">
              {frozen.length === 0 && <div className="dim">Empty.</div>}
              {frozen.map((f) => (
                <div className="labrow" key={f.id}>
                  <Sprite species={f.species} size={28} stage="Teen" />
                  <span className="bn">🧊 {f.name}</span>
                  <span className="dim">{f.species.name} · {f.species.body}</span>
                  {(game.tonics ?? 0) > 0 && <button className="ghost" title="Elder Tonic +2mo career span" onClick={() => setGame((g) => useTonic(g, f.id))}>🧪</button>}
                  <button className="ghost" disabled={barnFull} title="Thaw back into the stable" onClick={() => setGame((g) => thawFromLab(g, f.id))}>Thaw</button>
                </div>
              ))}
            </div>
            {labExpandCost(game) !== null && (
              <button className="ghost" disabled={game.gold < (labExpandCost(game) ?? Infinity)}
                onClick={() => setGame((g) => expandLab(g))}>➕ Expand freezer · {labExpandCost(game)}g ({game.labSlots} → {game.labSlots + 1})</button>
            )}
            {/* Fusion — pull from the stable or the freezer */}
            <div className="section-title">⚗️ Fuse (two monsters → a new species)</div>
            <div className="dim" style={{ fontSize: 12, marginBottom: 4 }}>
              Combine two monsters — from your stable or the freezer — into a brand-new fusion species.
            </div>
            <div className="fuserow">
              <select value={fuseA} onChange={(e) => setFuseA(e.target.value)}>
                <option value="">— monster A —</option>
                {fusable.map((m) => <option key={m.id} value={m.id}>{frozenIds.has(m.id) ? '🧊 ' : ''}{m.name} ({m.species.body})</option>)}
              </select>
              <select value={fuseB} onChange={(e) => setFuseB(e.target.value)}>
                <option value="">— monster B —</option>
                {fusable.map((m) => <option key={m.id} value={m.id}>{frozenIds.has(m.id) ? '🧊 ' : ''}{m.name} ({m.species.body})</option>)}
              </select>
              <button className="rankup"
                disabled={!spin || game.gold < FUSION_COST}
                onClick={() => { if (spin) setWheel({ result: spin.speciesId, pool: spin.pool, a: fuseA, b: fuseB }) }}>
                Fuse · {FUSION_COST}g
              </button>
            </div>
            {fuseA && fuseB && fuseA !== fuseB && (
              validPair
                ? <div className="hint">⚗️ {bodyOf(fuseA)} + {bodyOf(fuseB)} → a <b>{spin?.classLabel}</b>.</div>
                : <div className="neg" style={{ fontSize: 12 }}>🚫 No known fusion for {bodyOf(fuseA)} + {bodyOf(fuseB)}. Valid recipe: Mammal + Reptilian → Saurian.</div>
            )}
            {fusable.length < 2 && <div className="hint">You need at least two monsters to fuse.</div>}
          </div>
        </div>
        )
      })()}

      {wheel && (
        <FusionWheel pool={wheel.pool} result={wheel.result}
          onDone={() => { setGame((g) => fuse(g, wheel.a, wheel.b)); setFuseA(''); setFuseB(''); setWheel(null) }} />
      )}

      {/* ---- MARKET: buy monsters, licenses, supplies, healing ---- */}
      {area === 'market' && (
      <div className="townmap">
        {/* Market */}
        <div className="card loc">
          <TipBanner game={game} setGame={setGame} id="market">
            🛒 Buy your first monster here — cheap is fine, training matters far more than the roll.
          </TipBanner>
          <div className="loc-h"><span>🛒 Market</span>{game.marketCoach > 0 && (
            <span className="dim">🎓 stock trained to {LEAGUES[game.marketCoach === 2 ? 4 : 2].name}</span>
          )}</div>
          {barnFull && <div className="hint">🏠 Stable full — upgrade a barn to buy.</div>}
          <ScoutPanel game={game} setGame={setGame} />
          <div className="offers">
            {game.market.length === 0 && <div className="dim">Sold out — market refreshes at the start of each month.</div>}
            {game.market.map((o, i) => {
              const m = offerMonster(o)
              const afford = game.gold >= o.price
              const prof = trainingProfileFor(m.species)
              return (
                <div className={'offer' + (step === 'buy' ? ' tut-highlight' : '')} key={o.seed}>
                  {/* Compact by default (three full cards made Town very long);
                      the full MonsterCard is one click away. */}
                  <details className="offer-details">
                    <summary className="offer-brief">
                      <Sprite species={m.species} size={44} />
                      <span className="offer-brief-text">
                        <b>{m.name}</b> {o.scouted && <span title="Found by your Market Scout">🔎</span>} <span className="dim">· {m.species.name} · {m.className}</span>
                        <span className="offer-brief-sub">
                          <AptMarks prof={prof} softFlaw={isPrestigeBody(m.species.body)} /> <span className="dim">· {m.species.lifespan}y</span>
                        </span>
                      </span>
                      <span className="offer-brief-more dim">details ▾</span>
                    </summary>
                    <MonsterCard m={m} />
                  </details>
                  <button disabled={!afford || barnFull} onClick={() => setGame((g) => buyMonster(g, i))}>
                    Buy · {o.price}g
                  </button>
                </div>
              )
            })}
          </div>
        </div>

        {/* Infirmary (2026-07-25): pay to mend wounds NOW instead of resting a
            week away — fee scales with league and how much is missing.
            Stamina is untouched; only Rest cures fatigue. */}
        <div className="card loc">
          <div className="loc-h"><span>⛑ Infirmary</span><span className="dim">mends HP &amp; MP · not stamina</span></div>
          {game.stable.filter((c) => !c.retired && infirmaryFee(c) > 0).length === 0
            ? <div className="dim">Everyone is in fighting shape.</div>
            : game.stable.filter((c) => !c.retired && infirmaryFee(c) > 0).map((c) => (
              <div className="shoprow" key={c.id}>
                <div>
                  <b>{c.name}</b>
                  <div className="dim">{c.hp}/{maxHp(c.stats)} HP · {c.mp}/{maxMana(c.stats)} MP</div>
                </div>
                <button disabled={game.gold < infirmaryFee(c)} onClick={() => setGame((g) => healAtInfirmary(g, c.id))}>
                  Heal · {infirmaryFee(c)}g
                </button>
              </div>
            ))}
        </div>

      </div>
      )}

      {/* ---- RANCH SHOP: licenses, barn, comfort, care upgrades, contracts ---- */}
      {area === 'shop' && (
      <div className="townmap">
        <div className="card loc">
          <div className="loc-h"><span>🏗️ Ranch Shop</span></div>
          {/* League license (v0.5): unlocked by WINNING the rank-up trial, then
              bought here — the whole account advances a league. */}
          {game.licenseEarned > game.licenseIndex ? (
            <div className="shoprow license-ready">
              <div>
                <b>🎫 {LEAGUES[game.licenseIndex + 1].name} License</b>
                <div className="dim">Trial won! Unlocks the {LEAGUES[game.licenseIndex + 1].name} league for your whole stable.</div>
              </div>
              <button disabled={game.gold < nextLicenseCost(game)} onClick={() => setGame((g) => buyLicense(g))}>
                Buy · {nextLicenseCost(game)}g
              </button>
            </div>
          ) : game.licenseIndex < LEAGUES.length - 1 && (
            <div className="shoprow">
              <div>
                <b>🎫 {LEAGUES[game.licenseIndex + 1].name} License</b>
                <div className="dim">Beat the {LEAGUES[game.licenseIndex].name} Champion (rank-up trial, at the Ranch) to unlock · {nextLicenseCost(game)}g</div>
              </div>
              <button disabled>🔒</button>
            </div>
          )}
          <div className="shoprow">
            <div>
              <b>Bigger Barn</b>
              <div className="dim">Capacity {game.barnCapacity} → {game.barnCapacity + 1}</div>
            </div>
            <button disabled={game.gold < barnCost(game)} onClick={() => setGame((g) => upgradeBarn(g))}>Buy · {barnCost(game)}g</button>
          </div>
          {/* Monster-market upgrades (v0.77): more stock, aimed stock, better stock. */}
          <div className="shoprow">
            <div>
              <b>Monster Market Slots</b>
              <div className="dim">{marketSlotCost(game) === null
                ? `✓ Maxed — ${MARKET_BASE_SLOTS + MARKET_SLOTS_MAX} monsters on offer`
                : `One more monster on offer each month · ${MARKET_BASE_SLOTS + game.marketSlots} → ${MARKET_BASE_SLOTS + game.marketSlots + 1}`}</div>
            </div>
            <button
              disabled={marketSlotCost(game) === null || game.gold < (marketSlotCost(game) ?? Infinity)}
              onClick={() => setGame((g) => buyMarketSlot(g))}
            >
              {marketSlotCost(game) === null ? '✓ Maxed' : `Buy · ${marketSlotCost(game)}g`}
            </button>
          </div>
          <div className="shoprow">
            <div>
              <b>Monster Market Scout</b>
              <div className="dim">{game.marketScout === 0
                ? 'Name a species to hunt for · 15% chance per market slot'
                : game.marketScout === 1
                  ? 'Upgrade: 25% per slot, and track a second species at once'
                  : '✓ 25% per slot · two species tracked'}</div>
            </div>
            <button
              disabled={scoutCost(game) === null || game.gold < (scoutCost(game) ?? Infinity)}
              onClick={() => setGame((g) => buyMarketScout(g))}
            >
              {scoutCost(game) === null ? '✓ Owned' : `${game.marketScout === 0 ? 'Buy' : 'Upgrade'} · ${scoutCost(game)}g`}
            </button>
          </div>
          {coachVisible(game) && (
            <div className="shoprow">
              <div>
                <b>Market Coach</b>
                <div className="dim">{game.marketCoach === 0
                  ? `${LEAGUES[2].name}-league stock · raises every unbred monster's training cap ${WILD_GEN1_CAP} → ${WILD_GEN1_CAP + COACH_CAP_LIFT[1]} · +${COACH_SURCHARGE[1]}g each`
                  : game.marketCoach === 1
                    ? `Upgrade: ${LEAGUES[4].name}-league stock · cap ${WILD_GEN1_CAP + COACH_CAP_LIFT[1]} → ${WILD_GEN1_CAP + COACH_CAP_LIFT[2]} · +${COACH_SURCHARGE[2]}g each`
                    : `✓ ${LEAGUES[4].name}-league stock · cap ${WILD_GEN1_CAP + COACH_CAP_LIFT[2]} · +${COACH_SURCHARGE[2]}g each`}</div>
              </div>
              <button disabled={!canBuyMarketCoach(game)} onClick={() => setGame((g) => buyMarketCoach(g))}>
                {coachCost(game) === null ? '✓ Owned'
                  : game.licenseIndex < (coachLeague(game) ?? 0) ? `🔒 ${LEAGUES[coachLeague(game) ?? 0].name}`
                    : `${game.marketCoach === 0 ? 'Buy' : 'Upgrade'} · ${coachCost(game)}g`}
              </button>
            </div>
          )}
          {/* Comfort set (v0.6): stable-wide permanent +2 months career span each. */}
          {COMFORT_ITEMS.map((it) => (
            <div className="shoprow" key={it.id}>
              <div>
                <b>{it.icon} {it.name}</b>
                <div className="dim">+2 months career span — every monster, forever{game.comfortOwned.includes(it.id) ? ' · ✓ owned' : ''}</div>
              </div>
              {game.comfortOwned.includes(it.id)
                ? <button disabled>✓</button>
                : <button disabled={game.gold < it.price} onClick={() => setGame((g) => buyComfortItem(g, it.id))}>Buy · {it.price}g</button>}
            </div>
          ))}
          {/* Extreme Training Manual (v0.6): unlocks the extreme drill row. */}
          <div className="shoprow">
            <div>
              <b>📕 Extreme Training Manual</b>
              <div className="dim">Unlocks extreme drills: +{EXTREME_GAIN} to one stat, −{EXTREME_COST} to two others, −{EXTREME_DRILL_STAMINA} stamina{game.extremeUnlocked ? ' · ✓ owned' : ''}</div>
            </div>
            {game.extremeUnlocked
              ? <button disabled>✓</button>
              : <button disabled={game.gold < EXTREME_MANUAL_COST} onClick={() => setGame((g) => buyExtremeManual(g))}>Buy · {EXTREME_MANUAL_COST}g</button>}
          </div>
          {/* Diverse Training Manual (v0.90): the pair-training tier. */}
          <div className="shoprow">
            <div>
              <b>📗 Diverse Training Manual</b>
              <div className="dim">Unlocks diverse drills: +{DIVERSE_GAIN} to TWO stats at once, no malus, −{DIVERSE_DRILL_STAMINA} stamina{game.diverseUnlocked ? ' · ✓ owned' : ''}</div>
            </div>
            {game.diverseUnlocked
              ? <button disabled>✓</button>
              : <button disabled={game.gold < DIVERSE_MANUAL_COST} onClick={() => setGame((g) => buyDiverseManual(g))}>Buy · {DIVERSE_MANUAL_COST}g</button>}
          </div>
          {/* Battle Analyst (v0.84): deepens the post-fight match analysis. */}
          <div className="shoprow">
            <div>
              <b>🔎 Battle Analyst</b>
              <div className="dim">{game.battleAnalyst ? 'Hired — reads the opponent’s gameplan and advises after every fight.' : 'Post-fight: reveals the opponent’s gameplan and gives tactical advice for your next match.'}</div>
            </div>
            {game.battleAnalyst
              ? <button disabled>✓ Hired</button>
              : <button disabled={game.gold < BATTLE_ANALYST_COST} onClick={() => setGame((g) => buyBattleAnalyst(g))}>Hire · {BATTLE_ANALYST_COST}g</button>}
          </div>
          <div className="shoprow">
            <div>
              <b>🧺 Pantry Contract</b>
              <div className="dim">{game.pantryContract ? 'Owned — 20% off normal foods.' : 'Permanent 20% off normal foods.'}</div>
            </div>
            <button disabled={game.pantryContract || game.gold < PANTRY_CONTRACT_COST} onClick={() => setGame((g) => buyPantryContract(g))}>
              {game.pantryContract ? '✓ Owned' : `Buy · ${PANTRY_CONTRACT_COST}g`}
            </button>
          </div>
          <div className="shoprow">
            <div>
              <b>🏰 Grand Larder</b>
              <div className="dim">{game.grandLarder ? 'Owned — 20% off premium foods.' : '20% off premium foods (training & fruits).'}</div>
            </div>
            <button disabled={game.grandLarder || game.gold < GRAND_LARDER_COST} onClick={() => setGame((g) => buyGrandLarder(g))}>
              {game.grandLarder ? '✓ Owned' : `Buy · ${GRAND_LARDER_COST}g`}
            </button>
          </div>
          <div className="shoprow">
            <div>
              <b>Special Breeding License</b>
              <div className="dim">{game.specialLicense
                ? '✓ Unlocked Draconic & Abyssal'
                : `Unlocks Draconic & Abyssal · requires ${LEAGUES[SPECIAL_LICENSE_LEAGUE].name} league`}</div>
            </div>
            <button disabled={!canBuySpecialLicense(game)} onClick={() => setGame((g) => buySpecialLicense(g))}>
              {game.specialLicense ? '✓ Owned'
                : game.licenseIndex < SPECIAL_LICENSE_LEAGUE ? `🔒 ${LEAGUES[SPECIAL_LICENSE_LEAGUE].name}`
                  : `Buy · ${SPECIAL_LICENSE_COST}g`}
            </button>
          </div>
          <div className="shoprow">
            <div>
              <b>Elite Breeding License</b>
              <div className="dim">{game.eliteLicense
                ? '✓ Unlocked Mythical'
                : `Unlocks Mythical · requires ${LEAGUES[ELITE_LICENSE_LEAGUE].name} league`}</div>
            </div>
            <button disabled={!canBuyEliteLicense(game)} onClick={() => setGame((g) => buyEliteLicense(g))}>
              {game.eliteLicense ? '✓ Owned'
                : game.licenseIndex < ELITE_LICENSE_LEAGUE ? `🔒 ${LEAGUES[ELITE_LICENSE_LEAGUE].name}`
                  : `Buy · ${ELITE_LICENSE_COST}g`}
            </button>
          </div>
        </div>
      </div>
      )}
    </>
  )
}

// ============================ Ranch (raising loop) ============================
// The stat a drill primarily trains — the one with a positive gain (basic
// drills have exactly one entry; intensive drills pair it with a malus stat).
const primaryStatOf = (d: Drill): Stat => Object.entries(d.gains).find(([, v]) => (v as number) > 0)![0] as Stat

// A "last week" digest line with its numeric deltas tinted — losses (the line
// that tells you a monster came home hurt) previously read identically to
// gains. Splits on signed numbers only; all other text passes through.
function DigestLine({ text, className }: { text: string; className: string }) {
  const parts = text.split(/([+-]\d+)/g)
  return (
    <div className={className}>
      {parts.map((p, i) =>
        /^-\d+$/.test(p) ? <span key={i} className="neg">{p}</span>
          : /^\+\d+$/.test(p) ? <span key={i} className="pos">{p}</span>
            : p)}
    </div>
  )
}

// One training-row block: a drill's LIVE preview for the selected monster this
// week (exact, not estimated — previewWeekEffects shares applyWeek's seeded
// rng) so the happiness-weighted roll shows the real number, not a nominal one.
function TrainBlock({ d, career, food, forage, gear, selected, onClick }: {
  d: Drill; career: Career; food: WeekPlanEntry['food']; forage?: boolean; gear: GameState['trainingGear']; selected: boolean; onClick: () => void
}) {
  const stat = primaryStatOf(d)
  const preview = previewWeekEffects(career, d.id, food, forage, gear)
  const gain = preview.statDeltas[stat]
  const malusEntries = (Object.entries(d.gains) as [Stat, number][]).filter(([, v]) => v < 0)
  const stamCost = drillStamina(d.kind)
  // A diverse drill raises TWO stats, so it prints both rather than a single gain.
  const gainStats = (Object.entries(d.gains) as [Stat, number][]).filter(([, v]) => v > 0).map(([k]) => k)
  const gainText = gain !== undefined ? `${gain > 0 ? '+' : ''}${gain} ${stat}` : `+${d.gains[stat]} ${stat}`
  // Aptitude coloring (user spec 2026-07-20): a stat this species trains FASTER
  // (major/minor) gets its number tinted to the stat's own colour instead
  // of plain white, so the boost is visible right on the number, uniformly
  // across every drill. No box on the gain — the box is reserved for the
  // intensive-drill malus stat, which keeps its existing boxed treatment.
  const prof = trainingProfileFor(career.species)
  const hasBenefit = stat === prof.major || stat === prof.minor
  return (
    <button className={'trainblock' + (selected ? ' selected' : '')} onClick={onClick} title={d.desc}>
      <div className="trainblock-name" style={{ color: STAT_COLOR[stat] }}>{d.name}</div>
      <div className="trainblock-sub">
        {d.kind === 'diverse'
          ? gainStats.map((gs, i) => (
            <span key={gs}>{i > 0 ? ', ' : ''}
              <span className="benefit-gain" style={gs === prof.major || gs === prof.minor ? { color: STAT_COLOR[gs] } : undefined}>
                +{preview.statDeltas[gs] ?? d.gains[gs]} {gs}
              </span>
            </span>
          ))
          : <span className="benefit-gain" style={hasBenefit ? { color: STAT_COLOR[stat] } : undefined}>{gainText}</span>}
        {malusEntries.map(([ms, mv]) => <span key={ms}>, <span className="benefit-malus">{preview.statDeltas[ms] ?? mv} {ms}</span></span>)} · −{stamCost} stam
      </div>
    </button>
  )
}

// The week's activity picker — six stat columns (basic + intensives + extreme),
// an OTHER column for rest/excursion, and the diverse row once unlocked.
//
// Extracted from RanchView (v0.92) so the weekly feed-and-train walkthrough can
// use it. Food and training are ONE decision per monster — the drill previews
// read the food through previewWeekEffects, so choosing a training food and
// seeing the drill numbers move belongs on the same screen. The Ranch keeps the
// roster overview and the tournament calendar; the week's plan is set here.
function TrainingPicker({ career, plan, gear, extremeUnlocked, diverseUnlocked, onPick }: {
  career: Career; plan: WeekPlanEntry; gear: GameState['trainingGear']
  extremeUnlocked: boolean; diverseUnlocked: boolean; onPick: (activity: string) => void
}) {
  const restPrev = previewWeekEffects(career, 'rest', plan.food, plan.forage, gear)
  const excPrev = previewWeekEffects(career, 'excursion', plan.food, plan.forage, gear)
  return (
    <>
      <div className="trainrow">
        {STATS.map((stat) => {
          const basic = BASIC_DRILLS.find((d) => primaryStatOf(d) === stat)!
          const intensives = INTENSIVE_DRILLS.filter((d) => primaryStatOf(d) === stat)
          const extreme = EXTREME_DRILLS.find((d) => primaryStatOf(d) === stat)
          const gearTier = gear[stat] ?? 0
          return (
            <div className="traincol" key={stat}>
              <div className="traincol-h" style={{ color: STAT_COLOR[stat] }}>{stat}{gearTier > 0 && <span className="dim"> ⚙+{gearTier * 5}%</span>}</div>
              <TrainBlock d={basic} career={career} food={plan.food} forage={plan.forage} gear={gear} selected={plan.activity === basic.id} onClick={() => onPick(basic.id)} />
              {intensives.map((d) => (
                <TrainBlock key={d.id} d={d} career={career} food={plan.food} forage={plan.forage} gear={gear} selected={plan.activity === d.id} onClick={() => onPick(d.id)} />
              ))}
              {extremeUnlocked && extreme && (
                <TrainBlock d={extreme} career={career} food={plan.food} forage={plan.forage} gear={gear} selected={plan.activity === extreme.id} onClick={() => onPick(extreme.id)} />
              )}
            </div>
          )
        })}
        <div className="traincol">
          <div className="traincol-h dim">OTHER</div>
          <button className={'trainblock' + (plan.activity === 'rest' ? ' selected' : '')} onClick={() => onPick('rest')}>
            <div className="trainblock-name">Rest</div>
            <div className="trainblock-sub">
              <span className="benefit-gain">+{restPrev.staminaDelta} stam</span>
              {restPrev.hpDelta > 0 && <>, <span className="benefit-gain">+{restPrev.hpDelta} HP</span></>}
              {restPrev.mpDelta > 0 && <>, <span className="benefit-gain">+{restPrev.mpDelta} MP</span></>}
            </div>
          </button>
          <button className={'trainblock' + (plan.activity === 'excursion' ? ' selected' : '')} onClick={() => onPick('excursion')}>
            <div className="trainblock-name">Excursion</div>
            <div className="trainblock-sub"><span className="benefit-gain">+{excPrev.goldDelta}g</span>, <span className="benefit-malus">{excPrev.staminaDelta} stam</span></div>
          </button>
        </div>
      </div>
      {diverseUnlocked && (
        <>
          <div className="section-title">Diverse Training <span className="dim">· two stats at once, no malus</span></div>
          <div className="trainrow diverserow">
            {DIVERSE_DRILLS.map((d) => (
              <TrainBlock key={d.id} d={d} career={career} food={plan.food} forage={plan.forage}
                gear={gear} selected={plan.activity === d.id} onClick={() => onPick(d.id)} />
            ))}
          </div>
        </>
      )}
    </>
  )
}

// The planned action's benefit, shown while picking food (user spec 2026-07-20):
// training shows each stat bar going current → new, rest shows the stamina gain,
// excursion shows the flat gold purse. Gains render white; maluses render black.
// Live and exact — previewWeekEffects shares applyWeek's seeded rng, and the
// preview re-rolls with the post-feed happiness as the food selection changes.
function PlanBenefit({ career, plan, gear }: { career: Career; plan: WeekPlanEntry; gear: GameState['trainingGear'] }) {
  const preview = previewWeekEffects(career, plan.activity, plan.food, plan.forage, gear)
  const drill = ALL_DRILLS.find((d) => d.id === plan.activity)
  const label = drill ? `💪 ${drill.name}` : plan.activity === 'excursion' ? '🧭 Excursion' : '😴 Rest'
  const cap = LEAGUES[career.licenseIndex].cap
  return (
    <>
      <div className="section-title">This week's plan — {label}</div>
      <div className="planbenefit">
        {drill && (Object.keys(drill.gains) as Stat[]).map((stat) => {
          const cur = career.stats[stat]
          const delta = preview.statDeltas[stat] ?? 0
          const next = cur + delta
          const basePct = (Math.min(cur, next) / cap) * 100
          const diffPct = (Math.abs(delta) / cap) * 100
          return (
            <div className="benefitrow" key={stat}>
              <span style={{ color: STAT_COLOR[stat], fontWeight: 700 }}>{stat}</span>
              <span className="bar">
                <i style={{ width: `${basePct}%`, background: STAT_COLOR[stat] }} />
                {delta !== 0 && <i style={{ width: `${diffPct}%`, background: delta > 0 ? '#fff' : '#000' }} />}
              </span>
              <span className="v">{cur} → {next}</span>
              {delta > 0 ? <span className="benefit-gain">+{delta}</span>
                : delta < 0 ? <span className="benefit-malus">{delta}</span>
                  : <span className="dim">capped</span>}
            </div>
          )
        })}
        {plan.activity === 'rest' && (() => {
          const hpMax = maxHp(career.stats)
          const mpMax = maxMana(career.stats)
          return (
            <>
              <div className="benefitrow">
                <span style={{ fontWeight: 700 }}>HP</span>
                <span className="bar">
                  <i style={{ width: `${(Math.min(career.hp, hpMax) / hpMax) * 100}%`, background: 'linear-gradient(90deg, #43a047, #7cb342)' }} />
                  {preview.hpDelta > 0 && <i style={{ width: `${(preview.hpDelta / hpMax) * 100}%`, background: '#fff' }} />}
                </span>
                <span className="v">{Math.min(career.hp, hpMax)} → {Math.min(career.hp, hpMax) + preview.hpDelta}</span>
                {preview.hpDelta > 0 ? <span className="benefit-gain">+{preview.hpDelta}</span> : <span className="dim">full</span>}
              </div>
              <div className="benefitrow">
                <span style={{ fontWeight: 700 }}>MP</span>
                <span className="bar">
                  <i style={{ width: `${mpMax > 0 ? (Math.min(career.mp, mpMax) / mpMax) * 100 : 0}%`, background: 'linear-gradient(90deg, #1e88e5, #42a5f5)' }} />
                  {preview.mpDelta > 0 && <i style={{ width: `${(preview.mpDelta / mpMax) * 100}%`, background: '#fff' }} />}
                </span>
                <span className="v">{Math.min(career.mp, mpMax)} → {Math.min(career.mp, mpMax) + preview.mpDelta}</span>
                {preview.mpDelta > 0 ? <span className="benefit-gain">+{preview.mpDelta}</span> : <span className="dim">full</span>}
              </div>
              <div className="benefitrow">
                <span style={{ fontWeight: 700 }}>Stamina</span>
                <span className="bar">
                  <i style={{ width: `${career.stamina}%`, background: 'var(--dex)' }} />
                  {preview.staminaDelta > 0 && <i style={{ width: `${preview.staminaDelta}%`, background: '#fff' }} />}
                </span>
                <span className="v">{career.stamina} → {career.stamina + preview.staminaDelta}</span>
                {preview.staminaDelta > 0 ? <span className="benefit-gain">+{preview.staminaDelta}</span> : <span className="dim">full</span>}
              </div>
            </>
          )
        })()}
        {plan.activity === 'excursion' && (
          <div className="benefitrow flat">
            <span style={{ fontWeight: 700 }}>Gold</span>
            <span className="benefit-gain big">+{preview.goldDelta}g</span>
          </div>
        )}
        {(drill || plan.activity === 'excursion') && (
          <div className="benefitrow flat">
            <span style={{ fontWeight: 700 }}>Stamina</span>
            <span className="benefit-malus">{preview.staminaDelta}</span>
          </div>
        )}
      </div>
    </>
  )
}

// The Ability Selection UI (§1b, mockup approved 2026-07-19): click a slot,
// then a pool move to swap it in. Filter by stat; equipped moves show dimmed
// in the pool. Changes apply immediately via onSetLoadout (no separate save
// The reusable tactics control grid (v0.81): five order groups + a plain-language
// summary. Used by the pre-fight tactics screen (once per fielded monster) and by
// the Sandbox fighter editor. `teamPlay` enables the multi-combatant orders
// (target priority) — off for a 1v1, on for a team fight.
function TacticsControls({ value, onChange, loadout, teamPlay }: {
  value: Tactics; onChange: (t: Tactics) => void; loadout: Move[]; teamPlay: boolean
}) {
  const cur = value
  const temp = TEMPERAMENT_INFO.find((o) => o.id === cur.temperament)!
  const prio = TARGET_PRIORITY_INFO.find((o) => o.id === cur.targetPriority)!
  const mana = MANA_POLICY_INFO.find((o) => o.id === (cur.manaPolicy ?? 'normal'))!
  const combo = COMBO_INFO.find((o) => o.id === cur.comboRole)!
  const preserve = PRESERVE_INFO.find((o) => o.id === (cur.preserve ?? 'off'))!
  const cc = CC_INFO.find((o) => o.id === (cur.ccPriority ?? false))!
  // Opening SEQUENCE: ordered list of up to 2 move ids. Click a move to add/remove.
  // ⚠️ The legacy single `openerId` fallback is gone (2026-08-01) — nothing has
  // written it since v0.81.
  const openerIds = cur.openerIds ?? []
  const openerMoves = openerIds.map((id) => loadout.find((mv) => mv.id === id)).filter((mv): mv is Move => !!mv)
  const setOpeners = (ids: string[]) => onChange({ ...cur, openerIds: ids.length ? ids : undefined })
  const toggleOpener = (id: string) => setOpeners(openerIds.includes(id) ? openerIds.filter((x) => x !== id)
    : openerIds.length >= 2 ? openerIds : [...openerIds, id])
  // ⚠️ THE TWO HALVES NEED DIFFERENT KIT, so they gate separately. The old single
  // `comboReady` demanded BOTH a setup and its matching payoff on ONE monster —
  // the self-combo case, which is only 17% of drafted monsters. Under prime/
  // detonate the whole point is that the halves sit on DIFFERENT monsters (59% can
  // prime, 26% can detonate), so one shared gate would have locked the control for
  // most of the roster it exists for.
  const canPrime = loadout.some((mv) => mv.status && CASHABLE_STATUSES.has(mv.status.kind))
  const canDetonate = loadout.some((mv) => !!mv.effects?.bonusVsStatus)
  const comboReady = canPrime || canDetonate
  const CC_KINDS_UI = ['stun', 'sleep', 'fear', 'confusion', 'silence', 'charm', 'knockback', 'blind']
  const ccReady = loadout.some((mv) => (mv.target === 'enemy' || mv.target === 'allEnemies') && mv.status && CC_KINDS_UI.includes(mv.status.kind))
  const summary = [
    { icon: temp.icon, name: temp.name, desc: temp.desc },
    openerMoves.length
      ? { icon: '▶', name: `Open: ${openerMoves.map((mv) => mv.name).join(' → ')}`, desc: openerMoves.length > 1 ? 'Scripts the first two plays in order.' : 'Always throws this move first when it can.' }
      : { icon: '🎲', name: 'Instinct opener', desc: 'The class picks its own first play.' },
    { icon: mana.icon, name: mana.name, desc: mana.desc },
    { icon: combo.icon, name: combo.name, desc: comboReady ? combo.desc : 'No combo piece equipped yet — no effect.' },
    ...(cur.preserve && cur.preserve !== 'off' ? [{ icon: preserve.icon, name: preserve.name, desc: preserve.desc }] : []),
    ...(cur.ccPriority ? [{ icon: cc.icon, name: cc.name, desc: ccReady ? cc.desc : 'No control move equipped yet — no effect.' }] : []),
    ...(teamPlay ? [{ icon: prio.icon, name: prio.name, desc: prio.desc }] : []),
  ]
  return (
    <>
      <div className="tacticgroups">
        <div className="tacticgroup">
          <div className="tacticgroup-h">Temperament</div>
          {TEMPERAMENT_INFO.map((o) => (
            <button key={o.id} className={'tacticopt' + (cur.temperament === o.id ? ' on' : '')}
              onClick={() => onChange({ ...cur, temperament: o.id })}>{o.icon} {o.name}</button>
          ))}
        </div>
        <div className="tacticgroup">
          <div className="tacticgroup-h">Opening sequence <span className="dim">· up to 2, in order</span></div>
          <button className={'tacticopt' + (openerMoves.length === 0 ? ' on' : '')}
            onClick={() => setOpeners([])}>🎲 Instinct</button>
          {loadout.map((mv) => {
            const pos = openerIds.indexOf(mv.id)
            return (
              <button key={mv.id} className={'tacticopt' + (pos >= 0 ? ' on' : '')}
                onClick={() => toggleOpener(mv.id)}>
                {pos >= 0 ? `${pos + 1}. ` : '▶ '}{mv.name}
              </button>
            )
          })}
        </div>
        <div className="tacticgroup">
          <div className="tacticgroup-h">Mana policy</div>
          {MANA_POLICY_INFO.map((o) => (
            <button key={o.id} className={'tacticopt' + ((cur.manaPolicy ?? 'normal') === o.id ? ' on' : '')}
              onClick={() => onChange({ ...cur, manaPolicy: o.id })}>{o.icon} {o.name}</button>
          ))}
        </div>
        <div className="tacticgroup">
          <div className="tacticgroup-h">Survival</div>
          {PRESERVE_INFO.map((o) => (
            <button key={o.id} className={'tacticopt' + ((cur.preserve ?? 'off') === o.id ? ' on' : '')}
              onClick={() => onChange({ ...cur, preserve: o.id })}>{o.icon} {o.name}</button>
          ))}
        </div>
        <div className="tacticgroup">
          <div className="tacticgroup-h">Control first{ccReady ? '' : ' 🔒'}</div>
          {CC_INFO.map((o) => {
            const disabled = o.id === true && !ccReady
            return (
              <button key={String(o.id)} disabled={disabled}
                className={'tacticopt' + ((cur.ccPriority ?? false) === o.id ? ' on' : '') + (disabled ? ' lockedopt' : '')}
                onClick={() => !disabled && onChange({ ...cur, ccPriority: o.id })}>{o.icon} {o.name}</button>
            )
          })}
          {!ccReady && <div className="hint">🕸 Equip a control move (stun, sleep, silence…) to use this.</div>}
        </div>
        <div className="tacticgroup">
          <div className="tacticgroup-h">Combo play{comboReady ? '' : ' 🔒'}</div>
          {COMBO_INFO.map((o) => {
            const disabled = (o.id === 'prime' && !canPrime) || (o.id === 'detonate' && !canDetonate)
            return (
              <button key={String(o.id)} disabled={disabled}
                className={'tacticopt' + (cur.comboRole === o.id ? ' on' : '') + (disabled ? ' lockedopt' : '')}
                onClick={() => !disabled && onChange({ ...cur, comboRole: o.id })}>{o.icon} {o.name}</button>
            )
          })}
          {!comboReady && <div className="hint">🔗 Equip a status move your team can cash, or a payoff move that cashes one.</div>}
        </div>
        {teamPlay && (
          <div className="tacticgroup">
            <div className="tacticgroup-h">Target priority</div>
            {TARGET_PRIORITY_INFO.map((o) => (
              <button key={o.id} className={'tacticopt' + (cur.targetPriority === o.id ? ' on' : '')}
                onClick={() => onChange({ ...cur, targetPriority: o.id })}>{o.icon} {o.name}</button>
            ))}
          </div>
        )}
      </div>
      <div className="tactic-summary">
        {summary.map((s, i) => (
          <div key={i} className="tactic-summary-row"><span className="tsr-icon">{s.icon}</span><span><b>{s.name}</b> — {s.desc}</span></div>
        ))}
      </div>
    </>
  )
}

// Neutral starting orders for a pre-fight tactics screen (v0.81): every member
// on balanced defaults, formation = the given roster order, no protect/mark.
function neutralMatchOrders(careers: Career[]): MatchOrders {
  return {
    tactics: Object.fromEntries(careers.map((c) => [c.id, { ...DEFAULT_TACTICS }])),
    formation: careers.map((c) => c.id),
  }
}

// step) — free any time except a monster's active tournament week.
function AbilitySelector({ m, name, onSetLoadout, onSetInnate, onSetTactics, onClose, showTactics = false, teamTacticsOpen = true }: {
  m: Monster; name: string; onSetLoadout: (ids: string[]) => void
  onSetInnate: (index: number) => void; onSetTactics?: (t: Tactics) => void; onClose: () => void
  showTactics?: boolean // the tactics editor is only shown in the Sandbox lab now (v0.81: real fights pick tactics pre-fight)
  teamTacticsOpen?: boolean // false until team battles are unlocked — locks the multi-combatant orders
}) {
  const [selectedSlot, setSelectedSlot] = useState<number | null>(null)
  const [filter, setFilter] = useState<Stat | 'All'>('All')
  const loadout = m.loadout
  const pool = filter === 'All' ? m.learned : m.learned.filter((mv) => mv.stat === filter)

  const swap = (move: Move) => {
    const slot = selectedSlot ?? 0
    const ids = [0, 1, 2]
      .map((i) => (i === slot ? move.id : loadout[i]?.id))
      .filter((id): id is string => !!id)
    onSetLoadout(ids)
    setSelectedSlot(null)
  }

  return (
    <div className="card abilityeditor">
      <div className="loc-h">
        <span>⚔ Edit Abilities — {name}</span>
        <button className="ghost" onClick={onClose}>✕ close</button>
      </div>
      <details className="editor-section" open>
        <summary className="editor-summary">⚔ Moves &amp; loadout</summary>
      <div className="hint">Pick a slot, then click a move to equip it.</div>
      <div className="abilityslots">
        {[0, 1, 2].map((i) => {
          const mv = loadout[i]
          return (
            <div key={i} className={'abilityslot' + (selectedSlot === i ? ' selected' : '')}
              onClick={() => setSelectedSlot(selectedSlot === i ? null : i)}>
              <div className="slotlabel">Slot {i + 1}{selectedSlot === i ? ' — pick a move below' : ''}</div>
              {mv ? (
                <>
                  <div className="mn">{mv.name}</div>
                  <div className="md">{mv.stat} · {mv.channel} · {manaCost(mv)} MP · cd {mv.cooldown}</div>
                </>
              ) : <div className="dim">empty slot</div>}
            </div>
          )
        })}
      </div>
      <div className="abilitychips">
        {(['All', ...STATS] as const).map((s) => (
          <button key={s} className={'abilitychip' + (filter === s ? ' on' : '')} onClick={() => setFilter(s)}>{s}</button>
        ))}
      </div>
      <div className="abilitypool">
        {pool.length === 0 && <div className="dim">No moves learned yet — train a stat past 40.</div>}
        {pool.map((mv) => {
          const equipped = loadout.some((l) => l.id === mv.id)
          return (
            <div key={mv.id} className={'move' + (equipped ? ' dim-eq' : '')} onClick={() => !equipped && swap(mv)}>
              <span className="lvl">{mv.stat} {mv.learnLevel}</span>
              <span className="mn">{mv.name}</span>
              <div className="md">{mv.desc} · {mv.channel} · {manaCost(mv)} MP · cd {mv.cooldown} · acc {mv.accuracy}{equipped ? ' · equipped' : ''}</div>
            </div>
          )
        })}
      </div>
      <button className="ghost" style={{ marginTop: 8 }} onClick={() => onSetLoadout([])}>Reset to suggested loadout</button>
      </details>

      <details className="editor-section">
        <summary className="editor-summary">✦ Innate passive</summary>
      <div className="hint">The 2nd choice is an alternative, not an upgrade.</div>
      <div className="abilitypool">
        {m.species.innate.map((a, i) => {
          const locked = i === 1 && !m.innateUnlocked
          const active = m.activeInnate === i
          return (
            <div key={a.name} className={'ability innatepick' + (active ? ' active' : '') + (locked ? ' locked' : '')}
              onClick={() => !locked && !active && onSetInnate(i)}>
              <span className="mn">{a.name}</span>
              <div className="md">{a.desc} {active ? '· ACTIVE' : locked ? `· 🔒 unlocks at ${INNATE_SECONDARY_LEVEL} in a stat` : ''}</div>
            </div>
          )
        })}
      </div>
      </details>

      {showTactics && onSetTactics && (
        <details className="editor-section">
          <summary className="editor-summary">🎯 Tactics — battle orders</summary>
          <div className="hint">Sandbox test orders for {name} — real fights pick tactics before each battle.</div>
          <TacticsControls value={m.tactics ?? DEFAULT_TACTICS} onChange={onSetTactics} loadout={m.loadout} teamPlay={teamTacticsOpen} />
        </details>
      )}
    </div>
  )
}

// Team-roster picker for team-size >1 tournaments (Tin+): same slot-click /
// pool-click convention as AbilitySelector above — click a slot, then a pool
// monster to fill it. Parent owns the persisted `monsterIds` array.
function TeamPicker({ pool, teamSize, monsterIds, onChange }: {
  pool: Career[]; teamSize: number; monsterIds: string[]; onChange: (ids: string[]) => void
}) {
  const [selectedSlot, setSelectedSlot] = useState<number | null>(null)
  const pick = (c: Career) => {
    const firstEmpty = Array.from({ length: teamSize }, (_, i) => i).find((i) => !monsterIds[i])
    const slot = selectedSlot ?? firstEmpty ?? 0
    const ids = Array.from({ length: teamSize }, (_, i) => (i === slot ? c.id : monsterIds[i])).filter((id): id is string => !!id)
    onChange(ids)
    setSelectedSlot(null)
  }
  return (
    <div className="teampicker">
      <div className="hint">
        Pick {teamSize} monsters — click a slot, then a monster below. <b>Slot order is your formation</b>:
        the first {frontRowCount(teamSize)} fight in the ⚔ front line, the rest in the 🏹 back line.
      </div>
      <div className="abilityslots">
        {Array.from({ length: teamSize }, (_, i) => {
          const id = monsterIds[i]
          const c = pool.find((x) => x.id === id)
          const cls = c ? classForStats(c.stats) : ''
          const row = rowOfSlot(i, teamSize)
          return (
            <div key={i} className={'abilityslot' + (selectedSlot === i ? ' selected' : '')}
              onClick={() => setSelectedSlot(selectedSlot === i ? null : i)}>
              <div className="slotlabel">{row === 'front' ? '⚔ Front' : '🏹 Back'} · slot {i + 1}</div>
              {c ? (
                <>
                  <div className="mn">{c.name}</div>
                  <div className="md">{cls} · {roleOfClass(cls)}</div>
                </>
              ) : <div className="dim">empty slot</div>}
            </div>
          )
        })}
      </div>
      <div className="abilitypool">
        {pool.map((c) => {
          const equipped = monsterIds.includes(c.id)
          const cls = classForStats(c.stats)
          const hurt = c.hp < maxHp(c.stats)
          return (
            <div key={c.id} className={'move' + (equipped ? ' dim-eq' : '')} onClick={() => !equipped && pick(c)}>
              <span className="lvl">{roleOfClass(cls)}</span>
              <span className="mn">{c.name}</span>
              <div className="md">
                {c.species.name} · {cls} · {LEAGUES[c.licenseIndex].name}
                {hurt ? ` · 🩹 ${c.hp}/${maxHp(c.stats)} HP` : ''}
                {staminaDamageMult(c.stamina) < 1 ? ` · 💤 ${c.stamina} stam` : ''}
                {equipped ? ' · picked' : ''}
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}

// A round-robin event's internal `label` ("Your Team" / "Rival Team N") is
// just a stable bookkeeping key — resolve it to the actual roster (for a
// name and an icon) wherever it's shown to the player (user spec 2026-07-22:
// "instead of rival teams, give them names or use the icons of the
// monsters"). Every match a label appears in carries the same fixed-full
// roster, so the first match found is enough.
function teamRoster(label: string, matches: EventMatch[]): Monster[] | null {
  const m = matches.find((mm) => mm.aLabel === label || mm.bLabel === label)
  if (!m) return null
  return m.aLabel === label ? m.teamA : m.teamB
}

// Round-robin results grid (user spec 2026-07-22, reference: Monster
// Rancher's bracket screen) — rows/columns are the field in placement order;
// each off-diagonal cell shows the ROW participant's result against the
// COLUMN participant (O win, ✕ loss, – draw). Row headers carry the lead
// monster's sprite + full team name instead of the internal label.
//
// The whole event is actually pre-simulated in one shot (advanceWeek), but
// the grid must not just dump every result at once (user spec 2026-07-22:
// "the bracket must begin empty... must not start complete") — `revealed`
// is the subset of `allMatches` treated as "already happened" so far, and
// ONLY that subset fills in cells. `allMatches` (always the full event) is
// still used for name/icon identity, since a team's roster shouldn't stay
// anonymous just because none of its matches have been revealed yet.
function BracketGrid({ standings, allMatches, revealed }: { standings: EventStanding[]; allMatches: EventMatch[]; revealed: EventMatch[] }) {
  const resultFor = (rowLabel: string, colLabel: string): 'win' | 'loss' | 'draw' | null => {
    const m = revealed.find((mm) => (mm.aLabel === rowLabel && mm.bLabel === colLabel) || (mm.aLabel === colLabel && mm.bLabel === rowLabel))
    if (!m) return null
    if (m.result.winner === 'draw') return 'draw'
    const rowIsA = m.aLabel === rowLabel
    return (rowIsA && m.result.winner === 'A') || (!rowIsA && m.result.winner === 'B') ? 'win' : 'loss'
  }
  return (
    <div className="bracket-grid-wrap">
      <table className="bracket-grid">
        <thead>
          <tr>
            <th />
            {standings.map((_, i) => <th key={i}>{i + 1}</th>)}
          </tr>
        </thead>
        <tbody>
          {standings.map((row, i) => {
            const roster = teamRoster(row.label, allMatches)
            return (
              <tr key={row.label}>
                <td className="bracket-row-head">
                  <span className="bracket-num">{i + 1}</span>
                  {roster && <Sprite species={roster[0].species} size={22} />}
                  <span className={row.isPlayer ? 'pos' : ''}>{roster ? roster.map((m) => m.name).join(' & ') : row.label}</span>
                </td>
                {standings.map((col, j) => {
                  if (i === j) return <td key={j} className="bracket-cell self" />
                  const res = resultFor(row.label, col.label)
                  return (
                    <td key={j} className={`bracket-cell ${res ?? ''}`}>
                      {res === 'win' ? 'O' : res === 'loss' ? '✕' : res === 'draw' ? '–' : ''}
                    </td>
                  )
                })}
              </tr>
            )
          })}
        </tbody>
      </table>
    </div>
  )
}

// Live round-robin standings (v0.84; extracted + memoized v0.861): the field is
// a pure function of the teams + the player's committed orders, so every match
// is rebuilt deterministically and revealed round by round — consistent with
// finalizeCup, which scores the identical matches at the end. Rebuilding means
// re-simulating up to C(parts,2) full team battles, so it's cached: the memo
// only recomputes when the staged cup advances (new orders / next match), not
// on every render of the battle screen.
function LiveStandingsCard({ ac, stable, matchIdx }: {
  ac: NonNullable<GameState['activeCup']>; stable: Career[]; matchIdx: number
}) {
  const data = useMemo(() => {
    // Derived here (not passed pre-mapped) so the memo keys on the stable
    // array's identity — a fresh .map() in the parent would defeat the cache.
    const playerCareers = ac.playerMonsterIds.map((id) => stable.find((c) => c.id === id)).filter((c): c is Career => !!c)
    const rivalTeams = ac.rivalTeams
    if (rivalTeams.length < 2) return null
    const parts = rivalTeams.length + 1
    const labelOf = (p: number) => (p === 0 ? 'Your Team' : `Rival Team ${p}`)
    const all: EventMatch[] = []
    const revealed: EventMatch[] = []
    let pk = -1
    let lastPlayerPos = -1
    roundRobinSchedule(parts).forEach(([i, j]) => {
      const involvesPlayer = i === 0 || j === 0
      let m: EventMatch
      if (involvesPlayer) {
        pk++
        const orders = ac.matchOrders[pk]
        const built = buildEventPlayerTeam(playerCareers, orders)
        const opp = applyMarkToOpponent(rivalTeams[(i === 0 ? j : i) - 1], orders?.mark)
        // Player is participant 0 = the low index i, hence always side A.
        m = { aLabel: labelOf(i), bLabel: labelOf(j), teamA: built.team, teamB: opp, result: simulateTeamBattle(built.team, opp, built.happiness, opp.map(() => 5)), involvesPlayer: true }
        if (orders && pk < matchIdx) { revealed.push(m); lastPlayerPos = all.length }
      } else {
        const a = rivalTeams[i - 1], b = rivalTeams[j - 1]
        m = { aLabel: labelOf(i), bLabel: labelOf(j), teamA: a, teamB: b, result: simulateTeamBattle(a, b, a.map(() => 5), b.map(() => 5)), involvesPlayer: false }
      }
      all.push(m)
    })
    // Reveal rival-vs-rival results up to the player's last completed match,
    // so parallel results surface as the tournament progresses.
    all.forEach((m, idx) => { if (!m.involvesPlayer && idx <= lastPlayerPos) revealed.push(m) })
    const rows = Array.from({ length: parts }, (_, p) => ({ label: labelOf(p), isPlayer: p === 0, wins: 0, draws: 0, losses: 0, hpFracSum: 0 }))
    const idxOf = (l: string) => rows.findIndex((r) => r.label === l)
    const frac = (m: EventMatch, side: 'A' | 'B', team: Monster[]) => m.result.finals.filter((f) => f.side === side).reduce((s, f) => s + f.hp / maxHp(team[f.slot].stats), 0) / team.length
    for (const m of revealed) {
      const ai = idxOf(m.aLabel), bi = idxOf(m.bLabel)
      if (m.result.winner === 'A') { rows[ai].wins++; rows[bi].losses++ } else if (m.result.winner === 'B') { rows[bi].wins++; rows[ai].losses++ } else { rows[ai].draws++; rows[bi].draws++ }
      rows[ai].hpFracSum += frac(m, 'A', m.teamA); rows[bi].hpFracSum += frac(m, 'B', m.teamB)
    }
    const standings: EventStanding[] = [...rows].sort((a, b) => b.wins - a.wins || b.hpFracSum - a.hpFracSum).map((s, i) => ({ ...s, placement: i + 1 }))
    return { all, revealed, standings }
  }, [ac, stable, matchIdx])
  if (!data) return null
  return (
    <div className="card" style={{ marginBottom: 10 }}>
      <div className="section-title">Standings</div>
      <BracketGrid standings={data.standings} allMatches={data.all} revealed={data.revealed} />
      {data.revealed.length === 0 && <div className="hint">Results fill in as each match is played.</div>}
    </div>
  )
}

// Post-fight causal analysis (v0.84), shown on the between-match hub and the
// results screen. Free tier: what happened (turning point, tactic ✓/✗, moments).
// Battle Analyst tier (Ranch Shop): the opponent's gameplan + concrete advice.
function MatchAnalysis({ fought, analyst }: { fought: { teamA: Monster[]; teamB: Monster[]; result: BattleResult }; analyst: boolean }) {
  const rep = useMemo(() => analyzeBattle(fought.result.events, fought.teamA, fought.teamB, fought.result, 'A'), [fought])
  const advice = useMemo(() => (analyst ? battleAdvice(rep, fought.teamA, fought.teamB, fought.result, 'A') : []), [rep, fought, analyst])
  if (!rep.turningPoint && rep.tacticOutcomes.length === 0 && rep.keyMoments.length === 0) return null
  return (
    <div className="card" style={{ marginBottom: 10 }}>
      <div className="section-title">📋 Match analysis</div>
      {rep.turningPoint && <div className="br-turn">{rep.turningPoint}</div>}
      {rep.tacticOutcomes.map((o, i) => <div key={i} className={'br-tactic ' + (o.ok ? 'ok' : 'no')}>{o.ok ? '✓' : '✗'} {o.text}</div>)}
      {rep.keyMoments.map((m, i) => <div key={i} className="br-moment">• {m}</div>)}
      {analyst ? (
        <>
          {rep.counterRead && <div className="br-counter">🧠 {rep.counterRead}</div>}
          <div className="analyst-advice">
            <div className="analyst-h">💡 Analyst's read</div>
            {advice.map((a, i) => <div key={i} className="br-advice">→ {a}</div>)}
          </div>
        </>
      ) : (
        <div className="hint">🔒 Hire a Battle Analyst (Ranch Shop) to read the opponent's gameplan and get tactical advice for your next fight.</div>
      )}
    </div>
  )
}

// Resume a part-fought tournament (v0.89 fix). Reloading mid-cup used to drop
// the player back at Match 1: `matchIdx` reset to 0 while the committed
// MatchOrders stayed in the save, so already-decided fights replayed one by one.
// Orders are only written when a fight is committed and the engine is a pure
// function of (monsters + orders), so every fought match reproduces exactly —
// which lets us rebuild the win/loss strip and skip straight to the right match.
function resumeOutcomes(g: GameState): ('win' | 'loss' | 'draw')[] {
  const ac = g.activeCup
  if (!ac) return []
  const careers = ac.playerMonsterIds.map((id) => g.stable.find((c) => c.id === id)).filter((c): c is Career => !!c)
  if (careers.length !== ac.playerMonsterIds.length) return []
  const oppOrder = ac.kind === 'trial' || ac.kind === 'rite' ? [0]
    : roundRobinSchedule(ac.rivalTeams.length + 1).filter(([i, j]) => i === 0 || j === 0).map(([i, j]) => (i === 0 ? j : i) - 1)
  const out: ('win' | 'loss' | 'draw')[] = []
  for (let k = 0; k < oppOrder.length; k++) {
    const orders = ac.matchOrders[k]
    if (!orders) break // first uncommitted match — that's where play resumes
    const built = buildEventPlayerTeam(careers, orders)
    const opp = applyMarkToOpponent(ac.rivalTeams[oppOrder[k]], orders.mark)
    const w = simulateTeamBattle(built.team, opp, built.happiness, opp.map(() => 5)).winner
    out.push(w === 'A' ? 'win' : w === 'B' ? 'loss' : 'draw')
  }
  return out
}

function RanchView({ game, setGame, onBattleScreen }: {
  game: GameState; setGame: Dispatch<SetStateAction<GameState>>; onBattleScreen: (v: boolean) => void
}) {
  // If every active monster already has food picked this week (e.g. the player
  // hopped Town -> Ranch and back), land straight on the stable instead of
  // replaying the feeding walkthrough; if only SOME are fed (a mid-week Market
  // buy), start feeding at the first unfed monster rather than monster 1.
  const firstUnfedIdx = game.stable.findIndex((c) => !c.retired && !game.weekPlans?.[c.id]?.food)
  const [phase, setPhase] = useState<'feeding' | 'stable' | 'battle'>(() =>
    game.activeCup ? 'battle' : game.stable.length > 0 && firstUnfedIdx === -1 ? 'stable' : 'feeding')
  const [decisionIdx, setDecisionIdx] = useState(() => Math.max(0, firstUnfedIdx))
  // Week plans live in GameState (persisted) so they survive navigating to
  // Town and back, and reloads — this was a real papercut as component state.
  const weekPlan = game.weekPlans ?? {}
  const setPlanFor = (monsterId: string, entry: WeekPlanEntry) =>
    setGame((g) => ({ ...g, weekPlans: { ...(g.weekPlans ?? {}), [monsterId]: entry } }))
  const [calendarMonth, setCalendarMonth] = useState(() => monthOfWeek(game.week))
  const [teamPick, setTeamPick] = useState<Record<string, string[]>>({})
  const [selectedTournamentId, setSelectedTournamentId] = useState<string | null>(null)
  const [battleOver, setBattleOver] = useState(false)
  // Computed ONCE on mount: the matches already fought in a part-played cup.
  const [resumed] = useState(() => resumeOutcomes(game))
  const [matchIdx, setMatchIdx] = useState(resumed.length)
  // Bracket hub sub-phase (v0.81): pre-cup lore -> next-match hub (scout the
  // opponent) -> pick tactics -> the fight (simulated live with those orders)
  // -> back to the hub -> ... -> finalize -> post-cup announcement.
  // Resuming mid-cup skips the pre-cup lore and lands on the between-match hub.
  const [battleSub, setBattleSub] = useState<'preamble' | 'bracket' | 'tactics' | 'fight' | 'announce'>(resumed.length > 0 ? 'bracket' : 'preamble')
  // In-progress per-fight orders (the pre-fight tactics screen edits this), the
  // built+simulated current match, and the player's running win/loss strip.
  const [matchTactics, setMatchTactics] = useState<MatchOrders | null>(null)
  const [liveMatch, setLiveMatch] = useState<{ teamA: Monster[]; teamB: Monster[]; result: BattleResult } | null>(null)
  const [lastFought, setLastFought] = useState<{ teamA: Monster[]; teamB: Monster[]; result: BattleResult } | null>(null)
  const [fightOutcomes, setFightOutcomes] = useState<('win' | 'loss' | 'draw')[]>(resumed)
  // Which of the player's upcoming matches have been paid-scouted, and at
  // what tier — keyed by matchIdx, reset each new tournament event.
  const [scouted, setScouted] = useState<Record<number, 'basic' | 'full'>>({})
  // Pre-signup field scouting (2026-07-25): rival teams are deterministic per
  // (seed, week, tournament), so they can be scouted BEFORE committing a
  // roster — when loadout edits are still free and the intel is actionable.
  // Keyed `${tournamentId}:${rivalIdx}`; local state, same convention as
  // `scouted` above (paying again at the bracket is match-day re-intel).
  const [fieldScout, setFieldScout] = useState<Record<string, 'basic' | 'full'>>({})
  const [trialPick, setTrialPick] = useState<string[]>([]) // rank-up trial roster picks (v0.5)
  const [sigPick, setSigPick] = useState<string | null>(null) // which monster is selected in the rite-prize claim panel (v0.91)
  const [selectedMonsterId, setSelectedMonsterId] = useState(() => game.stable.find((c) => !c.retired)?.id ?? game.stable[0]?.id ?? '')
  const [abilityEditorFor, setAbilityEditorFor] = useState<string | null>(null)
  const [showHistoryFor, setShowHistoryFor] = useState<string | null>(null)
  const [renamingId, setRenamingId] = useState<string | null>(null)

  // Tell App when the battle screen is up, so it can hide the Bestiary footer.
  const onBattleScreenNow = phase === 'battle' && (!!game.activeCup || !!game.lastBattle)
  useEffect(() => {
    onBattleScreen(onBattleScreenNow)
    return () => onBattleScreen(false)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [onBattleScreenNow])

  // A clicked tournament's entry panel renders BELOW the tall training grid —
  // scroll it into view so clicking a 🏆 doesn't look like it did nothing.
  const entryRef = useRef<HTMLDivElement>(null)
  useEffect(() => {
    if (selectedTournamentId) entryRef.current?.scrollIntoView({ behavior: 'smooth', block: 'nearest' })
  }, [selectedTournamentId])

  // Same trap: the ability editor replaces the training row, which sits below
  // the whole detail card, so it can open entirely off-screen — "Edit Abilities"
  // looked like a dead button. Measured: at 375x812 it mounts ~1380px down (a
  // 568px gap); even at 1280x720 it needed a 716px scroll. Worse on mobile,
  // where the detailgrid stacks to one column, but NOT mobile-only.
  // ⚠️ 'auto', NOT 'smooth' like entryRef above. An animated scroll is silently
  // a NO-OP wherever scroll animations are suppressed, which would reproduce
  // the exact bug this fixes. This one has to be guaranteed to land.
  const abilityRef = useRef<HTMLDivElement>(null)
  useEffect(() => {
    if (abilityEditorFor) abilityRef.current?.scrollIntoView({ behavior: 'auto', block: 'nearest' })
  }, [abilityEditorFor])

  // Scout-the-field rival teams (v0.861 memo): the field is deterministic per
  // (seed, week, tournament), but generating 3-5 full trained teams used to
  // re-run on EVERY RanchView render while an entry panel was open. Cached
  // here (above the early returns, per hooks rules) and read at the panel.
  const scoutRivalTeams = useMemo(() => {
    const t = selectedTournamentId
      ? tournamentCalendarFor(game.seed, yearOfWeek(game.week)).find((x) => x.id === selectedTournamentId)
      : null
    return t ? generateRivalTeamsForTournament(game, t) : null
    // Output is a pure function of these (rival personality is fixed per game).
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [game.seed, game.week, game.licenseIndex, selectedTournamentId])

  if (game.stable.length === 0) {
    return (
      <>
        <div className="ranchtop">
          <button className="ghost" onClick={() => setGame((g) => goto(g, 'town'))}>← 🏛 Town</button>
        </div>
        <p className="sub">Your stable is empty. Head to Town → Market to buy a monster.</p>
      </>
    )
  }

  // Tournament battle screen: a round-robin EVENT resolved this week, walked
  // through as a Monster-Rancher-style bracket hub (user spec 2026-07-22) —
  // pre-cup lore -> bracket standings (pay to scout the next opponent, then
  // Fight) -> the match itself -> back to the bracket -> repeat -> a post-cup
  // announcement. Rival-vs-rival matches aren't replayed, only listed.
  // ---- Post-event ANNOUNCE screen (v0.81): finalize has run, activeCup is
  // cleared and lastBattle holds the fully-scored event.
  if (phase === 'battle' && !game.activeCup && game.lastBattle && battleSub === 'announce') {
    const lb = game.lastBattle
    const tourney = tournamentCalendarFor(game.seed, yearOfWeek(game.week)).find((t) => t.id === lb.tournamentId)
    const lore = tourney ? cupLore(tourney) : null
    return (
      <>
        <div className="ranchtop">
          <span>🏟 {lb.tournamentName}</span><span>📅 {dateLabel(game.week)}</span><span>🪙 {game.gold}g</span>
        </div>
        <div className="card">
          <div className="section-title">🏆 {lb.tournamentName} — Final Results</div>
          <BracketGrid standings={lb.standings} allMatches={lb.matches} revealed={lb.matches} />
          {lore?.outroFlavour && <p className="sub">{lore.outroFlavour}</p>}
          <div className="battle-summary">
            {lb.isTrial
              ? lb.playerPlacement === 1
                ? `🎫 VICTORY!${lb.goldReward > 0 ? ` +${lb.goldReward}g —` : ''} the ${LEAGUES[Math.min(leagueIndexOf(lb.league) + 1, LEAGUES.length - 1)].name} license is now available in the Ranch Shop.`
                : `Defeated. The Champion holds the gate — recover, train, and challenge again in a few weeks.`
              : lb.goldReward > 0
                ? `You finished ${placementLabel(lb.playerPlacement)} of ${lb.fieldSize}! +${lb.goldReward}g${lb.expNote ? ` · training bonus: ${lb.expNote}` : ''}`
                : `You finished ${placementLabel(lb.playerPlacement)} of ${lb.fieldSize} — no reward this time. Train harder and try again.`}
          </div>
        </div>
        {lastFought && <MatchAnalysis fought={lastFought} analyst={game.battleAnalyst} />}
        <div className="carerow" style={{ justifyContent: 'center' }}>
          <button className="enter" onClick={() => setPhase('feeding')}>Continue →</button>
        </div>
      </>
    )
  }

  // ---- Interactive EVENT (v0.81): the staged cup/trial is fought match by
  // match — scout the opponent, pick this fight's tactics, watch it resolve
  // live, repeat — then finalize rewards. Each player match is simulated at the
  // moment its orders are committed, so tactics genuinely decide the outcome.
  if (phase === 'battle' && game.activeCup) {
    const ac = game.activeCup
    const isTrial = ac.kind === 'trial' || ac.kind === 'rite'
    const playerCareers = ac.playerMonsterIds.map((id) => game.stable.find((c) => c.id === id)).filter((c): c is Career => !!c)
    const teamSize = playerCareers.length
    const tourney = isTrial ? null : tournamentCalendarFor(game.seed, yearOfWeek(ac.week)).find((t) => t.id === ac.tournamentId)
    const league = isTrial ? LEAGUES[game.licenseIndex].name : (tourney?.league ?? LEAGUES[game.licenseIndex].name)
    const lore = tourney ? cupLore(tourney) : null
    const tournamentName = isTrial ? `Rank-up Trial — the ${league} Champion` : (tourney?.name ?? 'Cup')
    const rivalTeams = ac.rivalTeams
    const fieldSize = isTrial ? 2 : rivalTeams.length + 1
    // Ordered opponents (player-match index -> rival-team index), matching the
    // schedule finalizeCup scores against (player is participant 0, always the
    // low index, hence always side A in its matches).
    const oppOrder = isTrial ? [0]
      : roundRobinSchedule(rivalTeams.length + 1).filter(([i, j]) => i === 0 || j === 0).map(([i, j]) => (i === 0 ? j : i) - 1)
    const nPlayerMatches = oppOrder.length
    const oppIdx = oppOrder[matchIdx]
    const opponentTeam = oppIdx !== undefined ? rivalTeams[oppIdx] : null
    const opponentLabel = isTrial ? 'League Champion' : `Rival Team ${(oppIdx ?? 0) + 1}`
    const header = (
      <div className="ranchtop">
        <span>🏟 {tournamentName}</span><span>📅 {dateLabel(game.week)}</span><span>🪙 {game.gold}g</span>
      </div>
    )
    const progress = (
      <div className="dim" style={{ fontSize: 12, marginBottom: 6 }}>
        {Array.from({ length: nPlayerMatches }, (_, i) => {
          const o = fightOutcomes[i]
          return <span key={i} style={{ marginRight: 6 }}>{o === 'win' ? '✅' : o === 'loss' ? '❌' : o === 'draw' ? '➖' : i === matchIdx ? '🔸' : '·'} M{i + 1}</span>
        })}
      </div>
    )

    if (battleSub === 'preamble') {
      const perMonsterBudget = (LEAGUES[leagueIndexOf(league)]?.cap ?? 100) * 3.5
      const avgTotal = teamSize ? playerCareers.reduce((s, c) => s + STATS.reduce((t, k) => t + c.stats[k], 0), 0) / teamSize : Infinity
      const underdog = avgTotal < perMonsterBudget * RIVAL_BAND_MIN
      return (
        <>
          {header}
          <div className="card">
            <div className="section-title">{tournamentName} — {league} League</div>
            <p className="sub">{isTrial
              ? `The ${league} Champion awaits. Win, and the ${LEAGUES[Math.min(leagueIndexOf(league) + 1, LEAGUES.length - 1)].name} license opens in the Ranch Shop. Lose, and it's back to training.`
              : lore?.intro ?? `${tournamentName} is under way.`}</p>
            {!isTrial && <p className="dim">Prize on the line: up to {tourney?.rewards.gold ?? 0}g for 1st place, {fieldSize} teams competing round robin. You set your battle orders before each fight.</p>}
            {underdog && (
              <p className="dim">⚠ The field here fights at the {league}-league standard, and your team looks young for it — a rough day is normal. Every match is experience.</p>
            )}
            <div className="carerow" style={{ justifyContent: 'center' }}>
              <button className="enter" onClick={() => setBattleSub('bracket')}>{isTrial ? 'To the Trial →' : 'Enter the Cup →'}</button>
            </div>
          </div>
        </>
      )
    }

    if (battleSub === 'bracket') {
      // Live round-robin standings (v0.84): rebuilt in LiveStandingsCard, which
      // memoizes the full-field re-simulation — it only recomputes when the
      // staged cup's orders advance, not on every render of this screen.
      const bracketCard = isTrial ? null : <LiveStandingsCard ac={ac} stable={game.stable} matchIdx={matchIdx} />
      // All player matches fought → finalize and show the announce screen.
      if (matchIdx >= nPlayerMatches || !opponentTeam) {
        return (
          <>
            {header}
            {progress}
            {bracketCard}
            <div className="carerow" style={{ justifyContent: 'center' }}>
              <button className="enter" onClick={() => { setGame((g) => (ac.kind === 'rite' ? finalizeRite(g).game : ac.kind === 'trial' ? finalizeTrial(g).game : finalizeCup(g))); setBattleSub('announce') }}>See Results →</button>
            </div>
          </>
        )
      }
      const tier = scouted[matchIdx]
      const buyScout = (t: 'basic' | 'full') => {
        const fee = scoutFee(league, t)
        if (game.gold < fee) return
        setGame((g) => ({ ...g, gold: g.gold - fee }))
        setScouted((s) => ({ ...s, [matchIdx]: t }))
      }
      return (
        <>
          {header}
          <p className="sub">{tournamentName} — {league} league{isTrial ? '' : `, ${fieldSize} teams, round robin`}. Match {matchIdx + 1} of {nPlayerMatches}.</p>
          {progress}
          {lastFought && <MatchAnalysis fought={lastFought} analyst={game.battleAnalyst} />}
          {bracketCard}
          <div className="card">
            <div className="section-title">Next up: {opponentLabel}</div>
            <div className="scout-report">
              {opponentTeam.map((m, i) => <ScoutReport key={i} m={m} tier={tier} />)}
            </div>
            {tier !== 'full' && (
              <div className="carerow" style={{ marginTop: 8 }}>
                {!tier && (
                  <button className="ghost" disabled={game.gold < scoutFee(league, 'basic')} onClick={() => buyScout('basic')}>
                    🔍 Scout class &amp; loadout — {scoutFee(league, 'basic')}g
                  </button>
                )}
                <button className="ghost" disabled={game.gold < scoutFee(league, 'full')} onClick={() => buyScout('full')}>
                  🔍 Full scouting report — {scoutFee(league, 'full')}g
                </button>
              </div>
            )}
            <div className="carerow" style={{ justifyContent: 'center', marginTop: 8 }}>
              <button className="enter" onClick={() => {
                // Carry the previous fight's orders forward (v0.81): start from the
                // last match's committed orders, only clearing the focus target
                // since the opponent is different. Keep in-progress edits if the
                // player already opened this match's orders and went Back.
                const prev = ac.matchOrders[matchIdx - 1]
                setMatchTactics((mt) => mt ?? (prev ? { ...prev, mark: undefined } : neutralMatchOrders(playerCareers)))
                setBattleSub('tactics')
              }}>Set Battle Orders →</button>
            </div>
          </div>
        </>
      )
    }

    if (battleSub === 'tactics' && opponentTeam) {
      const orders = matchTactics ?? neutralMatchOrders(playerCareers)
      // Careers in the player's chosen formation order (front half = front line).
      const ordered = orders.formation.map((id) => playerCareers.find((c) => c.id === id)).filter((c): c is Career => !!c)
      const setOrders = (o: MatchOrders) => setMatchTactics(o)
      const moveUp = (idx: number) => {
        if (idx <= 0) return
        const f = [...orders.formation];[f[idx - 1], f[idx]] = [f[idx], f[idx - 1]]
        setOrders({ ...orders, formation: f })
      }
      const commit = () => {
        const built = buildEventPlayerTeam(playerCareers, orders)
        const opp = applyMarkToOpponent(opponentTeam, orders.mark)
        const result = simulateTeamBattle(built.team, opp, built.happiness, opp.map(() => 5))
        setGame((g) => (g.activeCup ? { ...g, activeCup: { ...g.activeCup, matchOrders: { ...g.activeCup.matchOrders, [matchIdx]: orders } } } : g))
        setLiveMatch({ teamA: built.team, teamB: opp, result })
        setBattleSub('fight')
      }
      return (
        <>
          {header}
          <p className="sub">Battle orders vs {opponentLabel} — Match {matchIdx + 1} of {nPlayerMatches}.</p>
          {teamSize > 1 && (
            <div className="card" style={{ marginBottom: 10 }}>
              <div className="section-title">Formation &amp; team orders</div>
              <div className="hint">Order = the line-up. The front half shields the back; melee must break the front line first.</div>
              <div className="formationrow">
                {ordered.map((c, i) => (
                  <div key={c.id} className="formationchip">
                    <button className="ghost small" disabled={i === 0} onClick={() => moveUp(i)}>▲</button>
                    <span>{i < frontRowCount(teamSize) ? '🛡' : '🏹'} {c.name}</span>
                  </div>
                ))}
              </div>
              <div className="protectrow">
                <span className="dim" title="The team guards this monster: taunts fire sooner for it, heals go to it first">🛡 Protect:</span>
                <button className={'tacticopt small' + (!orders.protectId ? ' on' : '')} onClick={() => setOrders({ ...orders, protectId: undefined })}>Nobody</button>
                {ordered.map((c) => (
                  <button key={c.id} className={'tacticopt small' + (orders.protectId === c.id ? ' on' : '')} onClick={() => setOrders({ ...orders, protectId: c.id })}>{c.name}</button>
                ))}
              </div>
              {/* ⚠️ THE MARK IS GATED ON SCOUTING, AND IT WAS NOT BEFORE. This picker listed
                  every opponent BY NAME, with a 🏹 marking their back row, to a player who
                  had paid nothing — so the scout's whole product was already on screen for
                  free next to the button that sells it. Man-marking is the one order that
                  names a specific monster rather than a KIND, which makes it the natural
                  thing for intel to unlock; leaving it open undercut the feature it should
                  have been advertising. */}
              <div className="protectrow">
                <span className="dim" title="Your whole team hunts the marked monster while it can be reached">🎯 Man mark:</span>
                {!scouted[matchIdx] ? (
                  <span className="dim">Scout this match to see who you are facing — you cannot mark a monster you have not identified.</span>
                ) : (<>
                  <button className={'tacticopt small' + (orders.mark === undefined ? ' on' : '')} onClick={() => setOrders({ ...orders, mark: undefined })}>Nobody</button>
                  {opponentTeam.map((m, i) => (
                    <button key={i} className={'tacticopt small' + (orders.mark === i ? ' on' : '')} onClick={() => setOrders({ ...orders, mark: i })}>
                      {m.name}{rowOfSlot(i, opponentTeam.length) === 'back' ? ' 🏹' : ''}
                    </button>
                  ))}
                </>)}
              </div>
            </div>
          )}
          {ordered.map((c) => {
            const cm = careerMonster(c)
            return (
              <details key={c.id} className="editor-section" open={teamSize === 1}>
                <summary className="editor-summary">🎯 {c.name}'s orders</summary>
                <TacticsControls value={orders.tactics[c.id] ?? DEFAULT_TACTICS} loadout={cm.loadout} teamPlay={teamSize > 1}
                  onChange={(t) => setOrders({ ...orders, tactics: { ...orders.tactics, [c.id]: t } })} />
              </details>
            )
          })}
          <div className="carerow" style={{ justifyContent: 'center', marginTop: 8 }}>
            <button className="ghost" onClick={() => setBattleSub('bracket')}>← Back</button>
            <button className="enter" onClick={commit}>Fight →</button>
          </div>
        </>
      )
    }

    if (battleSub === 'fight' && liveMatch) {
      return (
        <>
          {header}
          <p className="sub">Match {matchIdx + 1} of {nPlayerMatches}: Your Team vs {opponentLabel}</p>
          <ArenaBattle key={matchIdx} teamA={liveMatch.teamA} teamB={liveMatch.teamB} result={liveMatch.result} league={league} playerSide="A" onDone={() => setBattleOver(true)} />
          {battleOver && (
            <div className="carerow" style={{ justifyContent: 'center' }}>
              <button className="enter" onClick={() => {
                const w = liveMatch.result.winner
                setFightOutcomes((o) => [...o, w === 'A' ? 'win' : w === 'B' ? 'loss' : 'draw'])
                setLastFought(liveMatch) // keep it for the between-match / results analysis
                setBattleOver(false); setLiveMatch(null); setMatchTactics(null); setMatchIdx((i) => i + 1)
                // Last fight → finalize and jump STRAIGHT to the results screen
                // (no intermediate "See Results" page). Otherwise on to the next
                // match's hub.
                if (matchIdx + 1 >= nPlayerMatches) { setGame((g) => (ac.kind === 'rite' ? finalizeRite(g).game : ac.kind === 'trial' ? finalizeTrial(g).game : finalizeCup(g))); setBattleSub('announce') }
                else {
                  // Record progress in the save too, so `doneThrough` stays truthful.
                  setGame((g) => (g.activeCup ? { ...g, activeCup: { ...g.activeCup, doneThrough: matchIdx } } : g))
                  setBattleSub('bracket')
                }
              }}>{matchIdx + 1 >= nPlayerMatches ? 'See Results →' : '→ Next Match'}</button>
            </div>
          )}
        </>
      )
    }

    // Fallback (e.g. reloaded mid-event onto an unexpected sub) — restart the hub.
    return (
      <>
        {header}
        <div className="carerow" style={{ justifyContent: 'center' }}>
          <button className="enter" onClick={() => setBattleSub('preamble')}>Continue the {isTrial ? 'Trial' : 'Cup'} →</button>
        </div>
      </>
    )
  }

  // The feeding walkthrough covers ACTIVE monsters only (v0.79 fix): Hall of
  // Fame retirees don't eat, and with unlimited retirees the queue would
  // otherwise grow a pointless click (and food bill) per honouree, every week.
  const feedIdxs = game.stable.map((c, i) => (c.retired ? -1 : i)).filter((i) => i >= 0)
  // Snap a stale index (e.g. the monster at this slot just retired) onto the queue.
  const currentCareer = game.stable[decisionIdx]?.retired || !game.stable[decisionIdx]
    ? game.stable[feedIdxs[0] ?? 0]
    : game.stable[decisionIdx]
  const currentPlan: WeekPlanEntry = weekPlan[currentCareer.id] || { activity: 'rest', food: '' }
  // ⚠️ pendingCupIsThisWeek, NOT just pendingTournament: a cup may be reserved a
  // week early (v0.92) and that reservation week is still a training week.
  const cupThisWeek = pendingCupIsThisWeek(game)
  const competingThisWeek =
    (cupThisWeek && !!game.pendingTournament?.monsterIds.includes(currentCareer.id)) ||
    !!game.pendingTrial?.monsterIds.includes(currentCareer.id) ||
    !!game.pendingRite?.monsterIds.includes(currentCareer.id)
  const nextFeedIdx = feedIdxs.find((i) => i > decisionIdx)
  const prevFeedIdx = [...feedIdxs].reverse().find((i) => i < decisionIdx)
  const advanceFeeding = () => {
    if (nextFeedIdx !== undefined) setDecisionIdx(nextFeedIdx)
    else {
      setPhase('stable')
      setSelectedMonsterId(game.stable.find((c) => !c.retired)?.id ?? game.stable[0].id)
    }
  }

  // --- Feeding: sequential per-monster, food only (each monster has its own
  // tastes, so a single bulk-feed button can't work) — happens BEFORE the
  // stable screen every week.
  if (phase === 'feeding') {
    const st = stageInfo(currentCareer.ageWeeks, careerSpanYears(currentCareer))
    return (
      <>
        {game.pendingEvent && (
          <EventModal pe={game.pendingEvent} gold={game.gold}
            onChoose={(i) => setGame((g) => resolveEvent(g, i))} />
        )}
        <div className="ranchtop">
          <button className="ghost" onClick={() => setGame((g) => goto(g, 'town'))}>← 🏛 Town</button>
          <span>📅 {dateLabel(game.week)}</span>
          <span>🪙 {game.gold}g</span>
          <span>Feeding {feedIdxs.indexOf(decisionIdx) + 1}/{feedIdxs.length}</span>
          {prevFeedIdx !== undefined && <button className="ghost" onClick={() => setDecisionIdx(prevFeedIdx)}>← Previous</button>}
        </div>
        <p className="sub">Feed {currentCareer.name} for the week.</p>

        {isInjured(currentCareer) && (
          <TipBanner game={game} setGame={setGame} id="injury">
            {currentCareer.name} is hurt — only a week's <b>Rest</b> or the Town <b>Infirmary</b> heals HP,
            and injured monsters fight badly.
          </TipBanner>
        )}
        {decisionIdx === 0 && (game.lastWeek?.length ?? 0) > 0 && (
          <div className="card lastweek">
            <div className="section-title">Last week</div>
            {game.lastWeek.map((l, i) => (
              <DigestLine key={i} text={l} className={l.startsWith('🏟') || l.startsWith('🏁') ? 'lw-hl' : 'dim'} />
            ))}
          </div>
        )}

        <div className="career">
          {/* Compact feeding card: just what the feeding decision needs —
              condition, identity, preferences. Full stats/loadout live on the
              stable screen. */}
          <div className="card">
            <div className="careerbar">
              <span>{currentCareer.species.name} · {classForStats(currentCareer.stats)}</span>
              <span>{st.stage} · age {st.ageYears}y / career {+careerSpanYears(currentCareer).toFixed(1)}y · {LEAGUES[currentCareer.licenseIndex].name}</span>
            </div>
            <div className="feedhead">
              <Sprite species={currentCareer.species} size={72} stage={st.stage} />
              <div>
                <div className="name">{currentCareer.name}</div>
                <div className="meta">Food preferences: <b className="up">♥ {foodName(currentCareer.favouriteFood)}</b> · <b className="down">✖ {foodName(currentCareer.hatedFood)}</b></div>
              </div>
            </div>
            <ConditionMeters hp={currentCareer.hp} mp={currentCareer.mp} stamina={currentCareer.stamina} happiness={currentCareer.happiness} stats={currentCareer.stats} />
          </div>

          <div className="card actions">
            {currentCareer.retired ? (
              <div className="retired">🏁 {currentCareer.name} has retired and can no longer compete.</div>
            ) : (
              <>
                <div className="section-title">Food — buy 1 this week</div>
                <div className={'foodgroups' + (currentPlan.food || currentPlan.forage ? '' : ' foods-missing')}>
                  {([['normal', 'Rations'], ['training', 'Training foods'], ['premium', 'Premium']] as [FoodTier, string][]).map(([tier, label]) => {
                    const discounted = tier === 'normal' ? game.pantryContract : game.grandLarder
                    return (
                      <div className="foodgroup" key={tier}>
                        <div className="foodgroup-h">{label}{discounted ? ' · 🛒 −20%' : ''}</div>
                        <div className="foods">
                          {FOODS.filter((f) => f.tier === tier).map((f) => {
                            const price = Math.max(1, Math.round(game.foodMarket[f.id] * foodDiscountFor(game, f.id)))
                            const afford = game.gold >= price
                            const selected = currentPlan.food === f.id
                            const eff = foodEffectLabel(f, currentCareer)
                            return (
                              <button key={f.id} className={`food ${f.tier}${selected ? ' selected' : ''}`} disabled={!afford}
                                onClick={() => setPlanFor(currentCareer.id, { ...currentPlan, food: selected ? '' : f.id, forage: false })}
                                title={f.desc}>
                                <span className="food-top">{f.icon} {f.name}{selected ? ' ✓' : ''}</span>
                                <span className={'food-eff ' + eff.cls}>{eff.primary}</span>
                                {eff.cost && <span className="food-cost">{eff.cost}</span>}
                                <span className="food-price">{price}g</span>
                              </button>
                            )
                          })}
                        </div>
                      </div>
                    )
                  })}
                </div>
                {/* Forage fallback (user spec): only when nearly broke (< 10g) —
                    a free "feed" that costs stamina + happiness so a skint player is
                    never soft-locked out of advancing. */}
                {game.gold < 10 && (
                  <button className={'forage-option' + (currentPlan.forage ? ' selected' : '')}
                    onClick={() => setPlanFor(currentCareer.id, { ...currentPlan, food: '', forage: !currentPlan.forage })}>
                    <span className="forage-top">🌿 Forage for the week{currentPlan.forage ? ' ✓' : ''}</span>
                    <span className="forage-sub">no gold — but −{FORAGE_STAMINA_COST} stamina · −{FORAGE_HAPPINESS_COST} happiness</span>
                  </button>
                )}
                {/* Training now sits WITH the food (v0.92). One monster, one
                    screen, one decision: the drill previews read the selected
                    food through previewWeekEffects, so a training food visibly
                    moves the numbers on the drill you are choosing. */}
                <div className="section-title" style={{ marginTop: '1rem' }}>Training — pick this week's work</div>
                {competingThisWeek ? (
                  <div className="retired">
                    🏟 {currentCareer.name} competes this week — the event takes the whole week, so there's no training.
                    Feed it well and send it in.
                  </div>
                ) : (
                  <TrainingPicker
                    career={currentCareer}
                    plan={currentPlan}
                    gear={game.trainingGear}
                    extremeUnlocked={game.extremeUnlocked}
                    diverseUnlocked={game.diverseUnlocked}
                    onPick={(activity) => setPlanFor(currentCareer.id, { ...currentPlan, activity })}
                  />
                )}
                <PlanBenefit career={currentCareer} plan={currentPlan} gear={game.trainingGear} />
              </>
            )}
            <div className="carerow" style={{ marginTop: '1rem' }}>
              <button
                className="enter"
                disabled={!currentCareer.retired && !currentPlan.food && !currentPlan.forage}
                title={!currentCareer.retired && !currentPlan.food && !currentPlan.forage ? 'Pick a food (or forage) for this monster first' : undefined}
                onClick={advanceFeeding}
              >
                {nextFeedIdx !== undefined ? 'Next Monster →' : 'Continue to Stable →'}
              </button>
            </div>
          </div>
        </div>
      </>
    )
  }

  // --- Stable screen (§1c): free-navigation stable strip + detail panel +
  // training row condensed by stat, with a persistent right-hand action rail.
  const selectedCareer = game.stable.find((c) => c.id === selectedMonsterId) ?? game.stable[0]
  const selM = careerMonster(selectedCareer)
  const selProf = trainingProfileFor(selectedCareer.species)
  const selPlan: WeekPlanEntry = weekPlan[selectedCareer.id] || { activity: 'rest', food: '' }

  const activityName = (p?: WeekPlanEntry) => {
    if (!p) return null
    if (p.activity === 'rest') return '😴 Resting'
    if (p.activity === 'excursion') return '🧭 Excursion'
    const d = ALL_DRILLS.find((x) => x.id === p.activity)
    return d ? `💪 ${d.name}` : null
  }

  const currentMonth = monthOfWeek(game.week)
  const currentWeek = weekOfMonth(game.week)
  const isCurrentMonth = calendarMonth === currentMonth
  const tournamentsThisMonth = tournamentCalendarFor(game.seed, yearOfWeek(game.week)).filter((t) => t.month === calendarMonth)
  const visibleLeagues = LEAGUES.slice(0, visibleLeagueCount(game))
  const visibleTournamentsThisMonth = tournamentsThisMonth.filter((t) => visibleLeagues.some((lg) => lg.name === t.league))
  const selectedTournament = visibleTournamentsThisMonth.find((t) => t.id === selectedTournamentId) ?? null
  const trialGate = trialStatus(game) // on-demand rank-up trial (v0.5)

  const doAdvanceWeek = () => {
    // advanceWeek consumes game.weekPlans and carries each ACTIVITY into the
    // new week itself (food resets — it's bought fresh weekly).
    const next = advanceWeek(game)
    setGame(next)
    setCalendarMonth(monthOfWeek(next.week))
    setDecisionIdx(0)
    setBattleOver(false)
    setMatchIdx(0)
    setBattleSub('preamble')
    setScouted({})
    setFightOutcomes([])
    setLiveMatch(null)
    setLastFought(null)
    setMatchTactics(null)
    setSelectedMonsterId(next.stable.find((c) => !c.retired)?.id ?? next.stable[0]?.id ?? '')
    setPhase(next.activeCup ? 'battle' : 'feeding')
  }

  // Signed-up event name for the status strip.
  const pendingEventName = game.pendingTournament
    ? tournamentCalendarFor(game.seed, yearOfWeek(game.week)).find((t) => t.id === game.pendingTournament!.tournamentId)?.name
    : null

  return (
    <>
      {/* Persistent status strip: gold + date were previously invisible on the
          stable screen, where every economic decision actually happens. */}
      <div className="ranchtop">
        <button className="ghost" onClick={() => setGame((g) => goto(g, 'town'))}>← 🏛 Town</button>
        <span>📅 {dateLabel(game.week)}</span>
        <span>🪙 {game.gold}g</span>
        {pendingEventName && <span className="up">✅ {pendingEventName}</span>}
      </div>
      <div className="feedok">✓ this week is planned — check the calendar, or advance the week</div>
      {trialGate.ok && !game.pendingTrial && (
        <TipBanner game={game} setGame={setGame} id="rankup">
          🎖 A monster can now attempt the {LEAGUES[game.licenseIndex].name} rank-up trial — train two or
          three stats first, as champions punish one-trick builds.
        </TipBanner>
      )}
      {/* Freeze-window warning: the single most punishing rule in the game — a
          retired monster can never be bred or fused. Fires once, at the first
          Elder (final career year) with freezer room available. */}
      {(() => {
        const elder = game.stable.find((c) => !c.retired && stageInfo(c.ageWeeks, careerSpanYears(c)).stage === 'Elder')
        const room = (game.labFrozen ?? []).length < (game.labSlots ?? LAB_SLOTS_BASE)
        return elder && room && (
          <TipBanner game={game} setGame={setGame} id="freezewindow">
            ⏳ {elder.name} is in its final career year — freeze it at the 🧪 Lab <b>before it retires</b>
            if you ever want to breed or fuse it.
          </TipBanner>
        )
      })()}
      {/* Gen-1 ceiling: the wild-monster wall is invisible until you hit it. */}
      {(() => {
        const walled = game.stable.find((c) => {
          if (c.retired || (c.generation ?? 1) > 1 || isFusionBody(c.species.body) || isPrestigeBody(c.species.body)) return false
          // Fire against the gen-1 wild wall itself (wildCap, 800 by default) —
          // at Platinum the league cap EQUALS the wall, and that is exactly
          // where it blocks the Masters trial, so "wall < league cap" was the
          // wrong test.
          const wall = c.wildCap ?? WILD_GEN1_CAP
          return Math.max(...STATS.map((k) => c.stats[k])) >= wall - 60
        })
        return walled && (
          <TipBanner game={game} setGame={setGame} id="gen1cap">
            🧱 {walled.name} is nearing the wild training ceiling ({statCapFor(walled)}) — bred, fused, and
            Market Coach–raised monsters climb higher.
          </TipBanner>
        )
      })()}

      <div className="stablescreen">
        <div className="stablemain">
          {/* Stable strip */}
          <div className="stablestrip">
            {game.stable.map((c) => {
              const label = activityName(weekPlan[c.id])
              return (
                <div key={c.id} className={'stablecard' + (c.id === selectedCareer.id ? ' selected' : '') + (c.retired ? ' retired' : '')}
                  onClick={() => { setSelectedMonsterId(c.id); setAbilityEditorFor(null); setShowHistoryFor(null); setRenamingId(null) }}>
                  <Sprite species={c.species} size={40} stage={stageInfo(c.ageWeeks, careerSpanYears(c)).stage} />
                  <span className="bn">{c.name}</span>
                  <div className="dim" style={{ fontSize: 10.5 }}>{c.species.name}</div>
                  {c.retired ? <span className="stablechip warn">🏁 retired</span>
                    : label ? <span className="stablechip ok">{label}</span>
                      : <span className="stablechip warn">😴 rest (no plan set)</span>}
                  {!c.retired && isInjured(c) && <span className="stablechip hurt">🩹 injured</span>}
                  {!c.retired && canRankUp(c) && <span className="stablechip star">⭐ trial ready</span>}
                </div>
              )
            })}
          </div>

          {/* Detail panel */}
          <div className="detailgrid">
            <div className="card detail-portrait">
              <Sprite species={selectedCareer.species} size={96} stage={stageInfo(selectedCareer.ageWeeks, careerSpanYears(selectedCareer)).stage} />
              <div className="detail-namerow">
                {renamingId === selectedCareer.id ? (
                  <input autoFocus defaultValue={selectedCareer.name} className="detail-nameinput" maxLength={24}
                    onBlur={(e) => { setGame((g) => renameMonster(g, selectedCareer.id, e.target.value)); setRenamingId(null) }}
                    onKeyDown={(e) => { if (e.key === 'Enter') (e.target as HTMLInputElement).blur() }} />
                ) : (
                  <>
                    <span className="bn">{selectedCareer.name}</span>
                    <button className="ghost iconbtn" title="rename" onClick={() => setRenamingId(selectedCareer.id)}>✎</button>
                  </>
                )}
              </div>
              <div className="dim" style={{ fontSize: 11 }}>{selectedCareer.species.name} · {selM.className}
                {(selectedCareer.potential ?? 1) > 1 && (
                  <span className="potential" title={`Bloodline potential ×${(selectedCareer.potential ?? 1).toFixed(2)} — trains ${Math.round(((selectedCareer.potential ?? 1) - 1) * 100)}% above the normal league ceiling`}> · {'★'.repeat(Math.round(((selectedCareer.potential ?? 1) - 1) / BREEDING_BONUS))} ×{(selectedCareer.potential ?? 1).toFixed(2)}</span>
                )}
              </div>
              {(() => {
                const st = stageInfo(selectedCareer.ageWeeks, careerSpanYears(selectedCareer))
                return <div className="dim" style={{ fontSize: 11 }}>{st.stage} · age {st.ageYears}y / career {+careerSpanYears(selectedCareer).toFixed(1)}y · {LEAGUES[selectedCareer.licenseIndex].name} league</div>
              })()}

              <button className="detail-actionbtn" disabled={game.pendingTournament?.monsterIds.includes(selectedCareer.id) ?? false}
                onClick={() => setAbilityEditorFor(abilityEditorFor === selectedCareer.id ? null : selectedCareer.id)}>
                ⚔ Edit Abilities{game.pendingTournament?.monsterIds.includes(selectedCareer.id) ? ' (locked — competing)' : ''}
              </button>
              <button className="detail-actionbtn" onClick={() => setShowHistoryFor(showHistoryFor === selectedCareer.id ? null : selectedCareer.id)}>
                🏆 Tournament History
              </button>
              {(game.tonics ?? 0) > 0 && (
                <button className="detail-actionbtn" onClick={() => setGame((g) => useTonic(g, selectedCareer.id))}>
                  🧪 Use Elder Tonic — +2 months career span ({game.tonics} left)
                </button>
              )}
              {(selectedCareer.generation ?? 1) > 1 && (
                <div className="dim" style={{ fontSize: 11 }}>
                  🧬 Gen {selectedCareer.generation} {'★'.repeat(Math.max(0, Math.round(((selectedCareer.potential ?? 1) - 1) / 0.05)))} · potential ×{(selectedCareer.potential ?? 1).toFixed(2)}
                  {selectedCareer.heritageStat ? ` · heritage ${selectedCareer.heritageStat} (+10% training)` : ''}
                </div>
              )}
              {/* Signature skill (v0.91): earned at an annual marquee, inherited
                  dormant. Shows the lineage explicitly — whose it was and which
                  event forged it — since that provenance IS the reward, and the
                  awaken bar so an heir's owner knows exactly what to train. */}
              {selectedCareer.signature && (
                <div className="dim" style={{ fontSize: 11 }}>
                  {selectedCareer.signature.awakened ? '★' : '☆'} Signature:{' '}
                  <b style={{ color: STAT_COLOR[selectedCareer.signature.stat] }}>{signatureName(selectedCareer.signature)}</b>
                  {selectedCareer.signature.inherited > 0
                    ? <> · inherited from {selectedCareer.signature.forgedBy} ({selectedCareer.signature.eventName})</>
                    : <> · forged at {selectedCareer.signature.eventName}</>}
                  {selectedCareer.signature.awakened
                    ? <> · <span className="pos">awakened</span></>
                    : <> · <span className="neg">dormant</span> — train {selectedCareer.signature.stat} to {selectedCareer.signature.awakenStat} (now {selectedCareer.stats[selectedCareer.signature.stat]})</>}
                </div>
              )}
              {/* Fusion training aptitude (v0.7): inherited per-monster, so it's not
                  visible from the species — show it explicitly here. */}
              {selectedCareer.bonusMajor1 && (
                <div className="dim" style={{ fontSize: 11 }}>
                  ⚗️ Fusion aptitude:{' '}
                  <b style={{ color: STAT_COLOR[selectedCareer.bonusMajor1] }}>+20% {selectedCareer.bonusMajor1}</b>
                  {selectedCareer.bonusMajor2 && <> · <b style={{ color: STAT_COLOR[selectedCareer.bonusMajor2] }}>+20% {selectedCareer.bonusMajor2}</b></>}
                  {selectedCareer.bonusMinor && <> · <span style={{ color: STAT_COLOR[selectedCareer.bonusMinor] }}>+10% {selectedCareer.bonusMinor}</span></>}
                  {selectedCareer.bonusFlaw && <> · <span className="neg">−10% {selectedCareer.bonusFlaw}</span></>}
                </div>
              )}
              {selectedCareer.retired && (
                <div className="dim" style={{ fontSize: 11 }}>🏛 Retired to the Hall of Fame — its career is over and its line is closed.</div>
              )}
              {showHistoryFor === selectedCareer.id && (
                <div className="tour-history">
                  <div className="tour-history-podiums">
                    🏆 {selectedCareer.tournamentHistory.filter((h) => h.placement <= 3).length} podium finishes
                  </div>
                  {selectedCareer.tournamentHistory.length === 0
                    ? <div className="dim">No tournaments entered yet.</div>
                    : selectedCareer.tournamentHistory.slice().reverse().map((h, i) => (
                      <div className="tour-history-row" key={i}>
                        <span>{h.name} <span className="dim">· {h.league}</span></span>
                        <span className={h.placement <= 3 ? 'pos' : 'dim'}>{placementLabel(h.placement)} of {h.fieldSize}</span>
                      </div>
                    ))}
                </div>
              )}

              <ConditionMeters hp={selectedCareer.hp} mp={selectedCareer.mp} stamina={selectedCareer.stamina} happiness={selectedCareer.happiness} stats={selectedCareer.stats} />
            </div>

            <div className="card detail-stats">
              {STATS.map((s) => {
                // Same ▲/▴/▼ aptitude vocabulary as the Market/Bestiary marks —
                // the stat is already the row label, so the tag is just the
                // arrow + magnitude, tinted to the stat.
                const tag = selProf.major === s ? '▲ +20%' : selProf.minor === s ? '▴ +10%' : selProf.flaw === s ? '▼ −20%' : ''
                return (
                  <div className="detailstat" key={s}>
                    {/* Aptitude tag sits right beside its stat's name — parked
                        at the row's far end it read as a detached floater. */}
                    <span style={{ color: STAT_COLOR[s], fontWeight: 700 }}>{s}</span>
                    <span className="detailstat-tag" style={{ color: STAT_COLOR[s] }}>{tag}</span>
                    <span className="bar"><i style={{ width: `${Math.min(100, (selectedCareer.stats[s] / LEAGUES[selectedCareer.licenseIndex].cap) * 100)}%`, background: STAT_COLOR[s] }} /></span>
                    <span className="v">{selectedCareer.stats[s]}</span>
                  </div>
                )
              })}
              {/* Battle kit at a glance — previously invisible on this screen
                  without opening the ability editor, leaving this card mostly
                  empty space below the six stat rows. */}
              <div className="detail-kit">
                <div className="detail-kit-h">Battle kit</div>
                {selM.loadout.map((mv) => (
                  <div className="detail-kit-move" key={mv.id}>
                    <span className="lvl">{mv.stat}</span>
                    <span>{mv.name}</span>
                    <span className="dim">{manaCost(mv)} MP · cd {mv.cooldown}</span>
                  </div>
                ))}
                {selM.loadout.length === 0 && <div className="dim">No moves learned yet — train a stat past 40.</div>}
                <div className="detail-kit-innate">
                  <span className="lvl">✦</span>
                  <span>{selM.species.innate[selM.activeInnate]?.name}</span>
                  <span className="dim">{selM.species.innate[selM.activeInnate]?.desc}</span>
                </div>
              </div>
              {/* Rank-up trial (v0.5): on-demand, PLAYER-level — beat the current
                  league's Champion to unlock the next license in the Ranch Shop.
                  The fight consumes the entered monsters' week, like a cup. */}
              {(() => {
                const league = LEAGUES[game.licenseIndex]
                const next = LEAGUES[game.licenseIndex + 1]
                if (!next) return null
                if (game.pendingTrial) return (
                  <div className="trial-panel">
                    <b>🎖 Trial set:</b> vs the {league.name} Champion — resolves on Advance Week.
                    <button className="ghost" onClick={() => setGame((g) => cancelTrial(g))}>Cancel</button>
                  </div>
                )
                if (game.licenseEarned > game.licenseIndex) return (
                  <div className="hint" style={{ marginTop: 10 }}>🎫 The {next.name} license is waiting in the Ranch Shop ({nextLicenseCost(game)}g).</div>
                )
                if (!trialGate.ok) return trialGate.reason?.startsWith('train a monster') && !canRankUp(selectedCareer)
                  ? null // quiet until someone is close — the ⭐ strip chips already signal readiness
                  : <div className="hint" style={{ marginTop: 10 }}>🎖 Rank-up trial: {trialGate.reason}</div>
                const size = teamSizeForLeague(league.name)
                const pool = game.stable.filter((c) => !c.retired)
                // Honest readiness signal (playtest fix): the champion fields
                // WELL-ROUNDED monsters at ~cap×1.8×1.25 total — one maxed stat
                // is not enough beyond Wood (sim: 1-stat builds win <10%, 3-stat
                // ~70%). Compare the picked team's totals against that target.
                const champTarget = league.cap * rivalBudgetMult(game.licenseIndex) * trialChampionMult(game.licenseIndex)
                const picked = trialPick.map((id) => pool.find((c) => c.id === id)!).filter(Boolean)
                const teamAvg = picked.length ? picked.reduce((s, c) => s + STATS.reduce((t, k) => t + c.stats[k], 0), 0) / picked.length : 0
                const ratio = teamAvg / champTarget
                return (
                  <div className="trial-panel">
                    <div className="section-title">🎖 Rank-up Trial — the {league.name} Champion</div>
                    <div className="dim">Beat a champion-grade {size}v{size} team to unlock the {next.name} license ({nextLicenseCost(game)}g). The fight takes the week; win or lose, your team comes home needing rest.</div>
                    {picked.length === size && (
                      <div className={ratio >= 0.85 ? 'up' : ratio >= 0.6 ? 'dim' : 'neg'} style={{ fontSize: 12 }}>
                        {ratio >= 0.85 ? `⚔ Your team (~${Math.round(teamAvg)} avg total) stands toe-to-toe with the Champion — a real shot.`
                          : ratio >= 0.6 ? `⚠ Your team (~${Math.round(teamAvg)} avg total) is the underdog vs ~${Math.round(champTarget)} — train a second stat before challenging.`
                            : `🛑 Your team (~${Math.round(teamAvg)} avg total) is severely outmatched vs ~${Math.round(champTarget)} — this will almost certainly fail.`}
                      </div>
                    )}
                    <div className="carerow" style={{ flexWrap: 'wrap', marginTop: 6 }}>
                      {pool.map((c) => (
                        <button key={c.id} className={'tacticopt small' + (trialPick.includes(c.id) ? ' on' : '')}
                          onClick={() => setTrialPick((p) => p.includes(c.id) ? p.filter((x) => x !== c.id) : p.length < size ? [...p, c.id] : p)}>
                          {c.name}
                        </button>
                      ))}
                    </div>
                    <button className="enter" style={{ marginTop: 6 }} disabled={trialPick.length !== size || !!game.pendingTournament}
                      title={game.pendingTournament ? 'Cancel your cup sign-up first — one arena event per week' : undefined}
                      onClick={() => { setGame((g) => startTrial(g, trialPick)); setTrialPick([]) }}>
                      ⚔ Challenge ({trialPick.length}/{size} picked)
                    </button>
                  </div>
                )
              })()}
              {/* Rite prize unclaimed (v0.91). Winning banks the reward rather than
                  forging it, because the PLAYER chooses which monster steps forward
                  and which of its body's moves it takes. Shown until claimed, so it
                  cannot be missed by clicking past the results screen. */}
              {game.riteReward && (() => {
                const winners = game.stable.filter((c) => game.riteReward!.monsterIds.includes(c.id) && !c.retired && !c.signature)
                if (!winners.length) return null
                const pick = winners.find((c) => c.id === sigPick) ?? winners[0]
                const choices = signatureChoicesFor(pick.species.body)
                return (
                  <div className="trial-panel" style={{ borderColor: 'var(--cha)' }}>
                    <div className="section-title">★ Signature Rite won — claim the prize</div>
                    <div className="dim">Choose which monster steps forward, then the move it takes. Whatever it currently has in that move&apos;s stat becomes the bar its heirs must reach to awaken an inherited copy — so a signature taken late is a harder legacy to live up to.</div>
                    <div className="carerow" style={{ flexWrap: 'wrap', marginTop: 6 }}>
                      {winners.map((c) => (
                        <button key={c.id} className={'tacticopt small' + (c.id === pick.id ? ' on' : '')} onClick={() => setSigPick(c.id)}>
                          {c.name} <span className="dim">· {c.species.body}</span>
                        </button>
                      ))}
                    </div>
                    <div className="dim" style={{ fontSize: 11, marginTop: 6 }}>{pick.name} may take one of {choices.length}:</div>
                    <div className="carerow" style={{ flexWrap: 'wrap', marginTop: 4 }}>
                      {choices.map((mv) => (
                        <button key={mv.id} className="tacticopt small" title={mv.desc}
                          onClick={() => { setGame((g) => claimSignature(g, pick.id, mv.id)); setSigPick(null) }}>
                          <b style={{ color: STAT_COLOR[mv.stat] }}>{mv.name}</b>
                          <span className="dim"> · {mv.stat} {mv.power > 0 ? mv.power : '—'} · {mv.target}</span>
                        </button>
                      ))}
                    </div>
                    <div className="dim" style={{ fontSize: 11, marginTop: 4 }}>
                      Awaken bar by stat: {[...new Set(choices.map((m) => m.stat))].map((st) => `${st} ${pick.stats[st]}`).join(' · ')}
                    </div>
                  </div>
                )
              })()}
              {/* The Signature Rite (v0.91): the ONLY source of a signature skill.
                  On-demand like the rank-up trial, but fought by the WHOLE active
                  roster, allowed ONCE A YEAR win or lose, and built harder than a
                  rank-up champion at every rung. Gated on TRAINER level, not on
                  the monster, so it stays invisible for a first season. */}
              {(() => {
                if (game.pendingRite) return (
                  <div className="trial-panel">
                    <b>★ Rite set:</b> your whole stable ({game.pendingRite.monsterIds.length}) faces the Rite Challengers — resolves on Advance Week.
                    <button className="ghost" onClick={() => setGame((g) => cancelRite(g))}>Cancel</button>
                  </div>
                )
                if (trainerLevel(game) < SIGNATURE_RITE_LEVEL) return null // stay quiet in the early game
                const gate = riteStatus(game)
                if (!gate.ok) return <div className="hint" style={{ marginTop: 10 }}>★ Signature Rite: {gate.reason}</div>
                const roster = riteRoster(game)
                const size = roster.length
                // ⚠️ The challenger side is CAPPED at the league's team size — see
                // stageRite. Labelling this NvN off the roster alone advertised a
                // 3v3 at Wood when the real fight is 3v1; a browser pass caught it.
                const foeSize = Math.min(size, teamSizeForLeague(LEAGUES[game.licenseIndex].name))
                const foeTarget = LEAGUES[game.licenseIndex].cap * rivalBudgetMult(game.licenseIndex) * riteChampionMult(game.licenseIndex)
                const teamAvg = roster.reduce((s2, c) => s2 + STATS.reduce((t, k) => t + c.stats[k], 0), 0) / size
                const ratio = teamAvg / foeTarget
                const heir = riteEligible(game).reduce((best, c) =>
                  STATS.reduce((t, k) => t + c.stats[k], 0) > STATS.reduce((t, k) => t + best.stats[k], 0) ? c : best)
                const heirTop = [...STATS].sort((x, y) => heir.stats[y] - heir.stats[x])[0]
                return (
                  <div className="trial-panel">
                    <div className="section-title">★ The Signature Rite — {size}v{foeSize}</div>
                    <div className="dim">
                      Your <b>whole active stable</b> ({size}) fights <b>{foeSize}</b> challenger{foeSize === 1 ? '' : 's'}, each built harder than a rank-up champion{size > foeSize ? ' — you outnumber them, which is what a deep stable buys you' : ''}. Win and one monster forges a <b>signature skill</b> — its own move, which its children inherit dormant and awaken by matching its stat. <b>Once a year, win or lose</b>; the fight takes everyone&apos;s week and all of them come home needing rest.
                    </div>
                    <div className="dim" style={{ fontSize: 12 }}>
                      On a win the signature goes to <b>{heir.name}</b> (highest total without one) — themed on <b style={{ color: STAT_COLOR[heirTop] }}>{heirTop}</b>.
                    </div>
                    <div className={ratio >= 0.85 ? 'up' : ratio >= 0.6 ? 'dim' : 'neg'} style={{ fontSize: 12 }}>
                      {ratio >= 0.85 ? `⚔ Your stable (~${Math.round(teamAvg)} avg total) stands with the challengers (~${Math.round(foeTarget)}) — a real shot.`
                        : ratio >= 0.6 ? `⚠ Your stable (~${Math.round(teamAvg)} avg total) is the underdog vs ~${Math.round(foeTarget)} — this is meant to be harder than a rank-up trial.`
                          : `🛑 Your stable (~${Math.round(teamAvg)} avg total) is severely outmatched vs ~${Math.round(foeTarget)} — a wasted year.`}
                    </div>
                    <button className="enter" style={{ marginTop: 6 }} disabled={!!game.pendingTournament || !!game.pendingTrial}
                      title={game.pendingTournament || game.pendingTrial ? 'One arena event per week — cancel the other first' : undefined}
                      onClick={() => setGame((g) => startRite(g))}>
                      ★ Attempt the Rite ({size} monster{size === 1 ? '' : 's'})
                    </button>
                  </div>
                )
              })()}
            </div>
          </div>

          {/* Ability editor OR training row */}
          {abilityEditorFor === selectedCareer.id ? (
            <div ref={abilityRef}>
            <AbilitySelector
              m={selM}
              name={selectedCareer.name}
              onSetLoadout={(ids) => setGame((g) => setLoadout(g, selectedCareer.id, ids))}
              onSetInnate={(index) => setGame((g) => setActiveInnate(g, selectedCareer.id, index))}
              onClose={() => setAbilityEditorFor(null)}
            />
            </div>
          ) : selectedCareer.retired ? (
            <div className="retired">🏁 {selectedCareer.name} has retired and can no longer train.</div>
          ) : (game.pendingTournament?.monsterIds.includes(selectedCareer.id) || game.pendingTrial?.monsterIds.includes(selectedCareer.id)) ? (
            <div className="retired">🏟 {selectedCareer.name} is competing this week — the event takes the whole week, no training. (Cancel the {game.pendingTrial ? 'trial' : 'sign-up'} to free the week.)</div>
          ) : (
            <div className="card plannedweek">
              <div className="section-title">This week's plan</div>
              <div className="plannedweek-row">
                <span className="plannedweek-act">{activityName(selPlan) ?? '😴 Resting'}</span>
                <span className="dim">
                  {selPlan.food ? `· ${foodName(selPlan.food)}` : selPlan.forage ? '· 🌿 Foraging' : '· no food chosen yet'}
                </span>
              </div>
              <div className="dim" style={{ marginTop: 6 }}>
                Food and training are chosen together in the weekly walkthrough — press <b>Advance Week</b>, or{' '}
                <button className="linkish" onClick={() => { setDecisionIdx(feedIdxs[0] ?? 0); setPhase('feeding') }}>open it now</button>.
              </div>
            </div>
          )}

          {/* Tournament calendar — always visible on the stable screen (v0.84) */}
          {(
            <div className="card loc" style={{ marginTop: 12 }}>
              <div className="loc-h">
                <span>📅 Tournament Calendar</span>
                <div style={{ display: 'flex', gap: '0.5rem' }}>
                  <button className="ghost" onClick={() => setCalendarMonth((mo) => mo === 1 ? 12 : mo - 1)}>◀</button>
                  <span>Month {calendarMonth}{isCurrentMonth ? ` · Week ${currentWeek} now` : ''}</span>
                  <button className="ghost" onClick={() => setCalendarMonth((mo) => mo === 12 ? 1 : mo + 1)}>▶</button>
                </div>
              </div>
              <div className="hint">
                Tournaments this month: {visibleTournamentsThisMonth.length}. Click a 🏆 for entry details.
              </div>

              {/* True calendar grid: one row per VISIBLE league (leagues unlock
                  with progress), one column per week — always drawn in full,
                  empty cells included (user spec 2026-07-19). */}
              <div className="calgrid">
                {visibleLeagues.map((lg, li) => {
                  const t = visibleTournamentsThisMonth.find((x) => x.league === lg.name)
                  const signedHere = t && game.pendingTournament?.tournamentId === t.id
                  const alreadyEntered = t && (game.enteredThisMonth ?? []).includes(t.id)
                  const isPastWeek = t && isCurrentMonth && currentWeek > t.week
                  const icon = signedHere ? '✅' : alreadyEntered ? '✔' : isPastWeek ? '➖' : '🏆'
                  const isOpenNow = t && isCurrentMonth && currentWeek === t.week && !alreadyEntered && !signedHere
                  void li // (trial ⭐ markers removed — trials are on-demand since v0.5)
                  return (
                    <div className="calgrid-row" key={lg.name}>
                      <div className="calgrid-label">
                        {lg.name} <span className="dim">{teamSizeForLeague(lg.name)}v{teamSizeForLeague(lg.name)}</span>
                      </div>
                      {[1, 2, 3, 4].map((w) => (
                        <div key={w} className={'calgrid-cell' + (isCurrentMonth && w === currentWeek ? ' now' : '')}>
                          {t && w === t.week && (
                            <button
                              className={'calicon' + (isOpenNow ? ' open' : '') + (selectedTournamentId === t.id ? ' selected' : '')}
                              onClick={() => setSelectedTournamentId(t.id)}
                              title={`${t.name} — Week ${t.week}`}
                            >
                              {icon}
                            </button>
                          )}
                        </div>
                      ))}
                    </div>
                  )
                })}
                <div className="calgrid-row calgrid-footer">
                  <div className="calgrid-label" />
                  {[1, 2, 3, 4].map((w) => (
                    <div key={w} className={'calgrid-wk' + (isCurrentMonth && w === currentWeek ? ' now' : '')}>Wk {w}</div>
                  ))}
                </div>
              </div>
              <div className="hint">🏆 open · ✅ signed up · ✔ competed · ➖ missed · ⭐ rank-up trials</div>

              {selectedTournament ? (() => {
                const t = selectedTournament
                const teamSize = teamSizeForLeague(t.league)
                const eligible = eligibleForTournament(game, t)
                const tIdx = leagueIndexOf(t.league)
                const signedHere = game.pendingTournament?.tournamentId === t.id
                const signedMonsters = signedHere ? game.stable.filter((c) => game.pendingTournament!.monsterIds.includes(c.id)) : []
                const alreadyEntered = (game.enteredThisMonth ?? []).includes(t.id)
                // Sign-ups open the week BEFORE the event as well as on it
                // (v0.92) — the roster has to be known before the feed-and-train
                // walkthrough opens, or entering would discard the plan just set.
                const isOpenWeek = isSignUpOpen(game, t)
                const isEarlyWeek = isOpenWeek && !(isCurrentMonth && currentWeek === t.week)
                const rawPickIds = (teamPick[t.id] ?? []).filter((id) => eligible.some((c) => c.id === id))
                // For 1v1 the select DEFAULTS to the first eligible monster — the
                // effective pick must include that default so the warnings below
                // render before the player ever touches the dropdown.
                const pickIds = teamSize === 1 && rawPickIds.length === 0 && eligible[0] ? [eligible[0].id] : rawPickIds
                const pickedCareers = pickIds.map((id) => eligible.find((c) => c.id === id)!).filter(Boolean)
                const teamFull = pickedCareers.length === teamSize
                const mult = teamFull ? rewardMultiplier(game.licenseIndex, t.league) : 1
                // Underpowered warning (v0.5): with per-player licensing a fresh
                // recruit can legally enter any league you hold — flag a team that
                // sits below the league's rival band rather than silently feeding it in.
                const leagueFloor = LEAGUES[tIdx].cap * rivalBudgetMult(tIdx) * RIVAL_BAND_MIN
                const underpowered = pickedCareers.filter((c) => STATS.reduce((s, k) => s + c.stats[k], 0) < leagueFloor * 0.8)
                const fatigued = pickedCareers.filter((c) => staminaDamageMult(c.stamina) < 1)
                const injured = pickedCareers.filter(isInjured)
                const condition = (c: Career) => {
                  const parts: string[] = []
                  if (c.hp < maxHp(c.stats)) parts.push(`${c.hp}/${maxHp(c.stats)} HP`)
                  if (maxMana(c.stats) > 0 && c.mp < maxMana(c.stats)) parts.push(`${c.mp}/${maxMana(c.stats)} MP`)
                  return parts.length ? ` · ${isInjured(c) ? '🩹 ' : ''}${parts.join(', ')}` : ''
                }
                return (
                  <div className="tour-entry" ref={entryRef}>
                    <div className="tour-entry-head">
                      <div><b>{t.name}</b> — {t.league} league · Week {t.week} · {teamSize === 1 ? '1v1' : `${teamSize}v${teamSize}`}</div>
                      <button className="ghost" onClick={() => setSelectedTournamentId(null)}>✕</button>
                    </div>
                    <div className="dim">
                      Free to enter · Rewards: {t.rewards.gold}g + training exp,
                      scaled by final placement (round-robin vs the rest of the field)
                    </div>
                    {isOpenWeek && !alreadyEntered && (
                      <TipBanner game={game} setGame={setGame} id="signup">
                        Your team fights every rival once, round robin — scout the field below, then pick
                        monsters and loadouts to match.
                      </TipBanner>
                    )}
                    {isOpenWeek && !alreadyEntered && (() => {
                      // Rival teams are week-seeded, so this preview IS the real
                      // field — read from the memo (this panel only renders for
                      // the selected tournament, which is what the memo holds).
                      const rivalTeams = scoutRivalTeams ?? generateRivalTeamsForTournament(game, t)
                      return (
                        <details className="scout-field">
                          <summary>🔍 Scout the field — {rivalTeams.length} rival teams</summary>
                          {rivalTeams.map((team, r) => {
                            const key = `${t.id}:${r}`
                            const tier = fieldScout[key]
                            const basicFee = scoutFee(t.league, 'basic')
                            const fullFee = scoutFee(t.league, 'full')
                            // Seated rival (v0.5): the named rival occupies this slot —
                            // their team runs THEIR personality's gameplan.
                            const seat = seatedRivalTeamIndex(game, t)
                            const isRivalTeam = seat === r
                            const gp = GAMEPLANS[isRivalTeam ? RIVAL_PERSONALITY_GAMEPLAN[game.rivals[0].personality] : gameplanForRivalTeam(game.seed, game.week, t.id, r)]
                            return (
                              <div key={key} className="scout-report">
                                <div className="section-title">
                                  {isRivalTeam ? <>🥊 {game.rivals[0].name}'s Team <span className="dim">· your rival{game.rivals[0].wins + game.rivals[0].losses > 0 ? ` · record ${game.rivals[0].wins}–${game.rivals[0].losses}` : ''}</span></> : `Rival Team ${r + 1}`}
                                </div>
                                {/* Gameplan reveal (LOOP_DESIGN Phase 3): the tactical intel scouting
                                    is FOR — revealed with the basic tier alongside class + loadout. */}
                                {tier ? (
                                  <div className="gameplan">
                                    <div className="gp-h">{gp.icon} {gp.name} <span className="dim">· {gp.tell}</span></div>
                                    {/* The WIN CONDITION (v0.91): the team is now BUILT to this plan —
                                        composition and loadouts both — so telling the player what it is
                                        trying to do is honest information they can actually play against. */}
                                    <div className="dim" style={{ fontSize: 11 }}>🏁 Their plan: {gp.winCon}</div>
                                    <div className="gp-counter">💡 {gp.counter}</div>
                                  </div>
                                ) : (
                                  <div className="gameplan locked"><div className="gp-h dim">🧠 Gameplan: ?? — scout to reveal</div></div>
                                )}
                                {team.map((m, i) => <ScoutReport key={i} m={m} tier={tier} />)}
                                {/* Mark orders moved to the pre-fight tactics screen (v0.81). */}
                                <div className="carerow">
                                  {!tier && (
                                    <button className="ghost" disabled={game.gold < basicFee}
                                      onClick={() => { setGame((g) => ({ ...g, gold: g.gold - basicFee })); setFieldScout((s) => ({ ...s, [key]: 'basic' })) }}>
                                      🔍 Class &amp; loadout — {basicFee}g
                                    </button>
                                  )}
                                  {tier !== 'full' && (
                                    <button className="ghost" disabled={game.gold < fullFee}
                                      onClick={() => { setGame((g) => ({ ...g, gold: g.gold - fullFee })); setFieldScout((s) => ({ ...s, [key]: 'full' })) }}>
                                      🔍 Full report — {fullFee}g
                                    </button>
                                  )}
                                </div>
                              </div>
                            )
                          })}
                        </details>
                      )
                    })()}
                    {signedHere ? (
                      <div>
                        ✅ {signedMonsters.map((c) => c.name).join(', ') || '?'} {signedMonsters.length === 1 ? 'is' : 'are'}{' '}
                        {isEarlyWeek ? <><b>entered for Week {t.week}</b> — still free to train until then</> : <>competing this week</>}{' '}
                        <button className="ghost" onClick={() => setGame((g) => cancelSignUp(g))}>Cancel</button>
                        {signedMonsters.length > 1 && <div className="dim" style={{ marginTop: 4 }}>🎯 Formation, protect &amp; target orders are set before each fight.</div>}
                      </div>
                    ) : alreadyEntered ? (
                      <div className="dim">✔ Already competed this month.</div>
                    ) : !isOpenWeek ? (
                      <div className="dim">
                        {isCurrentMonth && currentWeek > t.week ? `Week ${t.week} has passed for this event.`
                          : `Sign-ups open a week before the event — from Month ${t.month}, Week ${t.week - 1 || 4}.`}
                      </div>
                    ) : eligible.length < teamSize ? (
                      <div className="dim">
                        Requires {teamSize} eligible monster{teamSize > 1 ? 's' : ''} — only {eligible.length} available.
                        {teamSize > 1 && ` (Guests one league below ${t.league} may join, but at least one member must hold the ${t.league} license.)`}
                      </div>
                    ) : game.pendingTournament ? (
                      <div className="dim">Already entered a tournament this week.</div>
                    ) : teamSize === 1 ? (
                      <>
                        <div className="carerow" style={{ marginTop: 6, alignItems: 'center' }}>
                          <select value={pickIds[0]} onChange={(ev) => setTeamPick((sp) => ({ ...sp, [t.id]: [ev.target.value] }))}>
                            {eligible.map((c) => <option key={c.id} value={c.id}>{c.name} ({LEAGUES[c.licenseIndex].name}){condition(c)}</option>)}
                          </select>
                          <button className="signup" disabled={!!game.pendingTrial}
                            title={game.pendingTrial ? 'Cancel your rank-up trial first — one arena event per week' : undefined}
                            onClick={() => setGame((g) => signUp(g, t.id, pickIds))}>
                            {game.pendingTrial ? 'Trial already set this week' : 'Sign Up →'}
                          </button>
                        </div>
                        <div className="dim" style={{ fontSize: 12 }}>🏟 Competing takes the monster's week — it won't train.</div>
                        {underpowered.length > 0 && (
                          <div className="neg" style={{ fontSize: 12 }}>⚠ {underpowered.map((c) => c.name).join(', ')} sits well below the {t.league} standard — expect a rough field.</div>
                        )}
                        {mult < 1 && pickedCareers[0] && (
                          <div className="dim">⚠ you hold a license above {t.league} — punching down pays only {Math.round(mult * 100)}%.</div>
                        )}
                        {fatigued[0] && (
                          <div className="neg" style={{ fontSize: 12 }}>
                            💤 {fatigued[0].name} is fatigued ({fatigued[0].stamina}/100 stamina) — will fight at
                            −{Math.round((1 - staminaDamageMult(fatigued[0].stamina)) * 100)}% damage.
                          </div>
                        )}
                        {injured[0] && (
                          <div className="neg" style={{ fontSize: 12 }}>
                            🩹 {injured[0].name} is injured ({injured[0].hp}/{maxHp(injured[0].stats)} HP, {injured[0].mp}/{maxMana(injured[0].stats)} MP)
                            — it will ENTER the fight like this. Rest first unless you mean it.
                          </div>
                        )}
                      </>
                    ) : (
                      <>
                        <TeamPicker pool={eligible} teamSize={teamSize} monsterIds={pickIds} onChange={(ids) => setTeamPick((sp) => ({ ...sp, [t.id]: ids }))} />
                        <div className="carerow" style={{ marginTop: 8 }}>
                          <button className="signup" disabled={!teamFull || !!game.pendingTrial}
                            title={game.pendingTrial ? 'Cancel your rank-up trial first — one arena event per week' : undefined}
                            onClick={() => setGame((g) => signUp(g, t.id, pickIds))}>
                            {!teamFull ? `Pick ${teamSize - pickedCareers.length} more` : game.pendingTrial ? 'Trial already set this week' : 'Sign Up →'}
                          </button>
                        </div>
                        <div className="dim" style={{ fontSize: 12 }}>🏟 Competing takes each entered monster's week — they won't train.</div>
                        {underpowered.length > 0 && (
                          <div className="neg" style={{ fontSize: 12 }}>
                            ⚠ {underpowered.map((c) => c.name).join(', ')} {underpowered.length === 1 ? 'is' : 'are'} well below the {t.league} standard — expect a rough field.
                          </div>
                        )}
                        {mult < 1 && (
                          <div className="dim">⚠ you hold a license above {t.league} — punching down pays only {Math.round(mult * 100)}% of the rewards.</div>
                        )}
                        {fatigued.length > 0 && (
                          <div className="neg" style={{ fontSize: 12 }}>
                            💤 {fatigued.map((c) => c.name).join(', ')} {fatigued.length === 1 ? 'is' : 'are'} fatigued — will fight at reduced damage.
                          </div>
                        )}
                        {injured.length > 0 && (
                          <div className="neg" style={{ fontSize: 12 }}>
                            🩹 {injured.map((c) => `${c.name} (${c.hp}/${maxHp(c.stats)} HP)`).join(', ')} — injured monsters ENTER the fight like this. Rest first unless you mean it.
                          </div>
                        )}
                      </>
                    )}
                  </div>
                )
              })() : visibleTournamentsThisMonth.length > 0 && (
                <div className="dim tour-entry-hint">Click a tournament above to view entry details.</div>
              )}
            </div>
          )}
        </div>

        {/* Action rail */}
        <div className="rail">
          {(() => {
            // Every active monster needs a food chosen before the week can
            // advance (user spec 2026-07-22: "monsters always require food").
            const active = game.stable.filter((c) => !c.retired)
            const unfed = active.filter((c) => !weekPlan[c.id]?.food && !weekPlan[c.id]?.forage)
            const trainN = active.filter((c) => weekPlan[c.id] && weekPlan[c.id].activity !== 'rest' && weekPlan[c.id].activity !== 'excursion').length
            const excN = active.filter((c) => weekPlan[c.id]?.activity === 'excursion').length
            const restN = active.length - trainN - excN
            return (
              <>
                <button
                  className="railbtn primary"
                  disabled={unfed.length > 0}
                  title={unfed.length > 0 ? `${unfed.length} monster${unfed.length > 1 ? 's need' : ' needs'} food chosen first: ${unfed.map((c) => c.name).join(', ')}` : undefined}
                  onClick={doAdvanceWeek}
                >⏭<br />Advance<br />Week</button>
                <div className="rail-note" title="what Advance Week will resolve">
                  {unfed.length > 0
                    ? <div className="down">🍽 {unfed.length} unfed — pick food first</div>
                    : (
                      <>
                        <div>💪 {trainN} training</div>
                        <div>😴 {restN} resting</div>
                        {excN > 0 && <div>🧭 {excN} exploring</div>}
                      </>
                    )}
                  {pendingEventName && <div className="up">🏟 entered</div>}
                </div>
              </>
            )
          })()}
          <button className="railbtn" onClick={() => setGame((g) => goto(g, 'town'))}>🏛<br />Back to<br />Town</button>
        </div>
      </div>
    </>
  )
}

// --- Persistence: 3 independent save slots, each the whole GameState as plain JSON ---
const SAVE_SLOTS = 3
const LEGACY_SAVE_KEY = 'monster-tamer-save-v2' // pre-slot single save (v2: loadout/tournamentHistory)
const slotKey = (slot: number) => `monster-tamer-save-slot-${slot}`
const randomSeed = () => Math.random().toString(36).slice(2, 8)

function sanitizeAndMigrate(raw: string): GameState | null {
  try {
    const g = JSON.parse(raw)
    // sanity-check the save shape (older/foreign saves start fresh)
    if (typeof g?.week !== 'number' || !Array.isArray(g?.stable) || typeof g?.foodMarket !== 'object') return null
    // migrate pre-injury-system saves: monsters without tracked HP/MP wake at full
    for (const c of g.stable) {
      if (typeof c.hp !== 'number') c.hp = maxHp(c.stats)
      if (typeof c.mp !== 'number') c.mp = maxMana(c.stats)
      // migrate pre-innate-choice saves: both innates used to be always-on
      if (typeof c.activeInnate !== 'number') c.activeInnate = 0
      // Saves serialize the whole Species object, so ability descs/renames go
      // stale the moment species.ts changes — re-link to the live table by id.
      // (A species whose id itself was renamed keeps its stored snapshot.)
      const live = SPECIES.find((s) => s.id === c.species?.id)
      if (live) c.species = live
    }
    if (Array.isArray(g.frozen)) for (const f of g.frozen) {
      const live = SPECIES.find((s) => s.id === f.species?.id)
      if (live) f.species = live
    }
    // migrate pre-team-tournament saves: PendingTournament went from a single
    // `monsterId` to `monsterIds: string[]` — an old save carrying a live
    // sign-up would crash `.monsterIds.includes(...)` / `.map(...)`. Drop the
    // stale entry (sign-ups only ever last until the next weekly tick anyway).
    if (g.pendingTournament && !Array.isArray(g.pendingTournament.monsterIds)) g.pendingTournament = null
    if (g.pendingTournament && typeof g.pendingTournament.feePaid !== 'number') g.pendingTournament.feePaid = 0
    if (typeof g.weekPlans !== 'object' || g.weekPlans === null) g.weekPlans = {}
    if (!Array.isArray(g.lastWeek)) g.lastWeek = []
    // migrate pre-v0.77 saves: monster-market upgrades default to "not bought".
    if (typeof g.marketSlots !== 'number') g.marketSlots = 0
    if (typeof g.marketScout !== 'number') g.marketScout = 0
    if (typeof g.marketCoach !== 'number') g.marketCoach = 0
    if (typeof g.scoutPickA !== 'string') g.scoutPickA = null
    if (typeof g.scoutPickB !== 'string') g.scoutPickB = null
    // v0.77 gen-1 ceiling: back-fill from whatever coach tier the save holds.
    // wildCap is SYNCED stable-wide (coach tier), so always re-derive on load —
    // v0.87 lowered the ladder (800/900/1000 → 700/800/900), and statCapFor now
    // reads the coach tier out of this value for prestige caps too, so a stale
    // pre-v0.87 wildCap would misread as a higher tier.
    for (const c of g.stable) c.wildCap = wildCapFor(g)
    // migrate pre-round-robin tournamentHistory: placement was 'champion'|'none'
    if (Array.isArray(g.stable)) for (const c of g.stable) {
      if (Array.isArray(c.tournamentHistory)) for (const h of c.tournamentHistory) {
        if (typeof h.placement !== 'number') { h.placement = h.placement === 'champion' ? 1 : 2; h.fieldSize = h.fieldSize ?? 2 }
      }
    }
    // migrate pre-title-screen saves: no trainer name/tutorial flag existed
    if (typeof g.trainerName !== 'string' || !g.trainerName) g.trainerName = 'Tamer'
    if (typeof g.tutorialEnabled !== 'boolean') g.tutorialEnabled = false // already playing — skip tips by default
    if (typeof g.tutorialDismissed !== 'boolean') g.tutorialDismissed = true
    if (!Array.isArray(g.tipsSeen)) g.tipsSeen = []
    // migrate pre-food-overhaul saves (2026-07-25): the single `bulkFood` perk
    // (20% off all food) becomes the Pantry Contract (normal foods); the new
    // Grand Larder (premium foods) starts unowned. Career lastFood/truffleReady
    // default absent — no migration needed.
    if (typeof g.pantryContract !== 'boolean') g.pantryContract = !!g.bulkFood
    if (typeof g.grandLarder !== 'boolean') g.grandLarder = false
    delete g.bulkFood
    // migrate pre-events saves (LOOP_DESIGN Phase 1): no pending incident
    if (g.pendingEvent === undefined) g.pendingEvent = null
    // migrate pre-rival saves (LOOP_DESIGN Phase 2): mint a primary rival so
    // returning players get one too
    if (!Array.isArray(g.rivals) || g.rivals.length === 0) g.rivals = [generateRival(g.seed, 0)]
    // migrate pre-trainer-XP saves (LOOP_DESIGN Phase 5); potential stays absent (= 1.0)
    if (typeof g.trainerXp !== 'number') g.trainerXp = 0
    // migrate pre-per-player-license saves (v0.5): the player's license = the
    // highest any monster had earned (stable + frozen — nobody loses progress),
    // and every stable career syncs to it (the one per-player invariant).
    if (typeof g.licenseIndex !== 'number') {
      g.licenseIndex = Math.max(0,
        ...(Array.isArray(g.stable) ? g.stable.map((c: { licenseIndex?: number }) => c.licenseIndex ?? 0) : [0]),
        ...(Array.isArray(g.frozen) ? g.frozen.map((f: { licenseIndex?: number }) => f.licenseIndex ?? 0) : [0]))
    }
    if (typeof g.licenseEarned !== 'number') g.licenseEarned = g.licenseIndex
    if (g.pendingTrial === undefined) g.pendingTrial = null
    if (typeof g.trialCooldownUntil !== 'number') g.trialCooldownUntil = 0
    // v0.81: per-fight tactics — no event in flight for a pre-v0.81 save
    if (g.activeCup === undefined) g.activeCup = null
    // Resume: a save reloaded mid-event routes straight to the ranch, where the
    // battle flow picks up the staged cup (RanchView inits phase to 'battle').
    if (g.activeCup) g.area = 'ranch'
    // v0.6 economy-pass fields
    if (!Array.isArray(g.comfortOwned)) g.comfortOwned = []
    if (typeof g.trainingGear !== 'object' || !g.trainingGear) g.trainingGear = {}
    if (typeof g.tonics !== 'number') g.tonics = 0
    if (typeof g.studBooks !== 'number') g.studBooks = 0
    // v0.77: the stud farm is gone — the Lab freezer is the single preservation
    // store. Fold any banked studs into it (keeping breedCount/studBook) and give
    // the Lab enough slots to hold them, so no save loses a bloodline.
    if (Array.isArray(g.frozen) && g.frozen.length) {
      const migrated = g.frozen.map((f: Frozen) => ({
        ...careerFromFrozen(f, f.id), retired: true, breedCount: f.breedCount ?? 0, studBook: !!f.studBook,
      }))
      g.labFrozen = [...(Array.isArray(g.labFrozen) ? g.labFrozen : []), ...migrated]
      g.labSlots = Math.max(g.labSlots ?? 2, g.labFrozen.length)
      g.frozen = []
    }
    if (typeof g.labTechLoan !== 'boolean') g.labTechLoan = false
    if (typeof g.extremeUnlocked !== 'boolean') g.extremeUnlocked = false
    if (typeof g.diverseUnlocked !== 'boolean') g.diverseUnlocked = false
    if (typeof g.battleAnalyst !== 'boolean') g.battleAnalyst = false
    // v0.91 Signature Rite — absent on every pre-v0.91 save
    if (g.pendingRite === undefined) g.pendingRite = null
    if (g.riteReward === undefined) g.riteReward = null
    if (typeof g.riteCooldownUntil !== 'number') g.riteCooldownUntil = 0
    // v0.7 Lab freezer (separate from the stud farm)
    if (!Array.isArray(g.labFrozen)) g.labFrozen = []
    if (typeof g.labSlots !== 'number') g.labSlots = LAB_SLOTS_BASE
    for (const c of g.stable) if (c.licenseIndex !== g.licenseIndex) c.licenseIndex = g.licenseIndex
    return g as GameState
  } catch {
    return null
  }
}

function loadSlot(slot: number): GameState | null {
  const raw = localStorage.getItem(slotKey(slot))
  return raw ? sanitizeAndMigrate(raw) : null
}

function saveSlot(slot: number, game: GameState) {
  try { localStorage.setItem(slotKey(slot), JSON.stringify(game)) } catch { /* storage full/unavailable — play on */ }
}

// One-time migration: a save from before multi-slot support moves into slot 1
// so a returning player doesn't lose progress when this feature ships.
function migrateLegacySave() {
  try {
    if (localStorage.getItem(slotKey(1))) return
    const raw = localStorage.getItem(LEGACY_SAVE_KEY)
    if (!raw) return
    const g = sanitizeAndMigrate(raw)
    if (g) localStorage.setItem(slotKey(1), JSON.stringify(g))
  } catch { /* ignore */ }
}

function slotSummary(g: GameState) {
  const highestLeagueIdx = Math.max(0, ...g.stable.map((c) => c.licenseIndex), ...(g.labFrozen ?? []).map((f) => f.licenseIndex))
  return {
    trainerName: g.trainerName || 'Tamer',
    date: dateLabel(g.week),
    gold: g.gold,
    monsterCount: g.stable.length,
    league: LEAGUES[highestLeagueIdx]?.name ?? LEAGUES[0].name,
  }
}

// ============================ Title screen & save flow ============================
function TitleScreen({ onNewGame, onContinue }: { onNewGame: () => void; onContinue: () => void }) {
  return (
    <div className="titlescreen">
      <AreaBackdrop scene="title" />
      <div className="titlecard">
        <h1 className="titlelogo">Monster Tamer</h1>
        <p className="titletag">Raise it. Train it. Enter the circuit.</p>
        <div className="titlebtns">
          <button className="titlebtn primary" onClick={onNewGame}>
            <span>✨ New Game</span>
            <span className="btnsub">Start a fresh adventure in an open save slot</span>
          </button>
          <button className="titlebtn" onClick={onContinue}>
            <span>▶ Continue</span>
            <span className="btnsub">Resume from a saved game</span>
          </button>
        </div>
        <p className="titlever">v{APP_VERSION} · early alpha</p>
      </div>
    </div>
  )
}

// Small in-app modal — the native confirm()/prompt()/alert() dialogs looked
// jarring against the styled UI (and block the whole renderer while open).
function Modal({ title, children, actions }: { title: string; children: ReactNode; actions: ReactNode }) {
  return (
    <div className="modal-backdrop">
      <div className="modal-card">
        <div className="modal-title">{title}</div>
        <div className="modal-body">{children}</div>
        <div className="modal-actions">{actions}</div>
      </div>
    </div>
  )
}

// Weekly incident (LOOP_DESIGN Phase 1): a choice with a trade-off, shown over
// the feeding screen. Choices with a gold cost above the wallet disable.
function EventModal({ pe, gold, onChoose }: { pe: PendingEvent; gold: number; onChoose: (i: number) => void }) {
  return (
    <div className="modal-backdrop">
      <div className="modal-card">
        <div className="modal-title">{pe.title}</div>
        <div className="modal-body"><p className="ev-body">{pe.body}</p></div>
        <div className="modal-actions ev-actions">
          {pe.choices.map((ch, i) => {
            const cant = ch.cost != null && ch.cost > gold
            return (
              <button key={i} className="ev-choice" disabled={cant} onClick={() => onChoose(i)}
                title={cant ? 'Not enough gold' : undefined}>
                <span className="ev-label">
                  <span>{ch.label}</span>
                  {ch.cost != null && ch.cost > 0 && <span className={'ev-price' + (cant ? ' cant' : '')}>🪙 {ch.cost}g</span>}
                </span>
                {ch.note && <span className="ev-note">{ch.note}</span>}
              </button>
            )
          })}
        </div>
      </div>
    </div>
  )
}

function SlotPicker({ mode, onBack, onPickEmpty, onPickOccupied }: {
  mode: 'new' | 'continue'
  onBack: () => void
  onPickEmpty: (slot: number) => void
  onPickOccupied: (slot: number) => void
}) {
  // Slot management (2026-07-25): delete (confirmed), export (downloads the
  // raw save JSON — cheap insurance while alpha migrations still bite), and
  // import (a .json backup file into an empty slot). `refresh` re-reads
  // localStorage after any of them.
  const [refresh, setRefresh] = useState(0)
  const [confirmDeleteSlot, setConfirmDeleteSlot] = useState<number | null>(null)
  const [confirmOverwriteSlot, setConfirmOverwriteSlot] = useState<number | null>(null)
  const [importError, setImportError] = useState(false)
  const importTarget = useRef<number | null>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)
  const slots = useMemo(() => Array.from({ length: SAVE_SLOTS }, (_, i) => i + 1).map((slot) => ({ slot, game: loadSlot(slot) })),
    [refresh]) // eslint-disable-line react-hooks/exhaustive-deps
  const deleteSlot = (slot: number) => {
    localStorage.removeItem(slotKey(slot))
    setRefresh((r) => r + 1)
  }
  const exportSlot = (slot: number) => {
    const raw = localStorage.getItem(slotKey(slot))
    if (!raw) return
    const a = document.createElement('a')
    a.href = URL.createObjectURL(new Blob([raw], { type: 'application/json' }))
    a.download = `monster-tamer-slot-${slot}.json`
    a.click()
    URL.revokeObjectURL(a.href)
  }
  const onImportFile = async (file: File | undefined) => {
    const slot = importTarget.current
    importTarget.current = null
    if (!file || slot == null) return
    const g = sanitizeAndMigrate(await file.text())
    if (!g) { setImportError(true); return }
    localStorage.setItem(slotKey(slot), JSON.stringify(g))
    setRefresh((r) => r + 1)
  }
  return (
    <div className="titlescreen">
      <div className="titlecard slotcard">
        <h2>{mode === 'new' ? 'New Game — choose a slot' : 'Continue — choose a slot'}</h2>
        <div className="slotlist">
          {slots.map(({ slot, game }) => {
            const empty = !game
            const summary = game ? slotSummary(game) : null
            const disabled = mode === 'continue' && empty
            return (
              <div key={slot} className={'slotrow' + (empty ? ' empty' : '')}>
                <button
                  className="slotmain"
                  disabled={disabled}
                  onClick={() => (empty ? onPickEmpty(slot)
                    : mode === 'new' ? setConfirmOverwriteSlot(slot)
                      : onPickOccupied(slot))}
                >
                  <span className="slotnum">Slot {slot}</span>
                  {empty
                    ? <span className="slotmeta dim">— empty —{mode === 'new' ? ' (start here)' : ''}</span>
                    : (
                      <span className="slotmeta">
                        <b>{summary!.trainerName}</b> · {summary!.league} league · {summary!.date} · 🪙{summary!.gold}g · {summary!.monsterCount} monster{summary!.monsterCount === 1 ? '' : 's'}
                        {mode === 'new' && <span className="slotoverwrite"> · overwrite?</span>}
                      </span>
                    )}
                </button>
                <div className="slotactions">
                  {!empty && <button className="slotaction" title="Download this save as a JSON backup file" onClick={() => exportSlot(slot)}>⬇ Export</button>}
                  {!empty && <button className="slotaction danger" title="Delete this save" onClick={() => setConfirmDeleteSlot(slot)}>🗑 Delete</button>}
                  {empty && <button className="slotaction" title="Load a previously exported .json save backup into this slot" onClick={() => { importTarget.current = slot; fileInputRef.current?.click() }}>⬆ Import</button>}
                </div>
              </div>
            )
          })}
        </div>
        <button className="titlebtn back" onClick={onBack}>← Back</button>
        <input
          ref={fileInputRef} type="file" accept=".json,application/json" style={{ display: 'none' }}
          onChange={(e) => { void onImportFile(e.target.files?.[0]); e.target.value = '' }}
        />
        {confirmDeleteSlot != null && (
          <Modal
            title={`Delete the save in Slot ${confirmDeleteSlot}?`}
            actions={
              <>
                <button className="ghost" onClick={() => setConfirmDeleteSlot(null)}>Keep it</button>
                <button className="modal-danger" onClick={() => { deleteSlot(confirmDeleteSlot); setConfirmDeleteSlot(null) }}>🗑 Delete forever</button>
              </>
            }
          >
            This cannot be undone. Export a backup first if you might want it back.
          </Modal>
        )}
        {confirmOverwriteSlot != null && (
          <Modal
            title={`Overwrite Slot ${confirmOverwriteSlot}?`}
            actions={
              <>
                <button className="ghost" onClick={() => setConfirmOverwriteSlot(null)}>Keep it</button>
                <button className="modal-danger" onClick={() => { const s = confirmOverwriteSlot; setConfirmOverwriteSlot(null); onPickOccupied(s) }}>Overwrite it</button>
              </>
            }
          >
            Starting a new game here replaces the existing save. Export a backup first if you might want it back.
          </Modal>
        )}
        {importError && (
          <Modal
            title="Import failed"
            actions={<button className="ghost" onClick={() => setImportError(false)}>OK</button>}
          >
            That file doesn't look like a valid Monster Tamer save backup.
          </Modal>
        )}
      </div>
    </div>
  )
}

function NewGameSetup({ onBack, onStart }: { onBack: () => void; onStart: (trainerName: string, tutorialEnabled: boolean) => void }) {
  const [name, setName] = useState('')
  const [tutorial, setTutorial] = useState(true)
  const trimmed = name.trim()
  return (
    <div className="titlescreen">
      <div className="titlecard">
        <h2>Name your Tamer</h2>
        <input
          className="nameinput"
          value={name}
          maxLength={20}
          placeholder="Trainer name"
          onChange={(e) => setName(e.target.value)}
          autoFocus
        />
        <label className="tutorialtoggle">
          <input type="checkbox" checked={tutorial} onChange={(e) => setTutorial(e.target.checked)} />
          Show tutorial tips
        </label>
        <div className="titlebtns">
          <button className="titlebtn back" onClick={onBack}>← Back</button>
          <button className="titlebtn primary" disabled={!trimmed} onClick={() => onStart(trimmed, tutorial)}>Start Adventure →</button>
        </div>
      </div>
    </div>
  )
}

function AlphaDisclaimer({ onContinue }: { onContinue: () => void }) {
  return (
    <div className="titlescreen">
      <div className="titlecard disclaimer">
        <h2>🚧 Early Alpha</h2>
        <p>
          Monster Tamer is very early in development. Expect rough edges, balance swings, and
          missing pieces as the game keeps growing.
        </p>
        <p>
          The full loop is playable — raise monsters, win cups, and climb the leagues. Freeze your
          champions at the <b>Lab</b> before they retire, then breed dynasties or fuse brand-new species.
        </p>
        <button className="titlebtn primary" onClick={onContinue}>Got it, let's go!</button>
      </div>
    </div>
  )
}

// Contextual one-shot tutorial tips (2026-07-25 playtest addition): shown at
// the moment a system first matters (sign-up, first injury, rank-up week),
// only while tutorialEnabled, each dismissible exactly once (GameState.tipsSeen).
function TipBanner({ game, setGame, id, children }: {
  game: GameState; setGame: Dispatch<SetStateAction<GameState>>; id: string; children: ReactNode
}) {
  if (!game.tutorialEnabled || (game.tipsSeen ?? []).includes(id)) return null
  return (
    <div className="tipbanner">
      <span>💡 {children}</span>
      <button className="tutorial-dismiss" onClick={() => setGame((g) => ({ ...g, tipsSeen: [...(g.tipsSeen ?? []), id] }))}>✕</button>
    </div>
  )
}

// Guided-tutorial message box (v0.86) — Grandpa talking the player through the
// first-run beats. A dismissible overlay; the caller decides what "continue" does.
function GrandpaModal({ title, body, onClose }: { title?: string; body: string; onClose: () => void }) {
  return (
    <div className="tut-overlay" role="dialog" aria-modal="true">
      <div className="tut-box">
        <div className="tut-grandpa">👴</div>
        {title && <div className="tut-title">{title}</div>}
        <p className="tut-body">{body}</p>
        <button className="tut-continue" onClick={onClose}>Continue →</button>
      </div>
    </div>
  )
}

function TutorialBanner({ onDismiss }: { onDismiss: () => void }) {
  return (
    <div className="tutorial-banner">
      <div>
        <b>👋 How Monster Tamer works</b>
        <ul>
          <li><b>Every week:</b> feed each monster, pick its activity (train, rest, or excursion), then Advance Week.</li>
          <li><b>Earn gold in cups.</b> Enter tournaments at your league from Grandpa's Ranch. To move up a league, win the rank-up trial, then buy the license in the Ranch Shop.</li>
          <li><b>Plan your dynasty.</b> Freeze a monster at the 🧪 Lab <b>before its career ends</b> to breed or fuse it later. Once it retires to the Hall of Fame, the bloodline is closed.</li>
          <li><b>Raise the ceiling.</b> Wild monsters train to 700 at most — prestige monsters go higher, the Market Coach raises every ceiling in your stable, and bred or fused bloodlines climb highest of all.</li>
        </ul>
      </div>
      <button className="tutorial-dismiss" onClick={onDismiss}>✕</button>
    </div>
  )
}

type Screen = 'title' | 'slots' | 'setup' | 'disclaimer' | 'playing'

const THEME_KEY = 'mt-theme'
type Theme = 'dark' | 'light'
// Read the saved theme once, before first paint, so there's no flash of the
// wrong palette on reload. Dark is the default (the app's established look).
function initialTheme(): Theme {
  try { return localStorage.getItem(THEME_KEY) === 'light' ? 'light' : 'dark' } catch { return 'dark' }
}
// Persistent day/night switch — fixed top-right, mounted once so it rides above
// every screen. Writes data-theme on <html>, which flips the CSS token palette.
function ThemeToggle() {
  const [theme, setTheme] = useState<Theme>(initialTheme)
  useEffect(() => {
    document.documentElement.dataset.theme = theme
    try { localStorage.setItem(THEME_KEY, theme) } catch { /* private mode — non-fatal */ }
  }, [theme])
  const next = theme === 'dark' ? 'light' : 'dark'
  return (
    <button
      className="theme-toggle"
      onClick={() => setTheme(next)}
      title={`Switch to ${next} mode`}
      aria-label={`Switch to ${next} mode`}
    >
      <span>{theme === 'dark' ? '☀️' : '🌙'}</span>
      <span className="tt-label">{theme === 'dark' ? 'Day' : 'Night'}</span>
    </button>
  )
}

export function App() {
  const [screen, setScreen] = useState<Screen>('title')
  const [slotMode, setSlotMode] = useState<'new' | 'continue'>('continue')
  const [pendingSlot, setPendingSlot] = useState<number | null>(null)
  const [activeSlot, setActiveSlot] = useState<number | null>(null)
  const [view, setView] = useState<'game' | 'sandbox'>('game')
  const [game, setGame] = useState<GameState | null>(null)
  const [battleScreen, setBattleScreen] = useState(false) // hide the Bestiary footer mid-battle

  useEffect(() => { migrateLegacySave() }, [])

  useEffect(() => {
    if (activeSlot != null && game) saveSlot(activeSlot, game)
  }, [game, activeSlot])

  const enterSlot = (slot: number) => {
    const g = loadSlot(slot)
    if (!g) return
    setActiveSlot(slot)
    setGame(g)
    setView('game')
    setScreen('playing')
  }

  const startNewGame = (trainerName: string, tutorialEnabled: boolean) => {
    if (pendingSlot == null) return
    const g = newGame(randomSeed(), { trainerName, tutorialEnabled })
    saveSlot(pendingSlot, g)
    setActiveSlot(pendingSlot)
    setGame(g)
    setView('game')
    setScreen('disclaimer')
  }

  const titleScreen = (
    <TitleScreen
      onNewGame={() => { setSlotMode('new'); setScreen('slots') }}
      onContinue={() => { setSlotMode('continue'); setScreen('slots') }}
    />
  )

  // Each screen renders inside this wrapper so the theme toggle is mounted once
  // and rides above every screen (title, slots, setup, disclaimer, playing).
  const withChrome = (content: JSX.Element) => (<><ThemeToggle />{content}</>)

  if (screen === 'title') return withChrome(titleScreen)

  if (screen === 'slots') {
    return withChrome(
      <SlotPicker
        mode={slotMode}
        onBack={() => setScreen('title')}
        onPickEmpty={(slot) => { setPendingSlot(slot); setScreen('setup') }}
        onPickOccupied={(slot) => {
          // Overwrite confirmation lives inside SlotPicker as a styled modal —
          // by the time this fires in 'new' mode, the player already confirmed.
          if (slotMode === 'continue') enterSlot(slot)
          else { setPendingSlot(slot); setScreen('setup') }
        }}
      />,
    )
  }

  if (screen === 'setup') return withChrome(<NewGameSetup onBack={() => setScreen('slots')} onStart={startNewGame} />)
  if (screen === 'disclaimer') return withChrome(<AlphaDisclaimer onContinue={() => setScreen('playing')} />)
  if (!game) return withChrome(titleScreen) // structurally unreachable — 'playing' only sets once game is loaded

  return withChrome(
    <div className="app">
      <h1>Monster Tamer <span className="tag">/ prototype</span> <span className="version">v{APP_VERSION}</span></h1>
      <div className="tabs">
        <button className={'tab' + (view === 'game' ? ' on' : '')} onClick={() => setView('game')}>🎮 Game</button>
        <button className={'tab' + (view === 'sandbox' ? ' on' : '')} onClick={() => setView('sandbox')}>⚔️ Sandbox</button>
        <button className="tab" onClick={() => setScreen('title')}>🏠 Main Menu</button>
      </div>
      {view === 'game'
        ? (game.area === 'town'
          ? <TownView game={game} setGame={setGame as Dispatch<SetStateAction<GameState>>} />
          : <>
            {/* The arena paints its own league backdrop, so stand down during a battle. */}
            {!battleScreen && <AreaBackdrop scene="stables" />}
            <RanchView game={game} setGame={setGame as Dispatch<SetStateAction<GameState>>} onBattleScreen={setBattleScreen} />
          </>)
        : <SandboxView />}
      {!(view === 'game' && battleScreen) && (
        <Bestiary specialLicense={game.specialLicense} eliteLicense={game.eliteLicense} />
      )}
    </div>,
  )
}
