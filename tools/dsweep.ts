import { generateMonster } from '../src/monster'
import { simulateFieldBattle } from '../src/tamerengine/engine'
import { autoDeployByRole } from '../src/tamerengine/hex'
import { classForStats } from '../src/core'
const mk=(id:string,sp:string)=>generateMonster(id,{speciesId:sp,train:850}) as any
const OBST=[{x:19,y:6,w:2.2,h:2.2},{x:21,y:15,w:2.2,h:2.2},{x:13,y:11,w:2,h:2},{x:27,y:11,w:2,h:2}]
// Class-DIVERSE 3v3s: the old sweep was 5 mammals = Warrior/Tank/Rogue only, so
// every INT/WIS/CHA change was invisible to it.
const SETS=[
 {A:['kongrath','maelurk','larkessa'],   B:['aegisox','strixil','pinguox']},    // War/Wiz/Bard vs Tank/Sage/Ranger
 {A:['archmage-aleph','koalio','grivvel'],B:['frostwyren','nautilux','maneleo']},// Wiz/Orator/Rogue vs Wiz/Sshield/War
 {A:['strixil','quokkade','mantaris'],   B:['abyssomancer','tortavos','ursath']},// Sage/Bard/Ranger vs Wiz/Sshield/War
 {A:['lanterix','bruxaroo','carcharun'], B:['lurkerss','vespera','geckari']},   // Ssword/Capt/Sage vs Wiz/Orator/Rogue
]
let resolved=0,dur=0,kills=0,dmg=0,n=0
const byClass=new Map<string,{dmg:number,casts:number}>()
const id2class=new Map<string,string>()
for(const set of SETS) for(const sd of ['s1','s2','s3']){
  const A=set.A.map((s,i)=>mk(sd+'a'+i,s)),B=set.B.map((s,i)=>mk(sd+'b'+i,s))
  const front=(m:any)=>({front:m.stats.CON+m.stats.STR-m.stats.INT-m.stats.WIS})
  const pa=autoDeployByRole('A',A.map(front)),pb=autoDeployByRole('B',B.map(front))
  const r=simulateFieldBattle({seed:sd,teamA:A,teamB:B,obstacles:OBST as any,placeA:pa,placeB:pb})
  A.forEach((m,i)=>id2class.set('A'+i,classForStats(m.stats)))
  B.forEach((m,i)=>id2class.set('B'+i,classForStats(m.stats)))
  n++; dur+=r.duration; if(r.duration<55) resolved++
  for(const e of r.events as any[]){
    if(e.kind==='death') kills++
    if(e.kind==='hit'){ dmg+=e.dmg
      const c=id2class.get(e.id)??'?'; const s=byClass.get(c)??{dmg:0,casts:0}; s.dmg+=e.dmg; byClass.set(c,s) }
    if(e.kind==='cast'){ const c=id2class.get(e.id)??'?'; const s=byClass.get(c)??{dmg:0,casts:0}; s.casts++; byClass.set(c,s) }
  }
}
console.log(`CLASS-DIVERSE SWEEP (${n} fights, 12 classes represented)`)
console.log('resolved',resolved+'/'+n,' avg dur',(dur/n).toFixed(1)+'s',' kills',kills,' dmg/fight',(dmg/n).toFixed(0))
console.log('\ndamage by class (who actually contributes?):')
for(const [c,s] of [...byClass].sort((a,b)=>b[1].dmg-a[1].dmg))
  console.log('  ',c.padEnd(13),'dmg',String(Math.round(s.dmg/n)).padStart(5),' casts',String(Math.round(s.casts/n)).padStart(4))
