# Feature Specification: RCLootCouncil History Reconciliation and Dibs Evidence

**Feature Branch**: `006-rclootcouncil-history-reconciliation`

**Created**: 2026-09-09

**Status**: Draft

**Input**: User description: "Add a GM/Officer-controlled reconciliation feature for existing RCLootCouncil history. It must not run automatically, must guide the user with questions, must support manual confirmation of historical Dibs awards, must record proof in the Dibs addon, and must support guilds whose RCLootCouncil response label is different from 'Dibs'."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Start a controlled historical search (Priority: P1)

As a guild GM or Officer, I want to start a reconciliation search from the Officer interface, so that installing Dibs after several weeks of RCLootCouncil history does not silently change balances.

**Why this priority**: Historical data can repair a lost or newly installed Dibs ledger, but an automatic scan could create incorrect debits. A deliberate, reviewable operation is the safety boundary.

**Independent Test**: Load a test RCLootCouncil history containing three weeks of records, open the reconciliation action as a GM or Officer, answer the scope questions, and verify that the preview appears without changing any Dibs balance or transaction count.

**Acceptance Scenarios**:

1. **Given** RCLootCouncil contains existing history and Dibs has no matching transactions, **when** a GM or Officer presses **Reconcile RCLootCouncil history**, **then** a guided form asks for the target season, history range, response labels, and review mode before any import is possible.
2. **Given** the guided form is completed, **when** the GM or Officer starts the search, **then** the addon creates a read-only preview and reports candidate counts without creating, deleting, or changing a Dibs transaction.
3. **Given** a normal player, Master Looter, Raid Leader, Raid Assistant, or council member opens the Officer interface without a GM/Officer guild role, **when** they attempt to start reconciliation, **then** the action is unavailable or rejected and no preview or ledger mutation is created.
4. **Given** RCLootCouncil is absent, disabled, or degraded, **when** the reconciliation action is opened, **then** the addon explains that no compatible history is available and leaves existing Dibs data usable.

---

### User Story 2 - Find Dibs candidates with custom response labels (Priority: P1)

As a guild administrator, I want to tell the search which RCLootCouncil response labels represent a Dibs vote, so that another guild can use a label such as `Reserve`, `Priorité`, or `Main Need` without changing its loot policy.

**Why this priority**: RCLootCouncil response text is configurable and localized. Assuming one literal label would either miss valid awards or import unrelated awards.

**Independent Test**: Configure several explicit response aliases, search history containing matching, non-matching, localized, test, and normal awards, and verify the classification and reasons shown for every row.

**Acceptance Scenarios**:

1. **Given** the guild uses a response label other than `Dibs`, **when** a GM or Officer adds that exact label to the reconciliation policy and searches, **then** matching finalized awards appear as Dibs candidates.
2. **Given** an alias differs only by case or surrounding whitespace, **when** the search runs, **then** the normalized label matches while the original label is retained as evidence.
3. **Given** a response is not in the configured alias list, **when** it appears in history, **then** it is not automatically classified as a Dibs candidate.
4. **Given** a test, pending, rejected, or otherwise non-finalized response appears in history, **when** the search runs, **then** it is excluded or marked as rejected with a reason and cannot be imported by the guided flow.
5. **Given** the same visible label is used for different response identities in different RCLootCouncil profiles, **when** the search cannot distinguish them safely, **then** the row is marked for manual review instead of being silently accepted.

---

### User Story 3 - Review and confirm historical awards (Priority: P1)

As a GM or Officer, I want to review proposed historical awards and confirm only the Dibs that were actually granted, so that recovery remains accurate and accountable.

**Why this priority**: The guild must be able to repair a missing ledger without trusting imperfect history data or making an irreversible bulk decision.

**Independent Test**: Review a mixed preview, confirm one eligible row, reject one row, leave one ambiguous row pending, and verify that only the confirmed row changes the Dibs ledger.

**Acceptance Scenarios**:

