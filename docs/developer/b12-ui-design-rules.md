# Midnight UI Design System

**Status**: Project-wide design gate

**Scope**: All Player and Officer UI. These rules govern presentation and interaction;
they do not change ledger semantics, permissions, policy, synchronization, RCLootCouncil
ownership, or protected-action boundaries.

## Reference Pages

Use **Automatic Dibs** as the reference for dense, repeated roster data; use the
**Dashboard** for concise status summaries and clear section hierarchy; use **Guided
Setup** for ordered workflows, explanations, and primary actions. New pages should
compose these established patterns rather than invent page-specific visual styles.

## Visual Direction

All pages MUST use one simple Midnight layout across Player and Officer surfaces:

- dark translucent window;
- left navigation;
- one primary content area;
- simple section headers;
- white or light-gray normal text;
- muted secondary text;
- restrained yellow accent;
- semantic warning, error, and success colors;
- simple buttons, dropdowns, checkboxes, and sliders;
- fixed footer;
- consistent spacing.

Prioritize stability, readability, predictable layout, usability, and visual
consistency in that order. Pages MUST NOT add animations, gradients, elaborate cards,
custom visual effects, per-page themes, or a second design system. When equivalent
layout behavior can be implemented with fewer frames and anchors, the simpler
implementation is required.

## Layout Contract

Every page MUST fit the shared Midnight shell rather than inventing a page-specific
composition. Navigation is for selecting a page; the content area owns the selected
page; the footer remains stable for page status and primary workflow actions.

Tables and lists SHOULD primarily display information. They MUST keep readable column
widths, stable row geometry, bounded scrolling or pagination, and visible empty and
error states. Permanent `Action`, `Actions`, `Review`, or `Transfer` columns SHOULD NOT
be used when they contain only generic secondary commands.

### Shared Data Grid

Automatic Dibs and Dibs Administration are the reference pages for roster-style data
grids. New list pages SHOULD reuse the shared table page, fluid column allocator,
pagination footer, and page-slice helpers. Keep filtering, row projection, sorting, and
page-specific actions in the owning page; do not duplicate shared geometry or pager
controls.

The TreeGroup content frame bounds the page. Header, column header, scroll viewport, and
pagination footer are siblings; only row content belongs inside the scroll frame. The
footer remains inside the content frame, while the window Close control remains
window-owned. Action columns use a stable width sized to their longest button label and
padding. Descriptive columns absorb available width, compact numeric columns stay
bounded, and pagination stays inline until the content area genuinely requires stacking.

Future migration candidates are History, Requests, Pre-Dibs, Pending Awards, Vault
Review, Synchronization, and other roster/list views. This list records candidates only;
it does not schedule or imply their migration. Raid Readiness remains a dashboard/status
pattern rather than a data-grid page.

## Interaction Contract

Use the following default row behavior:

- **Left click** selects a row, opens or views details, or performs the primary
  non-destructive action.
- **Right click** opens the context menu for the selected object and its available
  secondary actions.
- **Visible buttons** are reserved for the primary workflow action and important
  confirmation, cancellation, or save actions.

Critical actions MUST remain visible outside a context menu. Secondary actions SHOULD
be contextual rather than occupying permanent table columns.

### Context Menu Actions

All pages MUST use one shared context-menu implementation, preferably the existing
`MSA-DropDownMenu-1.0` integration while it remains stable with the UI ownership model.
The menu MUST:

- open from the clicked row or object;
- contain only actions relevant to that object and its current state;
- respect Officer versus GM authorization;
- hide unavailable actions rather than showing misleading commands;
- close when its page or window closes;
- close when another context menu opens;
- remain inside screen bounds;
- use readable labels;
- omit generic table sorting commands unless explicitly required.

Suggested contextual actions are:

- **Player row**: View Dibs, View Pre-Dibs, View History, Copy Name-Realm.
- **Request row**: Open request, View player, View player Dibs, View history,
  Copy Name-Realm, Copy item link.
- **Pre-Dib row**: Open details, View player, View item, View history, Copy item
  link, and authorized Cancel/Revoke only when valid for the current state.
- **History or RCLootCouncil candidate**: Review, View item, Open Adventure Guide,
  View player history, Copy player, Copy item link, Show technical evidence.
- **Season row**: View, Set active, Rename, Archive, only when authorized and valid.

These are interaction examples, not permission grants. Availability is determined by
the existing object state and authorization services.

## Dangerous Actions

Accounting, destructive, or irreversible actions MUST NOT execute directly from a row
or ordinary context-menu item. This includes balance correction, Dib refund, Dib
revoke, historical import, critical-data deletion or archive, and canonical ledger
correction.

A context-menu entry MAY open an advanced workflow, but the workflow MUST perform the
existing authorization check, collect an explicit reason where required, and show an
explicit confirmation step before mutation. The UI MUST delegate the mutation to the
existing protected service boundary and MUST NOT write authoritative state directly.

Request detail pages MAY expose these as visible primary or advanced workflow actions:

- Ask for information;
- Resolve;
- Reject;
- Correct player or item;
- Correct balance;
- Refund Dib;
- Revoke Dib;
- Import historical.

The last five require the applicable authorization, reason, and confirmation flow.

## Acceptance Gates

A UI slice is not complete until focused checks demonstrate:

1. Player and Officer pages use the same Midnight shell, spacing, text hierarchy, and
   semantic state treatment.
2. The page remains readable at supported narrow and wide sizes without overlapping
   text, unstable anchors, or decorative layout exceptions.
3. Secondary row actions use the shared contextual menu and no unnecessary permanent
   action column was introduced.
4. Left-click and visible-button behavior provide the primary workflow without making
   critical actions context-menu-only.
5. Menu contents are object-aware, role-aware, state-aware, bounded to the screen,
   and cleaned up on page/window close or replacement.
6. Dangerous actions cannot execute without authorization and explicit confirmation;
   reason collection is enforced where required.
7. Empty, unavailable, warning, error, success, and disabled states remain readable
   without relying on color alone.
8. The focused Fengari tests, workspace diagnostics, `git diff --check`, and required
   Retail validation pass for the affected UI slice.

## Non-Goals

The UI does not introduce a new visual framework, page-specific themes, decorative
motion, a second context-menu system, direct accounting writes, or changes to domain
authority.
