# B12 Release Candidate Evidence

## Candidate record

- Version: `0.6.4-dev`
- Changelog: [`CHANGELOG.md`](../../CHANGELOG.md), dated `2026-09-22`
- Publication decision: `NOT READY - RETAIL VALIDATION PENDING`
- `ready`: `false`

This record is an index, not a Retail certification. The candidate must not be
called publishable until the required real-client evidence is complete.

## Evidence links

- Scope and implementation evidence: [`B12_Release_UI_Hardening_Evidence.md`](B12_Release_UI_Hardening_Evidence.md)
- Focused and full automated commands: [`quickstart.md`](../../specs/012-release-ui-stabilization/quickstart.md)
- Single-client Retail result: [`B12_Retail_Validation_Evidence.md`](B12_Retail_Validation_Evidence.md)
- Final installation and supported-route checklist: [`TEST_PLAN.md`](../TEST_PLAN.md)
- Player guidance: [`docs/player/README.md`](../player/README.md)
- Officer/GM guidance: [`docs/officer/README.md`](../officer/README.md)
- Developer testing and sandbox limitation: [`docs/developer/testing.md`](../developer/testing.md)

## Automated validation

- Focused B12 Fengari: `56 passed, 0 failed (17 files)`.
- Explicit full Fengari: `542 passed, 0 failed (129 files)`.
- Temporary `scripts/deploy.ps1` mirror verification: passed; deployed TOC
  reported `0.6.4-dev` and included `Core.lua`.
- Supported route integration coverage: `23 passed, 0 failed (1 file)`.
- Touched-file diagnostics: clean.
- Complete-surface `git diff --check`: clean apart from normal Windows
  LF/CRLF conversion warnings.

Fengari validates the deterministic test harness only. It does not establish
Retail frame, taint, BugSack, visual, package-installation, or multi-client
behavior.

## Retail and cross-client gates

- Real single-client Retail matrix: `PENDING_MANUAL_RETAIL_VALIDATION`.
- Required Retail matrix and release gate: [`B12_Retail_Validation_Evidence.md`](B12_Retail_Validation_Evidence.md).
- Cross-client applicability: `NOT REQUIRED: no B12 cross-client behavior change`.
- Two-client evidence is not claimed from single-client or Fengari results.

## Known limitations and baselines

- The unrelated historical baseline at
  `tests/integration/rclootcouncil_buttons_spec.lua:155` remains separate from
  B12 evidence and must not be relabeled as a B12 failure.
- `SANDBOX_STORE_TOO_LARGE` is a bounded, developer-only retained-store limit.
  Developer Mode is off by default, production storage/provider state remains
  isolated, and normal users are unaffected.
- Retail validation is a required operational gate and is not complete in this
  environment.
- T060 remains open because the documented clean-install and route checks do not
  replace real Retail execution or the required BugSack/taint review.

Final readiness decision: `BLOCKED - real single-client Retail validation is
required`. T051 and T060 remain open; no Retail certification or publishable
claim is made from the automated, deployment-mirror, or route-integration
results alone.

## Publication rule

Set `ready: true` only after the single-client Retail matrix is executed in a
real supported client, BugSack and diagnostics show no new Dibs-attributable
findings, the clean candidate package is installed successfully, and every
required checklist item is evidenced. Until then, keep the publication decision
blocked.

## Freeze-boundary review

The B12 source/test/documentation slices were reviewed against the freeze list:

- No B12 change adds or changes `AWARD_COMMIT`, `AWARD_PROPOSAL`, ledger/balance
  semantics, governance, coordinator/recovery, SyncV2, identity, production
  permissions, or the Pre-Dib lifecycle.
- RCLootCouncil remains the owner of its history, votes, and evidence; B12
  historical confirmation remains a protected Dibs-side append-only decision.
- Developer sandbox provider/store isolation remains fail-closed and bounded.

The working tree also contains unrelated Great Vault/B13 source changes whose
added `preDibs.acquisitions` and Vault diagnostics/merge lines match some of the
freeze keywords. Those changes are outside the B12 slice and are not attributed
to this release candidate.
