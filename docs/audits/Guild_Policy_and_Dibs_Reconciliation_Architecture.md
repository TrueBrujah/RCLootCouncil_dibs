# Guild Policy and Dibs Reconciliation Architecture

Status: Read-only architecture pass. No production code was changed.

## Decision

**ARCHITECTURE BLOCKERS REMAIN** for signed and automatic rank reconciliation.
The Guild Policy page, Wizard status step, page-specific authority messaging,
and read-only reconciliation preview can be planned independently. Do not
enable reconciliation writes for negative deltas or automatic modes until the
ledger contract, audit payload, and non-coordinator behavior below are resolved.

The design must preserve five separate authority boundaries: OperationalPolicy,
SEASON_CATALOG, Guild Loot Rules, the append-only Ledger, and local player
settings. A screen may link to another authority, but must not copy its values
into OperationalPolicy.

## Current Authority Map

| Authority | Current owner and data | Write / distribution path | Boundary |
|---|---|---|---|
| OperationalPolicy | `db.operationalPolicy`; hash-chained revisions and `POLICY_ADOPTED` state. Its allowlist is module enablement, public Pre-Dibs availability, per-season Pre-Dibs modes, and announcement channels. | Initial adoption is GM-only; later writes use the governance policy-writer rule. Changes are revisioned and announced through SyncV2. | Does not own seasons, rank allocations, loot-type decisions, ledger balances, or character eligibility. The `modules` values enable features; they are not the feature's substantive rules. |
| SEASON_CATALOG | `db.seasonCatalog`; revisioned seasons/current season, `rankRules`, and `guildConfiguration`. The configuration snapshot currently includes several legacy settings and eligibility policies. | `Seasons.PublishCatalog` creates a hash-chained catalog revision; SyncV2 announces/applies it. Catalog writes require an authorized OperationalPolicy writer, but the catalog remains a distinct authority. | A write-permission dependency on OperationalPolicy does not make catalog contents OperationalPolicy. |
| Rank Rules | `db.rankRules`, keyed by season and guild rank. `defaultAllocation` in guild `db.settings` is the fallback when an explicit rank rule is absent. | Rank edits use `rank.set` and are carried in `SEASON_CATALOG.rankRules`. | This is the source of expected allocation, not OperationalPolicy. Reconciliation is a separate Ledger mutation. |
| Guild Loot Rules | Local draft values in `db.settings.dibAllowedTypes` and `dibRCEnabledTypes`; adopted snapshot at `SEASON_CATALOG.guildConfiguration.guildLootRules`. | GM-only explicit adopt/publish through `Dibs.LootRules`, catalog publication, and SyncV2. The Loot Rules service provides its own status states. | A distinct authority embedded in the catalog envelope. Keep its draft/adoption state and status distinct from OperationalPolicy publication. RCLootCouncil response configuration remains an external integration projection. |
| Character Eligibility | `db.characterEligibility`, including season/family policies, relationships, and decisions. | `eligibility.policy.set` uses ProtectedActions and the CharacterEligibility service. `Seasons.GetGuildConfiguration` copies policies into a catalog snapshot, but the current policy-set action does not itself publish/announce a catalog revision. | The domain owner is CharacterEligibility. Catalog carriage is not proof that every edit is currently synchronized. Confirm and fix its publication contract before labeling it synchronized. |
| Ledger | `db.ledger.transactions` and player state; append-only local canonical transactions and, when V2 is enforced, coordinator-ordered commits. `SEASON_ALLOCATION` changes assigned/base allocation; other transaction deltas affect spendable balance. | ProtectedActions delegates to Ledger. V2 commits require coordinator authority; non-coordinator allocation writes can produce a proposal in the lower-level API. | Never edit `playerStates`, allocation, or balance directly. `ledger.adjust` changes balance and is not a substitute for changing assigned rank allocation. |
| Permissions / Governance | `Permissions.Evaluate` defines GM/officer authorization; Governance defines adopted guild authority, coordinator, and policy-writer rule. | Evaluated at ProtectedActions and Ledger boundaries. | Do not add a Guild Policy toggle that overrides action authorization or coordinator rules. |
| Guild-scoped legacy settings | `db.settings` includes fallback/default allocation, public Pre-Dibs availability, announcement channels/templates, and other guild configuration; parts are copied in `SEASON_CATALOG.guildConfiguration`. | Existing settings and migration paths; some values are read directly, others defer to OperationalPolicy when adopted. | These are not `Dibs.GetLocalSettings()`. Several overlap newer authorities and need explicit migration precedence. |
| Local player settings | `Dibs.GetLocalSettings()` returns the local per-character settings store, including language, debug levels, and developer-mode preference. | Local-only persistence; no guild authority or SyncV2 publication. | Keep presentation and developer preferences local. |

