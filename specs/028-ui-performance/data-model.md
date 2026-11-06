# Data Model: UI Rendering and Data Read Performance

No persistent entity or SavedVariables schema is introduced.

The grouped ledger read accepts an ordered list of player names or compact
member descriptors and returns one history summary per input index. It reads
the existing selected ledger and season, uses the existing bounded per-player
summary cache, and does not mutate transactions, balances, or revision state.

Any future Wizard/Sync projection cache is transient runtime state only. It
must have a bounded lifetime or weak-key ownership, explicit source revision
keys, and mutation-driven invalidation. A cache without those properties is
not part of this design.