1. **Given** a row has a stable award identity, item, winner, finalized status, and an explicit configured Dibs response, **when** an authorized administrator confirms it, **then** exactly one historical Dibs consumption is recorded for the selected season.
2. **Given** a row is missing an item, winner, stable identity, or final status, **when** an administrator reviews it, **then** the row is marked ambiguous or rejected and cannot be confirmed through the normal guided action.
3. **Given** a row is ambiguous but the GM or Officer has independent evidence, **when** they use manual confirmation, **then** the addon requires an explicit confirmation statement and reason before recording the historical consumption.
4. **Given** a confirmed row is selected again in the same or a later search, **when** the administrator confirms it again, **then** the addon reports it as already accounted for and does not debit another Dibs.
5. **Given** multiple candidates are selected for confirmation, **when** one candidate fails validation, **then** valid candidates are processed individually and the failed row remains unchanged with its reason shown.

---

### User Story 4 - Preserve complete evidence and privacy (Priority: P1)

As a guild member, I want a Dibs transaction to show why it was created, while keeping officer-only details private, so that loot accounting can be audited without exposing unrelated raid data.

**Why this priority**: A recovered balance is only trustworthy when the guild can trace it back to a specific RCLootCouncil record and see who confirmed it.

**Independent Test**: Confirm a historical row, inspect the player and Officer views, and verify that the ledger link and evidence are complete while unrelated candidates and votes remain hidden from normal players.

**Acceptance Scenarios**:

1. **Given** a historical award is confirmed, **when** the transaction is shown to a GM or Officer, **then** it includes the source, history or award identifier, winner, item, response label and identity when available, original award time, import time, importing actor, target season, and confirmation reason.
2. **Given** the history row has an unknown optional field, **when** its evidence is displayed, **then** the field is explicitly labeled unknown or unavailable rather than guessed.
3. **Given** a normal player views their own history, **when** a historical consumption is present, **then** they see a concise source and reason but not unrelated players, candidate lists, votes, or private administrator notes.
4. **Given** an unrelated RCLootCouncil history row exists, **when** reconciliation runs, **then** the original row and identifier remain unchanged and no Dibs evidence is attached to it.

---

### User Story 5 - Recover across seasons and date ranges (Priority: P2)

As a guild administrator, I want to choose which season and date range a confirmed historical award belongs to, so that a new guild or a guild recovering after a data loss can rebuild the correct period without rewriting prior accounting.

**Why this priority**: A three-week history may span a season boundary, and a guild may intentionally start Dibs from installation day instead of backdating every old award.

**Independent Test**: Search records before and after a season boundary, select a target season, confirm one in-range row, and verify that original award time and import time are both preserved.

**Acceptance Scenarios**:

1. **Given** a search covers a selected date range, **when** the preview is generated, **then** each candidate retains its original award timestamp and is shown against the selected target season.
2. **Given** a candidate falls outside the active season dates or has no season context, **when** the administrator confirms it, **then** the addon warns about the mismatch and requires an explicit target-season choice.
3. **Given** existing Dibs transactions are already present, **when** historical rows are imported, **then** they remain immutable and only new, confirmed transactions are appended.
4. **Given** the guild chooses to start from the installation date, **when** the date range is limited accordingly, **then** older RCLootCouncil records remain reference-only and do not affect Dibs balances.

## Edge Cases