Relevant implementation surfaces: [OperationalPolicy](../../src/modules/OperationalPolicy.lua), [Seasons](../../src/modules/Seasons.lua), [RankRules](../../src/modules/RankRules.lua), [LootRules](../../src/modules/LootRules.lua), [CharacterEligibility](../../src/modules/CharacterEligibility.lua), [Ledger](../../src/modules/Ledger.lua), [ProtectedActions](../../src/modules/ProtectedActions.lua), and [OfficerUI](../../src/ui/OfficerUI.lua).

### Candidate Settings

| Candidate | Current authority / behavior | Classification | Design disposition |
|---|---|---|---|
| Rank-change reconciliation behavior | RankRules calculates expected allocation from the current roster rank. Diagnostics count distinct rank snapshots in history; no roster rank-change reconciliation service or current automatic rank-change handler was found. | REQUIRES NEW BUSINESS FEATURE | Build a rank-transition projection and signed reconciliation contract before automating. |
| Positive reconciliation | `rank.reconcile` calls `Ledger.RegisterSeasonAllocation`; it accepts positive integer amounts. The old Assignments action applies positive missing allocations in bulk. | CURRENTLY SUPPORTED | Retain the manual positive path and migrate it to Automatic Dibs with preview, required reason, and fresh-state validation. Existing audit completeness is insufficient for the target workflow. |
| Negative reconciliation | `rank.reconcile` rejects amounts below 1; `SEASON_ALLOCATION` is positive-only. `ledger.adjust` is signed but changes spendable balance, not assigned allocation. | REQUIRES NEW BUSINESS FEATURE | Add and validate a canonical allocation-adjustment semantic; do not route a negative allocation delta to `ledger.adjust`. |
| MANUAL reconciliation mode | Existing missing-allocation batch is explicitly invoked by an Officer/GM; the current Automatic Dibs page is otherwise read-only. | CURRENTLY SUPPORTED | Make MANUAL the initial behavior and default. |
| AUTOMATIC_RECOMMENDATION mode | The current reconciliation projection can expose missing/surplus differences without mutation, but there is no rank-change recommendation workflow or policy field. | CAN SAFELY MOVE INTO POLICY | A future value may control recommendations only. It must never commit a Ledger transaction or imply that a row was reconciled. |
| AUTO_POSITIVE_ONLY mode | No automatic roster reconciliation writer was found. Positive ledger allocation writes exist only through explicit/bootstrap paths. | REQUIRES NEW BUSINESS FEATURE | Do not allow initially; rank freshness, duplicate prevention, coordinator routing, and audit contracts are not established. |
| AUTO_POSITIVE_AND_NEGATIVE mode | No signed allocation mutation exists. Negative balance/debt consequences are undefined for this operation. | REQUIRES NEW BUSINESS FEATURE | Prohibit until the negative transaction and spent-allocation semantics are validated. |
| Manual adjustment permissions | `Permissions` authorizes `ledger.adjust` to guild admins (GM/Officer) and applies ProtectedActions checks. | SHOULD REMAIN ELSEWHERE | Keep role/action authorization in Permissions and governance. Guild Policy may explain who can act, not override the gate. |
| Mandatory reasons | `ledger.adjust` requires a nonempty reason only when `source == "MANUAL_ADMIN"`. Old Assignments uses `manual_live_adjustment`, so it does not receive that backend check. `rank.reconcile` defaults a missing reason. | SHOULD REMAIN ELSEWHERE | Mandatory reasons are a ProtectedActions/Ledger safety invariant, not an administrator-selectable policy. Make enforcement uniform when migrating old controls. |
| Pre-Dibs enablement / behavior | OperationalPolicy supports `allowPublicPreDibs` and per-season `preDibModes`; `PreDibs` uses these when adopted and otherwise falls back to local guild settings. Module availability is also an OperationalPolicy value. | CURRENTLY SUPPORTED | This belongs in Guild Policy. Resolve the legacy mirror: `allowPublicPreDibs` is also in season-catalog configuration and an older settings control writes it directly. Never let a stale mirror overwrite an adopted revision. |
| Requests policy | OperationalPolicy currently has only `modules.requests` enablement. Request/dispute behavior has no corresponding policy value set. | REQUIRES NEW BUSINESS FEATURE | Keep the module gate; define request behaviors and semantics before adding policy fields. |
| Audit requirements | ProtectedActions and Ledger produce actor/target/reason/season transaction context for existing operations, but do not capture the full reconciliation snapshot requested here. | SHOULD REMAIN ELSEWHERE | Audit completeness and retention are platform invariants, not optional Guild Policy settings. Extend the canonical transaction contract for reconciliation. |
| Loot / RCLootCouncil policy references | `modules.rclootcouncil` is a feature gate; per-type RC and Adventure Guide decisions belong to Guild Loot Rules. RC profile/button configuration is external integration state. | SHOULD REMAIN ELSEWHERE | Guild Policy may show read-only links/status. Do not copy loot types, RC response indexes, or RC profile values into OperationalPolicy. |
| Eligibility policy | CharacterEligibility owns season/family policy and audits it. The season catalog currently snapshots these policies, but the policy-set action does not publish that snapshot. | SHOULD REMAIN ELSEWHERE | Keep the domain entity in CharacterEligibility. Establish an explicit publication/sync contract before claiming synchronized authority. |

