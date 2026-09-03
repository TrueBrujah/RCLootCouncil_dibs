# Contract: RCLootCouncil Adapter

Adapter responsibilities:

1. Detect availability (`absent`, `operational`, `degraded`).
2. Evaluate RC authority against current Master Looter identity.
3. Observe finalized local award events and forward to protected finalize path.
4. Expose candidate status projection and DIB response eligibility checks.

Adapter non-responsibilities:

- No edits to RC core files.
- No ownership of Dibs balances/history.
- No cross-raid sync of live RC session state.
