# Source-Driven Documentation Architecture

Status: READ-ONLY DESIGN. No production source, localization, existing documentation, generated output, or CI configuration was changed for this proposal.

## 1. Executive Summary

Adopt a hybrid model: small LuaCATS-style `@doc` annotations beside the behavior that owns a concept, translated prose in the existing `Dibs.L` localization tables, and deterministic generated indexes and documents. Do not introduce a second translation catalog or put manuals in code comments.

The metadata describes technical truth: semantic identity, owning module/symbol, lifecycle, audience, required permission, scope, audit behavior, reason requirements, and localization keys. The existing English and French locale files remain the authority for translated labels and help. A generator combines those inputs into role-filtered Markdown, CSV, JSON, and a small runtime help index. Human-authored guides retain tutorials, examples, procedures, and advice that cannot be safely derived from metadata.

This fits the current repository better than an external YAML/JSON catalog: `src/Types.lua` already uses LuaCATS annotations, locale strings already live in `Dibs.L`, docs are already split by role, and the repository already uses PowerShell scripts. There is no existing `tools/` directory, documentation generator, Python toolchain, or test CI workflow to preserve.

## 2. Current Documentation Architecture

- The addon TOC declares version `0.6.5` and loads `locales/enUS.lua` followed by `locales/frFR.lua` before modules and UI. enUS establishes the default `Dibs.L` table; frFR returns early outside the French client locale and overrides the translated entries when selected.
- The locale files contain both runtime messages and UI help. The UI audit counted 81 help-related keys in each locale. `Dibs.L` is the existing localization API; there is no separate help/localization framework.
- `Dibs.AceGUI.AddTooltip(widget, title, description)` is the shared tooltip renderer. Headers, sections, controls, and table cells reuse it. It accepts display strings, not semantic IDs.
- `src/Types.lua` documents runtime shapes with LuaCATS `---@class`, `---@field`, and aliases. No `---@doc.*` annotations or `Dibs.Help` API exist today.
- Player docs are in `docs/player/`; Officer and GM operations share `docs/officer/` guides; Developer references are in `docs/developer/`. The English/French guides contain authored procedures and examples. The matrix and consistency report record the recent 35-cluster UI audit.
- Tests use a small custom Lua test runner in `tests/run.lua`, descriptive `*_spec.lua` files, and Fengari. On this Windows environment, discovery is explicitly supplied through `DIBS_TEST_FILES` because Fengari lacks the runner's `io.popen` discovery backend.
- `scripts/` currently contains `select-spec.ps1` and `deploy.ps1`. There is no `tools/` directory, `package.json`, repository Python documentation tool, or generated-docs directory.
- GitHub Actions currently packages the `src/` tree on pushes to `dev`/`main` and builds tagged releases. Those workflows do not run the Lua tests or a documentation validator. The release version is also recorded in `CHANGELOG.md`.

## 3. Problems with the Current Approach

- A concept can be repeated in a tooltip, two role guides, a developer reference, and an audit table without a stable ID connecting those copies.
- `AddTooltip` knows only a title and a description. It cannot tell whether the help belongs to a Player, GM, or Developer, or find the implementation and permission behind it.
- Some tooltip calls use localization keys, while others pass English literals. A key-parity test cannot detect all hardcoded help, semantic duplicates, or orphaned entries.
- Role guides are valuable human-authored procedures, but facts such as permission, audit behavior, and scope can drift if restated manually in several places.
- Current tests verify selected help strings and locale parity, not source-to-doc relationships, role filtering, generator determinism, or translation orphans.
- The recent matrix records seven unfinished clusters but is not connected to implementation metadata or a repeatable validator.

## 4. Proposed Source-of-Truth Model

```text
Lua behavior + compact @doc metadata
             |
             +----> existing enUS/frFR Dibs.L strings
             |
             v
       documentation generator
             |
             +----> generated runtime help index
             +----> role Markdown and UI reference
             +----> terminology, CSV, JSON
             +----> optional later HTML
```

Treat the implementation as authoritative for behavior, permission checks, data scope, and audit semantics. Treat the existing locale tables as authoritative for translated copy. Treat authored guides as authoritative for tutorials and operational advice, while linking their technical facts to generated references instead of copying them.

Annotations identify and classify a concept; they must not restate business logic or contain paragraphs of user-facing prose. Generated output is a projection, never an input to runtime logic except for the generated semantic-ID-to-locale-key index described in Section 6.

