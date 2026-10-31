# Dependances et flux Lua / WoW

## Liens runtime revérifiés le 28 octobre 2026

- TOC → Sync.lua → SyncV2.lua : même table Dibs.Sync, redéfinitions actives
  vérifiées par test de provenance.
- Ace3.SetupRuntimeEvents → Core listeners, puis EncounterJournal/AceGUI :
  le propriétaire d'abonnement partagé remplace actuellement les callbacks.
- SyncV2.localRequest → PreDibs.GetHistory → vérification secondaire →
  MultiLedger.GetLedgerById → copie du ledger complet par entrée.
- HealthUI → Backup.List → copies de snapshots pour de simples métadonnées.
- Watcher de configuration RC → GetEffectiveValue → GetAuthoritySnapshot →
  Seasons.GetCatalogState → copie de toutes les révisions pour lire le numéro
  courant. RA-15 reproduit 200 copies sur 40 ticks avec 50 révisions synthétiques.
- Initialize → capability officer_ui → CreateWindow → rendu overview caché →
  dashboard → GetLootCatalog → scan Journal synchrone (RA-16).
- Heartbeat/roster settled → tous les index approuvés → BULK; à réception,
  chaque entrée → localRequest → GetHistory. 59 index courants de 20 demandes
  font 1180 lectures sous doubles (amplification RA-01), sans détail manquant.
- Annulation de DataUI → pendingImports/pendingRestores : charges utiles non
  libérées et sauvegardées dans le root courant.

