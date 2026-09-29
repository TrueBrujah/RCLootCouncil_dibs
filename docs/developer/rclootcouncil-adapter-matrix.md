# RCLootCouncil award-adapter matrix

RCLootCouncil is an optional evidence provider. It is never a Dibs ledger,
policy, governance, or coordinator authority. The adapter accepts only a
profile listed here; unknown means no automatic Dib consumption.

| Profile | RC version marker | Callback | Final status | Award evidence | History policy |
| --- | --- | --- | --- | --- | --- |
| `DIBS_RCLC_AWARD_TEST_V1` | `DIBS_TEST_RCLC_AWARD_V1` | `RCMLAwardSuccess(session, winner, status, itemLink, response)` | `awarded` only | Available for automated fixture tests | Read-only; not an identity fallback |
| `DIBS_RCLC_RETAIL_3_23_3` | Addon TOC metadata `3.23.3` | `RCMLAwardSuccess(session, winner, status, itemLink, response)` | `normal` only | Pilot candidate; requires the matching post-callback history ID | Read-only; the history ID is used only as evidence identity |
| Any other Retail or unknown profile | any other or absent marker | none accepted | none accepted | Unsupported / fail closed | Read-only projection only |

The fixture profile requires both the exact version marker and the explicit
profile marker, a message-registration surface, and a stable RC session id.
It exists to exercise the boundary without claiming support for a real
RCLootCouncil release.

The 3.23.3 pilot profile is selected only by exact addon TOC metadata and the
RCLC Master Looter module surface. It accepts direct `normal` awards only,
waits until the callback returns, then requires a new history ID whose item
and DIB response match the callback. Missing or mismatched history and rows
with prior history fail closed. This candidate is for controlled Retail
validation only and is not production approval.

`indirect`, `manually_added`, corrections, re-awards, trade-pending states,
unknown callbacks, malformed item links, and ambiguous recipient names are not
final evidence. They remain manual reconciliation matters. `normal` is accepted
only by the exact 3.23.3 candidate profile.

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

The 3.23.3 profile is a pilot candidate, not an approved production release.
Do not claim Retail support or use it for production loot until the live
checklists contain evidence for the exact profile/version.