### Storage Options Compared

| Option | Readability / maintenance | Localization | Parser / coupling | Output quality / tests / versioning | Assessment |
| --- | --- | --- | --- | --- | --- |
| A. Annotations directly in Lua, including prose | Facts stay near behavior, but large translated blocks clutter implementation and create comment churn. | Poor if prose is embedded; duplicates the existing locale system. | Simple for a tiny tag set, increasingly complex for multiline content; tightly couples copy to code. | Can trace symbols well, but role-specific output and localization tests are awkward. | Use for compact metadata only, not as a complete content solution. |
| B. Central Lua documentation catalog | Easy to browse in one place, but technical ownership can drift away from the implementation. | Could reuse `Dibs.L`, but a second catalog tends to duplicate keys or text. | Easy to parse by Lua, but a large central table creates coupling and merge conflicts. | Strongly testable and generatable; version/source links still need manual maintenance. | Better than scattered prose, but not sufficient as the technical source of truth. |
| C. Lua annotations plus a separate central prose catalog | Keeps code facts close and prose organized, but splits concept identity and copy across two authorities. | Risk of becoming a second translation system beside `Dibs.L`. | Moderate parser complexity and moderate coupling across catalogs. | Good role-aware output and testability; version history is still separate. | Viable only if the repository had no localization catalog to reuse. |
| D. External YAML/JSON metadata | Structured and approachable to tooling, but easy to separate from the behavior it describes. | Can store locale maps, yet duplicates the existing Lua localization source. | Good off-the-shelf parsing, with new schema/dependency and reference validation. | Excellent machine output and tests; source trace and version history need explicit links. | Not recommended for this repo's first implementation. |
| E. Compact Lua annotations + existing `Dibs.L` + generated indexes/docs | Technical facts stay beside code; translated copy remains in the familiar locale files. | Reuses the sole localization system and can add role-level keys incrementally. | A small constrained parser is required; no parallel catalog or runtime parsing of Lua comments. | Strong source traceability, deterministic outputs, locale validation, and lifecycle links to the changelog. | Recommended. |

Option E is the selected hybrid. It combines the proximity benefit of A, the structured outputs of C/D, and the existing localization architecture without maintaining a second prose authority.

## 5. Annotation Schema

Use one globally unique, stable, lowercase, dot-delimited ID. Do not derive IDs from filenames, display labels, or Lua function names because those may change independently.

Recommended fields:

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | Yes | Stable semantic concept ID, such as `ledger.adjust`. |
| `category` | Yes | Controlled topic such as `ledger`, `rank-rules`, `setup`, or `sync`. |
| `since` | Yes for published concepts | First addon version containing the concept/API. |
| `changed` | When applicable | Repeatable version marker for a material semantic/documentation change. |
| `deprecated` | Optional | First version in which the concept is deprecated. |
| `removed` | Optional | Removal version for a retired concept or compatibility shim. |
| `audience` | Yes | One or more of `player`, `officer`, `gm`, `developer`. |
| `permission` | Optional | Existing protected-action/permission ID, not a prose role list. |
| `scope` | Yes when meaningful | Controlled data/operation scope such as `player`, `guild`, `guild-season`, `character-local`, or `raid-session`. |
| `audit` | Yes for mutations | Boolean indicating whether the operation creates/updates retained audit evidence. |
| `reason-required` | Yes for audited manual operations | Boolean; distinguish policy requirements from merely optional notes. |
| `help-key` | Optional | Existing or new key in `Dibs.L` for `SHORT_HELP`. |
| `label-key` | Optional | Localized UI/reference label key. Add only when a current label needs localization or output needs a canonical label. |
| `reference-key` | Optional | Localization key for technical/reference material when that level is genuinely needed. |

Keep metadata values scalar or comma-separated controlled tokens so they remain readable in a comment and simple to validate. The parser should reject unknown fields, duplicate singleton fields, malformed booleans, invalid tokens, and unsupported versions. `audience` and `permission` are sets; repeated `changed` tags are allowed.

For permissions, prefer the stable protected action identifiers already used in `ProtectedActions.lua` (for example, `ledger.adjust` or `rank.set`). The role filter says who needs to understand a concept; the permission field records which guarded action is relevant. Do not infer authority from a tooltip or from audience membership.

## 6. Help Catalog Integration

Do not make every UI call parse comments or localization keys. Add a small `Dibs.Help` runtime facade in a future implementation:

