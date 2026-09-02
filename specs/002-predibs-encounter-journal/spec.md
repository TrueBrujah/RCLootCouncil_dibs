# Feature Specification: RCLootCouncil_dibs Pre-Dibs and Encounter Journal

## Goal

Allow players to request advance Dibs on supported raid loot and manage those requests through a localized UI.

## User Stories

### P1 - Create Pre-Dib

As a player, I can select a supported raid item and request a Pre-Dib before it drops.

### P1 - See request state

As a player, I can distinguish pending, confirmed, cancelled, fulfilled, and invalid Pre-Dib requests.

### P1 - Preserve Dib until award

A confirmed Pre-Dib does not consume a Dib merely because it exists or because the item drops.

### P2 - Public request awareness

Guild members can view active public Pre-Dib requests according to configured visibility.

### P2 - Localized Encounter Journal action

Where supported, the addon exposes a localized "I want to DIB this" action from the Encounter Journal raid loot experience.

## Transaction/request events

- DIB_REQUEST_CREATED
- DIB_REQUEST_CONFIRMED
- DIB_REQUEST_CANCELLED
- DIB_REQUEST_INVALIDATED
- DIB_REQUEST_FULFILLED

## Requirements

- Stable itemID is stored.
- Localized text is never used as an identifier.
- Multiple players may Pre-Dib the same item.
- Losing an award does not automatically consume or remove the request.
- Request creation is logged.
