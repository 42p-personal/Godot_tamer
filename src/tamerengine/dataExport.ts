// THE DATA EXPORT, AS A SHARED BUILDER.
//
// ⚠️ EXTRACTED FROM `tools/exportdata.ts` SO THE COMMITTED JSON CANNOT ROT. `data.json` is what
// the Godot port loads for its 141 moves, 65 species and the status behaviour table. If the
// TypeScript gains a move and the JSON does not, the port runs a smaller pool and NOTHING
// FAILS — the port just quietly disagrees with the game. `port.contract.test.ts` regenerates
// this and diffs it, exactly as it does for the three arithmetic contracts.
//
// ⚠️ DATA IS EXPORTED, NOT PORTED, AND THE DISTINCTION IS THE WHOLE POINT. These are TABLES.
// Rewriting them as GDScript literals would create a second copy that drifts the first time
// anyone retunes a number, and the drift would present as an engine disagreement rather than
// as stale data.
import { ALL_MOVES } from '../moves'
import { SPECIES } from '../species'
import { BIOS } from '../bestiary'
import { CLASSES, HARD_CONTROL_STATUSES, SPREADABLE_STATUSES, LEAGUES } from '../core'
import { CLASS_LINES, LINE_OF, LINES } from '../lines'
import { CLASS_BASIC, CHANNEL_CAST_TIME, CHANNEL_RANGE } from './types'
import { TEAM_SIZE_BY_LEAGUE } from '../town'
import { FIELD_STATUS, BENEFICIAL } from './status'
import { INNATE_EFFECTS } from '../innates'

export function buildDataExport() {
  return {
    schema: 1,
    note: 'Game DATA for the Godot port — tables, not logic. Regenerate with '
      + '`npx tsx tools/exportdata.ts`. Nothing here is hand-written on the Godot side.',
    moves: ALL_MOVES,
    species: SPECIES,
    // Long-form in-game bios, keyed by species id (src/bestiary.ts is the source; the one-line
    // `species[].flavour` stays for compact rows). Exported so the Godot screens tell the same
    // stories the lore doc does - a second hand-copied set would drift.
    bios: BIOS,
    // ⚠️ SPECIES CARRY INNATE NAMES/DESCRIPTIONS ONLY (`species[].innate: {name, desc}[]`) —
    // `Ability` never carried the numeric effect. Without this table a port reads "Chest Beat"
    // and "+50% damage on its first hit" as flavour text with no mechanism behind it — the
    // exact "port omits it and still passes" gap this file exists to close. Keyed by ABILITY
    // NAME to match `species[].innate[].name`; `validate.ts` guards that every name here has a
    // species carrier and vice versa (`docs/INNATES_ON_FIELD.md`).
    innateEffects: INNATE_EFFECTS,
    classes: CLASSES,
    lines: LINES,
    classLines: CLASS_LINES,
    lineOf: LINE_OF,
    // ⚠️ 19 ENTRIES FOR 18 CLASSES IS CORRECT. `Generalist` is the fallback for a stat pair
    // that derives no named class; it is ~3% of the population and it still needs a basic.
    classBasic: CLASS_BASIC,
    channelCastTime: CHANNEL_CAST_TIME,
    channelRange: CHANNEL_RANGE,
    // ⚠️ THE STATUS BEHAVIOUR TABLE TRAVELS AS DATA FOR A SPECIFIC REASON. The first cut of
    // `status_math.gd` hardcoded `MAX_STACKS = {bleed: 3}` and `LURCH_TO_SOURCE = {charm: 2.5}`
    // — two entries out of fifteen, copied by hand because they were the only two `applyStatus`
    // reads today. Add a second stacking status and the GDScript would silently not stack it.
    fieldStatus: FIELD_STATUS,
    beneficialStatuses: [...BENEFICIAL],
    hardControlStatuses: [...HARD_CONTROL_STATUSES],
    spreadableStatuses: [...SPREADABLE_STATUSES],
    leagues: LEAGUES,
    teamSizeByLeague: TEAM_SIZE_BY_LEAGUE,
  }
}
