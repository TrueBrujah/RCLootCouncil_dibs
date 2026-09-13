# B09 Retail validation checklist

RETAIL_RUNTIME_VALIDATION = PENDING_B10_RELEASE_GATE

Before promoting any real RCLootCouncil version into the B09 adapter matrix,
validate in Retail:

- Addon absent, disabled, late-loaded, and reloaded; Dibs core remains usable.
- Each proposed RC version/profile exposes the documented callback signature.
- Final award, pass/decline, unknown status, manually added history, correction,
  re-award, and duplicate callback behavior.
- Exact Name-Realm recipient and item identity behavior, including malformed and
  ambiguous data.
- Coordinator, non-coordinator, SYNC_BEHIND, handoff, unavailable, and recovery
  authority states with the B06 ledger.
- B08 combat projection behavior during a callback and after combat ends.
- No RC history mutation after creating or confirming a Dibs Pre-Dib.
- Unsupported RC versions report disabled automatic consumption while optional
  UI and standalone Dibs stay available.

Do not claim Retail adapter support until this checklist has evidence for the
specific profile/version added to `docs/developer/rclootcouncil-adapter-matrix.md`.
