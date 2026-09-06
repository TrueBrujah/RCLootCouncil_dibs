# Research: Pre-Dibs Encounter Journal

## Decision 1: Keep the Dibs ledger authoritative

- Decision: Pre-Dib requests remain proposals/reservations; only a protected finalized-award flow may append a Dib consumption transaction.
- Rationale: The constitution requires balances and history to come from the append-only Dibs ledger, not from UI state or RCLootCouncil.
- Alternatives considered:
  - Consume on request creation: rejected because a request is not an award.
  - Let RCLootCouncil own fulfillment: rejected because RC is optional and cannot reconstruct Dibs state.

## Decision 2: Reuse the existing Pre-Dib lifecycle and loot pipeline

- Decision: Keep one request lifecycle for standalone, Adventure Guide, Developer Mode, and optional RC entry points; normalize item context before creating a request.
- Rationale: Existing modules already provide request creation, status transitions, duplicate lookup, test isolation, and a shared request entry point.
- Alternatives considered:
  - Separate Adventure Guide requests: rejected because duplicate and fulfillment semantics would diverge.
  - Direct UI writes: rejected because integrations must not bypass domain boundaries.

## Decision 3: Enforce raid-only policy at both visibility and submission boundaries

- Decision: Hide or disable the Adventure Guide action outside raid contexts and reject direct submissions from non-raid contexts.
- Rationale: UI hiding alone is bypassable by stale callbacks or direct calls; the submission boundary must enforce the same policy.
- Alternatives considered:
  - UI-only filtering: rejected because it does not protect the request API.
  - Treat unknown instance contexts as dungeons: rejected because missing metadata can suppress legitimate raid loot; unknown item categories remain visible, while submission uses the existing safe context policy.

## Decision 4: Treat the sub-category matrix as local display policy

- Decision: Store category overrides in Dibs settings, use stable normalized category keys, block known non-Dib categories in the recommended preset, and allow unknown categories by default.
- Rationale: The matrix controls local visibility only and must not change eligibility, balance, or history.
- Alternatives considered:
  - Localized display strings as keys: rejected because localization is unstable.
  - Block all unknown categories: rejected because legitimate combat loot could disappear.

## Decision 5: Use idempotent finalized award references

- Decision: Fulfillment and consumption are keyed by a stable award reference and processed through the protected award acceptance path.
- Rationale: Replays must not append a second ledger transaction or fulfill a request twice.
- Alternatives considered:
  - Timestamp-based deduplication: rejected because retries and collisions are ambiguous.
  - Request status alone: rejected because the same award event may be delivered after partial processing.

## Decision 6: Keep RCLootCouncil optional

- Decision: RC may announce, display, or report a compatible local finalized award, but standalone Pre-Dibs and accounting must work when RC is absent or degraded.
- Rationale: This preserves the authority and privacy boundaries established by the core and constitution.
- Alternatives considered:
  - Require RC for all Pre-Dibs: rejected because the feature must operate independently.
  - Mirror live RC candidates/votes: rejected because live session data is outside this feature and the cross-raid privacy boundary.

## Decision 7: Defer protected UI work during combat

- Decision: Ordinary request/state operations may remain synchronous, while frame creation, visibility, anchoring, and refresh work must respect combat lockdown and resume when safe.
- Rationale: This follows the constitution and existing UI deferral behavior.
- Alternatives considered:
  - Force frame updates in combat: rejected because it risks taint and protected UI violations.
