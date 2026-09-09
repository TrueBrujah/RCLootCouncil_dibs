# Feature Specification: RCLootCouncil Item Mapping and Installation Assistant

**Feature Branch**: `010-rclootcouncil-item-mapping-assistant`

**Created**: 2026-09-09

**Status**: Implemented in `0.3.5`

**Input**: User description: "Align Dibs loot types with RCLootCouncil item families,
keep personal Catalyst out of Dibs, and provide a simple installation assistant that
preconfigures the Dibs response safely."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Understand and configure loot families (Priority: P1)

As a guild GM or Officer, I want Dibs loot types to use the same item concepts as
RCLootCouncil, so that I can configure Curios, Tier Set tokens, collections, and normal
loot without guessing which setting controls an item.

**Why this priority**: A wrong type mapping can either hide a valid Dibs action or allow
personal loot to consume a guild Dib.

**Independent Test**: Open the Dibs RCLootCouncil page with a profile containing the
RCLootCouncil additional-button families and verify that each family has a documented
Dibs meaning and policy path.

**Acceptance Scenarios**:

1. **Given** an RCLootCouncil profile contains Catalyst Items, Armor Token, Mounts,
   Pets, Recipes, Decor, Rare items, Items /w special effects, and equipment slots,
   **when** the mapping guide is opened, **then** every family is listed with its Dibs
   semantic meaning or its slot-only status.
2. **Given** a GM or Officer enables or disables a Dibs semantic family, **when** the
   same item is evaluated again, **then** the eligibility result follows that policy
   without changing the Dibs ledger.
3. **Given** an RCLootCouncil profile uses readable slot names such as Chest or Weapon,
   **when** the profile is displayed, **then** those names are recognized as compatible
   slot sets and do not become independent accounting families.

---

### User Story 2 - Classify items safely (Priority: P1)

As a player, I want the Dibs action to appear for eligible Curios and Tier Set tokens,
while personal Catalyst and cosmetic items remain excluded, so that the loot frame gives
me an accurate choice.

**Why this priority**: Classification is the boundary between a useful Dibs action and
an incorrect balance debit.

**Independent Test**: Evaluate representative Curio, Tier Set, Catalyst, cosmetic,
ordinary armor, weapon, mount, pet, recipe, and decor items under different policies.

**Acceptance Scenarios**:

1. **Given** a Context Token Curio, **when** the item is evaluated, **then** it belongs
   to the `TOKEN` family.
2. **Given** a class-based Tier Set or Armor Token, **when** the item is evaluated,
   **then** it belongs to `TOKEN_SET`, including when its broad item class is
   Miscellaneous.
3. **Given** a personal Catalyst or Cosmetic item, **when** the item is evaluated,
   **then** it cannot receive a Dibs action even when a broad catch-all policy is enabled.
4. **Given** ordinary armor, a weapon, or unclassified tradeable equipment has no more
   specific semantic family, **when** Standard loot is enabled, **then** it follows the
   configurable `OTHER` family.
5. **Given** a Mount, Pet, Recipe, or Decor item, **when** its family is enabled or
   disabled, **then** only that family policy changes its Dibs eligibility.

---

### User Story 3 - Complete first-time setup quickly (Priority: P1)

As a guild GM or Officer, I want a small installation assistant, so that I can select a
reasonable starting policy and prepare the Dibs button without manually rebuilding every
RCLootCouncil response set.

**Why this priority**: The first setup must be understandable during a raid preparation
without risking the guild's existing response configuration.

**Independent Test**: Run each assistant preset with RCLootCouncil available, absent, and
with additional response sets already enabled; compare policy, button readiness, and all
pre-existing response values before and after.

**Acceptance Scenarios**:

1. **Given** an authorized GM or Officer opens the assistant, **when** they choose
   `Curio + Tier Set`, **then** only `TOKEN` and `TOKEN_SET` are enabled for the starting
   Dibs policy and the Dibs response is prepared in the configured RCLootCouncil sets.
2. **Given** an authorized GM or Officer chooses `Standard loot + collections`, **when**
   the preset completes, **then** Curio, Tier Set, Mounts, Pets, Recipes, and Other are
   enabled while Decor remains disabled by default.
3. **Given** the Master Looter has additional RCLootCouncil sets enabled, **when** the
   assistant refreshes, **then** the Dibs response is available in the default and those
   already-enabled sets.
4. **Given** the assistant is run repeatedly, **when** the same preset or refresh is
   selected again, **then** no duplicate Dibs response is created and existing response
   text, colors, order, and slot selections remain unchanged.
5. **Given** RCLootCouncil is absent or unavailable, **when** the assistant applies a
   preset, **then** standalone Dibs remains usable and the response projection is retried
   when RCLootCouncil becomes available.
6. **Given** a normal player opens the same settings surface, **when** they attempt to
   apply a preset or refresh buttons, **then** the action is hidden or rejected and no
   policy or RCLootCouncil configuration changes.

## Edge Cases

- The RCLootCouncil profile contains a full response capacity; the assistant leaves all
  active responses intact and reports that the Dibs projection could not displace one.
- The profile uses an older alias or readable slot label; the mapping remains visible and
  the semantic policy is not silently changed.
- A Tier Set token has incomplete tooltip data but is present in the RCLootCouncil token
  table; it remains `TOKEN_SET` rather than falling through to Mounts or Other.
- Item metadata is unavailable, malformed, localized, or delayed; the action fails closed
  for personal or cosmetic categories and uses the documented fallback for ordinary loot.