- RCLootCouncil history is empty, unavailable, corrupt, or too old to expose a stable award identifier; the preview explains the limitation and offers manual evidence only where an administrator can identify the award safely.
- A response alias is renamed after the award; the old label remains available as a historical alias and the original text is retained.
- Two rows have the same player and item but different stable history identifiers; both remain separate candidates and can be accounted for independently.
- Two rows have the same player and item but no stable identifier; both are marked ambiguous and cannot be auto-confirmed.
- A row has a custom Dibs label but a non-finalized status; it remains excluded until a valid finalized record is available.
- A row was added manually, awarded indirectly, or recorded by a different RCLootCouncil version; the administrator sees the source status and must use manual confirmation if the normal evidence contract cannot be satisfied.
- A historical award is already represented by a Dibs transaction with a different reference; the administrator must link or reject it rather than creating a second consumption.
- A target season is archived, missing, or belongs to another guild; the import is rejected without changing either guild's data.
- The reconciliation window is closed, the user reloads the UI, or another officer confirms a row first; reopening the preview reflects the idempotent accounted status.
- A large history would make the interface unresponsive; the search uses bounded pages and reports when more records remain.
- The guild has no raid channel or the user is not currently grouped; local preview and evidence remain available without attempting live raid synchronization.
- The existing live award path has two separate provenance points: RCLootCouncil emits the `RCMLAwardSuccess` event, and Dibs processes the validated event through its own `FinalizeAward` accounting action. These names may appear as technical evidence labels for Officers, but neither label is a button or permission grant.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide a clearly labeled reconciliation action in the Officer interface that is available only to a verified guild GM or Officer.
- **FR-002**: The system MUST NOT scan, import, debit, or modify historical records automatically during addon load, reload, login, RCLootCouncil initialization, or history viewing.
- **FR-003**: Before searching, the guided flow MUST ask for a target season, history scope or date range, response aliases, and whether the administrator wants guided review or manual review.
- **FR-004**: The system MUST generate a read-only preview before any historical ledger mutation and MUST show total scanned rows and counts for eligible, already accounted, ambiguous, rejected, and unsupported rows.
- **FR-005**: Response aliases MUST be explicitly configured by a GM or Officer and MUST match after documented normalization of case and surrounding whitespace; fuzzy or guessed labels MUST NOT be accepted automatically.
- **FR-006**: A guided candidate MUST include a finalized award status, an explicit configured response alias, a stable award or history identity, a resolvable winner, and a resolvable item before it can be confirmed through the normal flow.
- **FR-007**: Test, pending, rejected, non-Dibs, and otherwise non-finalized records MUST NOT consume Dibs through the guided flow.
- **FR-008**: The manual flow MUST allow a verified GM or Officer to select an ambiguous or legacy row and explicitly confirm it as a Dibs award only after entering a reason and acknowledging the evidence limitation.
- **FR-009**: Every confirmed historical award MUST create at most one append-only Dibs consumption transaction in the selected season and MUST use the same balance, eligibility, and authorization rules as a live finalized award.
- **FR-010**: Duplicate confirmation MUST be idempotent by stable award identity or an administrator-approved evidence link; it MUST return the existing transaction status without changing the balance again.
- **FR-011**: Each imported transaction MUST preserve an evidence record containing, when available, the RCLootCouncil history or award identifier, session identity, item identity and link, winner identity, original award time, difficulty or mode, original response text and identity, finalization status, source, configured alias used, target season, import time, importing actor, review outcome, and reason.
- **FR-012**: Unknown evidence fields MUST be stored as unknown or unavailable and MUST never be inferred from unrelated rows, localized display text, or player guesses.
- **FR-013**: The feature MUST keep RCLootCouncil history, candidates, votes, sessions, and identifiers read-only, except for Dibs-owned records explicitly marked as created by Dibs under the existing compatibility rules.
- **FR-014**: Reconciliation and manual confirmation MUST remain guild-scoped and MUST NOT expose or merge another guild's or an unguilded character's Dibs data.
- **FR-015**: Master Looter, Raid Leader, Raid Assistant, council membership, and response-label ownership MUST NOT grant reconciliation or manual-import authority unless the actor is also a verified guild GM or Officer.
- **FR-016**: The feature MUST preserve the original award timestamp separately from the reconciliation timestamp and MUST require explicit administrator choice when the target season is uncertain or mismatched.
- **FR-017**: Existing Dibs transactions, seasons, balances, Pre-Dibs, and evidence MUST remain immutable during reconciliation; corrections MUST use the existing append-only correction model.
- **FR-018**: The Officer view MUST provide search, filtering, paging or bounded result display, candidate detail, confirmation, rejection, and an audit view showing the decision outcome for each row.
- **FR-019**: Normal players MUST see only their own confirmed historical consumption and a safe summary of its source and reason; complete candidate lists, evidence details, administrator notes, and other players' records MUST remain Officer-only.
- **FR-020**: The feature MUST work as a review tool when RCLootCouncil is absent or degraded by preserving existing Dibs data and explaining that compatible history is unavailable; it MUST not expand permissions or fabricate evidence.
- **FR-021**: The feature MUST distinguish the RCLootCouncil source event (`RCMLAwardSuccess`) from the Dibs accounting action (`FinalizeAward`) in its evidence and audit views; these references MAY be displayed to Officers when available, but the UI MUST NOT expose either name as a directly executable action or permission grant.
- **FR-022**: All buttons, questions, statuses, rejection reasons, evidence fields, and help text MUST be localized with English fallback and MUST explain whether the action changes the ledger or consumes a Dibs.
- **FR-023**: Every search, alias change, confirmation, rejection, manual override, and correction MUST be attributable to the authorized actor and retained in an append-only audit trail.
- **FR-024**: The Officer confirmation view MUST show only rows whose normalized response exactly matches a configured DIB alias and MUST provide one clear confirmation action that records an annotation and confirms the row as DIB.

