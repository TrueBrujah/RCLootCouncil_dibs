# Developer documentation

Start with [architecture.md](architecture.md), then use the focused references:

These references describe current source, not a Retail certification report.
See the [README version status](../../README.md#downloads) for published versus
local builds. Dated audits and [the original coverage report](coverage.md)
are historical evidence.

Source-annotated concepts also produce [generated references](../generated/ui-reference.md).
Those outputs are not an exhaustive feature/API inventory and must not be edited
manually. From the repository root:

```powershell
.\scripts\Generate-DibsDocs.ps1 -Check
# After an intentional change to source documentation metadata:
.\scripts\Generate-DibsDocs.ps1 -Generate
```

The check detects annotation/locale errors and stale generated files, not
incorrect prose in hand-written guides. Compare affected guides with code,
callers, contracts, and tests when behavior changes. Keep missing screenshot
captures explicit; never substitute old evidence for current Retail checks.

- [modules.md](modules.md)
- [api-reference.md](api-reference.md)
- [data-model.md](data-model.md)
- [events.md](events.md)
- [saved-variables.md](saved-variables.md)
- [sync-protocol.md](sync-protocol.md)
- [rclc-integration.md](rclc-integration.md)
- [combat-safety.md](combat-safety.md)
- [naming-conventions.md](naming-conventions.md)
- [testing.md](testing.md)
- [releasing.md](releasing.md)
- [contributing.md](contributing.md)
- [coverage.md](coverage.md)
- [Midnight UI Design System](b12-ui-design-rules.md)
