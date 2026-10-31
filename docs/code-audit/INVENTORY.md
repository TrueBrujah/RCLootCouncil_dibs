# Inventaire du depot Lua

## Instantané runtime du 28 octobre 2026

Le TOC charge 58 Lua applicatifs sur 59 présents; Types.lua n'est pas exécuté.
77 fichiers de bibliothèques sont protégés. L'ordre et les tailles sont consignés
dans [RUNTIME-INVENTORY-20261028.json](RUNTIME-INVENTORY-20261028.json).
Les fonctions de transport de SyncV2 remplacent celles de Sync; les bibliothèques,
tests, documents et scripts d'audit ne font pas partie du même périmètre chargé.
Le test ajouté rc_startup_work_audit_spec.lua mesure des copies et des ticks
synthétiques, sans ajout au TOC et sans modification de l'installation WoW.
Les sondes sync_guild_scale_audit_spec et startup_catalog_work_audit_spec
comptent les lectures sur burst de pairs et au rendu du dashboard caché;
elles ne constituent pas un test de 60 clients WoW natifs.
Voir [la revue runtime](PERFORMANCE-ARCHITECTURE-SECURITY-20261028.md) pour la
couverture effective de cette passe, qui ne reprend pas une certification des
58 sources à partir d'un ancien checkpoint.

## Perimetre / exclusions

Audit preparatoire du projet complet, base `dc388f9df313f1597e5c1a35078bb725c34c7f3e`,
branche `dev`, 2026-10-18. Aucun refactoring autorise.

Le [recensement machine](MACHINE-INVENTORY.json) contient les chemins du depot,
les definitions nommees, references `Dibs.*`, candidats de registrations dynamiques,
la carte de chargement et les suites de tests. C'est une analyse par expressions
regulieres, pas un parseur Lua ni une preuve d'accessibilite.

