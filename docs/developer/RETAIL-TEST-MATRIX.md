# Retail test matrix — RCLootCouncil_dibs

Statut global : **MANUAL_PENDING**

Cette matrice prepare la campagne de validation manuelle dans **WoW
Retail**. Aucun scenario n'a ete execute dans le client : tous les
scenarios `MANUAL_PENDING` sont a realiser.

Regles de statut :

| Statut | Signification |
|---|---|
| `AUTOMATED_PASS` | Le scenario est couvert par un test automatise qui passe. La couverture automatisee ne remplace pas l'execution Retail, elle indique seulement que le chemin de production est exerce en simulation. |
| `MANUAL_PENDING` | Le scenario doit etre execute dans le client. Aucun resultat n'est enregistre. |
| `MANUAL_PASS` | Le scenario a ete execute dans WoW Retail et le resultat observe est conforme. |
| `MANUAL_FAIL` | Le scenario a ete execute dans WoW Retail et le resultat observe ne conforme pas au contrat. |
| `BLOCKED` | Le scenario ne peut pas etre realise dans l'etat actuel (verrou, dependance, environnement). |

**Aucun scenario ne peut etre marque `MANUAL_PASS` sans execution reelle
dans le client.** La compilation Lua et la suite automatisee ne constituent
pas une validation Retail.

---

## 1. Installation et persistance

| # | Scenario | Statut | Couverture automatisee | Observation Retail |
|---|---|---|---|---|
| 1.1 | Installation propre : premiere ouverture, aucun SavedVariable | `AUTOMATED_PASS` | `migration_spec`, `persistence_recovery_spec` | |
| 1.2 | Upgrade depuis la version precedente : les donnees sont conservees | `AUTOMATED_PASS` | `migration_spec`, `rf0027` | |
| 1.3 | Chargement avec des SavedVariables existantes contenant un ledger legacy | `AUTOMATED_PASS` | `rf0027`, `persistence_recovery_spec` | |
| 1.4 | Redemarrage de WoW : l'etat est identique apres rechargement | `MANUAL_PENDING` | `persistence_recovery_spec` | |
| 1.5 | Sauvegarde de demarrage et quarantaine d'une valeur malformee | `AUTOMATED_PASS` | `persistence_recovery_spec` | |

## 2. Guilde et permissions

| # | Scenario | Statut | Couverture automatisee | Observation Retail |
|---|---|---|---|---|
| 2.1 | Un membre ordinaire ne voit pas le ledger des autres joueurs | `AUTOMATED_PASS` | `combat_safety_spec` | |
| 2.2 | Un officier voit le ledger complet de la guilde | `AUTOMATED_PASS` | `combat_safety_spec` | |
| 2.3 | Un membre ordinaire ne peut pas approuver une declaration | `AUTOMATED_PASS` | `rf0014_security_matrix`, `rf0020` | |
| 2.4 | Un Switches de guilde : les donnees de l'autre guilde sont invisibles | `AUTOMATED_PASS` | `guild_isolation_spec`, `local_guild_scope_spec` | |

## 3. Declaration main/alt (RF-0014, RF-0017, RF-0020)

| # | Scenario | Statut | Couverture automatisee | Observation Retail |
|---|---|---|---|---|
| 3.1 | Un joueur declare sa relation main/alt | `AUTOMATED_PASS` | `rf0017_player_group_derivation_spec` | |
| 3.2 | L'officier **approuve** la declaration : le groupe est cree | `AUTOMATED_PASS` | `rf0020_officer_relationship_review_spec` | |
| 3.3 | L'officier **refuse** avec motif : les donnees protegees sont intactes | `AUTOMATED_PASS` | `rf0020_officer_relationship_review_spec` | |
| 3.4 | L'officier **refuse** sans motif : la demande est refusee | `AUTOMATED_PASS` | `rf0020_officer_relationship_review_spec` | |
| 3.5 | Une approbation **ne fusionne jamais** deux joueurs sans lien | `AUTOMATED_PASS` | `rf0014_main_change_group_escape_spec` | |
| 3.6 | La decision persiste apres rechargement | `AUTOMATED_PASS` | `rf0020_officer_relationship_review_integration_spec` | |
| 3.7 | Une decision repetee est dedupliquee | `AUTOMATED_PASS` | `rf0020_officer_relationship_review_integration_spec` | |
| 3.8 | **Surface reelle** : l'onglet d'eligibilite de l'officier liste la declaration en attente et permet de l'approuver | `MANUAL_PENDING` | `rf0020_officer_relationship_review_spec` (logique) | |
| 3.9 | Un changement de main transfere le role de man character | `AUTOMATED_PASS` | `rf0014_main_change_group_escape_spec` | |