### Key Entities

- **Reconciliation Session**: A bounded, administrator-started search with target season, date or history scope, response aliases, creation time, actor, and preview state.
- **Response Alias Policy**: A guild- and season-scoped list of explicit RCLootCouncil response labels or identities that represent a Dibs vote, including normalized matching rules and change history.
- **History Candidate**: A read-only RCLootCouncil record classified as eligible, already accounted, ambiguous, rejected, or unsupported, with the reason and evidence available for review.
- **Historical Dibs Evidence**: Immutable provenance attached to a confirmed or rejected candidate, including source identifiers, item and winner context, response, status, timestamps, actor, alias, and review outcome.
- **Reconciliation Decision**: An administrator's confirmation, rejection, deferral, or manual override for one candidate, including reason and time.
- **Historical Dibs Transaction**: An append-only Dibs ledger consumption linked to one confirmed evidence record and deduplicated by stable award identity.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In automated and Retail acceptance tests, 100% of reconciliation previews leave Dibs balances, transaction counts, RCLootCouncil history, candidates, votes, and sessions unchanged.
- **SC-002**: A GM or Officer can configure a response alias, search a three-week history, understand the candidate counts, and reach the confirmation list in under two minutes during a normal test run.
- **SC-003**: Across a test corpus containing standard, localized, custom, case-varied, test, pending, and non-Dibs responses, 100% of rows are classified according to the explicit alias and finalization rules, with no fuzzy-label imports.
- **SC-004**: 100% of confirmed historical awards create exactly one Dibs transaction, and 100% of repeated confirmations return the existing result without another debit.
- **SC-005**: 100% of confirmed rows contain a complete evidence record or explicit `unknown` values for unavailable fields, including the confirming actor and reason.
- **SC-006**: In authority tests, 100% of reconciliation searches, alias changes, confirmations, manual overrides, and corrections succeed only for verified guild GMs or Officers.
- **SC-007**: In history-preservation tests, 100% of unrelated RCLootCouncil records and identifiers remain unchanged after repeated searches and imports.
- **SC-008**: In privacy tests, normal players can see only their own safe summary and cannot view the complete candidate list, administrator evidence, or another player's historical records.
- **SC-009**: A GM or Officer can recover a selected set of legacy awards with missing response metadata through manual confirmation while every such record remains visibly marked as manual and includes a reason.
- **SC-010**: When RCLootCouncil is absent or degraded, the feature produces a clear unavailable status and causes zero unauthorized Dibs mutations.
- **SC-011**: At least 95% of reviewed candidates in the acceptance test set display a concise, actionable reason for their classification without a Lua error or unusable interface.

## Assumptions

- The live RCLootCouncil integration remains the preferred source for new finalized awards; reconciliation exists for late installation, lost or incomplete Dibs data, and controlled guild recovery.
- `RCMLAwardSuccess` is an event emitted by RCLootCouncil after its award flow, while `FinalizeAward` is Dibs's protected accounting action after validation. The addon listens to the source event and records the accounting result in its own ledger; it does not call or replace RCLootCouncil's award controls.
- The default operation is preview-only until each selected row is explicitly confirmed. There is no background import and no one-click blind bulk debit.
- A guild may use any response label. A label becomes eligible only after a GM or Officer explicitly adds it to the guild's response alias policy; the original label and any available response identity remain in evidence.
- Exact normalized alias matching is the default. A manual GM/Officer confirmation is the only supported override when the response label or identity is missing.
- The target season defaults to the selected active season, but the administrator must be able to choose another existing season and must confirm date or season mismatches.
- Historical awards preserve their original award time and are appended with a separate reconciliation time; they do not rewrite older Dibs transactions.
- Existing award-reference idempotency remains authoritative. If an old row cannot be linked safely, the administrator must resolve it manually or leave it unaccounted.
- A manual confirmation is an administrative accounting decision, not proof that Blizzard or RCLootCouncil would award the item under a different rule.
- Complete account-alt discovery, Battle.net identity matching, and automatic external history imports remain outside this feature.
- The feature is guild-scoped and must obey the current constitution's GM/Officer authority, append-only ledger, RCLootCouncil ownership, privacy, diagnostic, and versioning rules.
