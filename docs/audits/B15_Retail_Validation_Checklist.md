# B15 Retail Validation Checklist

Status: `PENDING_MANUAL_RETAIL_VALIDATION`

Candidate: `0.6.4-dev`

- [ ] Open Diagnostics as GM and confirm all health checks are readable.
- [ ] Open Diagnostics as Officer and confirm the same bounded report is available.
- [ ] Open Diagnostics as a normal player and confirm administrative health details are denied.
- [ ] Disable or omit RCLootCouncil and confirm `Unavailable` is shown without implying live readiness.
- [ ] Exercise a degraded/read-only persistence state and confirm it is not presented as healthy.
- [ ] Refresh and reopen Diagnostics during and after combat without protected-frame or lifecycle errors.
- [ ] Confirm the technical disclosure contains status metadata only and no player names, ledger rows, or raw payloads.
- [ ] Confirm the existing debug report remains available below the health dashboard.

Automated Fengari evidence does not certify these Retail behaviors.
