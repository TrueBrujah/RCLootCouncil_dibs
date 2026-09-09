# Research Notes: Character Loot Eligibility and Main/Alt Governance

**Research date**: 2026-09-07

## Findings from public guild rules

The closest public example found is a May 9, 2025 loot policy published by the guild
Still Alive on Guilds of WoW:

- Main-spec need has priority over off-spec and alt rolls.
- Tier loot is limited to one piece until everyone sharing the token has received one,
  explicitly including all difficulties.
- Alts are restricted until a progression milestone and then are generally limited to
  off-spec; an officer-requested role exception is allowed.
- A main change requires officer approval, a gear-readiness condition, and a two-week
  probation during which the new character is limited to off-spec, with an exception for
  filling a missing role.
- Dibs are announced before the boss pull and a used Dibs is consumed only by the player
  who wins the item.

Source: [Still Alive loot rule](https://guildsofwow.com/still-alive/post/12493/loot-rule).

This is one guild's published policy, not an industry standard. It confirms that the
requested pattern is used in practice, but the addon must keep the duration, difficulty
scope, alt treatment, and exceptions configurable rather than hard-coded.

The same policy also implies a useful round-robin model for this feature: a late-arriving
member with no Tier piece should be prioritized until they reach the group's current
minimum, after which the next piece round can open for the group. This is an interpretation
for the addon, not a claim that the source guild uses an automated tracker.

An older public Ohana Gaming policy shows a related pattern: alt bids are placed below
guild off-spec bids, alts may receive compensation when they fill a needed raid role, and
promotion from alternate to guaranteed raider uses a two-week attendance minimum with an
exception for immediate composition needs.

Source: [Ohana Gaming DKP / Loot Rules](https://www.ohanagaming.com/guild-rules/dkp-loot-rules),
especially the loot priority and guaranteed-raider sections. This is a Classic-era DKP
policy, so it is evidence of a common governance pattern rather than a direct rule for
the current addon.

## Game-system constraints relevant to the design

Blizzard's Warband documentation says that many collections and progression systems are
account-wide, but it also distinguishes account-wide collection from character-specific
gear use and class-specific restrictions. The addon therefore must not assume that a
visible collection state is the same as a guild loot entitlement.

Source: [Blizzard: Get the Band Together for Warbands](https://worldofwarcraft.blizzard.com/en-us/news/24115313/get-the-band-together-for-warbands).

Public current-game guidance also notes that newer raids commonly have separate loot
opportunities by difficulty and that Tier Set appearance rules can span difficulties in
ways that differ from actual item eligibility. This supports making the guild's
cross-difficulty rule an explicit policy setting rather than deriving it from the game
lockout or transmog system.

Source: [Wowhead raid lockout and transmog guide](https://www.wowhead.com/guide/legacy-raid-guide-loot-lockouts-raid-skips-lfr-access-and-transmog-23879).

## Design conclusions

1. Track a stable loot family plus exact item and difficulty context. Item ID alone is
   not sufficient for Tier Set tokens, Curio upgrade variants, or future item families.
2. Model Tier Set fairness as configurable class/token groups with a lowest-progress
   round. A new eligible member must catch up before the group opens the next round.
3. Treat Curios as a non-class guild pool with an explicit completion status, defaulting
   to 4/4 slots, and a separate rule for stronger Mythic or upgrade-track items.
4. Make the default Tier Set policy shared across configured difficulties, matching the
   closest public guild example, but expose same-difficulty and custom scopes.
5. Treat a main/alt relationship as an explicit, officer-approved guild record. An addon
   cannot safely infer a player's complete Battle.net account or every alt from the local
   character alone.
6. Make the default main-change probation 14 days and keep the probation outcome and
   emergency role exception configurable and audited.
7. Count only finalized awards or explicit Officer/GM historical confirmations. Pending
   votes, unverified messages, traded items, and collection appearances do not silently
   become guild acquisition records.
8. Keep player-facing explanations narrow and officer-facing history complete. This
   prevents an alt policy from becoming an unintended account-identity disclosure.
9. Preserve the Adventure Guide's semantic item categories in the policy model:
   Curios map to `TOKEN`, class-based Tier Set tokens map to `TOKEN_SET`, and
   `CATALYST` stays outside Dibs because Catalyst progress is personal to each
   player. Equipment slots are only a compatibility projection for RCLootCouncil
   buttons and must not define the protected-loot family.

## Questions deferred for planning

- Which current raid item families should be included in the initial Curio and Tier Set
  catalog, and how should each family map across upgrade tracks?
- Should the default probation outcome be strict no-protected-loot or off-spec-only for
  the guild's first rollout? The specification selects strict no-main-spec protected
  loot while allowing the policy to be changed.
- Which manual evidence is sufficient for importing acquisitions from before the feature
  was enabled (RCLootCouncil history, officer confirmation, or both)?
