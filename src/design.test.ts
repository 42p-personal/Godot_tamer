// The design-consistency checks that used to be dev-console-only now gate CI:
// species/class/element/calendar coherence, orphaned statuses, innate-table
// drift, and reward-table sync. See validate.ts for what each check covers.
import { expect, it } from 'vitest'
import { designProblems } from './validate'

it('design tables are fully consistent', () => {
  expect(designProblems()).toEqual([])
})
