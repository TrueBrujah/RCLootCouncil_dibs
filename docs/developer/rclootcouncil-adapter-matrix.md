# RCLootCouncil award-adapter matrix

RCLootCouncil is an optional evidence provider. It is never a Dibs ledger,
policy, governance, or coordinator authority. The adapter accepts only a
profile listed here; unknown means no automatic Dib consumption.

| Profile | RC version marker | Callback | Final status | Award evidence | History policy |
| --- | --- | --- | --- | --- | --- |
| `DIBS_RCLC_AWARD_TEST_V1` | `DIBS_TEST_RCLC_AWARD_V1` | `RCMLAwardSuccess(session, winner, status, itemLink, response)` | `awarded` only | Available for automated fixture tests | Read-only; not an identity fallback |
| Any Retail or unknown profile | any other or absent marker | none accepted | none accepted | Unsupported / fail closed | Read-only projection only |

The fixture profile requires both the exact version marker and the explicit
profile marker, a message-registration surface, and a stable RC session id.
It exists to exercise the boundary without claiming support for a real
RCLootCouncil release.

`normal`, `indirect`, `manually_added`, corrections, re-awards, trade-pending
states, unknown callbacks, malformed item links, and ambiguous recipient names
are not final evidence. They remain manual reconciliation matters.

The normalized record contains the adapter profile/version, callback, semantic
status, Name-Realm recipient, item link/id, deterministic session evidence id,
and provenance. Raw RC tables never enter Dibs canonical state. Duplicate
identical evidence is idempotent; the same evidence id with different normalized
content is retained as a conflict and does not consume a second Dib.

RCLootCouncil history is a read-only projection. Dibs no longer writes Pre-Dib
rows through `OnHistoryReceived` or `GetHistoryDB`; existing `dibsOrigin`
records are preserved as display-only legacy evidence.

Late load uses the B07 `rclootcouncil` capability retry. The optional UI
projection can remain available while award evidence is unsupported. B08 owns
its combat-safe UI scheduling and is not changed by the adapter.

RETAIL_RUNTIME_VALIDATION = PENDING_B10_RELEASE_GATE

No actual Retail RCLootCouncil version is approved for automated award evidence
until a release profile is added here after live validation.
