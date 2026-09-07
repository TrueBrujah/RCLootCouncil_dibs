# Contract: RCLootCouncil and Dibs Authority

## Authority Matrix

| Actor | RCLootCouncil loot session | Finalize qualifying DIB award | Dibs settings/policy | Manual Dibs ledger |
|---|---:|---:|---:|---:|
| Guild Master | According to RCLC role | If verified current ML | Yes | Yes |
| Guild Officer | According to RCLC role | If verified current ML | Yes | Yes |
| Current RCLootCouncil Master Looter, not GM/officer | Yes | Yes, only for a validated local finalized DIB | No | No |
| Raid Leader without ML or guild authority | According to RCLC role | No | No | No |
| Raid Assistant | According to RCLC role | No | No | No |
| Council member | According to RCLC role | No unless also current ML | No | No |
| Ordinary player | Personal RCLC actions allowed by RCLC | No | No | Own permitted views only |

The table describes Dibs authority. RCLootCouncil remains the authority for its own loot
session permissions and award execution.

## Rules

1. Guild GM/officer status is verified from the current guild roster and configured officer
   rank policy.
2. The ML exception applies only to a validated finalized DIB award and its rule-defined
   debit; it does not create a general Dibs permission.
3. Raid roles and council membership alone never grant Dibs administration.
4. Incoming payload fields such as `actor`, `isOfficer`, `isMasterLooter`, or `authority`
   are claims, not proof.
5. Every receiver validates the actual local actor, sender identity, guild scope, and
   applicable RCLootCouncil state at the point of acceptance.
6. Unknown or changing authority is denied.
