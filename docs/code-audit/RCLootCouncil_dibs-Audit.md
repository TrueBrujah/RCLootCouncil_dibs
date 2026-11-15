# Audit technique — checkout principal et inventaire des worktrees

Date : 2026-11-10. Mode : audit, lecture seule du code, sans implémentation.

> **Référence pour les corrections actuelles :** [requalification sur v0812](RCLootCouncil_dibs-v0812-Requalification.md). Les 16 constats ont été revérifiés sur cet arbre complet : certains sont corrigés, d'autres restent reproduits avec le chargeur normal. Les recommandations de ce premier rapport ne doivent pas être reprises sans cette matrice actualisée. Erratum de calcul : les colonnes publiques du roster totalisent 1 010 pixels, pas 1 110.

> **Portée corrigée après la revue des worktrees :** les quatre analyses détaillées et les constats AUD-001 à 016 concernent le checkout principal, pas toutes les versions du projet. L'absence de sources dans ce checkout ne démontre pas leur perte dans le projet. SeasonalRoster et DatePicker sont présents dans -pr25-integrated et -v0812; les deux suites d'import y passent sans adaptation (9/9 dans chacun). La section L décrit cette comparaison. L'audit initial aurait dû inventorier ces états avant de retenir le checkout principal comme référence.

## A. Résumé exécutif

Le checkout audité présente des protections métier et réseau substantielles, mais plusieurs défauts d'intégrité empêchent de recommander sa publication en l'état. Le problème le plus immédiat est un arbre de sources incomplet : le TOC et le chargeur de tests exigent SeasonalRoster.lua, absent du disque et des fichiers suivis; deux scripts de bibliothèque référencés par embeds.xml manquent également. Les validations historiques de la fonctionnalité 029 ne peuvent donc pas être attribuées à ce checkout.

Les défauts les plus importants concernent les imports complets qui réinstallent un ancien état de ledger, les remplacements de configuration qui effacent avant de valider, les restaurations qui ressuscitent un ledger supprimé, et la sélection d'un brouillon comme saison courante. Un contrat Blizzard incorrect vide également le catalogue du Guide de l'aventurier. Un défaut réseau distinct permet à un membre de guilde d'interrompre le transfert SyncV2 d'un autre émetteur.

Aucun P0, aucune exécution de code par import et aucune écriture arbitraire distante dans le ledger n'ont été démontrés. Cela ne constitue pas une certification de sécurité. Les vérifications réseau et métier inspectées lient effectivement le sender au roster et imposent une autorité pour les écritures canoniques.

Les mécanismes de pagination, regroupement des événements, quotas et instrumentation UI constituent des acquis utiles. Deux chemins restent particulièrement défavorables à la mémoire : les aperçus annulés retiennent leurs données sans borne, et l'export complet copie la base entière avant d'exclure les sauvegardes et aperçus. Ces faits ne démontrent pas que les anciennes observations de 250 Mo ou de faible FPS proviennent exclusivement de ces chemins.

### Périmètre exact et état initial

| Élément | État constaté |
|---|---|
| Checkout | C:/Users/yc58/OneDrive/Documents/GitHub/RCLootCouncil_dibs |
| Branche / HEAD | 029-seasonal-raid-roster / da53a49c564ac7b5abbda96ce5de3ede8ff5a3e6 |
| Version source / TOC | 0.8.12, build « source », interfaces 120100 et 120105 |
| Changements préexistants | 44 chemins suivis modifiés/supprimés; AGENTS.md non suivi; index sans changement staged lors de l'inspection initiale |
| Inventaire | 60 fichiers Lua propriétaires présents, 77 fichiers sous src/libs, 230 suites *_spec.lua présentes; contrôle récursif de chargement : 109 fichiers présents, 3 références absentes |
| Référence d'intégrité | Empreintes SHA-256 de 906 chemins présents/suivis capturées en mémoire avant les tests |
| Instructions | AGENTS.md, constitution, instructions UI; spécifications pertinentes 005, 007, 020, 026, 028 et 029 consultées de façon ciblée |
| Rapport | Dossier documentaire existant docs/code-audit, pour éviter une nouvelle structure reports/audit |

L'audit détaillé initial porte sur les fichiers du checkout principal, y compris leurs modifications locales. Le complément de section L inventorie ensuite les huit worktrees et exécute deux suites ciblées dans -v0812 et -pr25-integrated; il ne constitue pas un audit détaillé complet de ces autres arbres. Aucune version installée de Dibs n'est supposée équivalente. Le dossier installé de RCLootCouncil a seulement été consulté en lecture seule pour vérifier un contrat d'intégration : sa version annoncée est 3.25.0.

Quatre sous-agents distincts ont utilisé GPT-6.1 Sol avec raisonnement élevé : architecture/qualité Lua; gouvernance/sécurité; compatibilité WoW/UI; tests/performance/mémoire. Trois ont travaillé simultanément, puis le quatrième a occupé le créneau libéré. Le coordinateur a vérifié les défauts majeurs dans les sources et reproduit séparément les chemins de saison, de scope d'import et d'entrée réseau. Aucun agent n'a modifié le code, les spécifications ou les bibliothèques.

Les sections suivantes distinguent les défauts reproduits, les preuves statiques, les défauts latents du code 029 et les validations nécessitant Retail. L'inspection est transversale; elle ne prétend pas avoir relu chaque ligne des 60 sources ni exécuté les 230 suites.

## B. Constats techniques priorisés

La priorité exprime l'ordre de traitement; la gravité exprime l'impact. P1 n'implique pas nécessairement une attaque réseau.

| ID | Priorité / gravité | Nature | Sujet |
|---|---|---|---|
| AUD-001 | P1 / HIGH | Confirmé, checkout | Module et tests 029 annoncés mais absents |
| AUD-002 | P1 / HIGH | Reproduit, diagnostic adapté | Import complet : ancien ledger et divergence d'alias |
| AUD-003 | P1 / HIGH | Reproduit, diagnostic adapté | Réglages effacés avant rejet d'un remplacement malformé |
| AUD-004 | P1 / HIGH | Reproduit, diagnostic adapté | Le scope local peut écrire des réglages de politique |
| AUD-005 | P1 / HIGH | Reproduit, diagnostic adapté | Restauration : résurrection d'un ledger supprimé |
| AUD-006 | P1 / HIGH | Reproduit, module isolé | Brouillon sélectionnable comme saison courante |
| AUD-007 | P1 / HIGH | Source Blizzard + diagnostic adapté | Retours EJ mal interprétés, fixture incorrecte |
| AUD-008 | P2 / MEDIUM | Reproduit, entrée réseau simulée | Fin de transfert étrangère détruisant l'état du propriétaire |
| AUD-009 | P2 / MEDIUM | Reproduit, diagnostic adapté | Aperçus annulés et snapshots conservés sans borne |
| AUD-010 | P2 / MEDIUM | Preuve statique + sentinelle | Copie complète avant exclusion des données volumineuses |
| AUD-011 | P2 / MEDIUM | Statique, conditionnel | Fallback d'événements sans AceEvent inopérant |
| AUD-012 | P2 / MEDIUM | Reproduit, vraie grille simulée | Comparateur descendant non strict |
| AUD-013 | P2 / MEDIUM | Confirmé statiquement | Options de la grille Statistics ignorées |
| AUD-014 | P2 / MEDIUM | Défaut latent 029 | Formulaire d'inscription conservé entre saisons |
| AUD-015 | P2 / MEDIUM | Défaut latent 029 | Colonnes dites fluides configurées comme fixes |
| AUD-016 | P3 / LOW | Confirmé documentaire | Statuts et références de validation contradictoires |

### AUD-001 — Sources exigées par le chargement absentes

