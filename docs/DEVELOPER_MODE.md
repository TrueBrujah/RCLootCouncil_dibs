# Developer Mode

## Purpose

Developer Mode allows local testing of the Dibs Request Dib workflow without requiring:

- Master Looter authority,
- raid/group context,
- real loot session events,
- RCLootCouncil command injection,
- any modification to RCLootCouncil source.

Developer Mode is an internal Dibs test adapter only.

## Commands

- /dibs dev on
- /dibs dev off
- /dibs dev status
- /dibs testitem <itemID>

Developer Mode is required for /dibs testitem.

## Typical local test flow

1. /dibs dev on
2. /dibs testitem 275658
3. Confirm the injected item appears in Player UI with DEV TEST marker.
4. Click Request Dib (DEV).
5. Confirm a test request is created.

## Safety guarantees

- Does not modify RCLootCouncil.
- Does not impersonate Master Looter.
- Does not send fake RC network messages.
- Does not emit production chat announcements for DEV test requests.
- Does not append production ledger transactions for DEV test requests.
- Does not rely on raid/group context.

## Data isolation

- DEV requests are marked with isTest = true.
- DEV requests are stored in runtime-only memory.
- DEV requests are not persisted as production pre-dibs.
- DEV requests are not written to the production ledger.

## Item loading behavior

The testitem command resolves item data with asynchronous-safe behavior:

- numeric item IDs are validated,
- item links with embedded item:ID are accepted,
- item cache misses are handled via async item loading when available,
- clean error messages are returned when loading fails.

Example failure:

[Dibs DEV] Unable to load item 275658

## Notes

Developer Mode is for development and validation only. It is not intended to replace normal raid loot workflows.