```lua
Dibs.Help.Get("rank.allocation", "short")
Dibs.Help.Attach(widget, "rank.allocation")
```

`Dibs.Help.Attach` resolves the concept's localized label and short-help keys, then delegates to the existing `Dibs.AceGUI.AddTooltip`. It must not duplicate tooltip rendering, permissions, or business logic. `Get` should return nil for unknown IDs and support an explicit fallback path rather than silently displaying a documentation ID.

Lua comments are not available at runtime, so the generator should emit a small, deterministic `src/generated/DocumentationHelpIndex.lua` mapping semantic IDs and content levels to localization keys. That file contains keys and IDs only, never translated prose. It is loaded after locale initialization and before the UI can request help. The generated file is checked in and freshness-checked in CI; the addon package already stages the entire `src/` tree.

Migrate controls incrementally. Existing calls such as `AddTooltip(widget, title, Dibs.L.UI_HELP_...)` remain valid during migration. First make `Dibs.Help.Get(id, "short")` resolve the same existing key; then convert selected call sites to `Dibs.Help.Attach`. Do not rewrite all 81 uses in one change. Retain a temporary compatibility mapping/allowlist until every legacy key is either attached to a semantic ID or deliberately classified as non-documentation runtime text.

## 7. Localization Integration

Keep `src/locales/enUS.lua` and `src/locales/frFR.lua` as the only translated-content source. Do not add a YAML, JSON, or second Lua prose catalog. Continue using the existing `Dibs.L` registry and TOC load order.

Map the current `UI_HELP_*` keys to `SHORT_HELP` first. Introduce additional namespaced keys only as a concept is migrated and actually needs another level, for example:

- `DOC_LEDGER_ADJUST_LABEL`
- `UI_HELP_DIBS_ADMIN` as its existing short-help key
- `DOC_LEDGER_ADJUST_OFFICER`
- `DOC_LEDGER_ADJUST_GM`
- `DOC_LEDGER_ADJUST_REFERENCE`
- `DOC_LEDGER_ADJUST_TECHNICAL`

The locale catalog is the translated copy; metadata carries the key references. Do not create duplicate values merely to rename existing keys. The validator should require enUS and frFR for every key referenced by a published concept, and progressively detect direct UI literals that have not migrated. During early migration, missing optional content levels are allowed; missing short help in either locale is a warning until the relevant concept is declared complete, then an error.

Labels are not consistently localization-backed today. Generate localized labels only from a real label key; otherwise mark the field unavailable during the seed phase or migrate the label deliberately. Do not mistake an ID-derived English title for a translated canonical label.

## 8. Audience / Role Model

Audience filtering is inclusive: a document includes a concept if its audience set contains that document's role. The four stable role tokens are `player`, `officer`, `gm`, and `developer`. GM material is separate from Officer output even where both roles share one authored guide today.

Examples:

- `ledger.balance`: Player, Officer, GM; never protocol internals.
- `ledger.adjust`: Officer, GM; audit and permission metadata required.
- `guild.setup.initialize`: GM, Developer; setup consequences for GM and implementation reference for Developer.
- `sync.v2.enforced`: Developer only.
- `sync.legacy_baseline_hash`: Developer only.

A concept can be visible to several roles while its content differs by level. A Player entry may contain a one-sentence consequence; a GM entry may explain authority and procedure; a Developer entry may describe invariants. Never derive a Developer paragraph by appending implementation details to a Player tooltip.

## 9. Version Metadata

Validate versions against the addon's actual convention: three numeric components with an optional prerelease suffix, such as `0.6.5` or `0.6.3-dev`. Keep version ownership aligned with `src/RCLootCouncil_dibs.toc` and `CHANGELOG.md`.

- `since` is the first addon release containing the concept.
- `changed` is repeatable and records versions in which its meaning or documentation contract materially changed; it contains a version only, not a changelog paragraph.
- `deprecated` and `removed` record lifecycle boundary versions. A physically deleted concept is absent from current references; its historical removal remains in the human changelog rather than requiring a dangling live annotation.
- Do not put change explanations in Lua comments. Keep release prose in `CHANGELOG.md`. When a change is documentation-significant, tag the changelog bullet with a stable cross-reference such as `[doc:ledger.adjust]`; the generator can then produce a version report by joining the annotation's `changed` versions to those authored notes.
- A changed version without a matching release note is a validation warning during migration and an error after version-history enforcement is enabled.

