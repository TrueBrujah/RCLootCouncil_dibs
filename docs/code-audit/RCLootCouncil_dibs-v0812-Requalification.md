# Requalification des 16 constats — référence v0812

Date : 2026-11-10. Mode : audit, aucun correctif implémenté.

Ce document devient la référence pour décider des corrections dans le worktree v0812. Il requalifie les constats du [premier rapport](RCLootCouncil_dibs-Audit.md), qui concernait principalement un autre checkout incomplet. Il ne remplace pas cet historique.

## 1. État de référence

- Dossier : C:/Users/yc58/OneDrive/Documents/GitHub/RCLootCouncil_dibs-v0812.
- Branche : 029-seasonal-raid-roster-v0812.
- HEAD : 52e941969134b0e34f3cfdcd26821f20774223b5.
- TOC local : version 0.8.12, build source, interfaces 120100/120105.
- État : changements staged, unstaged et fichiers non suivis préexistants. Ce n'est pas le contenu du seul commit HEAD.
- Empreintes initiales : 930 chemins capturés en mémoire; comparaison finale consignée en section 7.
- Aucun AGENTS.md propre à ce worktree trouvé. Les contraintes projet déjà fournies et AGENTS.md du checkout principal ont été respectés : bibliothèques en lecture seule, préservation des données et des changements.

Les sources et les tests sont lus/exécutés directement dans ce dossier, sans omettre de module et sans adapter le chargeur. Les microreproductions utilisent uniquement des SavedVariables synthétiques en mémoire.

Trois auditeurs spécialisés ont revérifié architecture/saisons, gouvernance/sécurité et WoW/UI; le coordinateur a contrôlé mémoire, tests runtime, limites de compilation et cohérence des preuves. Aucun verdict du premier checkout n'a été repris sur la seule base d'un nom de fichier identique.

## 2. Matrice des 16 constats

**Bilan : 10 confirmés, 3 corrigés, 2 partiellement corrigés, 1 non applicable à l'exécution locale.** Une réussite de test n'est une preuve que pour le scénario effectivement exercé.

