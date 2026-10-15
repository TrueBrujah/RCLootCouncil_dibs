# UI Contract: Shared History Filters

## Scope

This contract applies to filters embedded in existing Player and Officer history pages. It does not define a new combined timeline or a public network/API contract.

## Criteria

- Free-text query: item name/link/ID, recorded player name where Officer-visible, source/status labels from raw record fields, and recorded raid/boss names.
- Optional player selector/search: Officer-only.
- Optional date-from and date-to: inclusive dates in `YYYY-MM-DD` form.
- Optional season, status, and source criteria where supported by the source page.
- Empty criteria preserve the current page's existing scope and behavior.

## Semantics

- Criteria combine using AND; text is a case-insensitive literal substring.
- Search evaluates only raw fields in the page's existing authorized projection.
- Missing metadata never matches a placeholder, guessed value, or selected filter.
- Results use deterministic newest-first order and existing bounded pagination.
- A filter change resets pagination to the first valid page.
- Clear resets all criteria and returns to the page's existing unfiltered view.

## Security and mutation

- Player pages remain limited to the current player's existing guild/character scope and privacy-safe projections.
- Guild-wide search remains available only behind the existing verified GM/Officer boundary.
- Filtering is read-only and does not alter Dibs balances, requests, acquisition records, RCLootCouncil history, confirmation state, or sync traffic.
- Existing RCLootCouncil history preview and confirmation services remain the only path for importing or correcting historical awards.

## States

- Empty criteria: show the page's existing history.
- Valid criteria with matches: show matching rows.
- Valid criteria without matches: show a localized no-results state and a clear action.
- Invalid date or reversed range: show a validation error; do not execute a query with modified dates.
- Unavailable source: identify the unavailable source separately from a valid empty result.