This yields an output such as `Documentation changes in 0.6.5` without turning source comments into a second changelog.

## 10. Parser Architecture

Place the future entry point under the existing lowercase `scripts/` directory, for example `scripts/Generate-DibsDocs.ps1`. The repository has no current Lua parser dependency or documentation toolchain, so keep the first parser deliberately narrow and dependency-light.

1. Enumerate first-party Lua under `src/`, excluding generated output when reading annotations.
2. Read only contiguous `---@doc.*` comment blocks and the supported declaration/call immediately following each block. Record normalized relative path, line, and symbol.
3. Use a small lexical scanner for Lua strings/comments and supported declarations; do not treat a regex over the entire source file as a Lua parser. If the supported forms cannot be associated unambiguously, fail with file and line instead of guessing.
4. Read only locale assignments referenced by metadata. Support the existing direct `L.KEY = "..."` form and Lua escapes used by the catalog. Reject unsupported expressions for documented keys rather than attempting to execute addon Lua in PowerShell.
5. Validate and normalize metadata into an in-memory document model; sort by semantic ID and stable ordinal string comparison before output.
6. Render Markdown, CSV, JSON, and the optional runtime index from the same normalized model. `-Validate` is read-only; `-Generate` writes outputs; `-Check` regenerates in memory/temp and fails if committed outputs differ.

Keep annotation syntax intentionally smaller than LuaCATS. Unknown ordinary LuaCATS tags must not be parsed as DIBS metadata. The parser is a documentation extractor, not a general Lua analyzer or a replacement for LuaLS.

## 11. Markdown Generator

Generate the requested files under `docs/generated/`:

- `player-guide.md`
- `officer-guide.md`
- `gm-guide.md`
- `developer-reference.md`
- `ui-reference.md`
- `terminology.md`

Every file begins with `THIS FILE IS GENERATED. DO NOT EDIT MANUALLY.` and links to its owning role guide or source metadata where appropriate. Role documents filter by audience, group by category, and show localized content at the applicable levels. The UI reference groups by UI surface and semantic ID. The terminology reference contains canonical localized labels and concise definitions, excluding Developer-only terms from normal-role outputs.

Use stable headings and sort order so diffs are reviewable. Each concept ends with a source trace such as `src/modules/Ledger.lua - Ledger.AdminAdjust` and a relative source link with a generated line number. Link to authored workflow sections instead of copying their tutorial prose.

## 12. CSV Generator

Use UTF-8 and RFC 4180 quoting; one concept per row, stable ID sort, invariant boolean spelling (`true`/`false`), and semicolon-joined role/token sets. Recommended schema:

```text
Id,Module,Category,Since,Changed,Deprecated,Removed,Audience,Permission,Scope,HelpKey,LabelKey,Audit,ReasonRequired,LabelEN,LabelFR,ShortHelpEN,ShortHelpFR,PlayerHelpEN,PlayerHelpFR,OfficerHelpEN,OfficerHelpFR,GMHelpEN,GMHelpFR,ReferenceEN,ReferenceFR,TechnicalEN,TechnicalFR,SourceFile,SourceLine,Symbol
```

Empty optional content is an empty field, not a fabricated placeholder. CSV is an export format; do not use it as a hand-edited source catalog.

## 13. JSON Generator

JSON preserves structure rather than flattening role and lifecycle data. Use a stable top-level schema version and an array sorted by `id`. Keep locale values grouped by content level and use arrays for audiences, permissions, and changed versions. Include source file, line, symbol, and optional related authored-document anchors.

Example object shape:

```json
{
  "schemaVersion": 1,
  "id": "ledger.adjust",
  "module": "Ledger",
  "category": "ledger",
  "lifecycle": {
    "since": "0.6.0",
    "changed": ["0.6.5"],
    "deprecated": null,
    "removed": null
  },
  "audience": ["officer", "gm"],
  "permission": ["ledger.adjust"],
  "scope": "guild-season",
  "audit": true,
  "reasonRequired": true,
  "content": {
    "label": {"enUS": "Manual Dibs adjustment", "frFR": "Ajustement manuel des Dibs"},
    "shortHelp": {"enUS": "...", "frFR": "..."},
    "roleHelp": {"officer": {"enUS": "...", "frFR": "..."}}
  },
  "source": {
    "file": "src/modules/Ledger.lua",
    "line": 570,
    "symbol": "Ledger.AdminAdjust"
  }
}
```

