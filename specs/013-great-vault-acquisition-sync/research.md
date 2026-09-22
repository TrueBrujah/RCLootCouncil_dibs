# Research: Great Vault Acquisition Tracking and Guild Sync

**Feature**: `013-great-vault-acquisition-sync`
**Date**: 2026-09-21

## Decision 1: Capability-aware detection with a manual fallback

**Decision**: Treat automatic Great Vault claim detection as an optional runtime capability. The adapter may observe supported Retail reward/update signals only when it can prove item identity and a completed claim. `/dibs vault <itemID> [difficulty]` remains the supported fallback and produces a manual record.

**Rationale**: The repository currently has no Great Vault adapter, and a reliable claim event cannot be assumed across Retail client builds. Opening the Great Vault or displaying a reward choice is not proof that the reward was claimed. A capability probe plus manual fallback avoids false confirmed acquisitions.

**Alternatives considered**:

- Treat every Vault update as a claim: rejected because it can count unclaimed choices.
- Depend on one undocumented event name: rejected because client behavior and availability may vary.
- Remove the manual command: rejected because it would make the feature unusable when the API is unavailable.

## Decision 2: Reuse the existing Pre-Dibs acquisition collection

**Decision**: Store Great Vault records in the existing guild-scoped acquisition collection owned by `PreDibs`, extending the record with verification, reset, evidence, and synchronization metadata. Do not create a second Vault database.

**Rationale**: `PreDibs.RecordVaultAcquisition` and the player/officer acquisition views already provide the closest ownership boundary. Keeping one collection lets `CharacterEligibility` consume the same acquisition history and preserves existing records.

**Alternatives considered**:

- Add a separate `greatVault` database: rejected because it would duplicate acquisition rules and complicate migration and deduplication.
- Store Vault records in the Dibs ledger: rejected because a Vault claim is not a Dib grant or consumption.
- Store records in RCLootCouncil SavedVariables: rejected because RCLootCouncil is optional and cannot own Dibs state.

## Decision 3: Confirmed status controls eligibility

**Decision**: Automatic records with sufficient claim evidence and records explicitly confirmed by a verified GM/Officer may count for protected-loot eligibility. Manual, legacy, unverified, and reference-only records remain visible but follow the configured unknown-data behavior until resolved. Rejected records never count.

**Rationale**: This preserves fairness while allowing guilds to review uncertainty instead of silently blocking or granting priority.

**Alternatives considered**:

- Count all manual records immediately: rejected because a typo or false report could block a player.
- Ignore all uncertain records: rejected because it hides evidence and can grant an unfair duplicate.
- Let synchronization upgrade confidence: rejected because transport cannot create proof that the sender did not possess.

## Decision 4: Extend existing SyncV2 semantics, not transport

**Decision**: Represent Vault synchronization with bounded logical entities and reuse the existing `DIBS` transport, guild envelopes, digest/detail requests, chunk limits, sender validation, replay protection, and `SyncV2` governance. Logical meanings are `VAULT_DIGEST`, `VAULT_FETCH`, `VAULT_DETAIL`, and `VAULT_ACK` or equivalent result codes.

**Rationale**: The existing protocol already rejects live loot data, verifies guild identity, supports digest-driven recovery, and uses bounded detail transfers. A parallel transport would create conflicting security and recovery behavior.

**Alternatives considered**:

- Broadcast the complete SavedVariables database: rejected for privacy, size, and recovery safety.
- Add a second addon prefix: rejected because it would bypass existing validation and increase protocol surface.
- Synchronize only through RCLootCouncil: rejected because standalone Dibs must remain functional.

## Decision 5: Additive guild schema migration

**Decision**: Add the minimum new acquisition and sync metadata through an additive guild schema migration from the current guild version 6 to version 7. Existing records retain their identity, source, item, and timestamps; missing confidence fields are classified as legacy/manual rather than upgraded.

**Rationale**: The current persistence path already performs versioned guild migration and creates `preDibs.acquisitions`. An additive migration is compatible with existing data and keeps recovery behavior explicit.

**Alternatives considered**:

- Rewrite all existing acquisition records as automatic: rejected because it invents evidence.
- Rebuild the whole database: rejected because it risks unrelated ledger and guild data.
- Leave old records structurally untouched with no compatibility projection: rejected because new eligibility and sync code needs an explicit status.

## Decision 6: Privacy-filtered projections

**Decision**: Full evidence is available to verified GM/Officer clients after guild and authority validation. A normal player receives their own acquisition details and configured safe summaries only. Digests contain bounded identities, revisions, and hashes rather than full private evidence.

**Rationale**: The constitution requires guild and character isolation and limits diagnostic/sync disclosure. Eligibility can still be explained without exposing another player's private evidence.

**Alternatives considered**:

- Send full history to every guild member: rejected for privacy and unnecessary payload size.
- Hide all synchronized status from players: rejected because players need to understand their own eligibility.
- Use a cloud service: rejected by scope, privacy, and repository ownership constraints.

## Decision 7: Layered validation

**Decision**: Cover domain, migration, privacy, replay, and protocol contracts in Fengari tests. Reserve actual Retail Great Vault signal discovery, protected UI behavior, roster identity, and two-client delivery for manual validation.

**Rationale**: The test harness can prove deterministic state transitions and message rejection, but it cannot prove undocumented client events or real addon-chat behavior.

**Alternatives considered**:

- Claim full automatic API coverage in unit tests: rejected because WoW event availability must be verified in Retail.
- Make Retail validation optional: rejected because false claim detection is a release-blocking risk.