Les preuves et les limites sont détaillées dans
[l'audit runtime](PERFORMANCE-ARCHITECTURE-SECURITY-20261028.md).

## Carte verifiable

| Source (lien) | Cible (lien) | Nature du lien | Preuve | Certitude |
|---|---|---|---|---|
| [TOC](../../src/RCLootCouncil_dibs.toc) | [embeds](../../src/embeds.xml) | Chargement XML avant Lua applicatif | Premiere entree executable du TOC | HIGH |
| [embeds](../../src/embeds.xml) | [libs](../../src/libs) | Script/Include recursifs | `runtime_load_graph` du [recensement](MACHINE-INVENTORY.json) | HIGH apres exclusion des commentaires XML |
| [Ace3](../../src/integrations/Ace3.lua) | [Core](../../src/Core.lua) | Bootstrap tardif | Appel conditionnel `Dibs.SetupRuntimeEvents()` a la fin d'Ace3 | HIGH |
| [PlayerUI](../../src/ui/PlayerUI.lua) | [AceGUI](../../src/ui/AceGUI.lua) | Creation de controles | `createAceWindow` / Preferences appelle `AddRange` | HIGH |
| [PlayerUI](../../src/ui/PlayerUI.lua) | [MinimapButton](../../src/ui/MinimapButton.lua) | Mutation personnelle | Callback du slider appelle `SetScale`, reset appelle `ResetLayout` | HIGH |
| [MinimapButton](../../src/ui/MinimapButton.lua) | [Core](../../src/Core.lua) | Persistance locale | `getSettings` appelle `Dibs.GetLocalSettings` | HIGH |
| [MinimapButton](../../src/ui/MinimapButton.lua) | [Permissions](../../src/modules/Permissions.lua) | Choix de fenetre | `openOfficerOrPlayer` consulte `IsOfficer`/`IsGM` | HIGH |
| [AceGUI](../../src/ui/AceGUI.lua) | [Slider tiers](../../src/libs/AceGUI-3.0/widgets/AceGUIWidget-Slider.lua) | Contrat de callback | `AddRange` souscrit `OnMouseUp`; molette emet `OnValueChanged` | HIGH |
| [Test minimap](../../tests/integration/minimap_button_spec.lua) | [PlayerUI](../../src/ui/PlayerUI.lua) | Regression existante incomplete | Callback teste : OnMouseUp; pas de rerendu depuis false | HIGH; [RF-0001](INDEX.md#rf-0001), [RF-0002](INDEX.md#rf-0002) |
| [Core](../../src/Core.lua) | [Ace3](../../src/integrations/Ace3.lua) | Evenements | SetupRuntimeEvents appelle les wrappers; retour non exploite | HIGH; [RF-0004](INDEX.md#rf-0004) |
| [SyncV2](../../src/modules/SyncV2.lua) | [Sync](../../src/modules/Sync.lua) | Meme table partagee | V2 reutilise ContainsForbiddenLiveLootData et TraceIncoming/Outgoing | HIGH; [RF-0005](INDEX.md#rf-0005) |
| [Types](../../src/Types.lua) | [SyncV2](../../src/modules/SyncV2.lua) | Contrat documentaire, pas appel | Union DibsSyncMessageType vs registre TYPES | HIGH; [RF-0006](INDEX.md#rf-0006) |
| [Backup](../../src/modules/Backup.lua) | [ImportExport](../../src/modules/ImportExport.lua) | Snapshot/encodage | Create appelle GetPayload puis Export avec allowOversize | HIGH |
| [ImportExport](../../src/modules/ImportExport.lua) | [Backup](../../src/modules/Backup.lua) | Dependances reciproques tardives | Apply demande un snapshot de securite | HIGH; pas de boucle immediate de chargement |
| [DataUI](../../src/ui/DataUI.lua) | [Backup](../../src/modules/Backup.lua) | Preview puis Restore | Boutons preview/confirmation et statut keptLocal | HIGH; [RF-0009](INDEX.md#rf-0009) |
| [Profiles](../../src/modules/Profiles.lua) | [OperationalPolicy](../../src/modules/OperationalPolicy.lua) | Activation de politique adoptee | applyGuildProfilePolicy appelle Change pour patch supporte | HIGH; ne pas fusionner avec restore |
| [AuditExport](../../src/modules/AuditExport.lua) | [ImportExport](../../src/modules/ImportExport.lua) | Encodage seulement | EncodeReport utilise Encode puis prefixe DIBS-AUDIT-1 | HIGH; pas equivalent a Export("full") |
| [Profiles](../../src/modules/Profiles.lua) | [Backup](../../src/modules/Backup.lua) | Snapshot avant reset/delete guild | Appels Backup.Create dans Reset/Delete | HIGH; retours de ces snapshots a examiner ulterieurement |
| [SetupAssistant](../../src/ui/SetupAssistant.lua) | [Readiness](../../src/modules/Readiness.lua) | Projection | Evaluate reprend les probes et filtre guild/raid | HIGH |
| [SetupAssistant](../../src/ui/SetupAssistant.lua) | [SyncV2](../../src/modules/SyncV2.lua) | Sonde booleenne | syncStateCheck -> IsSyncBehind, pcall partiellement exploite | HIGH; [RF-0010](INDEX.md#rf-0010) |
| [SetupAssistant](../../src/ui/SetupAssistant.lua) | [ProtectedActions](../../src/modules/ProtectedActions.lua) | Delegation de mutation | ExecuteAction whitelist puis Execute | HIGH; [RF-0011](INDEX.md#rf-0011) |
| [Installation](../../src/modules/Installation.lua) | [HistoricalBaseline](../../src/modules/HistoricalBaseline.lua) / [MultiLedger](../../src/modules/MultiLedger.lua) | Initialisation et scan legacy | `Initialize`/`stageLegacyDiscovery` deduisent la completion du simple nombre d'evidences; la collecte persiste ledger et Pre-Dibs en deux appels | HIGH; [RF-0013](INDEX.md#rf-0013) |
| [Installation](../../src/modules/Installation.lua) | [Ledger](../../src/modules/Ledger.lua) / [HistoricalBaseline](../../src/modules/HistoricalBaseline.lua) | Detection vs collecte du ledger legacy | `detectRealLegacyData` utilise le ledger actif et ignore l'echec de `GetAllTransactions` sous `pcall`; `CollectLocalEvidence` lit `guild-primary` explicitement | HIGH pour les chemins; scope voulu et frequence d'exception UNKNOWN; [RF-0013](INDEX.md#rf-0013) |
| [Installation](../../src/modules/Installation.lua) | [MultiLedger](../../src/modules/MultiLedger.lua) / [OfficerUI](../../src/ui/OfficerUI.lua) | Setup officier et retour utilisateur | La branche officier ignore le resultat de collecte et celui de `ProposeLedger`, puis renvoie `ok=true`; `runInstallationAction` presente le resultat comme reussi | HIGH; [RF-0013](INDEX.md#rf-0013) |
| [Disputes](../../src/modules/Disputes.lua) | [ProtectedActions](../../src/modules/ProtectedActions.lua) / [Ledger](../../src/modules/Ledger.lua) | Corrections via actions protegees | `applyTargetCorrection` effectue deux `ledger.adjust`; `applyCorrection` utilise `ledger.adjust`, `ledger.refund` ou `ledger.use` selon l'action | HIGH; [RF-0012](INDEX.md#rf-0012) |
| [Disputes](../../src/modules/Disputes.lua) | [Ledger](../../src/modules/Ledger.lua) | Scope de transaction et d'evidence | `findTransaction` et les mutations n'incluent pas de `ledgerId`; l'ID n'est pas inclus dans la cle de correction et les recherches de rejeu lisent le ledger actif | HIGH; [RF-0012](INDEX.md#rf-0012) |
| [Ledger](../../src/modules/Ledger.lua) | [MultiLedger](../../src/modules/MultiLedger.lua) | Selection du ledger de mutation | `CommitLocalTransaction` et `commitCanonicalAdminAdjustment` retombent sur le ledger actif si aucun ID n'est fourni | HIGH; [RF-0012](INDEX.md#rf-0012) |
| [Ledger](../../src/modules/Ledger.lua) | [Governance](../../src/modules/Governance.lua) | Approbation du ledger et autorite canonique | Le ledger primaire est special-case; les autres doivent etre approuves; `localCoordinator` et le commit `AWARD_COMMIT` ne sont atteints que par l'ajustement canonique | HIGH; [RF-0012](INDEX.md#rf-0012) |
| [ProtectedActions](../../src/modules/ProtectedActions.lua) | [Permissions](../../src/modules/Permissions.lua) / [Ledger](../../src/modules/Ledger.lua) | Autorisation, execution et retour correction | `Execute` evalue l'acteur; `buildAudit` transporte `correctionKey` sans deduplication, et les wrappers ne propagent pas uniformement les erreurs Ledger | HIGH; [RF-0012](INDEX.md#rf-0012) |
| [Ledger](../../src/modules/Ledger.lua) | [SyncV2](../../src/modules/SyncV2.lua) | Replication du ledger V2 | L'ajustement canonique publie un `AWARD_COMMIT`; les ajustements `source="dispute-center"` empruntent la voie locale sans commit | HIGH; [RF-0012](INDEX.md#rf-0012) |
| [SyncV2](../../src/modules/SyncV2.lua) | [Ledger](../../src/modules/Ledger.lua) | Digest et rattrapage | Le digest suit `canonical.rootHash`/`nextSeq` et le rattrapage transfere les `AWARD_COMMIT`, non les transactions locales isolees | HIGH; revue ciblee, [RF-0012](INDEX.md#rf-0012) |
| [Wizard](../../src/modules/Wizard.lua) | [SetupAssistant](../../src/ui/SetupAssistant.lua) | Orchestration vers projection chargee plus tard | setupReport et GetTurnkeyStatus/GetGuidance sont appeles apres chargement | HIGH; ne pas conclure a une erreur TOC sur le seul ordre |
| [Capabilities](../../src/modules/Capabilities.lua) | [Core](../../src/Core.lua) | Enregistrement tardif de closures | registerOptionalCapabilities, puis Initialize/Retry | HIGH; contrat des valeurs de retour a poursuivre |
| [Installation](../../src/modules/Installation.lua) | [Governance](../../src/modules/Governance.lua) / [HistoricalBaseline](../../src/modules/HistoricalBaseline.lua) | Projection sans etat persistant propre | `GetStatus` derive gouvernance, autorite, baseline et protocole a chaque appel | HIGH; confirme dans l'architecture V2 |

## Entrees dynamiques WoW

| Evenement / callback / hook / XML / global | Handler | Conditions de chargement | Preuve |
|---|---|---|---|
| `PLAYER_LOGIN` | `MinimapButton.Initialize` | Frame bootstrap si `CreateFrame` existe | [MinimapButton](../../src/ui/MinimapButton.lua), fin du fichier |
| `OnClick` | `openPlayer` / `openOfficerOrPlayer` | Bouton cree | [MinimapButton.Create](../../src/ui/MinimapButton.lua) |
| `OnDragStart` / `OnUpdate` / `OnDragStop` | `updateDragPosition` | Drag gauche; OnUpdate retire a l'arret | [MinimapButton](../../src/ui/MinimapButton.lua) |
| AceEvent | `Adapter.handlers.events[receivedEvent]` | Enregistrement via Ace3 | [Ace3.RegisterEvent](../../src/integrations/Ace3.lua) |
| AceComm | `Adapter.handlers.comms[receivedPrefix]` | Prefixe enregistre via Ace3 | [Ace3.RegisterComm](../../src/integrations/Ace3.lua) |
| AceTimer / `C_Timer.After` | Callback fourni par appelant | Timer Ace disponible, sinon API WoW | [Ace3.ScheduleTimer](../../src/integrations/Ace3.lua) |
| `PLAYER_LOGIN` / `ADDON_LOADED` / roster / regen / system | `onRuntimeEvent` | AceEvent ou frame native selon Core | [Core.SetupRuntimeEvents](../../src/Core.lua); chemin degrade a revoir |
| Prefixe `DIBS` | `Sync.OnAddonMessage` version V2 | RegisterTransport appele au bootstrap et Initialize | [SyncV2](../../src/modules/SyncV2.lua), [Core](../../src/Core.lua) |
| `/dibs`, `/dib`, `/dids` | `Dibs.HandleSlashCommand` | `SetupSlashCommands` | [Core](../../src/Core.lua), SlashCmdList["DIBS"] |
| Globals, hooks, slash, autres `SetScript` | A verifier individuellement | Voir `dynamic_candidates` par fichier | [Recensement machine](MACHINE-INVENTORY.json), indices non exhaustifs |

## Risques et references inconnues

- `Dibs` est un namespace public; appelants hors depot : UNKNOWN.
- Les definitions sont parfois capturees dans des locals avant remplacement
  (`aceRegisterEvent`, `aceRegisterComm`). Ne pas confondre wrapper et recursion.
- Les references `Dibs.*` et callbacks du recensement sont des indices syntaxiques,
  pas des liens fonctionnels tous verifies; les commentaires peuvent aussi matcher.
- La disponibilite d'une bibliotheque LibStub depend aussi des autres addons et
  de leurs versions. Version effectivement utilisee dans Retail : UNKNOWN.
- Aucune certification Retail, autorite reseau ou resistance a la collusion par cet
  audit preparatoire. Le sujet est le refactoring, pas une revue de vulnerabilites.
- Readiness et SetupAssistant ne sont pas des doublons : le premier evalue le
  contexte operationnel/live et gere fraicheur/audit, le second projette des checks
  guild/raid et delegue des actions; Wizard orchestre des etapes/profils.
  Leurs helpers pcall/text similaires ne prouvent pas l'equivalence des modules.
- Le workflow de correction Disputes ne constitue pas une ecriture atomique:
  les appels append-only peuvent echouer separement, `correctionKey` n'est pas
  une cle d'idempotence Ledger, et en mode V2 la source `dispute-center` ne
  traverse pas le chemin canonique admin. Voir [RF-0012](INDEX.md#rf-0012) et le
  backlog futur [SPECKIT-BACKLOG](SPECKIT-BACKLOG.md).
- Le scope comptable d'une correction suit le ledger actif au moment de chaque
  lookup/ecriture; la demande sauvegardee ne retient ici que son contexte de
  saison. L'intention d'appliquer la correction au ledger actif ou au ledger
  portant la transaction originale reste UNKNOWN.
- Aucune fusion recommandee pour ImportExport/AuditExport : paquet reversible
  sensible vs projection anonyme bornee. Ils partagent seulement un encodeur.
