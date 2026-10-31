# Plan de refactoring FUTUR - aucune modification appliquee

## Priorité issue de la passe runtime du 28 octobre 2026

Avant les refactorisations historiques, mesurer le build installé fenêtres
fermées, puis traiter séparément abonnements/signatures d'événements, recherches
de digest et copies de ledgers, rétention des aperçus, intégrité des
imports/restaurations et bornes réseau. Préserver les historiques comptables
et comparer les mêmes volumes/mesures avant et après chaque lot.
Voir [les trois priorités et leurs tests](PERFORMANCE-ARCHITECTURE-SECURITY-20261028.md).
Aucun lot de correction n'est appliqué pendant cet audit.

Le retour 50–60 membres connectés précise deux lots : différer le premier rendu
officier caché pour éviter le scan Journal au reload (RA-16), puis indexer les
demandes par ID une fois par message (RA-01). Tester premier OnShow et invalidation
des demandes avant une réutilisation par génération. Une évolution ultérieure
des annonces vers un heartbeat compact doit conserver la convergence/repair et
les clients mixtes, avec concurrence/budget de calcul bornés. BULK seul régule
le réseau, sans rendre les scans ou les callbacks applicatifs progressifs.

Pour le lag au démarrage avec RC, RA-15 propose un premier changement borné :
utiliser GetCatalogRevision dans LootRules.GetAuthoritySnapshot au lieu de
copier GetCatalogState. Conserver GetCatalogRecord et NormalizeSnapshot;
vérifier les décisions et la prise en compte immédiate des révisions. Deux
tests ciblés reproduisent actuellement les copies inutiles. Comparer le repos
à 30/90/120 secondes avant/après, sans modifier les timers dans le même lot.

| Priorite | RF | Categorie | Action envisagee | Dependances | Risque | Test prealable | Gain estime |
|---|---|---|---|---|---|---|---|
| P1 | [RF-0001](INDEX.md#rf-0001) | Contrat UI | Molette pour le controle personnel sans changer tous les setters | AceGUI/PlayerUI/Slider | LOW local, MEDIUM global | Regression callback + interaction Retail | Taille affichee/appliquee coherente |
| P1 | [RF-0002](INDEX.md#rf-0002) | Projection UI | Preserver false lors du rendu | Getter et checkbox | LOW | Hide puis rerendu Preferences | Preference visible fidele |
| Invariant | [RF-0003](INDEX.md#rf-0003) | KEEP | Conserver bootstrap et API | TOC/PLAYER_LOGIN | MEDIUM | Suite minimap | Pas de regression du raccourci |
| P1 | [RF-0004](INDEX.md#rf-0004) | Robustesse bootstrap | Fallback sur succes reel d'enregistrement | Core/Ace3 | MEDIUM | AceEvent absent/en erreur + absence de doublons | Demarrage degrade fiable |
| Invariant | [RF-0005](INDEX.md#rf-0005) | KEEP | Conserver services Sync partages | TOC/V2/legacy | HIGH | Contrats sync/transport et callers | Eviter suppression incorrecte |
| P2 | [RF-0006](INDEX.md#rf-0006) | Documentation code | Types de messages alignes aux registres | Types/V1/V2/protocol docs | LOW | Comparaison des unions et registres | LuaLS/documentation fiables |
| P3 | [RF-0007](INDEX.md#rf-0007) | Candidat de suppression | Retirer seulement le helper local si encore sans usage | Backup/ImportExport | LOW | Recherche captures + backup/import/profiles | Petit nettoyage verifiable |
| P1 | [RF-0008](INDEX.md#rf-0008) | Etat des profils | Un profil actif coherent par bucket et scope | Profiles/DataUI/persistance | MEDIUM | A->B, scopes, personnages, echec activation | Statut deterministe |
| P2 | [RF-0009](INDEX.md#rf-0009) | Preview de restauration | Afficher les donnees qui seront conservees | Backup/DataUI/sync | MEDIUM | Preview non mutante + etat changeant | Confirmation informee |
| P1 | [RF-0010](INDEX.md#rf-0010) | Diagnostic | Ne pas presenter unknown comme synchronise | SetupAssistant/SyncV2 | MEDIUM | Getter absent/erreur/false/true | Warnings fiables |
| Invariant | [RF-0011](INDEX.md#rf-0011) | KEEP | Garder la delegation des mutations | ProtectedActions/Permissions | HIGH | Setup UI/contrats d'actions | Frontiere UI/domaine preservee |
| P1 | [RF-0012](INDEX.md#rf-0012) | Integrite comptable | Definir une correction ledger-scoped, idempotente, recuperable et canonique sous V2, avec erreurs de mutation explicites | Disputes/ProtectedActions/Permissions/Governance/Ledger/MultiLedger/SyncV2/Backup | HIGH | Echec de chaque jambe/compensation, rejeu stable et apres reopen, follower V2, changement de ledger actif, propagation des rejets, sauvegarde/reprise | Eviter les soldes divergents, faux diagnostics et transferts partiels |
| P1 | [RF-0013](INDEX.md#rf-0013) | Integrite de reconciliation legacy | Rendre les scans multi-sources atomiques/reprenables, aligner le scope et propager les erreurs de lecture/proposition | Installation/HistoricalBaseline/Ledger/MultiLedger/OfficerUI/docs | HIGH | Echec source 2 a la limite, reprise apres collecte partielle, detecteur en erreur, active != primary, echec de proposition officier | Eviter l'approbation d'un baseline incomplet ou un faux succes |

## Suppressions possibles

[RF-0007](INDEX.md#rf-0007) est le seul candidat. Closure locale non exportee,
fichier complet et recherches elargies examines; aucune suppression effectuee.

## Fusions de fonctions

Aucune equivalence demontree a ce stade.

## Fusions de fichiers

Aucune proposition fondee uniquement sur des noms proches ou la taille des fichiers.

## Renommages de symboles ou de fichiers

Conserver les noms publics, serialises et aliases historiques tant que leurs
consommateurs et migrations ne sont pas etablis.

## Ameliorations / decouplages

Traiter les controles personnels avant toute refonte de l'adaptateur generique.
Ne pas modifier les bibliotheques embarquees pour corriger un contrat applicatif.
Backup, Profiles et ImportExport dupliquent des helpers `clone` et les listes
PRESENTATION_KEYS/POLICY_KEYS (dans les deux derniers). Les semantiques de scopes,
confirmation, catalogue et politique ne sont pas equivalentes : pas de fusion
de fichiers recommandee. Un catalogue de cles commun ne pourra etre envisage
qu'apres comparaison des projections et contrats, pas a partir de leur seul nom.

## Ordre propose et criteres de validation

1. Completer la carte d'appels des surfaces concernees.
2. Ajouter les regressions avant toute correction future.
3. Appliquer seulement dans une demande d'implementation separee.
4. Rejouer les tests cibles et les scenarios Retail requis.

Ordre concret propose : RF-0012 (integrite V2 et reprise) et RF-0013
(completude de la reconciliation historique), RF-0004 et RF-0010 (visibilite
des pannes), RF-0008 (etat actif), RF-0001/RF-0002 (controles personnels),
RF-0009 (preview), RF-0006 (types), puis RF-0007 (nettoyage faible impact).
Les numeros RF ne representent pas cet ordre de priorite.

L'audit present autorise exclusivement documentation et annotations autonomes.
