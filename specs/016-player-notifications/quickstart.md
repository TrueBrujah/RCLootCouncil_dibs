# Quickstart: Player Notifications

1. Load the addon on a test character and create or confirm a local Pre-Dib.
2. Confirm the local chat message appears once.
3. Repeat the same lifecycle callback or reload the UI and replay the same event identity.
4. Confirm no duplicate message appears.
5. Disable notifications through the local notification setting/API and repeat an event.
6. Confirm that another player's request or acquisition creates no local message.

Automated validation:

```powershell
$env:DIBS_TEST_FILES='tests/contract/notifications_contract_spec.lua;tests/integration/notifications_wiring_spec.lua'; npx.cmd --yes fengari tests/run.lua
```

Retail validation remains mandatory for visible chat behavior and reload behavior.
