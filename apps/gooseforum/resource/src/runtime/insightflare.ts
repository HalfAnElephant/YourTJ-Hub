/**
 * A loaded InsightFlare SDK installs SPA navigation hooks. When a fresh page
 * payload disables collection, a full reload is required to remove those
 * hooks; merely updating the Vue payload would leave the old tracker alive.
 */
export function reloadIfInsightFlareDisabled(
  previousEnabled: boolean | undefined,
  nextEnabled: boolean | undefined,
  reload: () => void,
): boolean {
  if (previousEnabled === true && nextEnabled !== true) {
    reload()
    return true
  }
  return false
}
