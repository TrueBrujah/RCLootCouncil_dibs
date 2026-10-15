# Auditing and historical review

Use the Officer history and Data windows for read-only inspection of balances, requests, transactions, backups, profiles, disputes, and RC evidence. Dates are stored as Unix timestamps and should include the source date/time when available; a zero timestamp is missing data, not a valid award date.

For an RC history reconciliation:

1. Open the history view and select the candidate row.
2. Inspect winner, original owner, item, response, final status, award time, and evidence references.
3. Open the separate transfer/confirmation action, enter an annotation that explains the decision, and confirm it.
4. Confirming records an auditable historical award; rejecting leaves the candidate unconsumed.

Disputes use explicit review, information-request, no-correction, balance-correction, target-correction, resolve, and reopen actions. Corrections append evidence and new accounting records; they do not rewrite old transactions. Create a safety backup before restore/import and keep the checksum with the audit record.

Development 0.8.8 adds reasoned Resolved/Rejected -> Closed -> Archived stages.
These preserve the original stored dossier, full audit and correction links;
archives remain searchable. Capacity is explicit (500 dossiers / 120 events):
no terminal pruning or timeline truncation is performed. Previously truncated
history cannot be reconstructed. Corrected dossiers cannot be reopened to repeat
their compensation. Shared requests require the verified pinned coordinator/epoch
for all mutations; other officers inspect private read-only replicas.