## Proposed Guild Policy Contents

The Guild Policy route should be the human-facing editor/status surface for
OperationalPolicy's existing allowlist, not a new aggregate of all guild-owned
settings:

- Feature availability: current `modules` flags, described as enablement rather
  than as the underlying Requests, RCLootCouncil, or eligibility rules.
- Pre-Dibs: public availability and the per-season request mode.
- Announcements: public/officer channels. Templates and reminders remain
  separately labeled settings carried through the season-catalog configuration
  until their ownership is deliberately consolidated.
- Publication: `Policy not published` when there is no adopted record; otherwise
  `Active revision N`, with author/time and policy status where available.
- Related authorities: read-only status and links to Seasons/Rank Rules
  (SEASON_CATALOG), Loot Rules (Guild Loot Rules), Loot Eligibility
  (CharacterEligibility), and Ledger. These are references, not duplicated
  controls.

OperationalPolicy currently has no separate editable draft store: `Change`
creates/applies a new policy revision and announces it. The Wizard and page
must not invent a persisted `Draft` state. If product requires a review-before-
publish draft workflow, that is a separate business feature. Before initial
adoption, legacy fallback values may be shown as local/unpublished candidates;
only an explicit authorized adoption can make them OperationalPolicy.

Do not put Rank Rules, season lifecycle/current season, Loot Rules, eligibility
matching/outcomes, ledger allocations/balances, officer permissions, mandatory
audit behavior, RC configuration, local language/debug preferences, or request
resolution semantics into this record.

## Guided Setup Integration

Add Guild Policy as a distinct Wizard step immediately after Administration
and before Seasons. This is the point where the guild actor/authority is known,
before season-specific setup is reviewed. Preserve the existing `Dibs Rules`
step because it currently checks Loot Rules; do not relabel that check as
OperationalPolicy. The resulting workflow has 13 steps rather than silently
removing an existing check.