- 58 fichiers Lua de premiere partie dans `src/`, 49 233 lignes physiques.
- 235 fichiers Lua hors bibliothèques couverts par la [baseline](BASELINE.json), sources, tests et outils compris.
- 77 fichiers protégés sous `src/libs/` (dont 47 Lua), couverts par empreintes brutes strictes.
- 164 suites `*_spec.lua` recensees, pas toutes relues.
- Sources applicatives : 58 fichiers Lua dans `src/` hors bibliothèques; **58
  audits complètement, 0 partiellement, 0 uniquement inventorié**. Décompte
  reconstruit sur preuves observables (tag `@AUDIT` ou ligne de session
  nommant le fichier) : voir
  [AUTONOMOUS-SESSION-STATUS](AUTONOMOUS-SESSION-STATUS.md#reconciliation-full--partial--inventoried-session-6).
- Bibliothèques externes : le seul répertoire trouvé est `src/libs/`; lecture uniquement pour les contrats, aucun RF interne, annotation ou modification. La protection couvre tous les fichiers, pas seulement les 47 Lua inventoriés par l'ancienne baseline.
- Fichiers générés : `MACHINE-INVENTORY.json` et `BASELINE.json` sont des sorties d'outils, pas des modules applicatifs; la baseline n'est mise à jour que par le garde d'intégrité. Archives ZIP, journaux et données personnelles restent exclus des modifications; aucun contenu de journal privé utilisé.
- Inventaire global termine; revue semantique exhaustive **terminee** : les 58
  sources applicatives ont ete revues. Le detail des lectures humaines est
  dans [PROGRESS](PROGRESS.md) et
  [AUTONOMOUS-SESSION-STATUS](AUTONOMOUS-SESSION-STATUS.md). Cette revue ne
  remplace pas la validation Retail.

## Chargement TOC / XML

Source normative : [TOC](../../src/RCLootCouncil_dibs.toc).
Ordre exact des chemins et inclusions dans `runtime_load_graph` du recensement machine.

| Chemin | Charge par | Ordre / condition | Preuve |
|---|---|---|---|
| [embeds.xml](../../src/embeds.xml) | TOC | Avant Core | LibStub, MSA, CallbackHandler, SharedMedia, LibWindow, AceEvent, AceTimer, AceGUI, AceConfig, AceComm, AceSerializer |
| [Core.lua](../../src/Core.lua) | TOC | Apres bibliotheques | Creation de l'espace partage et fonctions appelees plus tard |
| [Locales](../../src/locales) | TOC | EN puis FR | Fallback et textes separes |
| [Modules](../../src/modules) | TOC | Apres locales | Definitions de services; ordre a conserver |
| [GreatVault.lua](../../src/integrations/GreatVault.lua) | TOC | Entre PreDibs et CharacterEligibility | Exception explicite dans la sequence des modules |
| [Adaptateurs](../../src/integrations) | TOC | Apres les modules principaux | Ace3, sandbox, Encounter Journal, RCLootCouncil |
| [UI](../../src/ui) | TOC | Apres adaptateurs | Midnight puis adaptateurs UI, etat, composants, controleurs |
| [RCLootCouncilOptions.lua](../../src/integrations/RCLootCouncilOptions.lua) | TOC | Dernier fichier | Integration des options apres creation des services/UI |
| [Types.lua](../../src/Types.lua) | Editeur, pas TOC | Annotation-only, intentionnel | En-tete et [documentation des modules](../developer/modules.md) |

La presence physique d'une bibliotheque ne prouve pas son chargement.
L'inclusion AceConfigDropdown est commentee dans
[AceConfig-3.0.xml](../../src/libs/AceConfig-3.0/AceConfig-3.0.xml) :
ne pas classer ce chemin inexistant comme une dependance manquante.
Les XML de tiers non atteints depuis `embeds.xml` ne sont pas des points d'entree
confirmes du runtime de cet addon.

## Fonctions et responsabilites

Tous les fichiers ci-dessous ont ete recenses; cette table ne signifie pas qu'ils
ont tous fait l'objet d'une revue ligne par ligne. Les definitions nommees et
les candidats de callbacks sont indexes par fichier dans le recensement machine.

L'etat d'analyse ci-dessous est celui de la session 4. Le detail des lectures
humaines et des sections restantes est dans
[PROGRESS](PROGRESS.md) et
[AUTONOMOUS-SESSION-STATUS](AUTONOMOUS-SESSION-STATUS.md).

| Module | Fichiers concernes | Role / exposition observee | Analyse terminee ? |
|---|---|---|---|
| Racine | [Core.lua](../../src/Core.lua), [Types.lua](../../src/Types.lua) | Namespace, facade, bootstrap / declarations LuaLS | **COMPLET** — Core : amorcage, facade `Dibs.CoreAPI`, facade de mutation, portee joueur. Types : annotations seules, lu integralement ; `DibsSyncMessageType` decrit le registre V1 et non V2 (fiche [RF-0006](INDEX.md#rf-0006) ouverte, risque LOW). |
| Locales | [enUS.lua](../../src/locales/enUS.lua), [frFR.lua](../../src/locales/frFR.lua) | Textes et aide, tables partagees | **COMPLET** — 978 cles de chaque cote, 0 ecart, 0 cle utilisee non definie. |
| Identite/autorite | [Identity](../../src/modules/Identity.lua), [Governance](../../src/modules/Governance.lua), [Permissions](../../src/modules/Permissions.lua), [ProtectedActions](../../src/modules/ProtectedActions.lua) | Services publics, isolation et gardes | **COMPLET** — les quatre files lues sur leurs points d'entree de mutation, de reception reseau et de derivation d'autorite. |
| Regles/comptabilite | [Seasons](../../src/modules/Seasons.lua), [LootRules](../../src/modules/LootRules.lua), [RankRules](../../src/modules/RankRules.lua), [Ledger](../../src/modules/Ledger.lua), [MultiLedger](../../src/modules/MultiLedger.lua), [OperationalPolicy](../../src/modules/OperationalPolicy.lua) | Saisons, politique, transactions, ledgers | **COMPLET** — ecriture append-only, idempotence, chaine de hachage et verifications d'autorite couvertes. |
| Demandes/loot | [PreDibs](../../src/modules/PreDibs.lua), [CharacterEligibility](../../src/modules/CharacterEligibility.lua), [LootPipeline](../../src/modules/LootPipeline.lua), [Disputes](../../src/modules/Disputes.lua), [RequestDelivery](../../src/modules/RequestDelivery.lua), [Notifications](../../src/modules/Notifications.lua) | Demandes, eligibilite, acquisition, suivi | **COMPLET** — transfert de correction partiellement non recuperable documente en [RF-0012](INDEX.md#rf-0012). |
| Transport/raid | [Sync](../../src/modules/Sync.lua), [SyncV2](../../src/modules/SyncV2.lua), [HistoricalBaseline](../../src/modules/HistoricalBaseline.lua), [RaidRelay](../../src/modules/RaidRelay.lua), [RaidPrompts](../../src/modules/RaidPrompts.lua), [IndependentRaid](../../src/modules/IndependentRaid.lua) | Protocoles et orchestration | **COMPLET** — enveloppe, cursor, reception de detail, redaction joueur/officier et interdiction de donnees de live loot couvertes. |
| Donnees | [ImportExport](../../src/modules/ImportExport.lua), [AuditExport](../../src/modules/AuditExport.lua), [Profiles](../../src/modules/Profiles.lua), [Backup](../../src/modules/Backup.lua) | Import, export, profils et sauvegardes | **COMPLET** — lecture complete ; pas une certification de toutes les branches. |
| Installation | [Installation](../../src/modules/Installation.lua), [Wizard](../../src/modules/Wizard.lua), [Readiness](../../src/modules/Readiness.lua), [DryRun](../../src/modules/DryRun.lua), [Capabilities](../../src/modules/Capabilities.lua) | Diagnostic, verification et configuration | **COMPLET** — RF-0013 sur le retour officier reste `PARTIALLY_FIXED` sur deux decisions metier. |
| Framework | [Ace3](../../src/integrations/Ace3.lua) | Adaptateur LibStub, comm, evenements, timers | **COMPLET** — lecture complete ; callers cibles. |
| Developer | [DeveloperMode](../../src/integrations/DeveloperMode.lua), [DeveloperSandbox](../../src/integrations/DeveloperSandbox.lua), [DeveloperSandboxStore](../../src/integrations/DeveloperSandboxStore.lua), [DeveloperSandboxScenarios](../../src/integrations/DeveloperSandboxScenarios.lua) | Environnement de developpement isole | **COMPLET** — isole par `RCLootCouncil_dibsSandboxDB`, distinct de la production ; mode developpeur obligatoire. |
| Integrations WoW/RC | [GreatVault](../../src/integrations/GreatVault.lua), [EncounterJournal](../../src/integrations/EncounterJournal.lua), [RCLootCouncil](../../src/integrations/RCLootCouncil.lua), [RCLootCouncilOptions](../../src/integrations/RCLootCouncilOptions.lua) | Adaptateurs externes | **COMPLET** — reception d'attribution, recu normalise avant mutation, et projection de bouton de l'editeur verifies. |
| UI partagee | [Midnight](../../src/ui/Midnight.lua), [EnvironmentAdapters](../../src/ui/EnvironmentAdapters.lua), [WindowState](../../src/ui/WindowState.lua), [AceGUI](../../src/ui/AceGUI.lua), [HistoryFilters](../../src/ui/HistoryFilters.lua) | Presentation, lifecycle, composants | **COMPLET** — AceGUI est un adaptateur sans politique : ses seules references metier sont la lecture de la liste de ledgers pour un menu de consultation (`MultiLedger.SetViewLedger` est une consultation locale de session). |
| UI controleurs | [SetupAssistant](../../src/ui/SetupAssistant.lua), [HealthUI](../../src/ui/HealthUI.lua), [DeveloperUI](../../src/ui/DeveloperUI.lua), [LogsUI](../../src/ui/LogsUI.lua), [DataUI](../../src/ui/DataUI.lua), [DebugLogsUI](../../src/ui/DebugLogsUI.lua), [PlayerUI](../../src/ui/PlayerUI.lua), [OfficerUI](../../src/ui/OfficerUI.lua), [MinimapButton](../../src/ui/MinimapButton.lua) | Routage et projections | **COMPLET** — `canViewOfficerData` lit le role du roster verifie et echoue en `player` ; toutes les mutations passent par `ProtectedActions.Execute` ; les lectures joueur sont filtrees par la cle du joueur et par `Disputes.ListForPlayer` (`PLAYER_SCOPE_REQUIRED`). Le point `OfficerUI.lua:3632` reste exclu de la mission : correctif preserve, test Retail non effectue. |
| Tests/outillage/docs | [tests](../../tests), [scripts](../../scripts), [specs](../../specs), [developer](../developer) | Contrats, harness, specifications, maintenance | Recenses; lectures ciblees seulement |

## Points suspects (a confirmer)

- Fichiers volumineux, lignes physiques au debut de l'audit :
  OfficerUI 9 502, RCLootCouncil 4 073, SyncV2 3 095,
  RCLootCouncilOptions 2 629, AceGUI 2 477, PlayerUI 2 470.
  La taille seule n'etablit ni duplication ni necessite de decoupage.
- Le retour de revue joint concernant la molette du slider est verifiable dans
  l'implementation actuelle; consigner le resultat dans [INDEX](INDEX.md).
- Aucune fonction declaree morte. Les appels par tables, callbacks, evenements,
  globals et autres addons restent des limites de l'analyse statique.
  Un seul candidat local `sizeOf`, apres lecture complete et recherches elargies,
  est documente [RF-0007](INDEX.md#rf-0007); il n'est pas supprime.
- Pas de renommage recommande a ce stade. Les conventions documentent les
  historiques CoreAPI lowerCamel et Eligibility alias; les raccourcir ou les
  normaliser sans migration casserait un contrat public.
