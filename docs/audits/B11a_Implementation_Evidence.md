# B11a Implementation Evidence

## Scope and commits

- Branch: `dev`
- `B11A_START_COMMIT=21fbe8b8bbfc84ef79f8e6e721f242cb6ee88308`
- `B11A_CHECKPOINT_COMMIT=21fbe8b8bbfc84ef79f8e6e721f242cb6ee88308`
- `B11A_RESULT_COMMIT=e66dc5723c6098772128950a5bf6b42d1e12e88b`

This pass implements only B11a / US1 Midnight UI Foundation. It does not implement
Developer Sandbox, player or Officer redesigns, request/eligibility workflows, RC
reconciliation UX, responsive/accessibility polish, production authority changes, or
SavedVariables guild-schema changes.

## Completed task IDs

- T001, T003
- T005-T007, T010
- T013-T019

Tasks T002, T004, T008-T009, T011-T012, T020-T064 remain open unless explicitly
completed by a later B11 implementation pass.

## Implementation evidence

- `src/ui/Midnight.lua` defines the single Midnight theme, semantic colors, typography,
  spacing, sizing, surfaces, contrast, bounded local scale, reusable panels/status/empty
  state/modal helpers, and safe native media fallbacks.
- `src/ui/EnvironmentAdapters.lua` probes optional ElvUI, Tukui, EllesmereUI, and
  BenikUI-family presentation providers, accepts only allowlisted presentation hints, and
  returns native Midnight on absence, unsupported values, or probe failure.
- `src/ui/WindowState.lua` keeps window position/scale under the per-character local
  presentation root and uses LibWindow when available.
- `src/ui/AceGUI.lua` applies resolved Midnight tokens, exposes an idempotent MSA context
  menu foundation, coalesces refresh callbacks, and flushes deferred UI work after combat.
- `src/RCLootCouncil_dibs.toc` and `src/embeds.xml` load the B11a modules and bundled
  LibSharedMedia/LibWindow dependencies. Presentation data is registered as
  `RCLootCouncil_dibsLocalDB` per character, separate from the guild database.

No B11a adapter reads arbitrary RCLootCouncil internals, changes RC click handlers,
changes ledger/governance/sync semantics, or grants production authority.

## Validation

Focused B11a, TOC, B08, and B09 boundary validation:

```text
17 passed, 0 failed (5 files)
```

Focused B11a suites:

```text
10 passed, 0 failed (3 files)
```

Full Fengari regression including all existing B00-B10 suites and B11a:

```text
323 passed, 1 failed (69 files)
```

The one failure is the pre-existing B08-era RCLootCouncil response projection baseline:

```text
FAIL RCLootCouncil DIB response projection /
renders the voting Dibs value from a normalized RCLootCouncil row identity
tests/integration/rclootcouncil_buttons_spec.lua:155: expected 2/2, got 1/1
```

No new diagnostics were reported for the B11a files, and `git diff --check` passed.

## Release decision

`B11a COMPLETE — READY FOR B11b`

B11b may begin from `e66dc5723c6098772128950a5bf6b42d1e12e88b` after reviewing the
known unrelated baseline failure above. Retail validation remains a separate required
gate for the addon release.
