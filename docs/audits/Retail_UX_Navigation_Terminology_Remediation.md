# Retail UX Navigation Terminology Remediation

Date: 2026-09-25

## Root Cause

The integration fixture did not provide the WoW `GetLocale()` API. The addon
loads `enUS.lua` and then `frFR.lua`, matching the TOC order. The French locale
only returns early when `GetLocale()` exists and reports a non-French locale;
with the API missing, French strings overwrote the English catalog. The Wizard
route was present, but its localized label did not match the English string
used by the test.

## Fixture Difference From Retail

Retail provides `GetLocale()` before addon files load. The fixture now provides
the same API, defaults to `enUS`, and supports an explicit `locale` override.
The fixture and Retail load the same source file order. Presentation role,
module registration, feature availability, and initialization were not the
cause of the missing English label.

The navigation tree is not cached or injected later. Both
`Dibs.OfficerUI.GetNavigationTree()` and the production `AceGUI.AddTree` call
use `getOfficerNavigationTree()` directly. That function builds entries from
the static `OFFICER_NAV_TREE`, filters by the presentation role and module
availability, and localizes labels from `Dibs.L`.

## Fix

- Added Retail-equivalent `GetLocale()` behavior to `tests/helpers/wow_api.lua`.
- Kept assertions against the actual GM role from the fixture bootstrap.
- Asserted the normal navigation mappings: Guided Setup to `wizard`, Raid
  Readiness to `setup`, and Guild Configuration to `installation`.
- Asserted that Setup Assistant and Guild Setup are absent as normal navigation
  labels.
- Kept semantic concept IDs `setup.assistant.readiness` and `guild.setup`, and
  kept all three route values unchanged.

## Retail Evidence

The user confirmed that the Retail Officer Control Center screenshot shows:

- Overview: Dashboard, Guided Setup, Raid Readiness.
- System: Settings, Modules, Guild Configuration, Synchronization, Diagnostics.

This confirms the production navigation UX recheck. The screenshot was not
available as a workspace image file, so this record captures the user's
Retail screenshot observation rather than embedding or linking the image.

## Production Code Status

Production code changed: **YES**, presentation only. Navigation labels, page
titles, contextual help, and current guide wording were clarified. Production
navigation behavior changed: **NO**. Guided Setup remains available, and the
`wizard`, `setup`, and `installation` route values are unchanged.

## Documentation And Validation

- Updated English and French labels and contextual help without changing
  navigation behavior.
- Updated current Officer guide terminology and regenerated all eight
  source-driven documentation artifacts.
- Documentation validation: 26 concepts, 0 errors, 0 warnings, complete enUS
  and frFR values, unique IDs; generated outputs are current.
- Focused Fengari tests: 23 passed, 0 failed across the installation/navigation
  integration test and localized UI help test.
- PowerShell documentation tests: 26 passed, 0 failed.
- Full Fengari suite: 655 passed, 1 failed across 140 files. The only failure
  is the known unrelated `tests/integration/predibs_sync_recovery_spec.lua:50`
  heartbeat timer count (`expected 1, got 2`).
- `git diff --check` passed; Git emitted only expected LF-to-CRLF warnings for
  generated files and locale catalogs.

## Decision

**FIX_FIXTURE**

**READY TO CONTINUE VALIDATION**

The fixture and focused navigation contract now match Retail. The unrelated,
previously known heartbeat failure remains a full-suite caveat; it is not
caused by this terminology or fixture change.