The new step is a status-and-navigation projection only:

```text
Guild Policy [!]
Policy not published
[Open Guild Policy]

Guild Policy [OK]
Active revision 4
[Open Guild Policy]
```

Derive state directly from `OperationalPolicy.GetState()` and its current
record. The button activates the Guild Policy route; no editor or copy of the
policy appears inside Guided Setup. An unpublished policy can be an
`ACTION_REQUIRED`/warning item, but must not independently block raid readiness
unless an existing readiness check says the missing policy is required.

`Wizard` currently has 12 ordered step IDs and stores the selected step as a
local numeric `wizardStepIndex`. Inserting a step shifts indices. Preserve the
selected logical step with a one-time index migration or persist a stable step
ID; do not silently reopen users on a different step. Update the step-status
projection and the OfficerUI route map together.

## Automatic Dibs Reconciliation

### Current Surface

The Officer Automatic Dibs page currently renders a seven-column history-like
table and has no Reconcile action. `BuildAutomaticAllocationDetails` mixes
historical assignment transactions with current roster fallback rows. Its
`amount` is sometimes an event delta and sometimes a current balance, not a
consistent `Assigned` value; its `expected` can be read from the current rank
even for an older event. `RankRules.GetAllocationReconciliation` is the better
source for a live comparison: it projects current rank, expected allocation,
assigned allocation (`Ledger.GetPlayerState().allocation`), missing, and
surplus. The separate spendable balance is not assigned allocation.

No writer for the `automatic_rank_assignment` source was found; Core's current
default-season bootstrap registers one local initial allocation, not a guild
roster rank-change reconciler. Keep event history in History. Make Automatic
Dibs a current-state reconciliation view, with any historical trail linked to
History rather than conflated with current rows.

### Proposed Rows

For the selected season, render one current row per unambiguous roster member:

| Player | Rank | Expected | Assigned | Difference | Reason | Action |
|---|---|---:|---:|---:|---|---|

`Difference = Expected - Assigned` using assigned allocation, not balance.
Positive is missing allocation; negative is surplus allocation; zero is
aligned. Rank should show the current rank used by RankRules. Reason should
explain the mismatch/source (for example, current rank rule differs from the
allocation recorded before a rank change); it is not a substitute for the
operator-entered audit reason.

Show `[Reconcile]` for every nonzero difference once the matching signed
transaction capability exists. Until then, a negative row must remain visible
but non-actionable with a clear explanation; it must not be silently skipped
or sent through a balance adjustment. Stale roster, ambiguous identity,
missing/unpublished catalog, missing rule, incompatible peer, sync-behind, or
unavailable coordinator states must fail closed.

## Reconcile and Reconcile All Safety Model

Every mutation must continue through `ProtectedActions.Execute("rank.reconcile",
...)` and the authoritative Ledger/canonical coordinator path. The UI must
never write SavedVariables or call a balance mutation to emulate allocation
reconciliation.

For an individual row:

1. Show a confirmation preview with player identity, season, catalog revision,
   current rank, assigned allocation, expected allocation, signed difference,
   and resulting allocation.
2. Require a nonempty operator reason. Enforce this at ProtectedActions, not
   only by disabling a widget.
3. Immediately before commit, re-resolve the unique target and re-read the
   active season/catalog revision, roster rank, expected value, assigned value,
   and balance. Reject a stale preview rather than applying a stale delta.
4. Have the canonical coordinator validate the expected prior allocation (a
   compare-and-set precondition) before appending. Include an idempotency key so
   retries or repeated clicks cannot apply the same difference twice.
5. Report committed, proposal-pending, stale, and rejected outcomes distinctly.
   Do not call a non-coordinator proposal “reconciled.”

`Reconcile All` should first present a preview: number of positive/negative/
aligned rows, total signed allocation change, target list, and season/catalog
revision. One explicit confirmation may apply eligible rows sequentially
through the same protected action, each with its own transaction and audit
record. This is not atomic: revalidate each row and report per-row successes,
stale rows, proposals, and failures. Never claim the whole batch succeeded if
only part committed. Until signed reconciliation is implemented, disable the
batch if any negative row is present rather than applying a surprising
positive-only subset.

