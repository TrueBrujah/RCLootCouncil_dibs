# Combat safety

WoW protected frames cannot be created, moved, shown, or changed freely during combat lockdown. `Dibs.ProtectedActions` and `Dibs.Readiness` keep authoritative action checks separate from pure data operations.

Safe during combat when no protected UI is touched: reading balances/history, evaluating eligibility, normalizing items, building sync manifests, validating packages, and updating in-memory/domain data when the caller has authority. UI creation, options refresh, Encounter Journal actions, and live award finalization must be deferred. Runtime handlers invalidate readiness on roster/world/zone changes and retry deferred UI work after `PLAYER_REGEN_ENABLED`.

Do not bypass the guard by calling an internal helper directly. Live award processing also requires capability and authority checks, not only an out-of-combat frame. Tests model these boundaries with WoW API doubles; Retail verification remains a manual step.
