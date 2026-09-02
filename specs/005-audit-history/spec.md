# Feature Specification: RCLootCouncil_dibs Audit and History UI

## Goal

Provide players and authorized staff with appropriate, inspectable history without exposing live inter-raid loot sessions.

## Player view

A player can see:
- current season
- allocation
- current Dib balance
- active Pre-Dibs
- own Dib history
- items received through Dib transactions

## Officer/GM view

Authorized users can see:
- all players
- all Dib transactions
- Pre-Dib history
- item award history recorded for Dib accounting
- administrative adjustments and reasons
- synchronization metadata where useful for troubleshooting

## Requirements

- No destructive delete of ledger history.
- Corrections reference or explain the corrected event.
- Historical rank is preserved.
- Filters by season, player, action, and item.
- "Who received what" reflects finalized awards only.