## 4. Pre-Dibs (RF-0022, RF-0028, RF-0030, RF-0045)

| # | Scenario | Statut | Couverture automatisee | Observation Retail |
|---|---|---|---|---|
| 4.1 | Pre-Dibs publics **actives** : un joueur soumet une demande publique | `AUTOMATED_PASS` | `rf0022_public_predibs_policy_spec` | |
| 4.2 | Pre-Dibs publics **desactives** : la soumission est refusee **sans ecriture** | `AUTOMATED_PASS` | `rf0022`, `rf0028`, `rf0030` | |
| 4.3 | Un joueur cree une demande privee pour lui-meme | `AUTOMATED_PASS` | `rf0045_predibs_request_integrity_spec` | |
| 4.4 | Une demande conserve son ledger : pas de copie dans un second ledger | `AUTOMATED_PASS` | `rf0045` (A13) | |
| 4.5 | Un joueur ne peut pas annuler la demande d'un autre | `AUTOMATED_PASS` | `rf0045` (A0x) | |
| 4.6 | Une confirmation par un tiers ne peut pas etre forgee par le proprietaire | `AUTOMATED_PASS` | `rf0045` (A18) | |

## 5. Reservation et consommation d'un Dib

| # | Scenario | Statut | Couverture automatisee | Observation Retail |
|---|---|---|---|---|
| 5.1 | Une reservation de Dib est creee a l'attribution d'un objet | `AUTOMATED_PASS` | `rf0031_dib_reservation_release_spec` | |
| 5.2 | La reservation est **liberee** quand la proposition devient terminale | `AUTOMATED_PASS` | `rf0031`, `rf0034` | |
| 5.3 | La liberation est **diffusee** aux pairs | `AUTOMATED_PASS` | `rf0034_peer_reservation_release_spec` | |
| 5.4 | Une reservation liberee ne ressuscite pas apres reconnexion | `AUTOMATED_PASS` | `rf0036_reservation_reconnection_spec` | |
| 5.5 | L'attribution d'un objet consomme exactement un Dib | `AUTOMATED_PASS` | `rclootcouncil_buttons_spec`, `ledger_award_spec` | |
| 5.6 | Le solde ne devient jamais negatif | `AUTOMATED_PASS` | `ledger_operation_spec` | |
| 5.7 | La consommation refuse un joueur non eligible | `AUTOMATED_PASS` | `rclootcouncil_buttons_spec` | |

## 6. Synchronisation multi-clients

| # | Scenario | Statut | Couverture automatisee | Observation Retail |
|---|---|---|---|---|
| 6.1 | Quatre clients convergent sur un meme etat | `AUTOMATED_PASS` | `rf0043_four_client_global_scenario_spec` | |
| 6.2 | Un client hors ligne **perd reellement** le message | `AUTOMATED_PASS` | `distributed_fixture_isolation_spec` (E06) | |
| 6.3 | Le client retrouve le message a la reconnexion | `AUTOMATED_PASS` | `distributed_fixture_isolation_spec` (E07) | |
| 6.4 | Un message duplique ne double compte rien | `AUTOMATED_PASS` | `distributed_fixture_isolation_spec` (E08) | |
| 6.5 | Un expéditeur forge est refuse | `AUTOMATED_PASS` | `distributed_fixture_isolation_spec` (E10) | |
| 6.6 | Le **changement de coordinateur** converge chez les pairs | `AUTOMATED_PASS` | `rf0035_coordinator_handoff_spec` | |
| 6.7 | Le rattrapage d'un Secondary Ledger aboutit | `AUTOMATED_PASS` | `rf0037_secondary_ledger_catchup_spec` | |
| 6.8 | Un snapshot canonique corrompu est refuse | `AUTOMATED_PASS` | `rf0038_canonical_snapshot_spec` | |
| 6.9 | **Synchronisation reelle entre quatre clients Retail** | `MANUAL_PENDING` | `rf0043` (simulation) | |

## 7. Sauvegarde, restauration, importation

