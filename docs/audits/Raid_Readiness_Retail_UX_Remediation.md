# Raid Readiness Retail UX Remediation

Date: 2026-09-25

## Classification

- Severity: **P3 UX**
- Retail confirmed: **YES**
- Defect class: **Separate UI composition defect**

## Root Cause

The `setup` route rendered the readiness report as a technical table with raw
check identifiers and generic configuration actions. It also placed season
creation and installation-mode controls directly below the diagnostics. These
controls were explicitly composed inside Raid Readiness; they were not leaked
from a shared page shell or caused by readiness evaluation.

## Remediation

- Replaced the table with an overall status, blocker/warning counts, and grouped
  Core DIBS, Raid, RCLootCouncil, Loot configuration, and Synchronization checks.
- Added friendly check/state labels, blocker-first ordering, concise completed
  rows, and targeted actions that open their owning Officer routes.
- Added separate Show all checks and Technical details disclosures. Technical
  details include check IDs, states, required status, reason codes, sources,
  impacts, and remediation.
- Removed season creation and installation-mode controls from Raid Readiness;
  retained Refresh and the local dry-run.
- Added matching enUS/frFR presentation strings and regenerated the affected
  source-driven documentation outputs.

## Behavioral Boundary

This is presentation-only. `Dibs.Readiness`, `Dibs.SetupAssistant.Evaluate`,
readiness verdicts, blocking policy, domain services, and action APIs were not
changed. The report is displayed as returned; the UI test verifies its status,
blocking count, and check data remain unchanged through disclosure and route
actions.

## Retail Evidence

Retail confirmed: **YES**, per the user's Retail UX review for this remediation.

## Validation

- Focused Fengari UI/navigation/readiness specs: **23 passed, 0 failed** across
  3 files.
- Full Fengari suite: **657 passed, 1 failed** across 140 files. The unrelated
  failure is `tests/integration/predibs_sync_recovery_spec.lua:50`, where the
  anti-entropy heartbeat timer count is 2 instead of the expected 1; this was a
  known baseline failure before this UX change.
- Documentation validation: **26 concepts, 0 errors, 0 warnings**, complete
  enUS/frFR values, unique IDs, and generated outputs current.
- PowerShell documentation tests: **26 passed, 0 failed**.
- `git diff --check`: passed; locale files may report expected LF-to-CRLF
  normalization warnings on Windows.

## Additional Retail UX Refinement (2026-09-25)

The GM's Retail review confirmed the remaining page was accurate but still read
like a diagnostic report. This is an additional **P3 UX** refinement, not a
readiness functional defect. Retail confirmed: **YES**, per the user's current
Retail screenshot observations.

- Reframed the page as a dashboard with an at-a-glance status, attention count,
  ready/total count, and an outside-raid note sourced from the existing report.
- Moved all non-ready checks ahead of ready summaries and used explicit text
  markers for Ready, Blocked, Needs attention, Unavailable, and Unknown states.
- Placed each issue's friendly label, explanation, and existing route action in
  consistent status/detail/action columns; route callbacks were not changed.
- Compressed successful checks into per-domain ready counts by excluding
  skipped checks from the displayed denominator. Individual successes remain
  hidden until Show all checks is selected.
- Grouped refresh, local dry-run, and collapsed Technical details in a Tools
  section. Technical identifiers remain absent from the normal view.
- Added matching enUS/frFR dashboard labels and retained the existing
  source-driven documentation workflow.

### Behavioral Boundary

- Readiness semantics changed: **NO**.
- Business behavior changed: **NO**.
- `Readiness.lua`, `SetupAssistant.lua`, RankRules, Sync, RCLootCouncil,
  SavedVariables, permissions, Ledger, and Governance were not changed.
  Status and check counts are presentation summaries of the existing report.

### Second-Pass Validation

- Focused Fengari UI, route, navigation, and readiness specs: **48 passed, 0
  failed** across 4 files.
- The focused UI spec verifies report-derived status/counts, issue-first
  ordering, ready-check compression and expansion, hidden IDs, all existing
  action targets, Technical details, configuration-control absence,
  enUS/frFR coverage, and unchanged projected report data.
- Documentation validation: **26 concepts, 0 errors, 0 warnings**, with no
  missing enUS/frFR values or duplicate IDs.
- `git diff --check`: passed. Protected readiness and business-logic modules
  have no worktree diff.
- The editor reports pre-existing unsupported `---@doc.*` annotations in
  `OfficerUI.lua` near the unrelated loot-eligibility declaration; the focused
  Lua suite passes.
- Full Fengari suite: **659 passed, 1 failed** across 140 files. The one failure
  is the known unrelated `predibs_sync_recovery_spec.lua:50` timer-count
  assertion (`expected 1, got 2`).
- Deployed with `scripts/deploy.ps1` to the configured Retail AddOns folder;
  SHA-256 checks confirm `OfficerUI.lua`, `enUS.lua`, and `frFR.lua` match the
  edited source.

## Decision

**READY FOR RETAIL VISUAL RECHECK.** A fresh in-client review is still needed
to confirm the final layout at Retail resolutions; this is not a commit
approval.

## Current-Model Loot Rules Readiness Remediation (2026-09-25)

- Replaced the invalid generic options-tree lookup with the same
  `GetLootTypeOptions().types` source used by the Officer Loot Rules page.
- Valid local options report READY; a missing source reports UNAVAILABLE; a
  malformed option object or empty value set reports a non-blocking warning.
- Local scope is disclosed separately with GM/Officer-specific wording. It
  explicitly says these values are not currently distributed guild-wide.
- Suppressed the generic operational-policy adoption banner only on the Loot
  Rules page and replaced it with the local-scope notice. Other routes retain
  the generic banner.
- OperationalPolicy, SyncV2, Loot Rules setters, SavedVariables, and authority
  behavior were not changed. Readiness does not read OperationalPolicy adoption
  when deriving the Loot Rules state.
- Deferred future architecture is tracked separately in
  [Guild-Wide Authoritative Loot Rules](Guild_Wide_Authoritative_Loot_Rules_Follow_Up.md).
- Focused SetupAssistant, readiness UI, and Loot Rules option specs: **43
  passed, 0 failed** across 3 files.
- OperationalPolicy, Governance bootstrap, and Sync status regressions: **22
  passed, 0 failed** across 3 files.
- Full Fengari suite: **669 passed, 1 failed** across 140 files. The only
  failure remains the unrelated known `predibs_sync_recovery_spec.lua:50`
  timer-count assertion (`expected 1, got 2`).
- Documentation validation: **26 concepts, 0 errors, 0 warnings**, with full
  enUS/frFR coverage.