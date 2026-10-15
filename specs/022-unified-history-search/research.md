# Research: Unified History Search and Filters

## Decision: Keep filters inside existing history pages

**Rationale**: The user selected shared filtering in existing Player and Officer pages rather than a new page that combines unlike record types. This preserves each page's meaning, existing permissions, and audit context.

**Alternatives considered**:

- A combined cross-source timeline: rejected because ledger transactions, Pre-Dib requests, Vault acquisitions, and RCLootCouncil history have different lifecycle and evidence meanings.
- Separate, unrelated filters for every page: rejected because filter behavior would continue to vary between the existing history views.

## Decision: Match recorded fields, not display strings

**Rationale**: Existing records may not contain raid/boss context or source metadata. Searching raw optional fields avoids false matches caused by UI placeholders such as "Unknown" and preserves the distinction between unavailable information and a genuine value.

**Alternatives considered**:

- Search formatted row text: rejected because it includes presentation fallbacks and makes semantics depend on labels.
- Infer missing raid/boss values from an item catalog: rejected because it could misrepresent historical evidence and is outside the approved scope.

## Decision: Reuse existing data and authorization boundaries

**Rationale**: Player and Officer controllers already expose personal and guild-scoped history through domain projections. The new filtering layer should operate only on the authorized projection and must not query private data on the Player surface.

**Alternatives considered**:

- Add storage/index tables or synchronize filter state: rejected because criteria are local presentation state and need no persistence or protocol changes.
- Move guild filtering into a new service: rejected because it duplicates existing authority and guild-membership boundaries.

## Repository Prior Art

- `src/ui/PlayerUI.lua`: Player Dibs history text query, Great Vault page, and player-safe acquisition projection.
- `src/ui/OfficerUI.lua`: `BuildLedgerDetails`, `BuildVaultAcquisitionReview`, `BuildPreDibDetails`, and paged Officer views.
- `src/ui/LogsUI.lua`: permission-checked RCLootCouncil history search and preview boundary.
- `src/ui/AceGUI.lua`: shared table page, fluid-column, scroll, and pagination helpers.
- `.github/instructions/ui.instructions.md` and `docs/developer/b12-ui-design-rules.md`: shared Midnight UI and bounded-list requirements.

## Open Unknowns

None blocking design. Fields absent from legacy or source-specific records remain unsearchable for those records and are never inferred.