The reconciliation audit/transaction contract must preserve at least:

- actor identity snapshot and authority;
- target identity snapshot;
- season ID and SEASON_CATALOG revision/hash used;
- old rank index/name and current rank index/name;
- old assigned allocation, expected allocation, signed delta, and resulting
  assigned allocation;
- mandatory operator reason, source, timestamp, transaction/idempotency ID;
- the associated canonical commit/proposal outcome.

The current ProtectedActions audit payload includes actor, target, season,
rank index/name, expected allocation, reason, and source, but no old assigned
value or previous rank. More importantly, the current canonical Ledger
transaction/hash does not persist rank index/name or expected allocation from
that payload. These fields must be part of a versioned canonical transaction
contract, not UI-only metadata.

### Rank-Change Examples and Mode Decision

| Transition | Expected change | Required signed difference | Safe interpretation |
|---|---:|---:|---|
| Member -> Guild Master | 1 -> 2 | +1 | Add one assigned allocation only after the fresh roster/rule state is verified and the canonical allocation event commits. |
| Guild Master -> Veteran | 2 -> 1 | -1 | Reduce assigned allocation, not “remove one DIB” from the spendable balance. If the reduction would make the current balance negative because Dibs were already spent, the product must define debt/earned-balance semantics before allowing it. |

Recommended policy choices:

- `MANUAL`: allow; initial default and only mutating behavior in the first
  reconciliation release.
- `AUTOMATIC_RECOMMENDATION`: allow as a later, non-mutating recommendation
  mode; it may surface changed rank/difference and notification, never append
  transactions.
- `AUTO_POSITIVE_ONLY`: do not allow yet. A grant is still a ledger mutation
  and can duplicate or use stale roster state.
- `AUTO_POSITIVE_AND_NEGATIVE`: do not allow until signed allocation semantics,
  debt treatment, transaction hashing, coordinator/proposal behavior, and
  compatibility are validated.

The release gate is not “a negative amount works in the UI.” Decide whether a
rank demotion can lower only unspent assigned allocation, create debt, or
require an explicit separate correction. `ledger.adjust` must remain a
spendable-balance operation and must not silently answer that domain question.

## Legacy Dibs Assignments Consolidation

The old panel is the `Dibs Assignments` AceConfig group under the RCLootCouncil
options integration. Its functions overlap the Officer Automatic Dibs,
Dibs Administration, and History surfaces.

| Old function | Classification | Destination / disposition |
|---|---|---|
| Season selector | MIGRATE | Use the selected season context in Automatic Dibs; do not maintain a second selection state. |
| Assignment log | DUPLICATE | Current rows overlap Automatic Dibs and assignment transactions overlap History. Keep until the new current-state view and History links are validated, then retire the duplicate log. |
| “Reconcile missing Dibs” bulk button | MIGRATE | Move to Automatic Dibs as previewed `Reconcile All`; preserve positive-only behavior until the signed contract is ready. |
| Player selector | MIGRATE | Use the selected player row in Dibs Administration, where identity and current balance are shown. |
| Arbitrary -9..+9 amount control | DEPRECATE | Do not retain this separate adjustment surface. Dibs Administration's explicit per-row +/-1 workflow is the safer existing path; broader amounts need a separately designed reviewed correction. |
| Reason input | MIGRATE | Use the required reason in the Dibs Administration confirmation flow or reconciliation confirmation. Enforce server-side at ProtectedActions. |
| “Apply live adjustment” | DEPRECATE | It duplicates Dibs Administration and uses `manual_live_adjustment`, which bypasses the `MANUAL_ADMIN` reason-required check and explicitly allows debt. Do not preserve this weaker path. |

Retire the old group only after migrated features have parity tests, old action
paths are no longer required by callers, docs/localization are updated, and
the remaining consumers of `Dibs.RCOptions.state` are checked. Do not remove
it during this architecture pass.

