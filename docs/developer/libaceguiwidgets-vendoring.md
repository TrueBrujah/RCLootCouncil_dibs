# LibAceGUIWidgets vendoring record

## Origin and scope

- Project: LibAceGUIWidgets by Pimptasty; official [CurseForge project and
  v0.12.0 release](https://www.curseforge.com/wow/addons/libaceguiwidgets/files/9466714)
  (project ID 1599206, file ID 9466714).
- Internal LibStub revision: `LibAceGUIWidgets-1.0`, `MINOR = 50`.
- Official release archive SHA-256:
  `a3c95a265ee220bd5b66e7416923faf1a4be590bc1dc173d2a0e61ae935a790b`.
- Embedded subset: the core, DatePicker, font, two textures, and their licenses
  under [src/libs/LibAceGUIWidgets](../../src/libs/LibAceGUIWidgets). Other
  upstream satellites are not included.
- The project uses the MIT license. The accompanying DejaVu font includes
  Bitstream Vera and Arev license notices and public-domain DejaVu changes.
  Keep both [LICENSE](../../src/libs/LibAceGUIWidgets/LICENSE) and
  [LICENSE-DejaVu.txt](../../src/libs/LibAceGUIWidgets/Fonts/LICENSE-DejaVu.txt)
  with the distributed files; review their conditions when updating.

The retention of the three pre-existing Dibs asset-path adaptations below was
selected for consolidation in lot 8D.1b. It does not authorize further changes
to third-party files or a commit, release, or deployment.

## SHA-256

These are raw file bytes from the official v0.12.0 archive and the Windows
working tree checked on 2026-11-11. Git text and line-ending normalization can
change working-tree or Git-blob bytes across environments; compare the actual
bytes and account for line endings rather than treating Git blob IDs as these
SHA-256 values.

| Relative file | Upstream SHA-256 | Integrated SHA-256 |
| --- | --- | --- |
| `LibAceGUIWidgets-1.0.lua` | `65cb30f1d32fb2d03e5a371f1b65286d3e60f5dd9ff927da05c7048d260b95f7` | `d58bf22bb01cc854a9b78dd8dbb08b469850c27ce19f13589de2ed18535a28bf` |
| `LibAceGUIWidgets-DatePicker.lua` | `488eb2f2f27b31bc61b822728bbf1755ad62f7cd59c7e7917b8878e359795bb8` | `f33731b4c8f302bb272ae7f3001007a137431572ece4032250e8ea8fb30d3bd8` |
| `Fonts/DejaVuSans.ttf` | `690243adfefe0ce154b547db6205794bd30ac4277275179517a90994f4980648` | `690243adfefe0ce154b547db6205794bd30ac4277275179517a90994f4980648` |
| `Fonts/LICENSE-DejaVu.txt` | `3f1a11bc99a21ddb62d0eb9f3ed2e1b530ed13230fc79e5aa68be2a0a1a8082f` | `3f1a11bc99a21ddb62d0eb9f3ed2e1b530ed13230fc79e5aa68be2a0a1a8082f` |
| `Textures/calendar.tga` | `0f634a34f03f664ca546d0780e8976224e04ebb25e626ba6e5d9252010056828` | `0f634a34f03f664ca546d0780e8976224e04ebb25e626ba6e5d9252010056828` |
| `Textures/copy.tga` | `540ba036d5dc28b385c1c771e73d6fd86f8c5a55be433568dfa4bd999ea51f2d` | `540ba036d5dc28b385c1c771e73d6fd86f8c5a55be433568dfa4bd999ea51f2d` |
| `LICENSE` | `0333c25c451f6f0d12bc9bbd38d996fc80a44f5ba05900fe50d045b4769a0a15` | `bd4529a704971dfb8af6a39154afdff7abcb75446e1aea18ffde208650a67646` |

The two Lua files match the archive byte-for-byte after applying only the three
path substitutions below. The font, font license, and textures are byte-identical.
The MIT license text is identical after normalizing upstream LF and local CRLF
line endings; its raw hashes therefore differ.

## Asset paths and packaging

The paths below are WoW runtime paths; Lua source represents backslashes as
escaped characters.

| File and resource | Upstream path | Integrated path | Reason |
| --- | --- | --- | --- |
| Core: symbol font | `Interface\AddOns\LibAceGUIWidgets\Fonts\DejaVuSans.ttf` | `Interface\AddOns\RCLootCouncil_dibs\libs\LibAceGUIWidgets\Fonts\DejaVuSans.ttf` | Locate the embedded font rather than the standalone addon's font. |
| Core: copy icon | `Interface\AddOns\LibAceGUIWidgets\Textures\copy.tga` | `Interface\AddOns\RCLootCouncil_dibs\libs\LibAceGUIWidgets\Textures\copy.tga` | Locate the embedded copy texture. |
| DatePicker: calendar icon | `Interface\AddOns\LibAceGUIWidgets\Textures\calendar.tga` | `Interface\AddOns\RCLootCouncil_dibs\libs\LibAceGUIWidgets\Textures\calendar.tga` | Locate the embedded calendar texture. |

[embeds.xml](../../src/embeds.xml) loads LibStub and AceGUI before the core and
DatePicker. VersionCheck-1.0 is optional. The addon TOC loads `embeds.xml` before
addon modules. The package workflows copy `src/` into `RCLootCouncil_dibs/`;
[.pkgmeta](../../.pkgmeta) likewise moves `src/` into that addon directory.
The two license files and all three assets must remain in the packaged library
directory. This record under `docs/` is not included in that addon package.

The paths assume the addon directory is named `RCLootCouncil_dibs`. Actual
resource rendering, load order with other addons supplying LibStub copies, and
fallback behavior require Retail validation; static checks do not prove them.
OfficerUI uses `LAGW-DatePicker` as an aid to draft date entry. The
[029 plan](../../specs/029-seasonal-raid-roster/plan.md) records the dependency,
fallback, and regression requirements. Coexistence and the adoption requirements
in [constitution XVI](../../.specify/memory/constitution.md#xvi-embedded-framework-integration)
still require runtime verification. The widget's Today and Clear buttons are
English; no public localization API or reliable external configuration was
identified. These two buttons alone are an approved temporary exception for the
unpublished 0.8.12 development build, without further library modifications.
The exception does not cover any other text or Dibs components, and does not
approve a stable release. Dibs-authored text remains localized in `src/locales/`.

## Future updates

1. Treat all `libs/` and `Libs/` files as read-only. A new dependency version,
   additional adaptation, or removal requires the project's explicit approval;
   this record does not grant permission to edit, replace, or patch vendored files.
2. Obtain the proposed official release and inspect it outside the repository
   without changing the existing copy. Record its source, revision, archive and
   file hashes, licenses, and required notices.
3. Compare every integrated file against that release, including these three
   substitutions and line endings. Report every difference; do not silently
   reapply changes or presume these adaptations still work with a new version.
4. Before any authorized integration, decide how the read-only rule and asset
   paths will be respected. Verify the selected files, licenses, TOC/XML order,
   package layout, LibStub coexistence and fallbacks, and relevant regression
   tests. Record remaining Retail and Lua 5.1 validation separately.
