# Repository UI Instructions

For every UI change, follow the project-wide Midnight UI Design System in `docs/developer/b12-ui-design-rules.md`.

- Use Automatic Dibs as the reference for dense roster and table workflows.
- Use Dashboard as the reference for status summaries, section hierarchy, and compact operational actions.
- Use Guided Setup as the reference for ordered workflows, explanations, and primary actions.
- Preserve the shared Midnight shell, navigation, typography, spacing, semantic status treatment, table geometry, and stable footer. Do not invent page-specific themes or visual systems.
- Before implementing a page, choose the closest reference pattern and reuse its existing AceGUI helpers and layout conventions.
- For list pages, prefer the shared table page, fluid columns, bounded scrolling, and pagination. Keep empty, unavailable, and error states explicit.
- Keep design and data scope distinct: presentation selectors must not silently change synchronization, permissions, or policy behavior.
- Update focused UI tests for navigation, empty states, and primary interactions. Run the relevant Fengari tests and `git diff --check` before deployment.