## Page-Specific Authority Status

The exact localized banner “Guild-wide rules are not active. Changes remain
local until the Guild Master adopts the policy.” is produced by
`BuildSynchronizationStatus` and rendered on five routes: **Pre-Dibs,
Modules, Seasons, Rank Rules, and Announcements**. It is not a universal
authority status; in particular, Seasons and Rank Rules are catalog-owned.

| Page | Correct status source | User-facing status direction |
|---|---|---|
| Seasons | SEASON_CATALOG | Show catalog revision and local/synchronized/behind state. Do not infer season publication from OperationalPolicy status. |
| Rank Rules | SEASON_CATALOG, including `rankRules` | Show the revision carrying the rule and sync freshness. Rank edits may be permitted by an OperationalPolicy writer rule, but that is authorization, not ownership. |
| Loot Rules | Guild Loot Rules service status | Use its own not-configured/local-legacy/ready/behind/incompatible states and authority revision. Do not call it OperationalPolicy. |
| Guild Policy | OperationalPolicy state/current record | “Policy not published” or “Active revision N.” Make any legacy local fallback explicit; do not call it a published draft. |
| Loot Eligibility | CharacterEligibility policy projection plus verified catalog publication status | Show season/family and whether its current policy is actually synchronized. The current set action does not publish a catalog record, so “synchronized” is not yet substantiated. |
| Announcements | Split authority | Channels: OperationalPolicy publication/revision. Templates/reminders: season-catalog guild configuration or explicitly local legacy setting. Label each source. |
| Pre-Dibs | Effective Pre-Dibs source | Show OperationalPolicy revision/mode when adopted; otherwise clearly mark the legacy local fallback. Explain public availability separately from module enablement. |
| Modules | OperationalPolicy modules | Show whether module enablement is published and which flags are effective. Do not imply every page's domain data is local. |

The Synchronization page already presents separate policy/catalog revisions
and peer revision columns. Preserve that distinction and make the top summary
state which authority is behind rather than collapsing them into one banner.

Before migration, resolve duplicate legacy writes: `allowPublicPreDibs` exists
in OperationalPolicy and catalog-carried `db.settings`; one older RC options
control reads/writes `db.settings` directly. Announcement channels also have
legacy settings mirrors. Once a valid OperationalPolicy revision exists, it
must win; catalog snapshots/local settings must never roll it backward. Before
first adoption, show legacy values as candidates for explicit GM review, not
as already published Guild Policy.

## UX Design-System Recommendation

Use the Raid Readiness hierarchy as the preferred structure, not a wholesale
visual redesign:

- **At a glance**: the page's primary state and the smallest useful summary.
- **Needs attention**: actionable problems first, each linked to its owning
  page/authority.
- **Ready/Active**: compact confirmation of healthy states; avoid repeating
  every raw field.
- **Tools**: normal actions and navigation, separated from status.
- **Technical details**: collapsed by default, with stable reason codes and
  revision/peer evidence for troubleshooting.

Current fit and migration priority:

1. **Guild Policy**: apply the hierarchy when introducing the page; distinguish
   unpublished, active revision, and related authority references.
2. **Dashboard**: it already has status badges, recent activity, and collapsed
   technical details, but lacks a concise “At a glance / Needs attention”
   grouping. Add prioritization without duplicating Raid Readiness checks.
3. **Guild Configuration**: retain its installation/readiness state and
   next-step actions; group recovery blockers before tools and keep technical
   state secondary.
4. **Synchronization**: make policy/catalog/ledger freshness the top summary,
   put recovery/announce/probe actions in Tools, and keep per-peer revision
   matrices as technical detail.
5. **Diagnostics**: already has overall health, service status, and collapsed
   technical/runtime details. Treat as the closest match; only normalize
   terminology and severity after the higher-traffic pages migrate.

Page-specific authority status remediation is a prerequisite, not part of a
generalized visual pass. Never use color or a generic “guild policy” badge as
the only indication of a distinct authority state.