- RCLootCouncil loads after Dibs or its profile changes later; the assistant status updates
  without resetting seasons, balances, Pre-Dibs, or history.
- A Dibs response is already present at a non-first position; the pair of button and
  response entries moves together and remains associated with the same non-Dibs response.
- An additional set is listed in the profile but is disabled; the assistant does not
  silently enable it.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST expose a Dibs semantic type list containing `TOKEN`,
  `TOKEN_SET`, `MOUNTS`, `PETS`, `RECIPE`, `DECOR`, `OTHER`, and a default fallback.
- **FR-002**: The system MUST classify a Retail Context Token as `TOKEN` using stable
  item metadata when available.
- **FR-003**: The system MUST classify a class-based Tier Set or Armor Token as
  `TOKEN_SET` using RCLootCouncil token data, tooltip evidence, or an equivalent stable
  signal.
- **FR-004**: The system MUST keep personal `CATALYST` and Cosmetic Items permanently
  ineligible for Dibs, Pre-Dibs, policy enablement, and ledger consumption.
- **FR-005**: The system MUST map RCLootCouncil Mounts, Pets, Recipes, and Decor groups
  to their corresponding independently configurable Dibs families.
- **FR-006**: The system MUST map RCLootCouncil Rare items and Items /w special effects
  to the configurable `OTHER` family.
- **FR-007**: The system MUST route ordinary armor, weapons, and otherwise unclassified
  tradeable equipment through `OTHER` when no more specific semantic family is present.
- **FR-008**: The system MUST treat RCLootCouncil equipment-slot groups as response
  routing hints that inherit semantic eligibility and MUST NOT create separate Dibs
  accounting families.
- **FR-009**: The system MUST show an in-game mapping guide that reports semantic,
  blocked, resolved, alias, and slot-only associations.
- **FR-010**: The Installation assistant MUST provide a Curio + Tier Set preset and a
  Standard loot + collections preset.
- **FR-011**: Applying an assistant preset MUST require verified Dibs GM/Officer settings
  authority and MUST update Dibs policy without writing a ledger transaction.
- **FR-012**: The assistant MUST prepare the dedicated Dibs response in the default
  RCLootCouncil set and additional sets already enabled by the Master Looter.
- **FR-013**: Button projection MUST be repeatable and MUST preserve existing response
  text, colors, order, slot selections, and active responses.
- **FR-014**: When a response set has no capacity, the assistant MUST leave the existing
  configuration unchanged and report that the dedicated response could not be inserted.
- **FR-015**: The assistant MUST remain usable in standalone mode and MUST retry projection
  after a late RCLootCouncil load or profile availability change.
- **FR-016**: The mapping and assistant MUST not modify RCLootCouncil source code, live
  loot-session authority, candidates, votes, history, or cross-raid data.
- **FR-017**: All assistant controls, mapping labels, policy names, and status messages
  MUST provide concise localized help text with an English fallback.

### Key Entities

- **Dibs Semantic Loot Family**: A policy category such as `TOKEN`, `TOKEN_SET`,
  `MOUNTS`, `PETS`, `RECIPE`, `DECOR`, or `OTHER`, with an enabled state in the current
  guild and season context.
- **RCLootCouncil Button Set**: A default or additional response set that may be a
  semantic family, a resolved item-dependent group, an alias, or an equipment-slot group.
- **Item Classification Result**: A stable family decision plus the evidence and fallback
  reason used when the item is evaluated.
- **Installation Preset**: A named starting policy and its expected button-projection
  behavior.
- **Projection Status**: Read-only readiness information for the default and enabled
  additional RCLootCouncil response sets.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of the mapping acceptance corpus classifies Curio, Tier Set, Catalyst,
  Cosmetic, Mount, Pet, Recipe, Decor, ordinary armor, and weapon examples according to
  the documented family rules.
- **SC-002**: 100% of personal Catalyst and Cosmetic examples remain ineligible even when
  `OTHER` or the broad RCLootCouncil Catalyst Items group is enabled.
- **SC-003**: A GM or Officer can choose a starting preset and understand its readiness
  status in under one minute during a normal first setup.
- **SC-004**: Repeating either assistant preset or the refresh action produces zero
  duplicate Dibs responses across the default and enabled additional sets.
- **SC-005**: In projection tests, 100% of pre-existing RCLootCouncil response values,
  order, slot choices, and active entries remain unchanged except for the dedicated Dibs
  insertion or an explicit paired move of an existing Dibs entry.
- **SC-006**: A full-capacity response set produces zero overwritten user responses and a
  clear readiness or capacity status.
- **SC-007**: Standalone tests pass with RCLootCouncil absent, and late-load tests prepare
  the response after RCLootCouncil becomes available without changing Dibs balances or
  history.
- **SC-008**: The automated suite contains zero failed tests after the feature changes,
  including ordinary-equipment fallback, Armor Token disambiguation, Cosmetic blocking,
  readable slot labels, and assistant controls.

## Assumptions

- RCLootCouncil remains optional and authoritative for its own loot-session responses and
  awards; Dibs remains authoritative for Dibs balances and history.
- The assistant intentionally prepares the default set and additional sets already
  enabled by the Master Looter. It does not silently enable new RCLootCouncil sets.
- The RCLootCouncil token table and stable item metadata are preferred evidence; tooltip
  text and semantic fallback are used only when needed.
- `OTHER` is a configurable catch-all for normal tradeable loot and RCLC alias groups;
  it does not override personal or cosmetic exclusions.
- The feature is guild-scoped, uses existing Dibs SavedVariables, and does not add
  account-alt discovery, historical reconciliation, or character eligibility tracking.
