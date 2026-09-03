# Research: RCLootCouncil Permission Authority

## Decision 1: RC-first exclusive authorization when available

- Decision: Use RCLootCouncil authority as first and exclusive source whenever RC is present and evaluable.
- Rationale: Prevents standalone fallback from bypassing raid authority.
- Alternatives considered: Hybrid allow-by-either was rejected because it violates deny precedence requirements.

## Decision 2: Fail closed for degraded RC states

- Decision: If RC appears present but authority is malformed/unverifiable, deny protected actions.
- Rationale: Security and integrity over availability in authority checks.
- Alternatives considered: Treating degraded as absent was rejected because it risks unauthorized writes.

## Decision 3: Protected mutation façade

- Decision: Route authoritative writes through `ProtectedActions.Execute` and `FinalizeAward`.
- Rationale: Centralized enforcement avoids hidden direct-write paths.
- Alternatives considered: Distributed checks in each UI/module call site were rejected as fragile.

## Decision 4: Dibs-owned accounting and idempotent award linkage

- Decision: Keep ledger authoritative and map finalized awards to one transaction using `awardRef`.
- Rationale: Enables deterministic rebuild without RC historical dependencies.
- Alternatives considered: RC-derived reconstruction was rejected to preserve optional integration.

## Decision 5: Local candidate projection with privacy guardrails

- Decision: Expose Dibs status for local candidates only and exclude live candidate/session data from sync payloads.
- Rationale: Supports council decisions while respecting multi-raid privacy.
- Alternatives considered: Syncing live candidates/votes was rejected by constitutional constraints.
