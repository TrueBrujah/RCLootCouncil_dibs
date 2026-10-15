# Private request contract

Add `requestDelivery=true` to protocol 2.1 capabilities, and `REQUEST_MESSAGE`
to WHISPER-only detail entities. Envelope chunk/count/size/TTL limits remain unchanged.
Payload kinds: submit, reply, snapshot, receipt. Every operation has bounded ID,
request ID, guild scope, revision and pinned authority epoch.

Submit/reply: actual sender must resolve to the claimed owner in the current guild;
receiver must be a current verified administrative coordinator. No ledger action.
Snapshot: sender must be current coordinator matching pinned epoch. Recipient must
be verified officer (full dossier) or the actual owner (explicit safe projection).
Receipt: matches pending operation, expected target and current authority; receipt
means accepted data, never conclusion. Rejection remains visible and recoverable.

Officers on other clients are read-only. Changed coordinator/epoch blocks mutation
of old delivered dossiers pending explicit safe recovery; no silent takeover.
Capability absent/offline recipient: pending/unsupported, no whisper attempt.
Developer Mode: neither sending nor receive acceptance touches production requests.
No private body, evidence, reply, or dossier travels on GUILD.