The real generated object must include only content levels present in the source; the ellipses above are explanatory placeholders, not valid catalog text.

## 14. HTML Recommendation

Defer HTML. Markdown is already the repository's native documentation format and can be reviewed in GitHub and locally without a new frontend/build dependency. If a website or offline help bundle later becomes a real requirement, generate HTML from the generated Markdown using one pinned renderer and shared CSS. Do not maintain an independent HTML template/content tree now.

## 15. Validation Rules

`-Validate` should report counts and all findings, then exit nonzero only for errors. Required checks:

- duplicate or malformed semantic IDs;
- unknown/missing metadata fields and invalid controlled values;
- invalid audience, permission, scope, booleans, or version syntax;
- missing/ambiguous source declaration or source path;
- metadata concept whose source symbol no longer exists;
- referenced help/label/role key absent in enUS or frFR;
- direct tooltip/help key with no concept mapping (or legacy allowlist entry);
- concept with no usable UI, API, role-document, or technical consumer (`orphan concept`);
- localized label identical to its short-help string, reported as a warning unless explicitly allowed;
- developer-only terms or concepts leaking into Player/Officer/GM generated output;
- deprecated/removed concepts accidentally emitted into current references;
- `changed` version without a matching `[doc:id]` changelog note after enforcement;
- generated output not deterministic/current under `-Check`.

For the developer-term rule, prefer concept audience metadata and a short maintained denylist of known implementation tokens (`V2_ENFORCED`, `ledgerEpoch`, `legacyBaselineHash`, `SyncV2`) as a second guard. Do not rely on English-only word scanning as the primary privacy/security boundary.

Staged severity matters. Start with missing translations and duplicate IDs as errors for the pilot concepts, while orphan keys and unmigrated source references are warnings backed by a reviewed legacy inventory. Tighten to errors only after the migration reaches the corresponding scope.

## 16. CI Integration

There is no current PR test workflow, so add documentation validation as a separate PR workflow when implementation begins rather than silently expanding the package job first. Run the validator and generator check on pull requests and on `dev`/`main`; run the Lua suite in the same CI gate. Run the same validation before package/release steps once stable.

Recommended developer flow:

```text
source or locale change
  -> pwsh scripts/Generate-DibsDocs.ps1 -Validate
  -> Lua/Fengari tests
  -> pwsh scripts/Generate-DibsDocs.ps1 -Generate
  -> pwsh scripts/Generate-DibsDocs.ps1 -Check
  -> git diff --check
```

Keep `-Validate` non-writing. `-Generate` should be explicit locally. CI uses `-Check`, never silently edits the checkout. Do not claim generated files are current if CI had to rewrite them.

## 17. Source Traceability

The generator derives `SourceFile` and `SourceLine` from the annotation block and declaration/call that owns it. Include the owning public symbol, for example:

- `src/modules/RankRules.lua` - `Dibs.RankRules.SetRankAllocation`
- `src/modules/Ledger.lua` - `Ledger.AdminAdjust`
- `src/modules/Governance.lua` - `Governance.ActivateV2`

Line numbers are useful navigation hints but change frequently; stable IDs and symbols are the durable trace. Optional `@doc.related` references may point to a UI builder, protected action, or authored workflow. These related references are validated but do not replace the primary source.

## 18. Migration Strategy

1. **Inventory and contract:** freeze the annotation grammar, role/content levels, controlled vocabularies, generated disclaimer, and output schema. Map the current 35 matrix groups and 81 help keys without changing their wording. Record known legacy keys so initial validation is informative rather than noisy.
2. **Parser and validator, warning-only:** implement the extractor with fixture tests. Validate locale key pairs and metadata in sample concepts. Do not generate public docs or add CI blocking yet.
3. **Pilot high-risk concepts:** annotate about ten concepts that have a clear implementation owner: balance, Pre-Dib submission, rank allocation, Guild Setup, manual adjustment, audit reason, synchronization status, restore confirmation, role permissions, and Developer Sandbox. Prefer mutation/authority boundaries first.
4. **Generated reference and review:** generate JSON/CSV/UI reference and role Markdown for only migrated concepts. Compare generated output against authored guides, correct gaps, and then commit outputs. Keep tutorials and step-by-step procedures in the existing authored guides.
5. **Role and UI expansion:** migrate the seven remaining help gaps and then the rest of the audited clusters. Convert call sites to `Dibs.Help.Attach` only as IDs and localized keys become complete. Keep legacy `AddTooltip` calls supported during the transition.
6. **Enforce in CI:** begin with duplicate IDs, malformed metadata, missing enUS/frFR for migrated IDs, developer leakage, and deterministic output as blocking. After the audited inventory is migrated, promote orphan key/concept checks and changelog links to blocking. Add package/release gates last.

