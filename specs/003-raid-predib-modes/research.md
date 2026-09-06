# Research: Raid Pre-Dib Modes

## Decision: Use mode-aware request validation

- **Decision**: Store one guild-season mode: `WILD_OPEN` or `ENCOUNTER`. Validate every public request through the shared request pipeline before persistence.
- **Rationale**: This makes slash, player UI, and Adventure Guide requests consistent. `WILD_OPEN` accepts supported raid items in the active season; `ENCOUNTER` also requires verified current player raid and matching loot context.
- **Alternatives considered**: Per-surface checks were rejected because they create bypasses and conflicting results. Reusing Adventure Guide selection as player location was rejected because it can display a raid while the player is elsewhere.

## Decision: Synchronize persisted active requests by manifest and delta

- **Decision**: A reconnecting player advertises active request IDs and revisions. An eligible officer asks for only missing or stale records; the player sends compact records directly and receives acknowledgements.
- **Rationale**: It supports requests made before any officer is online, avoids whole-database broadcasts, preserves offline-first behavior, and is idempotent.
- **Alternatives considered**: Guild-chat announcements alone were rejected because offline officers cannot recover them. Full snapshots were rejected because they grow with a season and overwrite mutable request status. Treating a raid relay as a source of truth was rejected because multiple officers may operate independently.

## Decision: Version mutable request state separately from the ledger

- **Decision**: Requests carry a monotonic revision and delivery acknowledgement metadata. Existing IDs merge only when the incoming revision is newer; immutable request origin fields remain unchanged. Finalized fulfillment remains an authorized operation.
- **Rationale**: Pre-Dib status changes are mutable while ledger entries remain append-only. Stable request IDs alone cannot distinguish an old pending copy from a later fulfilled copy.
- **Alternatives considered**: Timestamp-only last-write-wins was rejected because client clock ordering is unreliable. Allowing player sync traffic to finalize awards was rejected because it bypasses authority.

## Decision: Chunk compact addon messages with bounded recovery

- **Decision**: Use versioned message types `HELLO`, `MANIFEST`, `FETCH`, `TRANSFER_BEGIN`, `TRANSFER_CHUNK`, `TRANSFER_END`, and `REQUEST_ACK`, with transfer IDs, checksums, expiry, bounded retries, and a maximum payload budget.
- **Rationale**: Addon messages are size-constrained and delivery may be reordered or duplicated. The protocol contains Dibs request state only.
- **Alternatives considered**: One unbounded serialized message was rejected because long seasons can exceed transport limits. Synchronizing live candidates, drops, votes, or sessions was rejected by the privacy boundary.

## Decision: Keep reminders and prompts non-authoritative

- **Decision**: Reminders are authorized raid chat messages. Players opt in to raid-entry prompts; accepting a prompt opens a relevant Adventure Guide view only after verifying the player remains in that raid. Boss-specific navigation is offered only after a boss is known.
- **Rationale**: These actions assist players without spending Dibs, granting loot, or making decisions for them.
- **Alternatives considered**: Automatic Journal opening was rejected because the feature is opt-in. Raid-warning delivery was rejected as the default because it requires stronger raid permissions than a normal reminder.

## Decision: Defer UI-only work during combat

- **Decision**: Queue only the latest eligible prompt or Journal navigation during combat and revalidate it after combat ends.
- **Rationale**: UI opening and frame refresh are non-critical and must respect combat safety. Request persistence and normal announcement behavior remain independent.
- **Alternatives considered**: Showing a popup from encounter-start was rejected because it can occur during combat.

## Decision: Extend authorization deliberately

- **Decision**: Mode changes and Dibs policy remain behind the verified guild Officer/GM action boundary. A current Raid Leader or verified RCLootCouncil Master Looter may send an in-raid reminder as a non-accounting loot-session action; that role never authorizes Dibs settings, mode, grants, removals, or ledger changes.
- **Rationale**: Current officer detection is too narrow for the stated reminder roles, while ledger authority must remain unchanged.
- **Alternatives considered**: Reusing reminder permissions for ledger changes was rejected because chat authority must not grant accounting authority.

## Decision: Derive request difficulty from the active mode

- **Decision**: In Wild Open, a Pre-Dib stores the Adventure Guide difficulty selected at submission. In Encounter mode, it stores the verified current instance difficulty, even when the Adventure Guide shows another difficulty.
- **Rationale**: This preserves a player's deliberate target when requesting early while preventing a mismatched Journal filter from creating an incorrect encounter reservation.
- **Alternatives considered**: Always trusting the Adventure Guide filter was rejected because it can differ from the raid being run. Always trusting the raid difficulty was rejected because Wild Open allows advance requests outside a raid.

## Decision: Record Great Vault ownership separately from Dib accounting

- **Decision**: Great Vault rewards are saved as informational acquisition records, keyed by player, item, difficulty, source, and time. They display as Acquired but never change request state or the ledger.
- **Rationale**: Vault ownership helps a player avoid requesting an item already acquired while preserving the rule that only a finalized qualifying Dib award consumes a Dib.
- **Alternatives considered**: Treating Vault as a finalized award was rejected because it would consume a Dib. Automatic Vault detection was rejected because the client cannot reliably establish all reward provenance without player confirmation.