| ID | Verdict sur v0812 | Preuve actuelle et portée |
|---|---|---|
| AUD-001 | **Non applicable au chargement local; livraison à vérifier** | 61 entrées TOC, 112 fichiers référencés récursivement : zéro manquant. SeasonalRoster, fixtures et widgets présents. Plusieurs restent non suivis : leur présence locale ne prouve pas leur inclusion dans une livraison Git. |
| AUD-002 | **Corrigé pour le rollback/alias étudié** | ImportExport prépare les ledgers vivants, exclut ledger/ledgers/activeLedgerId de la recopie générique et republie leurs alias. Les régressions normales de préservation des transactions et alias passent. |
| AUD-003 | **Corrigé pour la perte avant erreur** | Apply refuse les collections malformées avant mutation et prépare les réglages dans une copie. Les cas local/guild malformés conservent leurs réglages et retournent une erreur contrôlée. Preview peut encore accepter la forme invalide; le dommage d'Apply est corrigé. |
| AUD-004 | **Confirmé — P1 / HIGH** | Import local merge d'une clé officerRankIndices : un membre devient officier dans les décisions locales. Un replace légitime efface des clés de politique hors scope. Aucun changement de rang Blizzard ni promotion distante démontré. |
| AUD-005 | **Confirmé — P1 / HIGH** | Vrai cycle création/approbation/archivage/suppression de ledger, puis restauration : le ledger réapparaît et son tombstone disparaît. |
| AUD-006 | **Confirmé — P1 / HIGH** | Vraie saison créée par SeasonalRoster : publication du catalogue perd isDraft; archivage de l'ancienne saison sélectionne le brouillon. La voie protégée season.set l'accepte également alors que son cycle roster reste DRAFT. |
| AUD-007 | **Confirmé — P1 / HIGH** | Tuple Blizzard EJ correct : le catalogue synthétique passe de 1 objet à 0, NO_RAID_LOOT_FOUND. La fixture retourne toujours le mauvais tuple. |
| AUD-008 | **Confirmé — P2 / MEDIUM** | Entrée OnAddonMessage sur GUILD : END d'un autre membre rejeté, mais transfert du propriétaire supprimé. |
| AUD-009 | **Partiellement corrigé** | Les annulations libèrent maintenant les packages et les restores ne retiennent que snapshotId. En revanche, des aperçus laissés ouverts/abandonnés restent sans expiration/borne trouvée; ce risque distinct ne doit pas être présenté comme l'ancienne rétention après annulation. |
| AUD-010 | **Corrigé pour la copie avant exclusion** | GetPayload(full) exclut les sous-arbres avant copie. Le test d'absence de copie de la DB complète passe. Backup.Create appelle encore GetPayload deux fois : optimisation résiduelle, sans réattribuer l'ancien défaut. |
| AUD-011 | **Confirmé — P2 / MEDIUM** | Sans AceEvent, runtimeEventsRegistered=true mais l'enregistrement retourne false; PLAYER_LOGIN ne lance pas Initialize. |
| AUD-012 | **Confirmé — P2 / MEDIUM** | Vraie grille et 100 valeurs ABC/abc : tri descendant lève invalid order function for sorting. |
| AUD-013 | **Confirmé — P2 / MEDIUM** | Appel réel Statistics : 8 arguments, argument 7 nil, options en 8e position ignorées par AddTable. |
| AUD-014 | **Confirmé — P2 / MEDIUM; plus latent** | Vraie callback saison A→B et Save : le formulaire conserve les choix de A et réécrit la spécialisation de B. |
| AUD-015 | **Allocation incorrecte confirmée — P2 / MEDIUM** | Colonnes sans poids : budget 502, largeur allouée 1 010, overflow=true. Colonnes Officer : 835 pour un hint 700. Le rendu Retail reste non observé. Correction de calcul du premier rapport : 1 010, pas 1 110. |
| AUD-016 | **Partiellement corrigé — P3 / LOW** | La documentation 029 décrit correctement l'activation comme inachevée. Checkpoint ancien, version de constitution et contrat nommé de promotion restent à réconcilier. |

### Ce qui est réellement corrigé