This order gives an early useful validator without requiring the whole addon to be annotated in one change, and avoids making generated manuals authoritative before their coverage is measured.

## 19. Test Strategy

Use small source/locale fixtures for parser and renderer tests. A pinned PowerShell/Pester test suite is appropriate for the generator because it is proposed as a PowerShell tool; keep it separate from runtime Lua tests. Continue Lua specs for `Dibs.Help.Get/Attach` once that runtime API exists. Required cases:

1. Parser extracts every supported `@doc` field and binds it to the following declaration.
2. Duplicate semantic ID fails with both source locations.
3. Missing enUS content fails.
4. Missing frFR content fails.
5. Audience filtering includes/excludes the expected IDs.
6. Player output excludes Developer-only concepts and known protocol internals.
7. Officer output includes administrative concepts but not GM-only setup authority.
8. GM output includes Guild Setup and governance concepts.
9. Developer output includes internal protocol state.
10. Markdown output is byte-for-byte deterministic.
11. CSV output is byte-for-byte deterministic and correctly quotes commas, quotes, and line breaks.
12. JSON output is byte-for-byte deterministic and parses with the declared schema version.
13. Generated output contains a valid relative source link, file, line, and symbol.
14. Orphan help key is detected, including the staged legacy-key exception behavior.
15. Label equal to short help produces the expected warning/error policy.
16. Invalid or unsupported lifecycle version is rejected.
17. Unknown audience, permission, scope, boolean, and metadata tag are rejected.
18. Orphan concept and stale source symbol are detected.
19. `changed` version without its keyed changelog note is detected after enforcement.
20. Generated runtime help index maps IDs to keys only and resolves current enUS/frFR values through `Dibs.L`.

Do not require all 20 checks to block CI in Phase 1; the migration section defines when each becomes authoritative.

## 20. Risk Register

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Source annotation drifts from actual permission or audit behavior | High | Annotate at the protected service boundary; cross-check permission/action IDs and audit tests. Do not infer from UI labels. |
| A second prose catalog appears beside `Dibs.L` | High | Keep translations only in existing locale files; generated indexes store keys, not prose. |
| Role filtering leaks protocol terms | High | Audience is required, Developer-only allowlist/denylist tests run against every normal-role output. |
| Lightweight parser binds a block to the wrong symbol | High | Restrict grammar, lex comments/strings, require adjacency, fail ambiguous bindings, and test realistic fixtures. |
| Existing 81 keys are reported as orphans during migration | Medium | Inventory and allowlist legacy references; initially warn, then remove exceptions as call sites migrate. |
| Generated diffs obscure meaningful manual documentation | Medium | Stable ordering, small focused commits, generated disclaimer, and authored guides remain separate. |
| Version markers duplicate changelog prose | Medium | Comments contain versions only; `CHANGELOG.md` owns explanations, joined by `[doc:id]`. |
| UI runtime index is stale or absent from packaging | High | Check in generated Lua index, list it explicitly in TOC, run generator `-Check` in CI, and test packaging. |
| French key exists but translation is untranslated English | Medium | Add human review to localization changes; parity tests alone are insufficient. Consider a targeted English-copy warning, not as sole validation. |
| Static analyzer output is stale and mistaken for a source defect | Medium | Recompute against current file version; match diagnostic ranges to source; keep generator validation independent of editor caches. |
| Generated role guides become substitutes for tutorials | Medium | Generate factual reference sections only; link to authored workflow guides for procedures and examples. |
| Pester adds a new CI dependency | Low/Medium | Pin a known Pester version, isolate it to the docs job, and keep validator runtime dependency-free. |

## 21. Example Lua Annotations

Illustrative only; this pass does not add these annotations. The action ID `ledger.adjust` exists in `ProtectedActions.lua`, and `Ledger.AdminAdjust` is the ledger implementation boundary.

```lua
---@doc.id ledger.adjust
---@doc.category ledger
---@doc.since 0.6.0
---@doc.changed 0.6.5
---@doc.audience officer,gm
---@doc.permission ledger.adjust
---@doc.scope guild-season
---@doc.audit true
---@doc.reason-required true
---@doc.help-key UI_HELP_DIBS_ADMIN
---@doc.label-key DOC_LEDGER_ADJUST_LABEL
function Ledger.AdminAdjust(playerName, amount, reason, source, seasonId, audit)
```

