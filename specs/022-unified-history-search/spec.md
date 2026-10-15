# Feature Specification: Unified History Search and Filters

**Feature Branch**: `022-unified-history-search`

**Created**: 2026-10-14

**Status**: Draft

**Input**: User description: "Recherche et filtres unifies : retrouver les attributions par objet, joueur, raid, boss, date et source. Les recherches doivent couvrir les vues Player/Officer et les historiques existants."

## Clarifications

### Session 2026-10-14

- Q: Pour rechercher dans les historiques, préfères-tu une page unique qui mélange les sources ou les mêmes filtres dans les pages Player/Officer existantes ? → A: Filtres partagés dans les pages existantes, pour garder le contexte et ne pas confondre les différents types d'enregistrements.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Find a Personal Record (Priority: P1)

As a player, I want to find my own recorded Dibs activity and Great Vault acquisitions by item, raid or boss, date, and source, so that I can quickly review what is recorded for me.

**Why this priority**: Players need a reliable way to inspect their own history without exposing another player's or an Officer's private information.

**Independent Test**: Seed personal Dibs and Great Vault records with different items, dates, sources, and encounter metadata; verify that matching filters show only the player's records and that clearing filters restores the full personal result set.

**Acceptance Scenarios**:

1. **Given** the player has records with supported searchable metadata, **When** they search by item or apply date and source filters, **Then** only matching personal records are shown.
2. **Given** a record has no raid or boss metadata, **When** the player filters by a raid or boss, **Then** the record does not falsely match and no missing metadata is invented.
3. **Given** the player clears the search and filters, **When** results refresh, **Then** the player's complete history in the current data scope is restored.
4. **Given** a player views a record, **When** they inspect its details, **Then** administrative-only evidence and unrelated player records remain hidden.

### User Story 2 - Find Guild Records (Priority: P1)

As a verified Guild Master or Officer, I want to search authorized guild records by player, item, raid, boss, date, status, and source, so that I can review an award or acquisition without manually paging through unrelated history.

**Why this priority**: Officers need to investigate questions using current, auditable guild evidence while preserving the existing authority and privacy boundaries.

**Independent Test**: Seed records for multiple guild members and supported sources; verify that a verified Officer can narrow results with combined filters and that an unauthorized player cannot access the guild-wide search.

**Acceptance Scenarios**:

1. **Given** a verified Officer searches guild history, **When** they combine player, item, date, status, or source criteria, **Then** the result set contains only records matching all active criteria.
2. **Given** a record includes raid or boss metadata, **When** an Officer filters by that value, **Then** matching evidence is found across the supported history views.
3. **Given** the viewer lacks guild-administration authority, **When** they attempt to access guild-wide records, **Then** the request is denied and no guild-wide data is disclosed.
4. **Given** the same record is available through more than one existing view, **When** it is searched, **Then** its existing identity and audit details are preserved and search does not create or alter records.

### User Story 3 - Understand Search Results (Priority: P2)

As a player or Officer, I want search results to explain their scope and handle empty or incomplete data clearly, so that I do not mistake missing evidence for a negative result.

**Why this priority**: Loot history can have incomplete legacy metadata, and a trustworthy search must distinguish "no match" from "not available."

**Independent Test**: Search a fixture with no matches, unavailable history, and legacy entries missing encounter metadata; verify the corresponding states are explicit and clearing filters recovers the available results.

**Acceptance Scenarios**:

1. **Given** filters match no records, **When** the result view refreshes, **Then** it shows an explicit no-results state and offers a clear-filters action.
2. **Given** a history source is unavailable, **When** the search view loads, **Then** it identifies the unavailable source rather than presenting it as an empty history.
3. **Given** results exceed one page, **When** the user navigates pages or changes filters, **Then** results remain deterministically sorted newest first and the page selection stays valid.

### Edge Cases

- The selected date range is malformed or its start is later than its end; the view reports the invalid range and does not silently reinterpret it.
- A filter value is absent from older or migrated records; those records remain searchable by the metadata they do contain.
- A source becomes unavailable while the user is viewing results; the view reports that source state without hiding available results from other sources.
- The user changes guild or character context; results are recalculated from the currently authorized data scope.
- Search returns a large history; filtering and pagination remain bounded and do not create an unbounded frame or duplicate records.
- Multiple active filters use AND semantics; the user can clear one filter without clearing the others.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The feature MUST provide a consistent search and filter experience embedded in the existing Player and Officer history views; it MUST NOT merge different record types into a new cross-source timeline.
- **FR-002**: Player views MUST return only the current player's records within the existing guild or character data scope.
- **FR-003**: Guild-wide search MUST require the same verified Guild Master or Officer authority as the existing guild history views.
- **FR-004**: Users MUST be able to search by item and, where present in an existing record, raid and boss.
- **FR-005**: Officers MUST be able to filter by player; both roles MUST be able to filter by date, status, and source where those fields are available and permitted.
- **FR-006**: Multiple active filters MUST be combined predictably so a record is included only when it satisfies every active filter.
- **FR-007**: Search MUST use only existing recorded evidence and MUST NOT invent missing item, raid, boss, source, date, player, or status values.
- **FR-008**: Search MUST preserve existing record identities, audit data, authority checks, guild and character isolation, and privacy projections; searching MUST NOT mutate the ledger, requests, acquisitions, or RCLootCouncil history.
- **FR-009**: Results MUST be deterministically sorted newest first and presented with bounded pagination.
- **FR-010**: The interface MUST distinguish no matches from an unavailable history source and MUST provide a way to clear filters.
- **FR-011**: Date range input MUST be validated; invalid or reversed ranges MUST be surfaced without returning success-shaped results.
- **FR-012**: Search controls, filter values, empty states, and unavailable states MUST be localized in English and French and include concise help text.

### Key Entities

- **History record**: An existing Dibs transaction, Pre-Dib history record, Great Vault acquisition, or available RCLootCouncil award-history record; carries only the fields already recorded by its source.
- **Search criteria**: Optional item, player, raid, boss, date-range, season, status, and source constraints; some criteria are restricted to Officer views.
- **Search result**: A privacy-safe projection of an existing history record, retaining its source identity and permitted audit details.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can locate a seeded record among 5,000 mixed history entries using the supported criteria in under 2 seconds on the test environment.
- **SC-002**: Across the focused privacy and authority test cases, zero records outside the viewer's permitted scope are returned.
- **SC-003**: Across the focused evidence test cases, zero records with missing encounter metadata match a raid or boss filter solely because of an invented/default value.
- **SC-004**: Every empty, unavailable, and invalid-date-range scenario produces a distinct user-visible state.
- **SC-005**: Searching or clearing filters causes zero changes to ledger balances, history identities, or acquisition counts.

## Assumptions

- The initial feature covers existing Player and Officer history surfaces and does not create new history, infer missing metadata, or change award/eligibility policy.
- Search covers Dibs ledger/history, Pre-Dib records, Great Vault acquisitions, and RCLootCouncil award history only where the corresponding source already provides an authorized history projection.
- Existing guild and character data-isolation rules remain authoritative; Player search is personal and guild-wide search is Officer-protected.
- Search criteria are local view state and do not need SavedVariables or synchronization.
- The feature remains usable when an optional history source, including RCLootCouncil, is unavailable.