## Phased Implementation Plan

### Phase 0: Resolve Domain and Ledger Blockers

- Approve the meaning of negative allocation change when the target has spent
  Dibs or has a lower current balance than the allocation reduction.
- Define the signed allocation transaction, reducer, replay/idempotency,
  canonical hash, V2 coordinator/proposal result, and old-peer compatibility.
- Extend the canonical audit contract to retain before/after assigned value
  and both old/current rank snapshots, tied to season/catalog revision.
- Choose deterministic adoption precedence for legacy Pre-Dibs and
  announcement values; verify how CharacterEligibility changes publish.

### Phase 1: Authority-Accurate Navigation and Status

- Add Guild Policy to the GUILD RULES navigation in the requested order:
  Seasons, Guild Policy, Rank Rules, Loot Rules, Announcements, Loot
  Eligibility.
- Add the Guided Setup status/navigation step after Administration; keep its
  scope to status and Open Guild Policy.
- Replace the five generic-banner usages with page-specific authority status.
- Surface local fallback versus published revision without silently importing
  or overwriting data.

### Phase 2: Reconciliation Projection and Manual Positive Flow

- Make Automatic Dibs a current roster/rule/assigned-allocation projection;
  separate historical assignments into History.
- Add stale-state preview and explicit required reason for positive
  reconciliation through ProtectedActions/Ledger.
- Display coordinator proposal/pending outcomes accurately. Do not add
  negative actions or batch partial-success ambiguity.

### Phase 3: Signed Reconciliation and Reconcile All

- Implement and test the approved canonical signed allocation event and
  compare-and-set/idempotency behavior.
- Add negative per-row action only after spent-balance/debt policy is decided.
- Add Reconcile All as preview plus explicit confirmation, per-row commits,
  per-row audit, and a complete partial-result report.
- Validate single-client and multi-client coordinator/non-coordinator cases,
  duplicate clicks, stale roster/catalog, reconnect/replay, and old supported
  peers before enabling it.

### Phase 4: Recommendations and Automation Decision

- Add `AUTOMATIC_RECOMMENDATION` only as a non-mutating policy option after
  rank-change detection and notification are validated.
- Re-evaluate `AUTO_POSITIVE_ONLY` and `AUTO_POSITIVE_AND_NEGATIVE` separately;
  neither is enabled by this architecture decision.

### Phase 5: Legacy UI Retirement and Hierarchy Migration

- Verify parity and migrate callers, help text, and localization; then remove
  the old Dibs Assignments option group in a separately reviewed change.
- Apply the Raid Readiness hierarchy in the priority order above without
  duplicating readiness or policy engines.

## Architecture Blockers

1. **No signed allocation-reconciliation ledger operation.** Current
   `SEASON_ALLOCATION` accepts only positive values and adjusts assigned
   allocation; `ledger.adjust` changes balance. Demotion behavior cannot be
   safely implemented by choosing one of these existing operations.
2. **Insufficient canonical audit context.** The ProtectedActions payload does
   not include old assigned allocation/previous rank, and the current Ledger
   canonical transaction/hash does not retain the rank and expected-allocation
   fields needed for reconstruction.
3. **Coordinator/proposal contract is incomplete for this UI.** The lower-level
   `CommitSeasonAllocation` may return a non-coordinator proposal, but the
   current `RegisterSeasonAllocation`/`rank.reconcile` wrapper does not expose
   that proposal as a reconciled result. Reconcile must define pending and
   coordinator outcomes before adding batch controls.
4. **Authority mirrors need deterministic migration.** Public Pre-Dibs and
   announcement settings have legacy `db.settings` copies; some older writes
   bypass OperationalPolicy. CharacterEligibility is copied into a catalog
   envelope but its policy-set path does not publish that envelope.

Until blockers 1-3 are resolved and validated, the approved scope is limited
to authority/status UX, read-only reconciliation, and a carefully bounded
positive manual migration. Therefore the final decision for the complete
requested evolution is **ARCHITECTURE BLOCKERS REMAIN**.