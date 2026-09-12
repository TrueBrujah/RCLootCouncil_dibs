# Governance Bootstrap (B02a)

`Dibs.Identity` uses full Name-Realm as the canonical member key. Comparison
normalizes only for matching; each immutable snapshot also retains the display
Name-Realm and may carry a GUID witness. A GUID is never a routing key and never
causes an automatic name, realm, or alias merge.

The identity service resolves a short name only when the current guild roster
has exactly one matching member. Its explicit outcomes are `RESOLVED`,
`AMBIGUOUS_IDENTITY`, `UNKNOWN_ROSTER_MEMBER`, and `ROSTER_UNAVAILABLE`.
`GUILD_ROSTER_UPDATE` invalidates roster freshness; governance checks refresh
the roster immediately before every mutation.

`db.governance` is an additive schema-1 store. New and upgraded guild data stays
in `POLICY_UNINITIALIZED` with revision `0` and hash `GENESIS`. Existing local
settings remain local legacy behavior and are never promoted to governance.

Only the current Guild Master, validated from the live roster, can explicitly
adopt or change governance. A record contains its schema, guild key, revision,
parent revision/hash, Name-Realm author and identity snapshot, timestamp/audit
metadata, policy content, and deterministic content hash. The receiver accepts
the same revision/hash idempotently, reports same-revision/different-hash as a
conflict, and rejects an unavailable parent chain.

B02a deliberately persists only inactive future concepts:
`coordinator = nil`, `ledgerEpoch = nil`, `baseline = nil`, and
`protocolState = LEGACY_LOCAL`. It implements no operational-policy writer, no
coordinator, no distributed ledger write, no V2 sync, and no RCLootCouncil change.
Aliases are represented as an empty future GM-reviewed record collection; they
are never inferred automatically.