| # | Scenario | Statut | Couverture automatisee | Observation Retail |
|---|---|---|---|---|
| 7.1 | Creation d'une sauvegarde complete | `AUTOMATED_PASS` | `rf0041_backup_restore_hardening_spec` B01 | |
| 7.2 | **Restauration** d'une sauvegarde complete : l'historique est retrouve | `AUTOMATED_PASS` | `rf0041` B08, `rf0046` C01 | |
| 7.3 | Une restauration ne remplace pas une chaine partagee plus recente | `AUTOMATED_PASS` | `rf0041` B12, B18 | |
| 7.4 | Une sauvegarde d'une autre guilde est refusee | `AUTOMATED_PASS` | `rf0041` B05, `rf0046` C04 | |
| 7.5 | Une sauvegarde incomplete est refusee avant toute ecriture | `AUTOMATED_PASS` | `rf0041` B03, `rf0046` C05 | |
| 7.6 | Une sauvegarde alteree est refusee | `AUTOMATED_PASS` | `rf0046` C14, `rf0047` D04 | |
| 7.7 | Une sauvegarde volumineuse est restaurable | `AUTOMATED_PASS` | `rf0046` C01 | |
| 7.8 | **Import** d'un paquet de configuration de guilde | `AUTOMATED_PASS` | `backup_import_profiles_spec` | |
| 7.9 | Un import complet ne remplace pas un ledger local plus recent | `AUTOMATED_PASS` | `rf0033_full_import_ledger_rollback_spec` | |
| 7.10 | **Recovery** : un paquet de recovery contradictoire est refuse | `AUTOMATED_PASS` | `rf0042_historical_recovery_hardening_spec` | |
| 7.11 | Sauvegarde et restauration **reelles** dans le client | `MANUAL_PENDING` | — | |

## 8. Litiges

| # | Scenario | Statut | Couverture automatisee | Observation Retail |
|---|---|---|---|---|
| 8.1 | Un joueur soumet une demande | `AUTOMATED_PASS` | `dispute_integrity_hardening_spec` B01 | |
| 8.2 | L'officier demande une information, le joueur repond | `AUTOMATED_PASS` | `dispute_integrity_hardening_spec` B23 | |
| 8.3 | L'officier refuse avec motif | `AUTOMATED_PASS` | `dispute_integrity_hardening_spec` B19 | |
| 8.4 | Un membre ordinaire ne peut pas resoudre un litige | `AUTOMATED_PASS` | `dispute_integrity_hardening_spec` B05 | |
| 8.5 | Un joueur distant ne voit pas la demande d'un autre | `AUTOMATED_PASS` | `dispute_integrity_hardening_spec` B13, B15 | |
| 8.6 | L'historique n'est jamais reecrit par un litige | `AUTOMATED_PASS` | `dispute_integrity_hardening_spec` B11 | |
| 8.7 | Une correction canonique reste **verrouillee** en production | `AUTOMATED_PASS` | `dispute_integrity_hardening_spec` B28, `t013_lock_verification_spec` | |
| 8.8 | Litiges dans le client : soumission, reponse, decision | `MANUAL_PENDING` | — | |

## 9. Validateur de correction canonique (RF-0012) — T041

| # | Scenario | Statut | Couverture automatisee | Observation Retail |
|---|---|---|---|---|
| 9.1 | Le chemin de correction canonique est **ferme** en production | `AUTOMATED_PASS` | `t013_lock_verification_spec`, `protected_actions_ledger_op_spec` | |
| 9.2 | La soumission directe est refusee | `AUTOMATED_PASS` | `canonical_dispute_operation_spec` | |
| 9.3 | L'acceptation par le coordinateur est refusee | `AUTOMATED_PASS` | `canonical_dispute_operation_spec` | |
| 9.4 | Les deux jambes d'un transfert cible sont commitees en une sequence | `AUTOMATED_PASS` | `canonical_dispute_operation_spec` | |
| 9.5 | Un rejeu exact est sans effet | `AUTOMATED_PASS` | `canonical_dispute_operation_spec` | |
| 9.6 | Une operation avec un contenu modifie est refusee | `AUTOMATED_PASS` | `canonical_dispute_operation_spec` | |
| 9.7 | **Campagne Retail T041 (14 scenarios)** | `MANUAL_PENDING` | `docs/developer/rf-0012-retail-test-runbook.md` | |
| 9.8 | **Observations Retail T041 (20 observations)** | `MANUAL_PENDING` | `docs/developer/rf-0012-retail-validation.md` | |

Le statut de T041 reste **`PENDING_MANUAL_VALIDATION`**. L'activation du
chemin de correction canonique en production est **interdite** tant que la
campagne n'est pas terminee.

## 10. Compatibilite RCLootCouncil

