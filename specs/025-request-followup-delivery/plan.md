# Implementation Plan: Request follow-up and delivery

**Date**: 2026-10-15 | **Spec**: [spec.md](spec.md)

## Summary
Extend Disputes and its existing Player/Officer views. Add private request operations
and acknowledgements on the bounded SyncV2 detail transport. A durable per-guild,
per-character outbox retries online capable peers. Delivered dossiers are writable
only on the current verified coordinator and pinned epoch; replicas are read-only.

## Technical Context
WoW Retail Lua, Ace3 serialization, existing SavedVariables/Identity/Governance/
ProtectedActions/Notifications. Fengari integration and contract suites; Windows
PowerShell runner. No dependencies, external servers, new accounting policy or
RCLootCouncil core changes. Existing queue/detail workflow is the UI reference.

## Constitution Check
Pass: I combat/UI guards retained; IV immutable compensations retained; V private
owner projection; VII optional RC; X replay-safe operations and explicit offline
pending; XI actual sender/roster authority; XIII additive migration; XV developer
transport isolation; XIX dated change note and 0.8.8-dev consistency.
Post-design: no justified exceptions. Unproven coordinator handoff fails closed.

## Project Structure
- `src/modules/Disputes.lua`: retained audit, revision, follow-up and lifecycle.
- `src/modules/RequestDelivery.lua`: durable queue, receive validation, reminders.
- `src/modules/SyncV2.lua`: additive capability/private entity and lifecycle pump.
- Existing PlayerUI/OfficerUI, locales, loader/TOC and focused tests.

## Implementation Sequence
1. Retention/lifecycle and follow-up with boundary tests.
2. Private persisted delivery, safe projection, coordinator fencing and simulated clients.
3. Existing UI controls and localized states.
4. Regression slices, documentation and manual Retail gates.

## Scope Safety
Remote officers receive private read-only queue replicas. They must use the
coordinator client for mutations; no distributed correction RPC is introduced.
Epoch handoff recovery is explicitly blocked rather than risking double correction.
Transport oversize errors retain pending work and never truncate original dossiers.
