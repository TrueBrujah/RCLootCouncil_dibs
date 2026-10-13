# Contract: Officer Governance and Setup Empowerment

**Feature**: `020-multi-ledger-independent-raid`
**Date**: 2026-10-12
**Layer**: Governance / Setup (`Dibs.Permissions`, `Dibs.Installation`, `Dibs.Governance`)

## 1. Permission Model Adjustments (`Dibs.Permissions`)

### 1.1 Actions Reclassified from GM-Only to Officer & GM (`ADMIN_ACTIONS`)

In accordance with Constitution Principle XI, the following actions are permitted for both verified Officers and the Guild Master:

- `settings.modify`: General Dibs settings adjustments.
- `season.create`: Creation and configuration of new seasons.
- `season.set`: Switching or activating a season.
- `rank.set`: Configuring rank-based point allocations.
- `installation.mode.set`: Switching between AUTO and STANDALONE modes.
- `predib.public.set`: Enabling or disabling public Pre-Dib visibility.
- `ledger.propose`: Proposing a new guild ledger instance.
- `installation.run`: Executing the Guided Setup wizard and baseline discovery.

For Guild Loot Rules, `settings.modify` permits verified officers to edit the local
draft and apply Dibs loot-policy presets. Adoption and publication of the shared
guild-wide policy remain Guild Master-only.

### 1.2 Actions Remaining Strictly Guild Master Only (`GM_ONLY_ACTIONS`)

The following actions strictly require verified Guild Master authority (rank 0) to prevent split-brain roots or unauthorized structural cutovers:

- `ledger.approve`: Officially authorizing a proposed guild ledger for guild-wide synchronization.
- `ledger.revoke`: Revoking an approved guild ledger.
- `ledger.archive`: Archiving an approved guild ledger.
- `governance.cutover`: Enforcing V2 distributed protocol cutover across the entire guild.
- `admin.appoint`: Appointing or revoking standalone administrative privileges.

---

## 2. Installation Module Adjustments (`Dibs.Installation`)

### 2.1 `Dibs.Installation.GetStatus(actor)`
- Updated to distinguish between `isOfficer` and `isGM`.
- The `blockers` list omits `GUILD_MASTER_REQUIRED` if the actor is a verified Officer or GM.
- If the actor is an Officer and no approved governance baseline exists, a warning `GM_CONFIRMATION_PENDING` is added rather than a fatal blocker.

### 2.2 `Dibs.Installation.Initialize(actor, options)`
- When executed by an **Officer**:
  - Validates officer authority via `Dibs.Permissions.IsOfficer()`.
  - Performs legacy discovery and baseline synthesis.
  - Proposes the initial or target guild ledger (`PROPOSED` state).
  - Returns `{ ok = true, reasonCode = "PROPOSAL_CREATED", status = ... }`.
  - Raid environment is prepared locally and can be tested.
- When executed by the **Guild Master**:
  - Retains full cutover and immediate approval capability.
  - Sets ledger state directly to `APPROVED`.
  - Returns `{ ok = true, reasonCode = "INITIALIZED", status = ... }`.