The comment is metadata only. The actual checks and audit record remain in executable Lua. `changed` records a version, while the explanatory release note remains in `CHANGELOG.md`, keyed with `[doc:ledger.adjust]`.

## 22. Example Generated Player Documentation

```markdown
<!-- THIS FILE IS GENERATED. DO NOT EDIT MANUALLY. -->

## Dibs balance

Your available Dibs belong to this guild and the active season. A qualifying
finalized award or authorized adjustment changes the balance. A Pre-Dib is a
request, not a spend.

Scope: Current guild, active season
Source: `src/modules/Ledger.lua` - `Ledger.GetBalance`
```

The Player view does not include manual-adjustment permission or protocol state. The exact wording is sourced from the enUS/frFR catalog; this excerpt illustrates structure only.

## 23. Example Generated GM Documentation

```markdown
<!-- THIS FILE IS GENERATED. DO NOT EDIT MANUALLY. -->

## Manual Dibs adjustment

Guild Masters and authorized Officers can adjust a member's current-season
balance. A meaningful reason is required and the retained audit evidence
includes the actor, target, previous balance, and resulting balance.

Permission: `ledger.adjust`
Scope: Guild season
Audit: Yes
Reason required: Yes
Source: `src/modules/Ledger.lua` - `Ledger.AdminAdjust`
```

The GM view may link to the authored setup/administration workflow. Generated reference text must not imply that the UI itself grants authority.

## 24. Example Generated Developer Documentation

```markdown
<!-- THIS FILE IS GENERATED. DO NOT EDIT MANUALLY. -->

## V2 enforced state

Protocol state is diagnostic implementation detail. Use the state and
transition invariants documented by the owning synchronization module when
changing compatibility or recovery behavior. This concept is excluded from
Player, Officer, and GM generated output.

Audience: Developer
Source: `src/modules/SyncV2.lua` - owning protocol-state implementation
```

The exact symbol and invariant reference must be confirmed when this concept is migrated. A generator must not invent a technical explanation from the identifier alone.

## 25. Example CSV Row

Illustrative RFC 4180 row; the values should be resolved from annotations and `Dibs.L`, not manually duplicated in a CSV source file:

```csv
ledger.adjust,Ledger,ledger,0.6.0,0.6.5,,,officer;gm,ledger.adjust,guild-season,UI_HELP_DIBS_ADMIN,DOC_LEDGER_ADJUST_LABEL,true,true,Manual Dibs adjustment,Ajustement manuel des Dibs,"Guild Masters and authorized Officers can adjust a member's current-season balance.","Les maitres de guilde et Officers autorises peuvent ajuster le solde de la saison active.",,,,,,,,,,src/modules/Ledger.lua,570,Ledger.AdminAdjust
```

The line number above is illustrative; the generator derives the current value.

## 26. Example JSON Object

```json
{
  "id": "rank.allocation",
  "module": "RankRules",
  "category": "rank-rules",
  "lifecycle": {
    "since": "0.6.0",
    "changed": [],
    "deprecated": null,
    "removed": null
  },
  "audience": ["officer", "gm"],
  "permission": ["rank.set"],
  "scope": "guild-season",
  "audit": false,
  "reasonRequired": false,
  "helpKeys": {
    "label": "DOC_RANK_ALLOCATION_LABEL",
    "shortHelp": "UI_HELP_RANK_ALLOCATION"
  },
  "content": {
    "label": {
      "enUS": "Rank Allocation",
      "frFR": "Allocation de Dibs par rang"
    },
    "shortHelp": {
      "enUS": "Starting Dibs assigned to a guild rank for the selected season.",
      "frFR": "Dibs attribues au depart a un rang de guilde pour la saison selectionnee."
    }
  },
  "source": {
    "file": "src/modules/RankRules.lua",
    "line": 171,
    "symbol": "Dibs.RankRules.SetRankAllocation"
  }
}
```

This shape is illustrative; lifecycle, translated values, line, and symbol must be extracted and validated. JSON should omit unprovided content levels rather than fill them with fabricated text.

## Final Decisions

