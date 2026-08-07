// PER-CLASS DIAGNOSIS — is this class actually able to fight?
//
// ⚠️ WHY THIS EXISTS. Pooled duration is nearly useless for diagnosing WHY a
// fight is slow: four separate levers measured NULL on it while the underlying
// problem sat in plain sight. This asks the question duration cannot — for each
// class: how often does it act, what fraction of its actions are the free
// attack, how much mana is it sitting on, and can it see its target at all?
//
// The pairing that matters: a class with HIGH mana and LOW casts is not
// resource-starved, it is BLOCKED (range, line of sight, or a spend gate). A
// class with LOW mana and HIGH casts is working as intended and simply poor.
//
// Usage: npx tsx tools/classdiag.ts
import { generateMonster, manaCost } from '../src/monster'
import { simulateFieldBattle, hasLineOfSight, fieldLoadout } from '../src/tamerengine/engine'
import { autoDeployByRole } from '../src/tamerengine/hex'
import { classForStats, Move } from '../src/core'
import { CHANNEL_RANGE, FIELD_MANA_COST_MULT } from '../src/tamerengine/types'

const mk = (id: string, sp: string) => generateMonster(id, { speciesId: sp, train: 850 }) as never
const OB = [
  { x: 19, y: 6, w: 2.2, h: 2.2 }, { x: 21, y: 15, w: 2.2, h: 2.2 },
  { x: 13, y: 11, w: 2, h: 2 }, { x: 27, y: 11, w: 2, h: 2 },
]
const COMPS: { name: string; a: string[]; b: string[] }[] = [
  { name: 'balanced', a: ['kongrath', 'maelurk', 'larkessa'], b: ['aegisox', 'strixil', 'pinguox'] },
  { name: 'all-caster', a: ['maelurk', 'strixil', 'archmage-aleph'], b: ['abyssomancer', 'carcharun', 'frostwyren'] },
  { name: 'double-front', a: ['aegisox', 'kongrath', 'maelurk'], b: ['ursath', 'maneleo', 'strixil'] },
  { name: 'mixed-arcane', a: ['lanterix', 'bruxaroo', 'carcharun'], b: ['lurkerss', 'vespera', 'geckari'] },
  { name: 'assassins', a: ['grivvel', 'mantevoke', 'larkessa'], b: ['aegisox', 'nautilux', 'frostwyren'] },
  { name: 'support-heavy', a: ['strixil', 'koalio', 'tortavos'], b: ['quokkade', 'carcharun', 'aegisox'] },
  { name: 'marksmen', a: ['pinguox', 'mantaris', 'maelurk'], b: ['kongrath', 'aegisox', 'strixil'] },
  { name: 'generalists', a: ['corvaan', 'tazzik', 'abyssomancer'], b: ['geckari', 'odonatra', 'sylvaglide'] },
  { name: 'tank-mirror', a: ['aegisox', 'tortavos', 'ursath'], b: ['vipramane', 'nautilux', 'crocmaw'] },
  { name: 'glass', a: ['archmage-aleph', 'grivvel', 'stormlerath'], b: ['lurkerss', 'balaenix', 'stellarion'] },
]
const SEEDS = ['s1', 's2', 's3', 's4', 'q1', 'q2', 'q3', 'q4']
const rangeOf = (mv: Move) => mv.range ?? CHANNEL_RANGE[mv.channel]
const mpCost = (mv: Move) => manaCost(mv) * FIELD_MANA_COST_MULT

interface C {
  units: number; casts: number; basics: number; dmg: number; secs: number
  mpSum: number; mpTicks: number; ticks: number; inRange: number; los: number; afford: number
}
const cls = new Map<string, C>()
const get = (k: string): C => {
  let c = cls.get(k)
  if (!c) {
    c = { units: 0, casts: 0, basics: 0, dmg: 0, secs: 0, mpSum: 0, mpTicks: 0, ticks: 0, inRange: 0, los: 0, afford: 0 }
    cls.set(k, c)
  }
  return c
}

