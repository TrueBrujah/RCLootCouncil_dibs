# Research: Robust RCLootCouncil Integration

## Decision: Detect capabilities instead of trusting version labels

- **Decision**: The adapter reports `absent`, `operational`, `degraded`, or `unsupported`
  from observed capabilities. A version string is supporting metadata only and never proves
  compatibility.
- **Rationale**: RCLootCouncil does not provide a single stable Dibs permission contract.
  Capability checks let Standalone Dibs continue when an optional surface is unavailable
  and fail closed when the adapter cannot prove that an action is safe.
- **Alternatives considered**: An allowlist of version numbers was rejected because a label
  does not prove that the required object, callback, or identity is present. Treating any
  loaded RCLootCouncil addon as operational was rejected because partial initialization can
  expose misleading state.

## Decision: Use one adapter boundary for discovery and lifecycle

- **Decision**: Centralize addon discovery, capability snapshots, status reasons, and hook
  installation in the RCLootCouncil adapter. Hooks are installed at most once per owner and
  retried only through a bounded lifecycle path.
- **Rationale**: Options, voting UI, loot UI, and award callbacks must not each infer a
  different compatibility state. Idempotent markers prevent duplicated buttons, callbacks,
  timers, and refresh loops when RCLootCouncil rebuilds a frame.
- **Alternatives considered**: Independent checks in every UI surface were rejected because
  they drift and make degraded behavior inconsistent. Direct modification of RCLootCouncil
  core files was rejected by the constitution and would make upgrades unsafe.

## Decision: Verify the local Master Looter for every award

- **Decision**: For award finalization, re-read the current RCLootCouncil Master Looter and
  require the callback actor to be the local client identity and to match that Master Looter.
  Raid Leader, Raid Assistant, council membership, and a remote actor payload are not proof.
- **Rationale**: The same addon message or callback may be visible to multiple clients. A
  client must not replay a remote ML object into its own ledger. Revalidation also handles a
  Master Looter change during a loot session.
- **Alternatives considered**: Trusting `GetLootMethod("master")` alone was rejected because
  it does not establish the RCLootCouncil actor for the specific finalized award. Trusting
  an `isMasterLooter` flag in a payload was rejected because payload claims are untrusted.
  Granting Dibs administration to the ML was rejected by the constitution.

## Decision: Require a stable award identity and fail closed when ambiguous

- **Decision**: Prefer an immutable RCLootCouncil history identifier. If unavailable, accept
  only a deterministic combination of a unique loot/session identity, award position, item,
  and winner that remains stable across duplicate delivery and reload. If no unique identity
  can be established, ignore the event without changing the ledger.
- **Rationale**: Idempotency must survive duplicate callbacks, reconnects, and reloads. An
  in-memory counter or a current-instance label can collide across sessions.
- **Alternatives considered**: Using a runtime-only generated ID was rejected because it can
  debit twice after reload. Using item and winner alone was rejected because the same item may
  be awarded repeatedly. Guessing from an encounter or instance name was rejected because it
  is not unique enough.

## Decision: Normalize an explicit DIB response only

- **Decision**: Convert the RCLootCouncil response to a canonical DIB code only when the
  source explicitly identifies `DIB`/`DIBS` according to the supported response contract.
  Surrounding text, case, and known presentation labels may be normalized; an ambiguous or
  absent response is rejected.
- **Rationale**: A candidate being eligible, a normal award, or a manually added record is
  not evidence that a Dib was spent. Explicit response validation is the accounting boundary.
- **Alternatives considered**: Treating every successful award as a DIB was rejected because
  it spends Dibs on ordinary loot. Searching arbitrary text for a substring was rejected
  because localized or explanatory text can create false positives.

## Decision: Keep RCLootCouncil history read-only and provenance-scoped

- **Decision**: The adapter may read history to obtain stable award identity and display
  context. It may mark or normalize only records explicitly created by Dibs and must retain
  original identifiers for all unrelated records.
- **Rationale**: RCLootCouncil owns its history. Dibs must not rewrite another addon's audit
  data as a side effect of loading or displaying the integration.
- **Alternatives considered**: Rebuilding all RC history IDs into a Dibs format was rejected
  because it can corrupt unrelated records. Copying the full history into Dibs was rejected
  because it duplicates ownership and exposes unnecessary data.

## Decision: Preserve the existing protected accounting path

- **Decision**: A valid adapter event is converted into the existing protected finalized-award
  command. Manual grants, removals, refunds, adjustments, settings, seasons, rank rules,
  and mode changes remain behind verified guild GM/officer authority.
- **Rationale**: One accounting path makes authorization, eligibility, ledger validation,
  audit fields, and idempotency consistent across Standalone and RCLootCouncil modes.
- **Alternatives considered**: Writing directly to `Ledger.Use` from a callback was rejected
  because it bypasses protected authorization and audit validation. Giving the ML a generic
  Dibs admin capability was rejected because loot authority and guild accounting authority
  are separate responsibilities.

## Decision: Keep optional integration failure non-destructive

- **Decision**: Absent, degraded, disabled, and unsupported RCLootCouncil states preserve Dibs
  seasons, requests, balances, and history. The UI reports the state and continues to expose
  Standalone functionality when possible.
- **Rationale**: RCLootCouncil is optional, and a compatibility failure must not become a
  data migration or an authority expansion.
- **Alternatives considered**: Disabling all Dibs when RC is unavailable was rejected because
  it breaks the standalone contract. Falling back from an unverified ML to a raid role was
  rejected because it weakens the security boundary.

## Decision: Test the matrix at contract, integration, and Retail levels

- **Decision**: Add focused tests for capability states, authority, response normalization,
  stable identity, history preservation, duplicate awards, privacy, and Standalone fallback;
  then run one-client and two-client Retail smoke scenarios.
- **Rationale**: Synthetic tests prove deterministic boundaries, while only a live client can
  reveal actual callback timing, frame rebuilds, RCLootCouncil data shape, and WoW API behavior.
- **Alternatives considered**: Relying only on the existing Lua suite was rejected because it
  cannot certify the installed RCLootCouncil build. Relying only on manual testing was rejected
  because replay and malformed-input cases are difficult to reproduce consistently by hand.

## Decision: Treat version and changelog updates as a release gate

- **Decision**: Every behavior/build change in this feature includes a dated changelog entry
  and a matching addon version increment; documentation-only changes still receive a note.
- **Rationale**: The constitution requires release traceability and makes compatibility
  changes auditable for guild users and future RCLootCouncil versions.
- **Alternatives considered**: Updating the version only at final packaging was rejected
  because intermediate test builds would be indistinguishable. Relying on commit messages
  alone was rejected because they are not visible in the addon distribution.
