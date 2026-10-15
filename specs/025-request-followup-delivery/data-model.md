# Data model

Guild `disputes.version=2` preserves requests/order/corrections and legacy IDs/statuses.
Each request adds monotonically increasing `revision`, optional `assignedTo`,
`followUpAt`, `deliveryAuthority={memberKey,epoch}`, and additive Closed/Archived.
Original evidence, replies, timeline and correction links remain retained.
Audit capacity is checked before any mutation/accounting append.

Per-character `requestDelivery[guildKey]` contains bounded pending operations keyed
by operation ID, delivery states keyed by request ID, replay receipts, and reminder
state. Operations carry kind, request ID, revision, authority epoch, safe body and
target. Receipt removes pending work only after matching current verified sender.
Saved receipt state prevents repeated acceptance after reload.

Transitions: existing Open/Under review/Need information -> Resolved or Rejected
-> Closed -> Archived. Close/archive require explicit reasons. Reopen is allowed
only without any prior linked compensation. Lifecycle/thread actions are data-only.
Archived dossiers remain searchable; no retention garbage collection is introduced.