- **Catégorie :** livraison, architecture, fiabilité des tests. **Confiance : certaine.**
- **Sources :** [TOC:39](../../src/RCLootCouncil_dibs.toc#L39), [chargeur de tests:32](../../tests/helpers/load_addon.lua#L32), [tâches 029:24](../../specs/029-seasonal-raid-roster/tasks.md#L24).
- Les deux listes de chargement référencent modules/SeasonalRoster.lua. Test-Path retourne False; aucune entrée git ls-files ne fournit ce fichier. Les suites seasonal_roster et leur fixture annoncées dans tasks.md sont également absentes.
- Le contrôle récursif TOC/XML révèle aussi l'absence de src/libs/LibAceGUIWidgets/LibAceGUIWidgets-1.0.lua et LibAceGUIWidgets-DatePicker.lua, référencés dans [embeds.xml:10](../../src/embeds.xml#L10). Le dossier existe, mais ses scripts attendus n'y sont pas présents. Ce constat vise le contenu de la dépendance fournie, pas son implémentation interne; aucune bibliothèque n'a été modifiée. Le mécanisme d'externals et le contenu d'une archive produite n'ont pas été exécutés ou certifiés.
- **Scénario et preuve :** les suites normales d'import, de setup et d'audit export échouent dans load_addon.lua:270 avant leur première validation métier : 0 succès / 14 échecs, répartis sur deux commandes et quatre fichiers.
- **Impact :** service saisonnier indisponible, couverture 029 non démontrable, build source incomplet. Le comportement exact de WoW face au fichier TOC manquant n'a pas été observé : ne pas en déduire que tous les scripts suivants cessent nécessairement de charger.
- **Recommandation :** retrouver la provenance vérifiée des sources et tests attendus, reconstruire un checkout cohérent, vérifier l'existence de toutes les entrées TOC/XML puis relancer les tests normaux. Un module vide ne constituerait pas un correctif.

### AUD-002 — Import complet : retour à un ancien ledger

- **Catégorie :** intégrité comptable. **Confiance : élevée.**
- **Sources actives :** [ImportExport.GetPayload:205](../../src/modules/ImportExport.lua#L205), [ImportExport.Apply:468](../../src/modules/ImportExport.lua#L468), [MultiLedger:57](../../src/modules/MultiLedger.lua#L57).
- L'export complet contient la carte db.ledgers. Apply valide/fusionne certaines transactions dans l'alias db.ledger, puis recopie toutes les clés du payload sauf ledger et preDibs. Il réinstalle donc db.ledgers depuis l'ancien export.
- **Scénario :** exporter, ajouter une transaction, puis importer l'ancien export; autre variante : changer l'état après l'aperçu et confirmer cet aperçu.
- **Preuve :** harness adapté, suites Import Apply/RF-0033 : quatre échecs ciblés incluant rollback et divergence d'alias. RF-0040 échoue sur A16, A17 et A25, notamment préservation d'une transaction récente et d'un changement postérieur à la preview.
- **Impact :** db.ledger et db.ledgers[activeLedgerId] peuvent diverger; un réalignement ultérieur utilise l'objet restauré. Le résultat visible peut perdre un solde ou un historique plus récent. Les ledgers secondaires entrants ne passent pas la même validation transactionnelle.
- **Frontière de confiance :** import manuel autorisé; aucune voie d'import automatique réseau identifiée.
- **Recommandation :** conserver les ledgers vivants, préparer une fusion append-only validée pour chaque ledger, revalider la fraîcheur à l'application et publier les résultats cohérents avec leurs alias. L'absence de remplacement du seul alias ledger ne protège pas la carte ledgers.

### AUD-003 — Remplacement malformé : effacement avant validation

- **Catégorie :** atomicité, configuration. **Confiance : élevée.**
- **Sources :** [Decode:279](../../src/modules/ImportExport.lua#L279), [Preview:317](../../src/modules/ImportExport.lua#L317), [mergeInto:358](../../src/modules/ImportExport.lua#L358), [Apply:478](../../src/modules/ImportExport.lua#L478).
- Decode/Preview laissent passer un nombre dans payload.presentation ou payload.settings. En stratégie replace, mergeInto vide la table cible avant d'appeler pairs sur cette valeur.
- **Scénario :** préparer un package correctement encodé et recalculer son checksum avec presentation=7 ou settings=7; confirmer un aperçu replace.
- **Preuve :** les deux régressions atteignent Apply avec le harness adapté : theme/defaultAllocation deviennent nil, puis une exception est levée.
- **Impact :** configuration partiellement perdue; le résultat n'est ni un refus contrôlé ni une opération atomique. Le scope local n'a pas le snapshot de sécurité employé pour guild/full.
- **Recommandation :** validation de forme dès Preview, révalidation avant Apply, calcul du résultat hors des tables vivantes, publication après toutes les validations. Préserver les réglages à l'identique en cas d'erreur.

### AUD-004 — Scope local : politique modifiable par les données importées

- **Catégorie :** frontière de scope, autorisations locales. **Confiance : élevée sur la mutation démontrée.**
- **Sources :** [listes de clés et roleAllowed:183](../../src/modules/ImportExport.lua#L183), [Apply:478](../../src/modules/ImportExport.lua#L478), [Permissions.rankIsOfficer:163](../../src/modules/Permissions.lua#L163); [feature 007 FR-015/019](../../specs/007-backup-export-import-profiles/spec.md#L137).
- PRESENTATION_KEYS filtre l'export, mais pas l'entrée d'Apply. Le scope local est autorisé au niveau service sans condition administrative. Un package local peut donc fournir officerRankIndices ou officerMaxRankIndex dans presentation.
- **Preuve :** diagnostic du coordinateur avec Player-Realm au rang 5 : Preview(local, merge) et Apply réussissent, et settings.officerRankIndices["5"] devient true. Un replace de présentation légitime peut également effacer les réglages hors de son scope.
- **Impact :** dérive de politique locale et incohérence des décisions fondées sur ces réglages.
- **Limite de sécurité :** la façade UI ProtectedActions protège data.import par l'autorité GM. Le scénario démontre une frontière de service/données incorrecte, pas un accès UI normal d'un joueur ni une escalade réseau. Un addon local partage déjà les tables Lua; ce fait n'est pas une attaque distante.
- **Recommandation :** rejeter les clés étrangères au scope entrant et remplacer uniquement les champs de présentation autorisés, en préservant les clés de politique.

### AUD-005 — Restauration complète : ledger supprimé ressuscité

- **Catégorie :** intégrité, cycle de suppression et récupération. **Confiance : élevée.**
- **Sources :** [Backup.keepNewerSharedState:51](../../src/modules/Backup.lua#L51), [Backup.Restore:164](../../src/modules/Backup.lua#L164), [MultiLedger.ApplyLedgerDeletion:460](../../src/modules/MultiLedger.lua#L460), [Governance.RecordLedgerDeletion:946](../../src/modules/Governance.lua#L946).
- Restore réinstalle l'ancien payload. keepNewerSharedState préserve certaines chaînes révisionnées et les ledgers encore vivants; il ne fusionne pas les marqueurs ledgerDeletionTombstones. L'enregistrement de suppression n'avance pas nécessairement la révision/hash servant à préserver la gouvernance.
- **Scénario :** sauvegarde full contenant un ledger archivé L; suppression autorisée de L; restauration de la sauvegarde.
- **Preuve :** diagnostic adapté : avant restauration, ledger absent et tombstone présent; après restauration réussie, ledger présent et tombstone absent.
- **Impact :** résurrection locale d'un ledger supprimé et perte de sa protection contre réapparition. La propagation ultérieure à d'autres clients n'a pas été reproduite et dépend des chemins de publication.
- **Recommandation :** conserver/fusionner les tombstones et preuves de suppression vivants indépendamment des révisions ordinaires; les réappliquer après restauration/import avant visibilité des ledgers. Ajouter une régression snapshot → suppression → restauration.

### AUD-006 — Brouillons : isolation perdue et activation legacy

- **Catégorie :** transitions de saison, intégrité fonctionnelle. **Confiance : élevée.**
- **Sources :** [normalizeCatalogSeasons:96](../../src/modules/Seasons.lua#L96), [createSeason:229](../../src/modules/Seasons.lua#L229), [GetCurrent/SetCurrent:259](../../src/modules/Seasons.lua#L259), [PublishCatalog:449](../../src/modules/Seasons.lua#L449), [ApplyCatalog:521](../../src/modules/Seasons.lua#L521), [ProtectedActions:134](../../src/modules/ProtectedActions.lua#L134).
- CreateDraft pose isDraft=true. La normalisation du catalogue omet ce champ, puis ApplyCatalog remplace les saisons locales par cette projection, y compris sur l'émetteur. GetCurrent peut sélectionner toute saison non archivée sans isDraft, même avec isActive=false. SetCurrent accepte directement un brouillon sans contrôle du manifeste.
- **Preuve :** module Seasons réel chargé seul, identité/autorité/temps/hash synthétiques : après PublishCatalog, isDraft=nil; après ArchiveSeason de l'ancienne saison, currentSeasonId vise le brouillon alors que isActive=false. SetCurrent sur un nouveau brouillon retourne aussi true.
- **Impact :** les prochaines opérations lisant la saison courante peuvent viser une saison préparatoire sans prévalidation du roster ou des allocations. Ce défaut existe dans Seasons présent, indépendamment de l'absence du service 029.
- **Contrat :** [029 FR-042/047](../../specs/029-seasonal-raid-roster/spec.md#L226). L'activation atomique T043/T054/T055 reste explicitement inachevée; l'absence de cette future fonction n'est pas assimilée seule à un bogue caché.
- **Recommandation :** préserver les états de brouillon dans le contrat de catalogue et fermer les sélections automatiques/legacy des brouillons; définir ensuite l'unique activation canonique et sa barrière SyncV2. Tester publication locale/distante et archivage de la saison précédente.

### AUD-007 — Contrat Blizzard EJ inversé et mock trompeur

- **Catégorie :** compatibilité Retail, fidélité des tests. **Confiance : élevée.**
- **Sources :** [getJournalEncounterDetails:837](../../src/integrations/EncounterJournal.lua#L837), [autre scan:1310](../../src/integrations/EncounterJournal.lua#L1310), [fixture:451](../../tests/helpers/wow_api.lua#L451).
- Le code lit le premier retour d'EJ_GetEncounterInfoByIndex comme identifiant et le deuxième comme nom. Le code Blizzard 12.1.0 consomme le nom, la description puis l'identifiant de boss. [Source primaire, ligne 1104](https://github.com/Gethe/wow-ui-source/blob/12.1.0/Interface/AddOns/Blizzard_EncounterJournal/Mainline/Blizzard_EncounterJournal.lua#L1104).
- **Scénario :** une rencontre nommée « Test boss » possède un objet. Avec le tuple fictif id/name, GetLootCatalog retourne 1 entrée et available=true. Avec le tuple Blizzard name/description/id, il retourne 0 entrée et available=false.
- **Impact :** scans arrêtés au premier boss, catalogue et association boss/objet dégradés. La fixture actuelle reproduit la même erreur de contrat et laisse réussir ses tests.
- **Recommandation :** corriger les deux lectures et la fixture ensemble, conserver une régression fondée sur le tuple Blizzard. Les valeurs de retour sont vérifiées; l'ensemble du parcours Retail reste à tester.

### AUD-008 — Fin de transfert étrangère : déni de service SyncV2

- **Catégorie :** sécurité réseau, disponibilité. **Confiance : élevée.**
- **Source :** [SyncV2.Receive:3110](../../src/modules/SyncV2.lua#L3110).
- TRANSFER_END supprime v2Transfers[transferId] avant de comparer le sender du transfert au membre réseau résolu.
- **Preuve renforcée du coordinateur :** passage par OnAddonMessage, sérialisation simulée, canal GUILD et entité GOVERNANCE. Un BEGIN valide du GM crée le transfert. Un END du membre Player-Realm avec le même ID/type retourne INVALID_TRANSFER_END, mais le transfert GM a déjà disparu.
- **Conditions :** membre vérifié de la même guilde et connaissance de l'ID, observable pour un transfert GUILD. Aucun besoin de se faire passer pour le GM : l'enveloppe de l'attaquant conserve sa vraie identité.
- **Impact :** interruption répétable des transferts et retards de convergence sous attaque active; aucune corruption comptable directe déduite.
- **Recommandation :** vérifier propriétaire, type, ledger et métadonnées avant toute suppression; conserver le transfert légitime lors d'une fin étrangère. Tester le vrai point d'entrée réseau et deux senders distincts.

### AUD-009 — Aperçus annulés : références persistantes sans borne

- **Catégorie :** mémoire, SavedVariables, cycle de vie. **Confiance : élevée.**
- **Sources :** [ImportExport.Preview:354](../../src/modules/ImportExport.lua#L354), [annulation:421](../../src/modules/ImportExport.lua#L421), [Backup.PreviewRestore:146](../../src/modules/Backup.lua#L146), [annulation:157](../../src/modules/Backup.lua#L157).
- Une annulation change decision mais ne retire ni pendingImports/package ni pendingRestores/snapshot. Aucune borne ou expiration de ces entrées n'a été trouvée.
- **Preuve :** 10 imports et 10 restores annulés laissent 10 packages et 10 références de snapshot. Après 8 sauvegardes supplémentaires, la liste backups respecte sa rétention de 5, mais les restores annulés conservent encore le snapshot retiré de cette liste.
- **Déclencheur/fréquence/volume :** une entrée par aperçu manuel; croissance avec le nombre d'aperçus. Limites d'encodage : package portable 250 000 octets, sauvegarde 32 Mio; ce ne sont pas des tailles de tables Lua mesurées. Les 10 références au même snapshot ne signifient pas 10 copies de ce snapshot.
- **Impact :** croissance persistante de références et conservation de données en dehors de la politique visible de backup. Aucune fuite native de frames ni mesure de mémoire retenue après GC Retail démontrée.
- **Recommandation :** libérer les données volumineuses après annulation/confirmation; conserver seulement les métadonnées d'audit nécessaires; borner et expirer les aperçus abandonnés. Préserver l'historique comptable.

### AUD-010 — Copie complète de la DB avant exclusion

- **Catégorie :** allocations temporaires, latence des opérations de données. **Confiance : élevée.**
- **Sources :** [ImportExport.GetPayload:205](../../src/modules/ImportExport.lua#L205), [Backup.Create:91](../../src/modules/Backup.lua#L91).
- GetPayload(full) effectue clone(db), puis enlève backups, pendingImports, pendingRestores et auditLog. Backup.Create appelle ce chemin et Export, qui reconstruit également le payload.
- **Preuve :** une sentinelle placée dans un backup est parcourue lors de GetPayload(full), bien que payload.backups soit nil. La sentinelle utilise __pairs sous Lua 5.4; la preuve de coût repose aussi directement sur l'ordre clone/exclusion.
- **Coût :** O(base vivante + backups + pending + audit) par copie, plusieurs copies possibles dans une opération de backup. Déclencheurs : export full, backup full et snapshots de sécurité de certaines opérations. Aucun coût par frame n'est établi par ce constat.
- **Impact :** pics d'allocation et pauses possibles, amplifiés par AUD-009. Pas d'imbrication durable récursive de backups affirmée : les champs sont bien exclus du payload final.
- **Recommandation :** construire le payload à partir des seules sections autorisées avant de les copier; réutiliser un payload validé entre préparation et encodage. Vérifier temps et mémoire transitoire sur des bases synthétiques représentatives, puis Retail.

### AUD-011 — Fallback AceEvent inopérant

- **Catégorie :** initialisation, dégradation contrôlée. **Confiance : élevée; condition d'occurrence externe.**
- **Sources :** [Core.SetupRuntimeEvents:2602](../../src/Core.lua#L2602), [Ace3.RegisterEvent:209](../../src/integrations/Ace3.lua#L209).
- Core teste l'existence du wrapper RegisterEvent, toujours présent, puis ignore ses retours false. Quand AceEvent ou son intégration manque, le frame natif n'est donc pas configuré et runtimeEventsRegistered est malgré tout fixé à true.
- **Impact conditionnel :** absence des événements Core, dont PLAYER_LOGIN et l'initialisation prévue. La bibliothèque est embarquée normalement; aucune panne AceEvent réelle observée dans le client.
- **Recommandation :** choisir le fallback selon le succès réel d'enregistrement et poser l'état enregistré après installation effective. Tester bibliothèque absente et échec d'Embed.

### AUD-012 — Tri descendant : comparateur invalide

- **Catégorie :** UI partagée, données. **Confiance : élevée.**
- **Source :** [AceGUI.sortGrid:1520](../../src/ui/AceGUI.lua#L1520).
- La comparaison emploie les minuscules ou les conversions numériques, mais l'égalité emploie les valeurs d'origine. Pour ABC/abc ou certaines représentations numériques équivalentes, le tri descendant peut retourner true dans les deux sens.
- **Preuve :** vraie AddTable du projet et 12 lignes alternant ABC/abc : gridState.Sort(1, "desc") lève « invalid order function for sorting » sous Lua 5.4, avec le harness adapté.
- **Impact :** pages/grilles interrompues ou ordre instable selon les données; pas un défaut limité au roster 029.
- **Recommandation :** une seule clé normalisée pour comparaison/égalité, puis originalIndex pour départager les égalités. Conserver le test via l'API de grille.

### AUD-013 — Statistics : options de table perdues

- **Catégorie :** UI, contrat de helper. **Confiance : élevée.**
- **Sources :** [OfficerUI:5854](../../src/ui/OfficerUI.lua#L5854), [signature AddTable:1210](../../src/ui/AceGUI.lua#L1210).
- renderStatisticsPage fournit un nil surnuméraire : la table d'options arrive en huitième argument d'une fonction qui en reçoit sept.
- **Impact certain :** options de colonnes fluides, largeur, géométrie, menu et emptyText de cet appel ignorées. Aucun débordement précis n'a été mesuré dans le client.
- **Recommandation :** rétablir le bon argument et tester les options transmises, puis les rendus étroit/large.

### AUD-014 — Formulaire saisonnier conservé entre saisons

- **Catégorie :** état UI. **Confiance : élevée statiquement; défaut latent.**
- **Sources :** [PlayerUI:2148](../../src/ui/PlayerUI.lua#L2148), [initialisation:2218](../../src/ui/PlayerUI.lua#L2218).
- Le changement de saison ne réinitialise ni les champs ni seasonalRosterFormLoaded. Les initialisations par ancienneValeur or inscriptionSélectionnée gardent le personnage, la spécialisation, la voie ou les rôles de la saison précédente.
- **Impact potentiel après restauration du service :** formulaire mélangeant le contexte B et les données saisies pour A. Aucune soumission saisonnière actuelle n'est affirmée : SeasonalRoster manque.
- **Recommandation :** lier le brouillon à seasonId/enrollmentId/revision; recharger ou préserver explicitement le brouillon de chaque contexte. Tester navigation A → B → A.

### AUD-015 — Tables 029 : largeur fluide sans poids

- **Catégorie :** géométrie UI. **Confiance : élevée sur les constantes; défaut latent.**
- **Sources :** [PlayerUI:2391](../../src/ui/PlayerUI.lua#L2391), [OfficerUI:6312](../../src/ui/OfficerUI.lua#L6312), [AllocateFluidColumnWidths:225](../../src/ui/AceGUI.lua#L225).
- Les colonnes concernées n'ont pas de weight positif; l'allocateur les traite comme fixes. L'option shrinkToFit n'est pas consommée. Sommes configurées : 1 010 pixels pour la table publique et 835 pour l'Officer; ce sont des calculs statiques, pas des mesures client. Le calcul public a été corrigé lors de la requalification.
- **Impact plausible :** repli des cellules et désalignement dans une fenêtre étroite. Le rendu saisonnier est bloqué par AUD-001.
- **Recommandation :** réutiliser les colonnes pondérées du helper partagé et définir le comportement quand les minima dépassent l'espace disponible. Aucun nouveau système UI nécessaire.

### AUD-016 — Documentation de validation ambiguë

- **Catégorie :** gouvernance technique, traçabilité. **Confiance : élevée.**
- **Sources :** [tâches 029](../../specs/029-seasonal-raid-roster/tasks.md), [checkpoint](../ai/CHECKPOINT.md#L6), [index historique](INDEX.md), [constitution:519](../../.specify/memory/constitution.md#L519).
- Les tâches cochées citent des sources/tests absents du checkout. Le checkpoint référence dc388f9 et les fonctionnalités 026/027. L'index contient RF-0033 « FIXED », tout en comportant un avertissement plus récent signalant que les imports échouent. La constitution annonce 2.8.0 dans son rapport d'amendement mais conserve 2.7.0 en pied.
- **Impact :** des résultats exacts pour un autre arbre peuvent être interprétés comme preuve du build présent; risque de décisions de release incorrectes.
- **Recommandation :** associer chaque validation au checkout, SHA et état local; conserver les constats historiques avec une mention claire de leur portée, réconcilier les statuts sans effacer l'historique. L'audit n'a modifié aucun de ces artefacts.

## C. Architecture et responsabilités

~~~mermaid
flowchart TD
  TOC[TOC et embeds XML] --> Core[Core et racine SavedVariables]
  Core --> Domain[Identité, politiques, saisons, rangs]
  Domain --> Ledger[Ledger et MultiLedger]
  Ledger --> Workflow[PreDibs, contestations, pipeline loot]
  Workflow --> Sync[Table Dibs.Sync : base V1 puis remplacements V2]
  Sync --> Missing[Entrée SeasonalRoster absente]
  Missing --> Services[Installation, Wizard, Readiness]
  Services --> Ace[Adaptateur Ace3 puis intégrations]
  Ace --> UI[Helpers UI, PlayerUI, OfficerUI]
~~~

Le graphe représente l'ordre de chargement principal, pas une liste exhaustive de dépendances. Les appels vers des modules chargés plus tard sont généralement différés à l'exécution. Aucune panne normale par cycle d'initialisation n'a été démontrée.

Core possède la racine persistante et le routage de guilde; Identity/Permissions définissent l'identité et l'autorité; Governance/OperationalPolicy portent les décisions; Seasons/RankRules la configuration saisonnière; Ledger les transactions et projections; MultiLedger la sélection et le cycle des registres. Les intégrations RC/EJ et l'UI consomment ces services.

Le principal coût architectural démontré est la multiplication des chemins de remplacement : ImportExport et Backup restaurent directement de grandes parties du même état que Ledger/MultiLedger protègent autrement. Les garanties ne sont donc pas uniformes selon la porte d'entrée. AUD-002/003/005 justifient une frontière commune de validation/publication des données; la taille des fichiers ne suffit pas à justifier une réécriture.

SyncV2 réutilise Dibs.Sync et remplace ses points d'entrée, dont Send, Receive, BuildManifest, OnAddonMessage et RegisterTransport. La façade Dibs.SyncV2 n'est pas un deuxième moteur complet. Des helpers/snapshots V1 restent disponibles : leur statut de compatibilité doit être explicite avant retrait. Le fallback compact historique sans AceComm n'est pas le transport actif; V2 refuse l'indisponibilité du transport.

L'activation 029 exige une tranche cohérente : préparation détachée des allocations, publication locale unique du ledger/politique/saison/manifeste, puis adoption distante lorsque toutes les révisions et empreintes concordent. Un rollback après plusieurs mutations n'est pas une transaction. Ce rapport ne valide pas cette architecture future et n'en a implémenté aucune partie.

## D. Gouvernance DIBS, persistance et frontières de confiance

Points favorables observés : les chemins canoniques du ledger vérifient l'autorité; les commits distants vérifient le coordinateur; les propositions relayées vérifient le rôle et l'acteur; le modèle ordinaire de correction reste append-only. Les anciens constats généraux de solde négatif ou de mutateurs réseau sans autorisation ne sont pas reconfirmés ici.

Les problèmes démontrés sont ciblés : les imports/restaurations peuvent remplacer des données protégées; les tombstones ne survivent pas correctement à certaines restaurations; les brouillons restent accessibles au sélecteur legacy. Le regroupement personne/Main/Alt et l'activation complète sont encore des travaux 029 prévus, sans preuve de fonctionnement de bout en bout dans cet arbre.

Une contradiction métier doit être arbitrée : [005 FR-015](../../specs/005-character-loot-eligibility/spec.md#L131) exige une durée de probation configurable; [029 FR-019](../../specs/029-seasonal-raid-roster/spec.md#L211) exige 14 jours à chaque approbation. [ApproveMainChange:527](../../src/modules/CharacterEligibility.lua#L527) accepte une date d'effet et une durée bornée entre 0 et 365 jours, avec défaut 14 jours. Ce n'est pas classé comme contournement confirmé tant que le contrat normatif n'est pas unifié.

Un addon installé localement partage les globales et les SavedVariables. Les arguments actor/internal/bootstrap accessibles par Lua ne sont donc pas assimilés à une faille réseau à eux seuls. Les scénarios d'import supposent une action locale ou un appel de service; AUD-008 constitue, lui, une interruption réseau démontrée avec l'identité réelle du membre.

## E. Compatibilité WoW et UI

Le TOC cible 12.1.0/12.1.5. Les sources Blizzard correspondant à 12.1.0 confirment le défaut de tuple EJ d'AUD-007. La présence des API modernes C_EncounterJournal et C_Item inspectées ne prouve pas que tous les parcours ou tous les retours sont compatibles.

Le code de l'intégration RC inspecté reporte des mutations UI lorsque InCombatLockdown l'exige. Aucune violation de protection Blizzard ni erreur de secret value n'a été démontrée. Le message historique « insecure scripts exceeded execution limit » indique un dépassement de temps; son nom ou le fichier d'un error handler ne démontre pas l'origine d'un problème de sécurité.

Risque d'affichage à vérifier : la copie installée de RCLootCouncil 3.25.0 réactive ses boutons dans Modules/lootFrame.lua:498–512 à chaque OnUpdate de la barre de temps lorsque les communications sont autorisées. Dibs applique leur état après LootFrame.Update et protège également OnRoll ([intégration:2168](../../src/integrations/RCLootCouncil.lua#L2168)). Une réactivation visuelle entre deux projections est plausible; aucune consommation indue n'est déduite, car le garde OnRoll reste présent. Test Retail nécessaire avec candidat inéligible et timer actif.

L'UI bénéficie déjà de tables partagées, pagination et gestion des fenêtres. Les recommandations portent sur les défauts AUD-012 à 015; elles ne remettent pas en cause les améliorations de performance existantes et ne demandent pas de nouvelle identité visuelle.

## F. Performance et mémoire

| Chemin | Déclencheur / fréquence | Volume / rétention | Conclusion |
|---|---|---|---|
| Aperçus import/restore | Action utilisateur, une entrée par aperçu | Packages/snapshots persistants, annulation sans libération | Défaut confirmé AUD-009 |
| Export/backup full | Action ou snapshot de sécurité | Copie de la DB et sections exclues après copie; répétition possible | Coût O(volume total) confirmé AUD-010 |
| SyncV2 | Startup, heartbeat 60 s, roster stabilisé | 8 transferts simultanés, 8 192 octets par payload, TTL 300 s; bornes d'index/replay | Pas de file de transfert sans borne démontrée |
| Événements roster | Regroupement après environ 1 s; garde lifecycle rapproché de 5 s | Travail dépendant des registres/demandes | Mesurer le nombre de scans sous rafale réelle |
| RequestDelivery | Retry 60 s; rappels espacés | Pending limité à 128, au plus 3 rappels par batch | Bornes favorables observées |
| DebugLogs / compteurs UI | Logs et instrumentation opt-in | Log runtime 300; agrégats UI limités à 512 couples kind/page | Pas de samples infinis trouvés |
| Caches RC par type/item | Consultation de règles et objets | Pas de cardinalité maximale observée pour deux caches de session | Risque P3, non fuite démontrée |

Les coûts de Sync dépendent aussi de l'historique et des ledgers; le seul nombre de membres en ligne ne décrit pas toute la charge. Aucune nouvelle attribution des 250 Mo historiques, aucun temps de page Retail et aucune comparaison FPS avant/après n'ont été mesurés par cet audit. Le delta de heap global de l'instrumentation reste bruité par le GC, sans attribution à un addon et sans mesure du volume total alloué. Les compteurs imbriqués ne doivent pas être additionnés comme des coûts indépendants.

Mesure Retail recommandée après rétablissement du build : même personnage/endroit et configuration RC, relever startup puis repos 60 s et 5 min, pages froides/chaudes, 20 ouvertures/fermetures, raid 20/60 joueurs, rafale loot/sync, puis reload. Capturer temps synchrone et travail asynchrone séparément; mémoire retenue après stabilisation et pics temporaires séparément. Comparer Dibs+RC, RC seul et Dibs seul dans des conditions comparables. Ne pas copier la DB dans l'instrumentation, journaliser chaque événement, ni forcer un GC en boucle.

## G. Tests : exécutions et limites

Outils utilisés : Lua natif 5.4.6 et PowerShell. Node 24.13.0 et Fengari sont présents, mais aucun nouveau résultat Fengari n'est revendiqué ici. Aucune installation de dépendance.

| Exécution | Résultat réel | Interprétation |
|---|---|---|
| Normal : import_apply_atomicity + rf0033_full_import_ledger_rollback | 0 PASS / 7 FAIL | Tous arrêtés par SeasonalRoster absent; scénarios métier non atteints |
| Normal : setup_assistant_contract + audit_export_contract | 0 PASS / 7 FAIL | Même blocage avant scénarios |
| Adapté : import_apply_atomicity + RF-0033 | 3 PASS / 4 FAIL | Scénarios d'import réellement atteints; défauts AUD-002/003 reproduits |
| Adapté : RF-0040 + permissions + character_eligibility + encounter_journal_catalog | 44 PASS / 3 FAIL | A16/A17/A25 échouent; autres contrôles limités aux fixtures |
| Adapté : RF-0040 seul, confirmation | 23 PASS / 3 FAIL | Répétition de confirmation, pas une nouvelle couverture |
| Module Seasons isolé | Brouillon perdu puis sélectionné; SetCurrent(draft)=true | AUD-006; identité/autorité/hash synthétiques, aucune validation réseau de catalogue |
| Micro-diagnostics adaptés | Restore/tombstone, tri, EJ, rétention et copie reproduits | Résultats détaillés dans les constats et l'annexe |
| Entrée OnAddonMessage simulée GUILD | END étranger rejeté mais transfert effacé | AUD-008, vérifie aussi le canal/type du point d'entrée |
| Guard PowerShell Lua 5.1 | SKIPPED : compilateur 5.1 absent | Plafonds d'upvalues/variables WoW non validés |
| Retail / deux clients réels | NON EXÉCUTÉ | Combat, secret values, rendu, FPS, mémoire et convergence réelle non certifiés |

Un harness adapté remplace uniquement le chargement du service absent par une fonction vide, en mémoire. Il laisse inchangés les fichiers du dépôt et les chemins d'import/backup/Sync/UI testés. Il permet de diagnostiquer ces chemins indépendants; il ne constitue pas un build fonctionnel et ne valide aucune fonctionnalité 029.

Les tests EJ qui réussissent avec le faux tuple constituent une lacune de fidélité des fixtures, pas une preuve de compatibilité Blizzard. La réussite sous Lua 5.4 ne couvre pas les limites propres au compilateur WoW. Les fixtures déjà marquées ACTIVE ou les aperçus read-only ne prouvent pas une vraie activation.

Tests prioritaires à ajouter lors d'une future phase d'implémentation : présence TOC/XML; imports typés et scoped; conservation des transactions/alias après aperçu obsolète; restauration respectant les tombstones; brouillons exclus des chemins legacy; tuple EJ Blizzard; deux senders sur le vrai point d'entrée Sync; tri à clés normalisées égales; libération des aperçus annulés. Pour l'activation : erreurs injectées avant commit, révisions exactes, ordre des dépendances, rejeu et maintien de l'ancienne saison.

## H. Dette technique et contradictions

1. **Frontières de mutation inégales :** import, restore et writers canoniques ne conservent pas les mêmes invariants. Bénéfice attendu d'un contrat commun : prévenir des retours arrière et régressions de récupération.
2. **Contrats API simulés trop librement :** le tuple EJ montre qu'un mock peut valider précisément l'erreur de production. Aligner les fixtures sur des sources de version ciblée.
3. **Saison canonique et voie legacy coexistantes :** le catalogue et les sélecteurs peuvent contourner l'isolation de brouillon, indépendamment du service 029 manquant.
4. **Cycle de vie des données temporaires :** les objets pending survivent à leur annulation et aux limites visibles des backups.
5. **Traçabilité des validations :** les sources et résultats de différents worktrees sont facilement confondus. Un SHA seul ne décrit pas un arbre dirty.

Réconciliation des anciens rapports : RV-003/004 sont reconfirmés par diagnostics adaptés; leur statut historique « FIXED » ne décrit pas ce checkout. Le fallback Sync historique ne doit pas être réintroduit comme défaut actif : SyncV2 refuse l'absence du transport. Les accusations générales de permissions absentes ou de solde négatif ne sont pas reconfirmées. Les optimisations UI historiques ne sont ni déclarées perdues ni certifiées intégralement : les helpers présents montrent ces mécanismes, mais seul le build complet et ses tests pourront établir leur état final.

## I. Plan d'amélioration proposé, sans implémentation

| Ordre | Action / constats | Bénéfice | Risque du changement | Effort | Dépendances / Spec Kit |
|---|---|---|---|---|---|
| P0 | Aucun défaut de cette priorité démontré | — | — | — | Ne pas confondre absence de P0 et feu vert release |
| P1-1 | Rétablir un arbre source/test cohérent, AUD-001 | Tests normaux et feature vérifiables | Mauvaise provenance ou mélange de worktrees | Moyen | Vérifier l'historique; aligner les preuves 029 |
| P1-2 | Sécuriser import full et scopes, AUD-002/003/004 | Préserver ledger et configuration | Compatibilité des anciens packages | Moyen/élevé | Contrat 007 existant; préciser migration si format change |
| P1-3 | Préserver tombstones après restore, AUD-005 | Empêcher résurrection de ledgers | Conflits de récupération à expliciter | Moyen | Contrat de suppression MultiLedger/constitution |
| P1-4 | Fermer activation legacy des brouillons, AUD-006 | Saison courante cohérente | Compatibilité du catalogue distant | Moyen | 029/contrat catalogue; activation complète ensuite |
| P1-5 | Aligner EJ et fixture, AUD-007 | Catalogue boss/objets utilisable | Variantes de retour selon API ciblée | Faible | Contrat Blizzard, test technique ciblé |
| P2-1 | Vérifier ownership avant suppression Sync, AUD-008 | Disponibilité des transferts légitimes | Rejeu/expiration à préserver | Faible | Protocole existant, correction technique |
| P2-2 | Finir cycle pending et copies full, AUD-009/010 | Mémoire et pauses réduites sur opérations de données | Compatibilité audit/reprise d'aperçu | Moyen | Politique de données temporaires; pas de suppression d'historique |
| P2-3 | Corriger fallback événementiel, tri et options, AUD-011/012/013 | Robustesse startup/UI | Régressions de tri/layout | Faible/moyen | Tests de helpers et scénarios absents/AceEvent |
| P2-4 | Revalider formulaires et largeurs 029, AUD-014/015 | Inscriptions et rendu cohérents | Conservation des brouillons utilisateur | Moyen | AUD-001, UI réelle et tests A/B saisons |
| P3 | Harmoniser preuves/version documentaire; borner caches seulement si utile | Maintenance et diagnostics fiables | Faible | Faible/moyen | AUD-016; mesures avant optimisation optionnelle |

Ordre de validation après corrections : tests techniques ciblés → matrice import/restore/ledger/sync → compilation compatible WoW → scénario 029 depuis état propre → deux clients Retail → mesures mémoire/FPS. Aucun statut de tâche ne doit être coché sur la seule base d'une reproduction avec le harness adapté.

## J. Décisions nécessitant une approbation

| Décision | Options | Recommandation et justification | Conséquences / travaux dépendants |
|---|---|---|---|
| Référence à intégrer pour retrouver 029 | Récupérer les fichiers manquants depuis une provenance vérifiée; ou reporter 029 et retirer ses points d'entrée dans un changement séparé | Reconstituer l'historique et les sources correspondant aux contrats approuvés avant intégration | Choix des commits à reprendre; ne pas copier aveuglément le worktree voisin |
| Probation Main/Alt | 14 jours fixes; durée configurable; politique saisonnière avec défaut 14 jours et exceptions auditables | Clarifier le contrat saisonnier, puis documenter explicitement toute exception; le besoin historique exprimait des règles ajustables | Harmoniser features 005/029, UI et tests; aucune durée changée par cet audit |
| Contrat d'activation canonique | Publication locale unique et manifeste comme barrière distante; ou maintien temporaire des services séparés avec activation indisponible | Préparation détachée + publication unique + adoption après dépendances exactes; conserver l'ancienne saison sur client incomplet | Évolution architecturale Spec Kit de T008/T040/T043/T049/T054/T055 avant implémentation cohérente |
| Récupération de données déjà affectées | Réparation assistée depuis backups/export/historique; ou investigation préalable sans mutation | Examiner d'abord des copies synthétiques/anonymisées et les preuves de provenance; ne pas deviner les transactions ni ressusciter des registres | Une réparation réelle des SavedVariables doit faire l'objet d'un périmètre et d'une confirmation séparés |

Les corrections purement techniques compatibles avec les exigences ne nécessitent pas de nouvelle décision métier. Cette mission reste un audit : aucune de ces options n'a été appliquée.

## K. Cinq améliorations principales

1. Retrouver un checkout complet et attribuer les tests au bon arbre avant toute conclusion de livraison.
2. Faire respecter les invariants du ledger par les imports et restaurations, y compris les tombstones et les alias.
3. Empêcher toute sélection d'un brouillon en dehors de la future activation canonique.
4. Corriger le tuple Blizzard EJ et les fixtures, puis préserver les transferts légitimes contre une fin étrangère.
5. Libérer les données d'aperçus terminés et éviter les copies de sections qui seront exclues du payload.

Défauts confirmés : AUD-001 à 013 selon les niveaux de preuve indiqués. Défauts latents : AUD-014/015. Dette documentaire : AUD-016. Risques restant à vérifier : réactivation visuelle RC, croissance des caches de session, charge en raid, mémoire retenue réelle et compatibilité Retail complète.

## L. Complément — comparaison des huit worktrees

L'inventaire initial était trop restrictif pour représenter l'ensemble du projet. Les états de travail sont différents et plusieurs portent des modifications non commitées importantes. Un même HEAD ne signifie donc pas que les sources sont identiques.

| Worktree (suffixe) | Branche | HEAD | SeasonalRoster présent | Suites seasonal_roster présentes | DatePicker présent |
|---|---|---|---|---|---|
| Principal | 029-seasonal-raid-roster | da53a49 | Non, mais référencé au TOC | 0 | Non |
| -pr25-ci | fix/pr25-fengari-memory | 81ca714 | Non, non référencé au TOC | 0 | Non |
| -pr25-fixes | fix/pr25-release-blockers | 81ca714 | Non, non référencé au TOC | 0 | Non |
| -pr25-history | fix/pr25-main-catchup | 6411d9e | Non, non référencé au TOC | 0 | Non |
| -pr25-integrated | docs/v0.8.11-release-notes | 52e9419 | Oui | 8 | Oui |
| -pr25-ui-release | release/v0.8.11-ui-performance | 7d2c7a7 | Non, non référencé au TOC | 0 | Non |
| -release-v0810 | release/v0.8.10-catch-up | ada6c04 | Non, non référencé au TOC | 0 | Non |
| -v0812 | 029-seasonal-raid-roster-v0812 | 52e9419 | Oui | 13 | Oui |

L'absence du service 029 dans les branches historiques qui ne le chargent pas n'est pas un défaut de ces branches. L'anomalie AUD-001 concerne le checkout principal qui le référence sans le fournir.

### Contre-vérification des imports dans les deux arbres plus complets

Les deux commandes normales, sans wrapper de chargement, ont été exécutées depuis chacun des dossiers -pr25-integrated et -v0812 :

~~~powershell
$env:DIBS_TEST_FILES='tests/integration/import_apply_atomicity_spec.lua;tests/integration/rf0033_full_import_ledger_rollback_spec.lua'
lua tests/run.lua
Remove-Item Env:DIBS_TEST_FILES
~~~

Résultat dans chacun : **9 passed, 0 failed (2 files)**. Les régressions vérifient notamment les remplacements malformés, les collections full invalides, les projections malformées, la préservation d'un grant récent, la cohérence des alias et le refus d'une seconde voie d'import canonique. Les défauts AUD-002/003 du checkout principal ne doivent donc pas être appliqués à ces deux arbres sur la seule base de l'audit initial.

### Différences de code et limites

Les empreintes de six fichiers critiques ont été comparées : ImportExport.lua, Backup.lua, Seasons.lua, SyncV2.lua, EncounterJournal.lua et ui/AceGUI.lua.

- Dans -pr25-integrated, aucun de ces six fichiers n'est identique à celui du checkout principal.
- Dans -v0812, seul Seasons.lua est identique; les cinq autres diffèrent.
- Plusieurs branches historiques partagent certains de ces fichiers avec le checkout principal; cette identité ne remplace pas l'examen de leurs appels, dépendances et tests.
- AUD-006 reste pertinent à vérifier dans -v0812, puisque son module Seasons est identique et que la reproduction isolée utilise ce module. Les intégrations saisonnières complètes de cet arbre n'ont pas été auditées dans ce complément.
- Le seul fait qu'un fichier diffère ne prouve pas qu'un défaut est corrigé. Inversement, un défaut d'un checkout ancien ou incomplet n'est pas une preuve de défaut dans un autre.

Les prochains audits détaillés doivent désigner un arbre complet comme référence et examiner ses différences, plutôt que reprendre automatiquement les 16 constats initiaux. Aucun fichier de ces autres worktrees n'a été modifié, copié ou fusionné. Aucun déploiement n'a été effectué.

## Annexe — Commandes et reproductions

### Exécutions normales

Depuis le checkout audité, Lua 5.4.6 :

~~~powershell
$env:DIBS_TEST_FILES='tests/integration/import_apply_atomicity_spec.lua;tests/integration/rf0033_full_import_ledger_rollback_spec.lua'
lua tests/run.lua
Remove-Item Env:DIBS_TEST_FILES

$env:DIBS_TEST_FILES='tests/contract/setup_assistant_contract_spec.lua;tests/contract/audit_export_contract_spec.lua'
lua tests/run.lua
Remove-Item Env:DIBS_TEST_FILES
~~~

Chaque commande retourne 0 passed, 7 failed; cause commune : failed to load src/modules/SeasonalRoster.lua, fichier introuvable.

### Harness adapté des suites existantes

~~~powershell
$env:DIBS_TEST_FILES='tests/integration/import_apply_atomicity_spec.lua;tests/integration/rf0033_full_import_ledger_rollback_spec.lua'
@'
local original = loadfile
loadfile = function(path, ...)
  if path == 'src/modules/SeasonalRoster.lua' then return function() end end
  return original(path, ...)
end
dofile('tests/run.lua')
'@ | lua -
Remove-Item Env:DIBS_TEST_FILES
~~~

Résultat : 3 passed, 4 failed. Le lot élargi utilise le même wrapper avec :

~~~powershell
$env:DIBS_TEST_FILES='tests/integration/rf0040_import_export_hardening_spec.lua;tests/unit/permissions_spec.lua;tests/unit/character_eligibility_spec.lua;tests/unit/encounter_journal_catalog_spec.lua'
~~~

Résultat : 44 passed, 3 failed, tous les échecs dans RF-0040. Le guard exécuté est tests/powershell/Test-DibsLua51Compilation.ps1; résultat SKIPPED, compilateur 5.1 absent.

### Préambule des micro-diagnostics, uniquement en mémoire

Les blocs Lua ci-dessous peuvent être envoyés à lua - par une here-string PowerShell, sans créer de test ou modifier de source. Le préambule est nécessaire pour chaque exécution indépendante.

~~~lua
package.path = 'tests/?.lua;tests/?/init.lua;' .. package.path
unpack = unpack or table.unpack
register_reset = function() end
local original = loadfile
loadfile = function(path, ...)
  if path == 'src/modules/SeasonalRoster.lua' then return function() end end
  return original(path, ...)
end
local _, d = require('helpers.load_addon').load({
  withAce3 = true,
  wow = {
    playerName='Tester-Realm', guildLeader=true,
    guildMembers={'Tester-Realm','Owner-Realm','Officer-Realm','Player-Realm'},
    guildRankIndices={0,3,1,3}
  }
})
~~~

### Entrée réseau simulée GUILD — AUD-008

~~~lua
local function deliver(m,s)
  local e=assert(d.Sync.BuildEnvelope(m))
  e.senderNameRealm=s
  e.senderMemberKey=string.lower(s)
  return d.Sync.OnAddonMessage('DIBS',d.Ace3.Serialize(e),'GUILD',s)
end
local ok,why=deliver({
  type='TRANSFER_BEGIN',transferId='guild-owned',
  entityType='GOVERNANCE',entityId='1',revision=1,
  contentHash='content',payloadHash='payload',chunkCount=1
},'Tester-Realm')
print(ok,why,d.runtime.v2Transfers['guild-owned']~=nil)
local ended,reason=deliver({
  type='TRANSFER_END',transferId='guild-owned',entityType='GOVERNANCE'
},'Player-Realm')
print(ended,reason,d.runtime.v2Transfers['guild-owned']~=nil)
~~~

Sorties : true / TRANSFER_STARTED / true, puis false / INVALID_TRANSFER_END / false.

### Scope local et politique — AUD-004

Après le préambule, recharger une fixture avec un joueur non officier :

~~~lua
local _, d = require('helpers.load_addon').load({
  withAce3=true,
  wow={
    playerName='Player-Realm',guildLeader=false,
    guildMembers={'GM-Realm','Player-Realm'},guildRankIndices={0,5}
  }
})
local _,p=d.ImportExport.Export('local')
p.payload.presentation.officerRankIndices={['5']=true}
p.checksum=nil
local unsigned=assert(d.ImportExport.Encode(p))
p.checksum=d.ImportExport.Checksum(unsigned:sub(#d.ImportExport.PACKAGE_PREFIX+1))
local encoded=assert(d.ImportExport.Encode(p))
local preview=assert(d.ImportExport.Preview(encoded,'local','merge','Player-Realm'))
local applied,reason=d.ImportExport.Apply(
  preview.previewId,true,'manual local import','Player-Realm')
print(applied~=nil,reason,d.GetDB().settings.officerRankIndices['5'])
~~~

Sortie : true / nil / true. Ce diagnostic appelle le service; il ne contourne ni n'exerce la façade UI GM.

### Restauration après suppression — AUD-005

~~~lua
local db=d.GetDB()
db.ledgers['archived-test']={
  id='archived-test',name='Old',status='ARCHIVED',
  transactions={},playerStates={},canonical={nextSeq=1}
}
local snap=assert(d.Backup.Create('full','before-delete','Tester-Realm'))
local deleted=d.MultiLedger.ApplyLedgerDeletion('Tester-Realm','archived-test',{})
print(deleted.ok,db.ledgers['archived-test']==nil,
  db.ledgerDeletionTombstones['archived-test']~=nil)
local p=assert(d.Backup.PreviewRestore(snap.snapshotId,'Tester-Realm'))
local restored=d.Backup.Restore(p.previewId,true,'repro','Tester-Realm')
print(restored~=nil,db.ledgers['archived-test']~=nil,
  db.ledgerDeletionTombstones and db.ledgerDeletionTombstones['archived-test']~=nil)
~~~

Sorties : true / true / true, puis true / true / nil.

### Tri et tuple EJ — AUD-012/007

~~~lua
local shell=assert(d.AceGUI.CreateWindow('test',900,650))
local rows={}
for i=1,12 do rows[i]={i%2==0 and 'ABC' or 'abc'} end
local grid=d.AceGUI.AddTable(shell,shell.window,{{title='Name'}},rows,300)
print(pcall(grid._dibsDataGrid.Sort,1,'desc'))
local wow=require('helpers.wow_api')
wow.installEncounterJournalContext({
  raidInstances={{id=900,name='Test raid'}},
  encounters={[900]={{id=901,name='Test boss'}}},
  loot={[901]={{itemID=280001,name='Test item',
    link='|Hitem:280001::::::::::::|h[Test item]|h|r'}}}
})
local a,ma=d.EncounterJournal.GetLootCatalog('',{refresh=true,limit=20})
print(#a,ma.available)
EJ_GetEncounterInfoByIndex=function(index,instanceID)
  if index==1 and instanceID==900 then
    return 'Test boss','Description',901,nil,nil,nil,900
  end
end
local b,mb=d.EncounterJournal.GetLootCatalog('',{refresh=true,limit=20})
print(#b,mb.available)
~~~

Sorties : false / invalid order function for sorting; puis 1 / true et 0 / false.

### Rétention d'aperçus et copie — AUD-009/010

~~~lua
local text=d.ImportExport.Export('local')
local db=d.GetDB()
for i=1,10 do
  local p=assert(d.ImportExport.Preview(text,'local','merge'))
  assert(d.ImportExport.Apply(p.previewId,false,'cancel'))
end
local ni=0
for _,v in pairs(db.pendingImports) do
  ni=ni+1
  assert(v.preview.decision=='cancelled' and v.package)
end
local snap=assert(d.Backup.Create('full','memory','Tester-Realm'))
for i=1,10 do
  local p=assert(d.Backup.PreviewRestore(snap.snapshotId,'Tester-Realm'))
  assert(d.Backup.Restore(p.previewId,false,'cancel','Tester-Realm'))
end
local nr=0
for _,v in pairs(db.pendingRestores) do
  nr=nr+1
  assert(v.preview.decision=='cancelled' and v.snapshot)
end
print('CANCELLED RETAINED',ni,nr,#db.auditLog)
for i=1,8 do assert(d.Backup.Create('full','prune','Tester-Realm')) end
local pinned,inlist=0,false
for _,v in pairs(db.pendingRestores) do
  if v.snapshot.snapshotId==snap.snapshotId then pinned=pinned+1 end
end
for _,v in ipairs(db.backups) do
  if v.snapshotId==snap.snapshotId then inlist=true end
end
print('BACKUP',#db.backups,inlist,pinned)
local reads=0
db.backups={{payload=setmetatable({marker=true},{
  __pairs=function(t) reads=reads+1; return next,t,nil end
})}}
local payload=d.ImportExport.GetPayload('full')
print('COPY',payload.backups==nil,reads)
~~~

Sorties : CANCELLED RETAINED 10 / 10 / 43; BACKUP 5 / false / 10; COPY true / 1. Les affectations concernent exclusivement les tables synthétiques du processus de test.

### Saison brouillon — AUD-006, sans chargeur adapté

~~~lua
local function copy(v)
  if type(v)~='table' then return v end
  local out={} for k,x in pairs(v) do out[k]=copy(x) end return out
end
time=function() return 1700000000 end
Dibs={
  db={seasons={},settings={},rankRules={}},DeepCopy=copy,
  GetGuildKey=function() return 'test-guild' end,
  GetPlayerName=function() return 'GM-Realm' end,
  Identity={CreateSnapshot=function()
    return {memberKey='gm-realm',displayName='GM-Realm'}
  end},
  OperationalPolicy={CanWrite=function() return true end},
  Sync={CalculateContentHash=function() return 'synthetic-hash' end}
}
Dibs.GetDB=function() return Dibs.db end
assert(loadfile('src/modules/Seasons.lua'))()
local old=Dibs.Seasons.Create('Old')
local draft=assert(Dibs.Seasons.CreateDraft('Draft','draft'))
assert(Dibs.Seasons.PublishCatalog('GM-Realm'))
print('draft flag',Dibs.db.seasons[draft.id].isDraft)
Dibs.Seasons.ArchiveSeason(old.id)
print('current is draft',Dibs.db.currentSeasonId==draft.id)
local nextDraft=assert(Dibs.Seasons.CreateDraft('Another','another'))
print('SetCurrent draft',Dibs.Seasons.SetCurrent(nextDraft.id))
~~~

Sorties : draft flag nil; current is draft true; SetCurrent draft true. Ce scénario n'examine pas la résistance du hash ou des permissions simulés.

### Intégrité finale

La comparaison SHA-256 finale des 906 chemins préexistants ne révèle aucune modification, suppression ou substitution. Le seul chemin ajouté est docs/code-audit/RCLootCouncil_dibs-Audit.md. Les changements locaux initiaux et l'index ont été préservés.

git diff --check et git diff --cached --check retournent 0. Le contrôle des liens locaux du rapport ne trouve aucun lien manquant. Les avertissements Git de conversion LF/CRLF concernent des fichiers déjà modifiés avant l'audit; aucun correctif de formatage n'a été appliqué.

Aucun test de ce rapport n'a utilisé les SavedVariables réelles. Aucun commit, push, déploiement, build de package, publication ou cycle d'implémentation Spec Kit n'a été exécuté. L'unique livrable écrit est ce rapport.
