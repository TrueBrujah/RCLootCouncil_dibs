# Quickstart: Unified History Search and Filters

## Prerequisites

- Run the repository tests through Fengari from the repository root.
- Use only synthetic player names and records in fixtures.
- For an in-game manual check, load the addon in Retail with one player client and, for Officer cases, a verified GM/Officer test character.

## Automated scenarios

1. Run the focused search/filter unit and integration tests selected in `tasks.md`.
2. Verify text, item, player, raid, boss, source, status, season, and inclusive date filters, including multiple criteria combined with AND semantics.
3. Verify malformed dates, reversed dates, missing metadata, clear filters, no results, unavailable RCLootCouncil history, and pagination after filtering.
4. Verify Player results cannot expose another player's records or Officer-only evidence.
5. Verify a non-Officer cannot obtain guild-wide search results.
6. Compare ledger balance, transaction identities, request/acquisition counts, and RCLootCouncil history before and after searches; all must be unchanged.

## Retail manual scenarios

1. Open `/dibs ui` > **History**, search for a known item and constrain its date; clear filters and confirm the prior page scope returns.
2. Open the Player **Great Vault** history and filter a recorded item/status/date; confirm the tooltip remains player-safe.
3. As a verified GM/Officer, open existing ledger/history and Vault review pages and search for a synthetic or known guild record by player/item/source/date.
4. Open RCLootCouncil history review and confirm its preview, authorization, and confirmation flow are unchanged.
5. Repeat with no matches, malformed/reversed dates, and the optional RCLootCouncil addon unavailable.

## Expected outcome

- Only records matching every valid active criterion appear.
- Missing metadata does not match fabricated placeholder text.
- Search results are newest-first and paginated.
- Search is read-only and does not expand the viewer's authority or data scope.

## Validation status

Automated test coverage is recorded in `tasks.md`. The Retail manual scenarios
above have not been executed in this environment; in-game presentation and
client/API behavior therefore remain unverified.
