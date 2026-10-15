# Data Model: Corrective Development Record

No new persisted entity is introduced.

- Acquisition `itemLink`: original complete variant when captured or supplied;
  retained through existing acquisition storage, not reconstructed from ID.
- Acquisition difficulty: existing Normal/Heroic/Mythic/UNKNOWN source category;
  separate from upgrade track and never used to forge a hyperlink.
- Owned preview: projected item link plus explicit presentation label; never
  written to the acquisition or promoted to confirmed.
- Local minimap visibility: existing per-character boolean; default visible.
- Online identity: existing roster-resolved member plus correct online field;
  unknown identity/authority must not become a valid recipient by default.
- Anonymous report: aggregate/allowlisted values; no executable import package.
- Statistics: read-only projection of existing transactions and selected dates.
