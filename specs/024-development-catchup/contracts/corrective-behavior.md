# Corrective Behavior Contract

| Requirement | Surface | Evidence |
|---|---|---|
| FR-001 | Passive selected-claim + local receipt + completed availability | `great_vault_retail_capability_spec.lua` |
| FR-002 | ID or exact full link; names with spaces; legacy and named colors | `great_vault_acquisition_spec.lua` |
| FR-003 | No base tooltip; unique owned preview; exact saved link wins | `great_vault_ui_spec.lua` |
| FR-004 | Left authorized route, right Player; repeated toggle; visibility | `minimap_button_spec.lua` |
| FR-005 | Correct roster online index; offline refuse; retry later | `b04_transport_spec.lua`, `sync_status_spec.lua` |
| FR-006 | Anonymous allowlist export; inclusive period statistics | `audit_export_contract_spec.lua`, `audit_export_ui_spec.lua`, `officer_history_statistics_spec.lua`, `officer_period_statistics_ui_spec.lua` |
| FR-007 | Existing 022/023 contracts remain authoritative | `unified_history_search_spec.lua`, `health_anomaly_contract_spec.lua`, `health_dashboard_ui_spec.lua` |
| FR-008 | Honest retrospective record and open Retail gates | This feature and original 013/022 manual tasks |

All paths above are suite basenames under `tests/`. No table entry certifies
real WoW behavior. Exported reports are not importable accounting packages.