[ImportExport:500](../../../RCLootCouncil_dibs-v0812/src/modules/ImportExport.lua#L500) prépare les ledgers; les exclusions génériques sont vers 547 et leur publication vers 568. Les [validations d'Apply:469](../../../RCLootCouncil_dibs-v0812/src/modules/ImportExport.lua#L469) et la copie de réglages vers 577 corrigent le scénario destructif malformé.

Les [annulations d'import:460](../../../RCLootCouncil_dibs-v0812/src/modules/ImportExport.lua#L460) et de [restore:200](../../../RCLootCouncil_dibs-v0812/src/modules/Backup.lua#L200) retirent maintenant les entrées pending. PreviewRestore conserve un identifiant de snapshot, pas sa copie complète.

[GetPayload:202](../../../RCLootCouncil_dibs-v0812/src/modules/ImportExport.lua#L202) sélectionne les sections avant de les copier. Les anciens constats « copie entière puis exclusion » et « snapshot retenu après annulation » ne sont donc plus des justifications valides pour modifier ces chemins.

## 3. Liste des corrections nécessaires

### P1 — Corriger d'abord les frontières de données et de saison

**AUD-004 — Scope local de l'import.**

- Sources : [ImportExport:197](../../../RCLootCouncil_dibs-v0812/src/modules/ImportExport.lua#L197), [Apply:577](../../../RCLootCouncil_dibs-v0812/src/modules/ImportExport.lua#L577).
- Préparer un package local exporté, ajouter presentation.officerRankIndices["4"]=true, recalculer le checksum, puis Preview/Apply avec un membre rang 4. Résultat actuel : isOfficer false → true dans le client courant.
- Le service applique toutes les clés entrantes, et replace remplace toute la table settings. La façade UI plus restrictive ne répare pas ce contrat de service.
- **Correction minimale :** whitelist entrante par scope et remplacement limité aux clés de présentation; préserver toutes les clés de politique hors scope.
- **Test à ajouter :** acteur membre réel, injection de clé de politique refusée ou exclue, puis replace légitime conservant exactement les réglages de guilde.
- **Rattachement :** feature 007 FR-015/FR-019; correction CHANGE conforme aux exigences. Aucune décision métier nécessaire.

**AUD-005 — Tombstones lors d'une restauration.**

- Sources : [Backup.keepNewerSharedState:51](../../../RCLootCouncil_dibs-v0812/src/modules/Backup.lua#L51), [Restore:216](../../../RCLootCouncil_dibs-v0812/src/modules/Backup.lua#L216), [Governance:1315](../../../RCLootCouncil_dibs-v0812/src/modules/Governance.lua#L1315).
- Le scénario utilise les services normaux : ProposeLedger → ApproveLedger → ArchiveLedger → Backup.Create(full) → DeleteLedger avec confirmation → PreviewRestore → Restore.
- Résultat actuel : avant restore, ledger absent/tombstone présent; après restore, ledger présent/tombstone absent.
- **Correction minimale :** conserver les tombstones et preuves de suppression vivants, les fusionner puis réappliquer leur exclusion avant de rendre les ledgers restaurés visibles. Ne pas se fier uniquement à la révision générique de gouvernance.
- **Test à ajouter :** le cycle ci-dessus, plus rejeu de restore et import d'un état antérieur à la suppression.
- **Rattachement :** features 007/020 et constitution IV; correction CHANGE, sans nouvelle règle métier.

**AUD-006 — Brouillons exclus des chemins de saison courante.**

- Sources : [CreateSeason:1450](../../../RCLootCouncil_dibs-v0812/src/modules/SeasonalRoster.lua#L1450), [projection du catalogue:96](../../../RCLootCouncil_dibs-v0812/src/modules/Seasons.lua#L96), [GetCurrent/SetCurrent:259](../../../RCLootCouncil_dibs-v0812/src/modules/Seasons.lua#L259), [ApplyCatalog:521](../../../RCLootCouncil_dibs-v0812/src/modules/Seasons.lua#L521).
- Deux chemins reproduits : publication puis archivage de l'ancienne saison; et ProtectedActions.Execute("season.set") sur le brouillon. Le cycle roster reste DRAFT dans les deux cas.
- **Correction minimale à concevoir :** conserver l'état préparatoire à travers le catalogue et refuser sa sélection explicite/implicite, y compris lorsque currentSeasonId est déjà renseigné.
- **Tests à ajouter :** publication locale, réception distante, archive de la saison précédente, premier retour de GetCurrent et action legacy season.set.
- **Rattachement :** feature 029. La compatibilité du catalogue et le marqueur de saison réellement activée doivent être explicités dans ses contrats avant modification. Une protection des brouillons ne doit pas être présentée comme une activation atomique terminée.

**AUD-007 — Contrat EJ et fixture.**

- Sources : [EncounterJournal:839](../../../RCLootCouncil_dibs-v0812/src/integrations/EncounterJournal.lua#L839), [second scan:1310](../../../RCLootCouncil_dibs-v0812/src/integrations/EncounterJournal.lua#L1310), [fixture:454](../../../RCLootCouncil_dibs-v0812/tests/helpers/wow_api.lua#L454).
- Le [code Blizzard 12.1.0](https://github.com/Gethe/wow-ui-source/blob/12.1.0/Interface/AddOns/Blizzard_EncounterJournal/Mainline/Blizzard_EncounterJournal.lua#L1104) consomme name, description, bossID. Le code et la fixture du projet inversent ce contrat.
- **Correction minimale :** lire le premier retour comme nom et le troisième comme identifiant dans les deux scans; corriger la fixture dans le même lot.
- **Test à ajouter :** vraie forme du tuple Blizzard et objet disponible; le catalogue doit rester disponible avec l'identité de boss correcte.
- **Rattachement :** intégration EJ existante, feature 002 et contrats concernés; correction technique, aucun nouveau choix fonctionnel.

### P2 — Robustesse transport, initialisation et UI

| Constat | Sources actuelles | Correction minimale et régression |
|---|---|---|
| AUD-008 | [SyncV2:3261](../../../RCLootCouncil_dibs-v0812/src/modules/SyncV2.lua#L3261) | Vérifier propriétaire et métadonnées avant suppression. END étranger via OnAddonMessage ne doit pas empêcher le transfert initial de finir. Rattacher à la fiabilité Sync existante. |
| AUD-011 | [Core:2620](../../../RCLootCouncil_dibs-v0812/src/Core.lua#L2620), [Ace3:210](../../../RCLootCouncil_dibs-v0812/src/integrations/Ace3.lua#L210) | Choisir le fallback d'événements selon le succès réel; vérifier PLAYER_LOGIN avec skipInitialize et AceEvent absent/Embed défaillant. |
| AUD-012 | [AceGUI:1517](../../../RCLootCouncil_dibs-v0812/src/ui/AceGUI.lua#L1517) | Même clé normalisée pour égalité et comparaison, puis originalIndex. Tester vraie grille, casse et représentations numériques équivalentes. |
| AUD-013 | [OfficerUI:5960](../../../RCLootCouncil_dibs-v0812/src/ui/OfficerUI.lua#L5960) | Retirer l'argument nil surnuméraire; vérifier les options reçues par le helper et le rendu étroit/large. |
| AUD-014 | [PlayerUI:2147](../../../RCLootCouncil_dibs-v0812/src/ui/PlayerUI.lua#L2147), [Save:2280](../../../RCLootCouncil_dibs-v0812/src/ui/PlayerUI.lua#L2280) | Lier le formulaire à seasonId/enrollmentId/revision et recharger le contexte. Test A→B→Save : les valeurs de B ne doivent pas être remplacées par A. Rattacher à 029. |
| AUD-015 | [PlayerUI:2390](../../../RCLootCouncil_dibs-v0812/src/ui/PlayerUI.lua#L2390), [OfficerUI:6425](../../../RCLootCouncil_dibs-v0812/src/ui/OfficerUI.lua#L6425), [allocateur:224](../../../RCLootCouncil_dibs-v0812/src/ui/AceGUI.lua#L224) | Employer poids/minima du helper partagé et définir un comportement lorsque les minima ne tiennent pas. Tester les largeurs calculées, puis Retail. |

La reproduction AUD-014 est désormais complète : A stocke balance/HEALER, B elemental/DAMAGER; le vrai changement de sélection A→B conserve balance/HEALER, et le vrai bouton Save réécrit B avec balance. Il ne s'agit plus d'un défaut latent bloqué par un service absent.

### Risques résiduels et préparation de livraison

- **AUD-009 : aperçus abandonnés.** Annuler est corrigé. Dix Preview d'import sans confirmation/annulation laissent dix packages pending; dix previews de restore laissent dix métadonnées snapshotId. Aucune borne/expiration trouvée. Ajouter une politique de durée/capacité dans feature 007 si cette amélioration est retenue; ne pas effacer l'historique comptable.
- **AUD-010 : copies restantes.** Le défaut initial est corrigé. Une instrumentation en mémoire de GetPayload observe encore deux appels par Backup.Create(full), avant les copies de snapshot. Cela justifie au plus une optimisation ultérieure fondée sur des mesures; aucun gain Retail n'est chiffré ici.
- **AUD-001 : inclusion Git.** Les fichiers non suivis nécessaires au fonctionnement devront être inclus dans la future intégration autorisée. Aucun commit ni staging n'a été effectué par cet audit.
- **Parité du loader :** même ensemble de modules que le TOC, mais DebugLogsUI est avancé dans l'ordre du loader. Aucune panne liée à cette différence n'a été démontrée; alignement à envisager dans la préparation des tests.
- **AUD-016 : documentation.** Le checkpoint référence encore dc388f9/026/027; la constitution annonce 2.8.0 mais conserve 2.7.0 en pied. Le contrat 029 annonce ReviewCorePromotion planifié alors que la promotion existe sous AdminUpdateEnrollment; clarifier l'API documentée.

## 4. Lots de travail proposés

Cette liste est une préparation de correction, pas une modification de tasks.md.

| Ordre | Lot | Critères de fin et dépendances |
|---|---|---|
| 1 | Scope local et conservation des suppressions : AUD-004/005 | Ajouter d'abord les régressions des scénarios confirmés; corriger ImportExport/Backup; tests 007/020, imports, restaurations et permissions. Les deux sous-parties peuvent être préparées séparément, puis validées ensemble. |
| 2 | Isolation des brouillons et contrat EJ : AUD-006/007 | Clarifier le contrat de catalogue dans 029 pour les brouillons; corriger EJ avec sa fixture. Les fichiers et responsabilités sont indépendants. |
| 3 | Propriétaire du transfert et fallback d'événements : AUD-008/011 | Tests au vrai point d'entrée transport et PLAYER_LOGIN sans Initialisation manuelle; préserver rejeu, expiration et chemin Ace3 normal. |
| 4 | UI : AUD-012/013/014/015 | Corriger d'abord les helpers partagés, puis les pages et leur état. Éviter des modifications simultanées du même AceGUI.lua/PlayerUI.lua. Valider sélections de saison, options, tri et fenêtres étroites/larges. |
| 5 | Préparation de livraison et validations externes | Vérifier ensemble source/test réellement intégré, compilation compatible WoW, puis Retail. La politique des previews abandonnées et les optimisations résiduelles peuvent être planifiées après les P1. |

Les lots 1, 3 et les corrections UI conformes aux contrats n'exigent pas de nouvelle règle métier. La modification du catalogue d'activation doit rester dans 029 et suivre sa conception. Aucun cycle SpecKit d'implémentation n'a été déclenché.

## 5. Tests effectivement exécutés

Tous les chemins ci-dessous sont relatifs au dossier v0812. Les suites utilisent le chargeur normal; aucun bypass de SeasonalRoster.

| Lot de tests | Fichiers | Résultat |
|---|---:|---:|
| import_apply_atomicity + rf0033_full_import_ledger_rollback | 2 | 9 PASS / 0 FAIL |
| rf0040_import_export_hardening + backup_import_profiles + b04_transport | 3 | 90 PASS / 0 FAIL |
| runtime_audit_20261028 | 1 | 16 PASS / 0 FAIL |
| seasonal_roster_activation/lifecycle/sync/migration/feature_gate | 5 | 35 PASS / 0 FAIL |
| encounter_journal_catalog + b11_retail_ui004_ownership + seasonal_roster_signup/public/officer_ui | 5 | 33 PASS / 0 FAIL |
| officer_period_statistics_ui | 1 | 4 PASS / 0 FAIL |
| **Total des suites distinctes de cette passe** | **17** | **187 PASS / 0 FAIL** |

Ces réussites n'annulent pas les dix constats : les microreproductions complémentaires exercent des cas absents des suites. En particulier, la fixture EJ erronée et le chargement manuel d'Initialize peuvent masquer les erreurs de contrat/initialisation.

Microreproductions exécutées sans écrire de fichier :

- Lua 5.4.6, services normaux : modification de politique locale, cycle complet de suppression/restore, END réseau étranger, tri réel, options Statistics, changement de saison et Save, allocation des colonnes.
- Fengari, loader normal et vrai SeasonalRoster : brouillon après publication/archive, voie protégée legacy season.set, PLAYER_LOGIN avec AceEvent absent et skipInitialize.
- Lua 5.4.6 : dix previews d'import et dix previews de restore laissées pending; compteur de deux appels GetPayload dans Backup.Create. Ce sont des comptes d'opérations/références, pas des mesures de mémoire WoW.

### Commandes des suites

Depuis v0812, affecter DIBS_TEST_FILES à l'une des sélections suivantes, exécuter lua tests/run.lua, puis retirer la variable d'environnement.

~~~powershell
$env:DIBS_TEST_FILES='tests/integration/import_apply_atomicity_spec.lua;tests/integration/rf0033_full_import_ledger_rollback_spec.lua'
lua tests/run.lua
Remove-Item Env:DIBS_TEST_FILES
~~~

Autres sélections exactes :

~~~text
tests/integration/rf0040_import_export_hardening_spec.lua;tests/integration/backup_import_profiles_spec.lua;tests/unit/b04_transport_spec.lua

tests/integration/runtime_audit_20261028_spec.lua

tests/unit/seasonal_roster_activation_spec.lua;tests/unit/seasonal_roster_lifecycle_spec.lua;tests/integration/seasonal_roster_sync_spec.lua;tests/integration/seasonal_roster_migration_spec.lua;tests/integration/seasonal_roster_feature_gate_spec.lua

tests/unit/encounter_journal_catalog_spec.lua;tests/integration/b11_retail_ui004_ownership_spec.lua;tests/integration/seasonal_roster_signup_ui_spec.lua;tests/integration/seasonal_roster_public_ui_spec.lua;tests/integration/seasonal_roster_officer_ui_spec.lua

tests/integration/officer_period_statistics_ui_spec.lua
~~~

Le guard tests/powershell/Test-DibsLua51Compilation.ps1 retourne **SKIPPED**, compilateur 5.1 absent. Son exit code 0 ne constitue pas une validation de compilation. Aucun outil ni dépendance installé pour contourner cette limite.

## 6. Validations et décisions encore nécessaires

1. **Activation 029 :** PrepareActivationManifest/ValidateActivationManifest sont read-only. T008/T040/T043/T049/T054/T055 restent ouverts. Les 35 tests saisonniers ne prouvent ni commit d'activation ni adoption de manifeste. Le marqueur canonique, les dépendances exactes, l'idempotence et la publication/adoption atomiques nécessitent toujours leur conception cohérente.
2. **Retail :** deux clients, ordre d'arrivée Sync, reprise d'un client incomplet, combat, rendu étroit/large et comportement RC. Aucune exécution réelle dans WoW pendant cette passe.
3. **Compilation :** vérifier avec le compilateur compatible les plafonds upvalues/locales; Lua 5.4 et Fengari ne suffisent pas.
4. **Règle de probation :** conflit 005 durée configurable / 029 quatorze jours fixes toujours à arbitrer avant de modifier cette règle. Aucun choix implicite effectué.
5. **Performances réelles :** aucun nouveau temps de page, FPS ou volume de mémoire attribué à Dibs mesuré. L'amélioration des tests de copie n'autorise pas à déclarer l'addon optimisé en raid.

La prochaine étape recommandée est le lot 1 : **fermer le scope local des imports et préserver les suppressions après restauration**, avec régressions en premier. Le lot brouillons doit être préparé en parallèle sur son contrat 029, sans transformer une protection legacy en activation partielle.

## 7. Préservation de l'état

La comparaison SHA-256 finale des 930 chemins de v0812 ne relève aucune modification, suppression ou création. Les changements staged, unstaged et fichiers non suivis initiaux sont conservés.

git diff --check et git diff --cached --check dans v0812 retournent 0. git diff --check dans le checkout principal retourne aussi 0. Le contrôle des liens locaux de ce rapport ne trouve aucun chemin manquant.

Les seuls livrables écrits sont ce rapport et l'actualisation du rapport initial dans le dossier docs/code-audit du checkout principal. Aucun code, test, spécification, bibliothèque ou SavedVariables réelle n'a été modifié; aucun commit, push, déploiement ou publication effectué.
