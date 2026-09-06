# Contract: Difficulty and Vault Acquisition

## Request Difficulty

- Every new Pre-Dib contains `difficulty` when the client can identify it.
- In `WILD_OPEN`, `difficulty` is the Adventure Guide selection at submission time.
- In `ENCOUNTER`, `difficulty` is the verified current raid instance difficulty at submission time.
- A visible Adventure Guide selection must not override actual raid difficulty in `ENCOUNTER`.
- Active request identity includes player, item, season, and difficulty.

## Vault Acquisition

- A Vault acquisition record contains stable player and item identity, known difficulty, source `VAULT`, and acquisition time.
- It appears as `Acquired` in relevant Adventure Guide and officer views.
- It is informational only: it never invokes a protected ledger action, consumes a Dib, fulfills a request, or prevents a future request.
- When provenance cannot identify difficulty, the record is stored as `UNKNOWN` and remains informational.
