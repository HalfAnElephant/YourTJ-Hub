import { describe, expect, test, vi } from 'vitest'
import { reloadIfInsightFlareDisabled } from '../src/runtime/insightflare'

describe('InsightFlare runtime policy transition', () => {
  test.each([
    [true, false, true],
    [true, undefined, true],
    [false, false, false],
    [false, true, false],
    [true, true, false],
    [undefined, false, false],
  ])('reloads only when enabled changes to disabled', (previous, next, shouldReload) => {
    const reload = vi.fn()

    const didReload = reloadIfInsightFlareDisabled(previous, next, reload)

    expect(didReload).toBe(shouldReload)
    expect(reload).toHaveBeenCalledTimes(shouldReload ? 1 : 0)
  })
})
