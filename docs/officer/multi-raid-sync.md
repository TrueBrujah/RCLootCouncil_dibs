# Multi-raid operation and synchronization

Each raid may have its own active relay and encounter context. Configure one authorized relay when reminders need to be broadcast, and keep officers aware of which guild bucket is active.

The `DIBS` channel synchronizes bounded guild accounting and Pre-Dibs revisions. It validates guild membership, sender authority, protocol version, request ownership, and transfer limits. A manifest/retry can recover a missed request. Duplicate transaction IDs are ignored through the seen-transaction store.

Synchronization never transfers items, live RC candidates, votes, or responses between raids. If two raids award items at the same time, each local RC workflow remains authoritative and only eligible accounting metadata is reconciled afterward.
