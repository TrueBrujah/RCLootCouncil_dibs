# Data Model: Unified History Search and Filters

This feature adds no persisted entity or SavedVariables schema. It operates on transient criteria and existing authorized history projections.

## Search Criteria

An in-memory view value supplied by the active history page:

| Field | Meaning | Validation / access |
|---|---|---|
| `query` | Case-insensitive text across allowed raw metadata fields | Trim whitespace; empty means no text constraint |
| `playerName` | Exact or text player match, Officer pages only | Must be a current/authorized guild player according to the owning page |
| `item` | Item name, link, or ID search | Missing item metadata does not match |
| `instanceName` | Raid/instance criterion | Match only recorded instance metadata |
| `encounterName` | Boss/encounter criterion | Match only recorded encounter metadata |
| `fromDate` | Inclusive beginning date | Must parse as an actual calendar date |
| `toDate` | Inclusive ending date | Must parse as an actual calendar date and not precede `fromDate` |
| `seasonId` | Existing season scope | Existing page semantics remain authoritative |
| `status` | Existing record or verification status | Match the source status, not a display fallback |
| `source` | Existing origin/source value | Missing source remains missing and does not match a selected source |

Player-visible criteria omit `playerName` and receive only the local player's privacy-safe projection. Officer-only criteria are not exposed by Player projections.

## History Record Projection

An existing ledger transaction, Pre-Dib request/history entry, Great Vault acquisition, or RCLootCouncil award-history candidate. Each record keeps its existing identity and source. Search reads only fields supplied by the owning source and does not add inferred metadata.

## Search Result

A transient, ordered subset of the records supplied to a history page, plus source availability and empty-state information. Search results do not become authoritative records and are discarded when the view is closed or its scope changes.

## Match and ordering rules

- Active criteria combine with AND semantics.
- Text matching is case-insensitive and uses literal substring matching.
- Date boundaries are inclusive and based on calendar dates in the local game client.
- Rows sort newest first; equal timestamps use a stable record identity as a tie-breaker.
- Pagination occurs after filtering and sorting and is bounded by existing shared UI helpers.
- A missing field never matches a non-empty criterion.