- **Q1. Should metadata live directly in Lua?** Yes, compact annotations belong beside the owning behavior; keep them to structured facts and keys.
- **Q2. Should long prose live in Lua?** No. Keep manuals and long explanations in authored guides; keep localized short/role content in locale tables.
- **Q3. Should existing localization remain authoritative for translated help?** Yes. `Dibs.L` in enUS/frFR remains the sole translated-content source.
- **Q4. Should generated Markdown be committed?** Yes, after deterministic generation is established; reviewers can inspect docs alongside source changes and users can read docs without running tooling.
- **Q5. Should HTML be generated directly or from Markdown?** Defer HTML; if needed later, derive it from generated Markdown with a pinned renderer.
- **Q6. Should missing documentation eventually fail CI?** Yes for migrated/published concepts and all required locales; use warning-only staged enforcement during inventory migration.
- **Q7. What should be the canonical documentation ID format?** Stable lowercase dot-delimited IDs such as `ledger.adjust` and `rank.allocation`, independent of labels and file names.
- **Q8. How should version history be represented?** `since`, repeatable version-only `changed`, `deprecated`, and `removed` metadata; descriptive notes stay in `CHANGELOG.md` and link by `[doc:id]`.
- **Q9. How should UI tooltips consume the same documentation source?** Through `Dibs.Help.Attach/Get` backed by a generated ID-to-localization-key index; the existing AceGUI helper continues rendering the tooltip.
- **Q10. What is the recommended phased implementation?** Define schema and warning-only validator; pilot high-risk concepts; generate/review reference output; migrate remaining concepts and seven help gaps; then enforce completeness and generated-output freshness in CI.

## Static Checker Issue: PlayerUI

The current `src/ui/PlayerUI.lua` contains a single `local helpText = Dibs.L or {}` at the top, and current tooltip uses reference `helpText.UI_HELP_*`. A search finds no remaining direct `Dibs.L.UI_HELP_*` access in that file. The previous `get_errors` results continued to attach `undefined field 'L'` diagnostics to downstream locations that now use `helpText`, even after the source substitutions; those reported ranges therefore appear stale or misattributed, not evidence that the old direct accesses remain.

There is also a genuine static-contract gap: `Dibs.L` is initialized by both locale files, but `---@class Dibs` in `src/Types.lua` does not declare an `L` field. Thus the access `Dibs.L` in the alias can legitimately be reported as an undefined field by a fresh type analysis even though runtime initialization is valid. This is not a runtime localization defect and not a Lua parser limitation; it is an omitted type declaration, combined with stale diagnostic locations. A future fix should add the accurate locale-table type to the LuaCATS contract and then refresh/re-run analysis against the saved current file.

The documentation validator must not consume editor diagnostics as its source parser or report database. It should read the current saved files, attach its own line numbers, and report exact current source spans. If an editor diagnostic is optionally imported, verify its file version/range against the current source before classifying it; otherwise mark it stale/unverified. This prevents editor-cache false positives from becoming documentation validation findings.

## Seven Existing UI Help Gaps as Acceptance Examples

The architecture can represent all seven matrix gaps without expanding source comments into prose. Each needs a stable ID, an owning source reference, a role/audience set, required metadata, and the appropriate enUS/frFR content level. None is fixed by this design pass.

| Existing gap | Example concept ID | Expected generated coverage |
| --- | --- | --- |
| Player RCLootCouncil status | `ui.player.rclc-status` | Player short help and next step; Developer reference may explain adapter diagnostics. Never expose raw protocol tokens to Player output. |
| Officer review requests | `disputes.review-request` | Officer/GM help describes evidence, review state, and responsibility; Player output describes only the player's own request and next action. |
| Historical RCLootCouncil reconciliation | `history.rc-reconciliation` | Officer/GM reference captures read-only preview, confirmation authority, evidence, and audit impact; Developer reference links the adapter. |
| Announcements | `announcements.channel-scope` | Officer/GM help states channel, audience, and consequence; localized in both languages. |
| Player raid readiness | `readiness.player-status` | Player explanation and next action plus separate Officer/GM remediation reference; no internal diagnostic jargon in Player output. |
| Ledger/audit history columns | `ledger.audit-entry` | Shared terminology for date, target, operation, amount, reason, and evidence, with role-filtered explanations. |
| Raid Relay | `raid-relay.proposal` | Officer/GM help explains authority and canonical accounting; Developer-only details clarify that live loot-session state is not relayed. |

The validator should make each a test fixture for role filtering, localization completeness, source traceability, and Developer-term exclusion once that concept is migrated.