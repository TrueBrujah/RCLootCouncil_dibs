# B13 Retail Validation Checklist

Status: pending one-client Retail execution.

Automated Fengari evidence is recorded in
[B13_Implementation_Evidence.md](B13_Implementation_Evidence.md); it does not
replace these client checks.

## Environment

- [ ] Record addon version and Retail client build.
- [ ] Test with RCLootCouncil absent or unavailable.
- [ ] Test with RCLootCouncil loaded in the supported integrated mode.
- [ ] Record character, guild, season, and active weekly reset context.

## Great Vault detection

- [ ] Opening the Great Vault creates no confirmed acquisition.
- [ ] Viewing a reward choice creates no confirmed acquisition.
- [ ] Claiming one reward with a supported Retail signal creates exactly one
      `AUTOMATIC_CONFIRMED` record with item, character, source, timestamp, and
      reset context.
- [ ] Repeating the claim observation does not create a duplicate.
- [ ] An unavailable or ambiguous Retail signal reports manual-only or review
      status and does not create an automatic confirmation.

## Manual fallback and ledger boundary

- [ ] `/dibs vault <itemID> [difficulty]` creates one labeled manual record.
- [ ] Repeating the command is idempotent.
- [ ] The player view shows status, source, reset, sync state, and eligibility
      explanation without private evidence.
- [ ] Balance, ledger history, and request fulfillment remain unchanged.

## Lifecycle and safety

- [ ] Reload preserves the acquisition without duplication.
- [ ] Reconnect recovery does not duplicate the acquisition.
- [ ] The command and review windows defer safely during combat.
- [ ] The Officer Vault Review view shows bounded records and requires a reason
      for a decision.
- [ ] A missing or malformed Retail API path leaves local manual recording
      available.

## Evidence

Record screenshots, exact observed callback/event names, item IDs, reset IDs,
and any unavailable API details here after the Retail run:

- Client/build:
- Character/guild:
- Claim result:
- Manual fallback result:
- Reload/reconnect result:
- Screenshots:
- Notes:
