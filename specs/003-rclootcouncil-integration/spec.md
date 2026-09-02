# Feature Specification: RCLootCouncil_dibs RCLootCouncil Integration

## Goal

Integrate Dibs with RCLootCouncil as an optional adapter while keeping all loot-session behavior local to the raid.

## User Stories

### P1 - Display Dib status

As a council member, I can see relevant Dib status for local candidates.

### P1 - Use DIB response

As an eligible player, I can declare a Drop-Dib through the supported local RCLootCouncil flow.

### P1 - Respect Pre-Dib eligibility

When valid Pre-Dibs exist for an item, configured priority rules can prevent non-Pre-Dib candidates from using the DIB response while still allowing non-Dib fallback responses.

### P1 - Consume on finalized award

A Dib is consumed only after the item award is finalized and qualifies for Dib consumption.

## Requirements

- Do not modify RCLootCouncil core.
- Use supported module/extension APIs and messages where available.
- Dibs remains authoritative for balance and history.
- RCLootCouncil data is not required to rebuild balances.
- No local live loot data leaves the raid through Dibs cross-raid sync.

## Out of scope

- Guild-wide live loot feed
- Cross-raid candidate lists
- Cross-raid council votes