| # | Scenario | Statut | Couverture automatisee | Observation Retail |
|---|---|---|---|---|
| 10.1 | RCLootCouncil absent : le coeur de Dibs reste utilisable | `AUTOMATED_PASS` | `rclootcouncil_contract_spec` | |
| 10.2 | RCLootCouncil present : la repartition des reponses est respectee | `AUTOMATED_PASS` | `rclootcouncil_response_normalization_spec` | |
| 10.3 | Un clic DIB refuse est refuse sur un joueur non eligible | `AUTOMATED_PASS` | `rclootcouncil_buttons_spec` | |
| 10.4 | La projection RC ne modifie pas le ledger de l'addon | `AUTOMATED_PASS` | `rclootcouncil_projection_spec` | |
| 10.5 | **RC reel installe en raid** : attribution, reponse, consommation | `MANUAL_PENDING` | — | |

## 11. Combat et securite de l'interface

| # | Scenario | Statut | Couverture automatisee | Observation Retail |
|---|---|---|---|---|
| 11.1 | Aucune action bloquante en combat | `AUTOMATED_PASS` | `combat_safety_spec` | |
| 11.2 | Les rafraichissements sont coalesces | `AUTOMATED_PASS` | `b11_refresh_combat_spec` | |
| 11.3 | Une confirmation d'histoire est data-only en combat | `AUTOMATED_PASS` | `b12_historical_transfer_actions_spec` | |
| 11.4 | En combat : aucune mutation comptable declenchee | `MANUAL_PENDING` | `combat_safety_spec` | |

## 12. Interface et documentation

| # | Scenario | Statut | Couverture automatisee | Observation Retail |
|---|---|---|---|---|
| 12.1 | La fenetre joueur s'ouvre et affiche l'onglet courant | `AUTOMATED_PASS` | `b11_player_ui_spec` | |
| 12.2 | La fenetre officier s'ouvre et affiche l'onglet courant | `AUTOMATED_PASS` | `b11_officer_dashboard_spec` | |
| 12.3 | Le badge d'integration RC respecte la precedence | `AUTOMATED_PASS` | `rf0019_player_eligibility_surface_spec` | |
| 12.4 | Chaque controle a une aide contextuelle, en FR et en EN | `AUTOMATED_PASS` | `localized_ui_help_spec` | |
| 12.5 | **Navigation reelle** dans les deux fenetres | `MANUAL_PENDING` | `b11_officer_navigation_spec` | |
| 12.6 | **Rendu des fenetres** dans le client | `MANUAL_PENDING` | `b11_responsive_ui_spec` | |

## 13. Independant (hors guilde)

| # | Scenario | Statut | Couverture automatisee | Observation Retail |
|---|---|---|---|---|
| 13.1 | Le mode independant n'ecrit aucune donnee de production | `AUTOMATED_PASS` | `b11_sandbox_lifecycle_spec`, `b11_sandbox_scenarios_spec` | |
| 13.2 | Le contexte de developpement est isole de la comptabilite | `AUTOMATED_PASS` | `developer_mode_spec` | |
| 13.3 | Le mode independant en raid | `MANUAL_PENDING` | `independent_raid_spec` | |

## 14. Reprise apres incident

| # | Scenario | Statut | Couverture automatisee | Observation Retail |
|---|---|---|---|---|
| 14.1 | La reconstruction apres une interruption restitue un etat identique | `AUTOMATED_PASS` | `rf0039_projection_rebuild_interruption_spec` | |
| 14.2 | La reconstruction est deterministe | `AUTOMATED_PASS` | `canonical_dispute_operation_spec` | |
| 14.3 | Une operation acceptee mais non projetee est reprenable | `AUTOMATED_PASS` | `canonical_dispute_operation_spec` | |
| 14.4 | **Reprise reelle** apres un redemarrage force | `MANUAL_PENDING` | — | |

---

## Recapitulatif

| Statut | Nombre de scenarios |
|---|---|
| `AUTOMATED_PASS` | 76 |
| `MANUAL_PENDING` | 13 |
| `MANUAL_PASS` | **0** |
| `MANUAL_FAIL` | **0** |
| `BLOCKED` | **0** |
| **Total** | **89** |

Les 13 scenarios `MANUAL_PENDING` sont regroupes en 5 campagnes :

1. **Persistance et redemarrage** (1.4)
2. **Surface de revue officier** (3.8)
3. **Synchronisation reelle entre quatre clients** (6.9)
4. **Sauvegarde, restauration et importation reelles** (7.11)
5. **Litiges reels** (8.8)
6. **Campagne Retail T041** (9.7, 9.8)
7. **Compatibilite RC reelle** (10.5)
8. **Combat et interface reels** (11.4, 12.5, 12.6, 13.3, 14.4)

La publication exige l'execution et la consignation de tous les scenarios
`MANUAL_PENDING`.