for (const comp of COMPS) for (const sd of SEEDS) {
  const A = comp.a.map((s, i) => mk(`${sd}${comp.name}a${i}`, s))
  const B = comp.b.map((s, i) => mk(`${sd}${comp.name}b${i}`, s))
  const front = (m: never) => {
    const st = (m as never as { stats: Record<string, number> }).stats
    return { front: st.CON + st.STR - st.INT - st.WIS }
  }
  const r = simulateFieldBattle({
    seed: sd + comp.name, teamA: A, teamB: B, obstacles: OB,
    placeA: autoDeployByRole('A', A.map(front)), placeB: autoDeployByRole('B', B.map(front)),
  })
  const info = new Map<string, { cls: string; kit: Move[] }>()
  const reg = (arr: never[], side: string) => arr.forEach((m, i) => {
    info.set(side + i, {
      cls: classForStats((m as never as { stats: never }).stats),
      kit: fieldLoadout(m as never).filter((x) => x.type === 'damage'),
    })
  })
  reg(A, 'A'); reg(B, 'B')
  for (const [, v] of info) { const c = get(v.cls); c.units++; c.secs += r.duration }

  for (const e of r.events as never as {
    kind: string; id: string; move: string; dmg: number
    units?: { id: string; x: number; y: number; hp: number; mp: number; maxMp: number; state: string }[]
  }[]) {
    if (e.kind === 'cast') { const c = get(info.get(e.id)!.cls); c.casts++; if (e.move === 'Attack') c.basics++ }
    if (e.kind === 'hit') get(info.get(e.id)!.cls).dmg += e.dmg
    if (e.kind !== 'snapshot' || !e.units) continue
    const live = e.units.filter((u) => u.state !== 'dead' && u.hp > 0)
    for (const u of live) {
      const v = info.get(u.id)!
      const c = get(v.cls)
      c.mpTicks++; c.mpSum += u.mp / Math.max(1, u.maxMp)
      if (!v.kit.length) continue
      const foes = live.filter((x) => x.id[0] !== u.id[0])
      if (!foes.length) continue
      const near = foes.reduce((b, x) =>
        Math.hypot(x.x - u.x, x.y - u.y) < Math.hypot(b.x - u.x, b.y - u.y) ? x : b, foes[0])
      const best = v.kit.reduce((b, mv) => (mv.power > b.power ? mv : b), v.kit[0])
      c.ticks++
      if (Math.hypot(near.x - u.x, near.y - u.y) <= rangeOf(best)) c.inRange++
      if (best.channel === 'melee' || hasLineOfSight({ x: u.x, y: u.y }, { x: near.x, y: near.y }, OB)) c.los++
      if (u.mp >= Math.min(...v.kit.map(mpCost))) c.afford++
    }
  }
}

const pct = (a: number, b: number) => (b ? (a / b * 100).toFixed(0) : '0') + '%'
console.log(`PER-CLASS DIAGNOSIS — ${COMPS.length * SEEDS.length} fights, train 850\n`)
console.log('class          units  casts/u  BASIC%  dmg/u  dmg/cast   meanMP  inRANGE   LoS  afford')
for (const [k, c] of [...cls].sort((a, b) => b[1].dmg / b[1].units - a[1].dmg / a[1].units)) {
  console.log(
    '  ' + k.padEnd(13)
    + String(c.units).padStart(5)
    + (c.casts / c.units).toFixed(1).padStart(9)
    + pct(c.basics, c.casts).padStart(8)
    + (c.dmg / c.units).toFixed(0).padStart(7)
    + (c.dmg / Math.max(1, c.casts)).toFixed(1).padStart(10)
    + pct(c.mpSum, c.mpTicks).padStart(9)
    + pct(c.inRange, c.ticks).padStart(9)
    + pct(c.los, c.ticks).padStart(6)
    + pct(c.afford, c.ticks).padStart(8))
}
console.log('\ninRANGE / LoS are measured for the class\'s HIGHEST-POWER damage move vs the')
console.log('nearest enemy. High meanMP + low casts/u = blocked, not starved.')
