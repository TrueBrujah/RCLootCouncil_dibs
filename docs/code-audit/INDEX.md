# Index de l'audit Lua

> **Passe runtime du 28 octobre 2026, HEAD cb3f12a :**
> [rapport performances/architecture/sécurité](PERFORMANCE-ARCHITECTURE-SECURITY-20261028.md)
> et [mesures Retail](RETAIL-PERFORMANCE-PROTOCOL-20261028.md).
> Les statuts RF historiques ci-dessous ne certifient pas le worktree courant :
> imports/restaurations échouent à plusieurs régressions. Les constats RA-01 à
> RA-16 du nouveau rapport donnent sources actives, confiance, risque, preuves,
> tests et propositions. Aucune annotation ou logique de production n'a changé.

> Perimetre : inventaire structurel du projet complet; **revue semantique
> terminee sur les 58 sources applicatives** de `src/` hors bibliotheques
> (58 COMPLET / 0 PARTIAL / 0 INVENTORIED). Les statuts ne sont pas des
> autorisations de modifier le code.
> Base : `dc388f9`, 2026-10-18. RF-0013 partiellement corrige et RF-0014
> corrige le 2026-10-19; voir
> [AUTONOMOUS-SESSION-STATUS.md](AUTONOMOUS-SESSION-STATUS.md) pour l'etat
> vivant.
>
> Les fiches `NEED_UPDATE` et `KEEP` ci-dessous restent **ouvertes** : elles
> n'ont pas ete corrigees. Aucune ne presente un risque P0/P1 confirme ; les
> corriger demanderait un arbitrage de contrat. RF-0006 a ete reconfirme en
> session 4 (l'alias `DibsSyncMessageType` decrit le registre V1, pas V2).
>
> **RF-0012 a ete reclassifie `FIXED` en session 4** : son `Evidence` decrivait
> la voie de correction anterieure a la spec 026, qui n'existe plus. Voir la
> section « Resolution appliquee » de la fiche.
>
> Les fiches RF-0001, RF-0002, RF-0004, RF-0007, RF-0009 et RF-0010 ont ete
> **reconduites** en session 4 : leur code cible est inchange, leur preuve
> reste exacte.

| ID | Status | Confidence | Fichier | Sujet | Risque |
|---|---|---|---|---|---|
| [RF-0001](#rf-0001) | NEED_UPDATE | HIGH | AceGUI | Slider et molette | LOW |
| [RF-0002](#rf-0002) | NEED_UPDATE | HIGH | PlayerUI | Fallback booleen des Preferences | LOW |
| [RF-0003](#rf-0003) | KEEP | HIGH | MinimapButton | Point d'entree UI local | MEDIUM |
| [RF-0004](#rf-0004) | NEED_UPDATE | HIGH | Core | Fallback si AceEvent indisponible | MEDIUM |
| [RF-0005](#rf-0005) | KEEP | HIGH | Sync | Service V1 reutilise par V2 | HIGH |
| [RF-0006](#rf-0006) | NEED_UPDATE | HIGH | Types | Union des messages obsolete | LOW |
| [RF-0007](#rf-0007) | TO_REMOVE | HIGH | Backup | Helper local sizeOf non reference | LOW |
| [RF-0008](#rf-0008) | FIXED | HIGH | Profiles | Plusieurs profils marques actifs | MEDIUM |
| [RF-0009](#rf-0009) | NEED_UPDATE | HIGH | Backup | Preview generique avant restore sync-safe | MEDIUM |
| [RF-0010](#rf-0010) | NEED_UPDATE | HIGH | SetupAssistant | Sonde sync inconnue affichee ready | MEDIUM |
| [RF-0011](#rf-0011) | KEEP | HIGH | SetupAssistant | Delegation des actions protegees | HIGH |
| [RF-0012](#rf-0012) | FIXED | HIGH | Disputes | Transfert de correction non atomique et hors chaine V2 | HIGH |
| [RF-0013](#rf-0013) | FIXED | HIGH | Installation | Scan legacy incomplet traite comme deja effectue | HIGH |
| [RF-0014](#rf-0014) | FIXED | HIGH | CharacterEligibility | Un changement de main fusionne deux joueurs sans lien | HIGH |
| [RF-0015](#rf-0015) | FIXED | MEDIUM | Wizard | Une verification obligatoire masquee par une verification facultative | MEDIUM |
| [RF-0016](#rf-0016) | FIXED | MEDIUM | Readiness | La porte d'attribution live contredit le drapeau du meme resultat | MEDIUM |
| [RF-0017](#rf-0017) | FIXED | HIGH | CharacterEligibility | Un identifiant de groupe de joueur fourni par l'appelant fusionne ou divulgue des donnees | HIGH |
| [RF-0018](#rf-0018) | FIXED | MEDIUM | Profiles | Plusieurs profils restent actifs et GetActive renvoie un profil arbitraire | MEDIUM |
| [RF-0019](#rf-0019) | FIXED | HIGH | PlayerUI | Le badge d'integration RCLootCouncil applique la precedence des operateurs | HIGH |
| [RF-0020](#rf-0020) | FIXED | MEDIUM | OfficerUI | Aucune interface n'expose la revue des declarations main/alt par un GM ou un Officier | MEDIUM |
| [RF-0021](#rf-0021) | FIXED | LOW | sync_status_spec | La fixture de test utilise un `lastSeenAt` fige, hors de la fenetre de heartbeat | LOW |
| [RF-0022](#rf-0022) | FIXED | HIGH | LootPipeline | La voie de repli contourne l'interdiction de Pre-Dibs publics | HIGH |
| [RF-0023](#rf-0023) | FIXED | LOW | validate_audit.py | Le vocabulaire de statuts du validateur est plus etroit que la convention du code | LOW |
| [RF-0024](#rf-0024) | FIXED | HIGH | PlayerUI | La surface de declaration main/alt est orpheline dans la fenetre atteignable | HIGH |
| [RF-0025](#rf-0025) | FIXED | HIGH | CharacterEligibility | Un identifiant de groupe fourni par l'appelant marque un enregistrement d'acquisition | HIGH |
| [RF-0026](#rf-0026) | FIXED | HIGH | Ledger | La reconstruction des projections diverge du chemin incremental et vide les soldes | HIGH |
| [RF-0027](#rf-0027) | FIXED | HIGH | Ledger | Le hachage canonique suppose un instantane d'identite present | HIGH |
| [RF-0028](#rf-0028) | FIXED | HIGH | Core | La commande slash contournait la politique publique des Pre-Dibs | HIGH |
| [RF-0029](#rf-0029) | FIXED | HIGH | EncounterJournal | La route Adventure Guide contournait la politique publique | HIGH |
| [RF-0030](#rf-0030) | FIXED | HIGH | PlayerUI | Le repli local contournait la politique publique | HIGH |
| [RF-0031](#rf-0031) | FIXED | HIGH | Ledger | Une proposition terminale conservait sa reservation de Dib | HIGH |
| [RF-0032](#rf-0032) | KEEP | HIGH | MultiLedger | Les protections canoniques s'appliquent aux Secondary Ledgers | HIGH |
| [RF-0033](#rf-0033) | FIXED | HIGH | ImportExport | Un import complet annulait un ledger local plus recent | HIGH |
| [RF-0034](#rf-0034) | FIXED | HIGH | SyncV2 | Une reservation diffusee n'est jamais liberee chez les pairs | HIGH |
| [RF-0035](#rf-0035) | FIXED | HIGH | SyncV2 | Le transfert de coordinateur ne converge jamais chez les pairs | HIGH |
| [RF-0036](#rf-0036) | KEEP | HIGH | SyncV2 | Une reservation liberee ne ressuscite pas apres reconnexion | HIGH |
| [RF-0037](#rf-0037) | KEEP | HIGH | SyncV2 | Le rattrapage d'un Secondary Ledger est verifie | HIGH |
| [RF-0038](#rf-0038) | FIXED | HIGH | Ledger | Un snapshot canonique corrompu est accepte comme valide | HIGH |
| [RF-0039](#rf-0039) | KEEP | HIGH | Ledger | La reconstruction apres interruption est verifiee | HIGH |
| [RF-0040](#rf-0040) | KEEP | HIGH | ImportExport | L'importation complete est verrouillee | HIGH |
| [RF-0041](#rf-0041) | FIXED | HIGH | Backup | Une restauration ne validait pas l'instantane | HIGH |
| [RF-0042](#rf-0042) | FIXED | HIGH | HistoricalBaseline | Un paquet contradictoire etait applique | HIGH |
| [RF-0043](#rf-0043) | KEEP | HIGH | SyncV2 | Le scenario global a quatre clients converge | HIGH |
| [RF-0044](#rf-0044) | KEEP | HIGH | Governance | L'exception de retard de l'adoption est limitee | HIGH |
| [RF-0045](#rf-0045) | FIXED | HIGH | PreDibs | Une demande de Pre-Dibs etait copiee dans un second ledger | HIGH |
| [RF-0046](#rf-0046) | FIXED | HIGH | Backup | Une sauvegarde valide ne pouvait plus etre restauree | HIGH |
| [RF-0047](#rf-0047) | FIXED | HIGH | Backup | La validation d'instantane n'etait pas exercee par la restauration | HIGH |

Voir [INVENTORY](INVENTORY.md), [DEPENDENCIES](DEPENDENCIES.md),
[REFACTOR-PLAN](REFACTOR-PLAN.md), [PROGRESS](PROGRESS.md) et
[SPECKIT-BACKLOG](SPECKIT-BACKLOG.md).

<a id="rf-0001"></a>
## RF-0001 - AddRange : changement a la molette non applique

- Status: NEED_UPDATE
- Confidence: HIGH
- Risk: LOW
- Source: [AceGUI.lua](../../src/ui/AceGUI.lua) - `Adapter.AddRange`
- Evidence: Souscription uniquement a `OnMouseUp`. Dans le
  [Slider embarque](../../src/libs/AceGUI-3.0/widgets/AceGUIWidget-Slider.lua),
  `Slider_OnMouseWheel` appelle `slider:SetValue`; `Slider_OnValueChanged`
  emet `OnValueChanged`, sans `OnMouseUp`. Le
  [controle Preferences](../../src/ui/PlayerUI.lua), `minimapButtonScale`,
  persiste et redimensionne seulement dans le callback fourni a AddRange.
  Le [test existant](../../tests/integration/minimap_button_spec.lua)
  invoque seulement `callbacks.OnMouseUp`. La remarque jointe de #22 est donc
  encore applicable a cette revision.
- Rationale: La valeur affichee peut changer sans redimensionnement ni persistance.
  Il s'agit d'un defaut de contrat de callback, pas d'un besoin de remplacer AceGUI.
- References/Dependencies: PlayerUI Preferences; `Adapter.RenderOptionsGroup`
  appelle aussi AddRange pour des options generiques. Le changement global de
  frequence des callbacks pourrait provoquer des mutations repetees; leurs setters
  doivent etre verifies avant de generaliser. [RF-0003](#rf-0003).
- Proposed action: Dans une demande future, prendre en charge `OnValueChanged`
  pour ce controle personnel, sans multiplier les ecritures administratives;
  tester molette, drag, saisie clavier, reset, bornes et persistance apres reload.
  Aucun patch de comportement dans cet audit.
  Probe Fengari synthetique : `minimapButtonScale.callbacks.OnValueChanged == nil`.

<a id="rf-0002"></a>
## RF-0002 - Preferences : false remplace par true

- Status: NEED_UPDATE
- Confidence: HIGH
- Risk: LOW
- Source: [PlayerUI.lua](../../src/ui/PlayerUI.lua) - variable locale `visible` dans `frame.Refresh`
- Evidence: L'expression `...GetVisible() or true` donne `true` quand
  `GetVisible()` renvoie `false`. `AddCheckBox` initialise sa valeur a ce resultat.
  [MinimapButton.SetVisible](../../src/ui/MinimapButton.lua) enregistre bien `false`.
  Le [test Preferences](../../tests/integration/minimap_button_spec.lua) part
  uniquement de la valeur par defaut, cochee; il ne rerend pas apres masquage.
- Rationale: L'icone peut etre correctement masquee alors que le controle apparait
  coche lors d'une nouvelle ouverture de Preferences. Pas de preuve de corruption
  de la preference par le simple rendu.
  Probe Fengari synthetique : getter `false`, checkbox `true` apres ouverture.
- References/Dependencies: `MinimapButton.GetVisible`, `Adapter.AddCheckBox`,
  `Dibs.GetLocalSettings`, [RF-0003](#rf-0003).
- Proposed action: Distinguer absence de getter et valeur booleenne false dans une
  correction ulterieure; ajouter une regression hide -> ouvrir Preferences ->
  controle decoche, puis afficher/reouvrir. Ne pas changer la valeur par defaut.

<a id="rf-0003"></a>
## RF-0003 - Create : entree confirme du raccourci minimap

- Status: KEEP
- Confidence: HIGH
- Risk: MEDIUM
- Source: [MinimapButton.lua](../../src/ui/MinimapButton.lua) - `MinimapButton.Create`
- Evidence: TOC charge le fichier; frame bootstrap enregistre `PLAYER_LOGIN`,
  puis appelle `Initialize` -> `Create`. `SetVisible` peut aussi creer le bouton.
  `OnClick` choisit la fenetre selon Permissions; drag installe puis retire
  `OnUpdate`. Le [test minimap](../../tests/integration/minimap_button_spec.lua)
  couvre creation, clicks, persistance, commandes, drag et taille.
- Rationale: Point d'entree indirect essentiel; ne pas supprimer faute d'un appel
  direct dans le TOC. Les callbacks constituent son contrat.
- References/Dependencies: Core.GetLocalSettings, Permissions, PlayerUI, OfficerUI,
  APIs Minimap/CreateFrame/GetCursorPosition; EN/FR. Aucun effet comptable dans ce
  fichier. Autres addons appelant cette API publique : UNKNOWN.
- Proposed action: Conserver l'API, le bootstrap et la duree bornee d'OnUpdate;
  garder les preferences personnelles hors de la sync lors des corrections futures.

<a id="rf-0004"></a>
## RF-0004 - SetupRuntimeEvents : detection de fonction plutot que succes

- Status: NEED_UPDATE
- Confidence: HIGH
- Risk: MEDIUM
- Source: [Core.lua](../../src/Core.lua) - `Dibs.SetupRuntimeEvents`
- Evidence: `usingAceEvent` teste l'existence de `Dibs.Ace3.RegisterEvent`;
  les retours des enregistrements sont ignores avant `runtimeEventsRegistered=true`.
  [Ace3.RegisterEvent](../../src/integrations/Ace3.lua) existe meme quand
  `Adapter.libs.event` est absent et renvoie alors `false`. Le fallback frame
  est seulement dans le `else`. Ace3 appelle SetupRuntimeEvents en fin de fichier.
  Donc si le wrapper existe sans sa bibliotheque, les evenements ne sont pas
  enregistres par ce chemin, mais la fonction annonce etre deja initialisee.
  Probe Fengari synthetique confirme `RegisterEvent=false` puis
  `SetupRuntimeEvents=true` et son flag `true`.
- Rationale: Le mode degrade n'utilise pas son fallback natif. Les bibliotheques
  sont normalement embarquees : ce n'est pas une preuve d'echec du package normal.
- References/Dependencies: TOC -> Core -> Ace3; `PLAYER_LOGIN` ->
  `Dibs.Initialize`; `CHAT_MSG_ADDON`; tests
  [raid_prompt](../../tests/integration/raid_prompt_spec.lua) et
  [load_addon](../../tests/helpers/load_addon.lua). Les doubles existants
  trouvent AceEvent dans les scenarios observes; panne/retrait en Retail : UNKNOWN.
- Proposed action: Tester l'absence/erreur AceEvent avec wrapper present, puis
  basculer sur les enregistrements natifs si necessaire dans une correction
  separee; eviter doublons et faux succes, verifier le retry.

<a id="rf-0005"></a>
## RF-0005 - Sync.lua n'est pas integralement obsolete

- Status: KEEP
- Confidence: HIGH
- Risk: HIGH
- Source: [Sync.lua](../../src/modules/Sync.lua) - `Dibs.Sync.ContainsForbiddenLiveLootData`
- Evidence: Le TOC charge Sync.lua avant SyncV2.lua, et V2 prend
  `local Sync = Dibs.Sync`. V2 redefinit Send, Receive, OnAddonMessage et
  RegisterTransport, mais ses chemins Send et Receive appellent encore
  `Sync.ContainsForbiddenLiveLootData`. `Sync.TraceIncoming`/`TraceOutgoing`
  proviennent aussi du fichier initial et sont utilises dans V2.
- Rationale: Deux fichiers partageant le meme namespace ne sont pas deux modules
  interchangeables. Supprimer le premier ferait disparaitre des services actifs.
  Aucun verdict d'inutilite sur les autres fonctions V1 n'est etabli.
- References/Dependencies: [SyncV2](../../src/modules/SyncV2.lua),
  [Core](../../src/Core.lua), [TOC](../../src/RCLootCouncil_dibs.toc).
  Appels publics externes, snapshots et chemins legacy : UNKNOWN tant que non traces.
- Proposed action: Conserver. Avant un futur decoupage, separer explicitement
  utilitaires partages et protocoles, inventorier chaque symbole remplace et
  encore exporte, puis rejouer contrats transport/sync/raid; ne pas fusionner
  automatiquement les implementations V1/V2.

<a id="rf-0006"></a>
## RF-0006 - Documentation des types de messages en retard

- Status: NEED_UPDATE
- Confidence: HIGH
- Risk: LOW
- Source: [Types.lua](../../src/Types.lua) - `DibsSyncMessageType`
- Evidence: L'alias inclut surtout MANIFEST/FETCH/REQUEST du protocole precedent,
  alors que le registre `TYPES` au debut de
  [SyncV2](../../src/modules/SyncV2.lua) contient notamment DIGEST,
  DETAIL_FETCH, TRANSFER_ACK, LEDGER_DIGEST, CHANNEL_TEST,
  SYNC_REPAIR_REQUEST et SYNC_REPAIR_ACK, absents de l'alias.
  [api-reference](../developer/api-reference.md) renvoie a Types.lua pour les
  modeles. L'en-tete de Types et le TOC confirment son role statique intentionnel.
- Rationale: Documentation integree au code incomplete pour les outils LuaLS.
  Ne pas le traiter comme un fichier mort parce qu'il n'est pas charge par WoW.
- References/Dependencies: `DibsSyncEnvelope.type`, registre V2 et
  [sync-protocol](../developer/sync-protocol.md). Couverture des autres types
  du fichier : pas encore auditee.
- Proposed action: Aligner les declarations sur les versions et registres reels
  lors d'une future mise a jour documentaire; garder l'exclusion runtime du TOC.
  Ne pas supprimer les types legacy sans examiner les consommateurs.

<a id="rf-0007"></a>
## RF-0007 - sizeOf : candidat local sans reference retrouvee

- Status: TO_REMOVE
- Confidence: HIGH
- Risk: LOW
- Source: [Backup.lua](../../src/modules/Backup.lua) - `local function sizeOf(payload)`
- Evidence: Lecture complete de Backup; `sizeOf` n'est ni appele, ni exporte,
  ni stocke dans une table, ni capture par les callbacks/aliases du fichier.
  Recherche mot entier `sizeOf` dans Lua, XML, TOC, Markdown, PowerShell,
  Python et JSON du depot : seule definition et recensement machine.
  Le parametre `payload` n'est pas utilise. La taille de `Create` provient
  directement de `#packageText`, sans passer par ce helper.
- Rationale: Candidat de suppression, pas suppression appliquee. Contrairement
  aux APIs globales, cette closure locale n'est pas accessible via `_G[name]`.
- References/Dependencies: Son corps appelle `ImportExport.Export("local")`
  (qui journalise un export); aucune invocation observee. Le reste de Backup
  expose `CreateSnapshot`, `ListSnapshots`, `Preview`, `RestoreSnapshot` par
  alias : ces APIs distinctes ne sont pas candidates a supprimer.
  Acces extraordinaires via debug/upvalues ou outils externes : UNKNOWN.
- Proposed action: Rechercher de nouveau les captures et usages a la revision
  d'implementation, puis supprimer seulement ce helper si toujours inutilise;
  rejouer sauvegarde/import/profils. Ne pas supprimer Export ni ses audits.

<a id="rf-0008"></a>
## RF-0008 - Activate : ancien profil laisse actif

- Status: FIXED (voir [RF-0018](#rf-0018))
- Confidence: HIGH
- Risk: MEDIUM
- Source: [Profiles.lua](../../src/modules/Profiles.lua) - `M.Activate`
- Evidence: Activate fixe `profiles.active[key(scope,name)]=true` et
  `profile.active=true` sans desactiver les autres profils du meme bucket.
  `GetActive` renvoie le premier profil actif rencontre via `pairs`.
  Probe Fengari synthetique : creer A/B locaux, activer A puis B, List renvoie
  deux profils `active=true`. Le resultat GetActive depend alors de l'iteration.
- Rationale: Le statut ne represente pas un basculement fiable entre profils.
  La [spec 007](../../specs/007-backup-export-import-profiles/spec.md), story 2,
  decrit bien le changement du profil actif; les tests existants n'activent
  qu'un seul profil. Pas de conclusion de corruption des transactions.
- References/Dependencies: Create, Activate, GetActive, Rename, Delete,
  `profiles.active`, buckets local/guild, `charKey`; [DataUI](../../src/ui/DataUI.lua).
  Le marqueur `profiles.active` n'inclut pas le personnage, alors que le bucket
  local le fait : isolation du marqueur a verifier avant migration.
- Proposed action: Dans une correction separee, rendre le basculement coherent
  dans le scope/bucket cible, sans toucher l'autre scope ni les ledgers.
  Tester A->B->A, rename/delete, deux personnages, confirmation de politique
  et rejet d'activation sans changer le profil actif precedent.
- Resolution (2026-07-20) : le basculement est desormais coherent dans le
  scope cible. `Activate` retire le drapeau et l'index des autres profils du
  meme scope, et `GetActive` consulte l'index qui fait autorite. Les scopes
  `guild` et `local` restent independants, et aucun ledger n'est touche.
  Tests : `tests/integration/rf0018_single_active_profile_spec.lua`.

<a id="rf-0009"></a>
## RF-0009 - PreviewRestore : effets conserves non visibles avant confirmation

- Status: NEED_UPDATE
- Confidence: HIGH
- Risk: MEDIUM
- Source: [Backup.lua](../../src/modules/Backup.lua) - `M.PreviewRestore`
- Evidence: La preview annonce seulement `declared scope`, `strategy=replace`,
  `conflicts={}` et impact `replace=1` pour full. Le restore, lui, appelle
  `keepNewerSharedState` et renvoie `keptLocal` (chaines/ledgers conserves);
  le scope guild preserve aussi un catalogue publie.
  [DataUI.addPreview](../../src/ui/DataUI.lua) affiche les champs de preview;
  la liste `keptLocal` apparait seulement apres confirmation dans le statut.
  [backup_sync_restore_spec](../../tests/integration/backup_sync_restore_spec.lua)
  couvre deja les revisions plus recentes conservees, pas leur annonce en preview.
- Rationale: Le comportement sync-safe est intentionnel et doit etre conserve;
  la preview generique n'explique pas les principales omissions avant validation.
  La [spec 007](../../specs/007-backup-export-import-profiles/spec.md), story 1,
  demande de montrer ce qui changerait avant confirmation.
- References/Dependencies: keepNewerSharedState, SHARED_CHAINS, ledgerProgress,
  DataUI.addPreview, Restore; [saved-variables](../developer/saved-variables.md).
  Etat susceptible de changer entre preview et confirmation.
- Proposed action: Extraire ulterieurement une projection sans mutation de la
  decision de conservation, la montrer avant confirmation, et recalculer a
  l'application. Tester preview non mutante, etat evoluant entre les etapes,
  chaines divergentes et restauration apres factoryreset. Ne pas revenir a un
  remplacement aveugle pour faire correspondre le code a la preview.

<a id="rf-0010"></a>
## RF-0010 - syncStateCheck : absence/exception assimilee a synchronise

- Status: NEED_UPDATE
- Confidence: HIGH
- Risk: MEDIUM
- Source: [SetupAssistant.lua](../../src/ui/SetupAssistant.lua) - `syncStateCheck`
- Evidence: `call` renvoie le succes pcall puis sa valeur ou erreur.
  syncStateCheck utilise seulement `select(2, call(IsSyncBehind)) == true`;
  l'absence de getter, une exception, nil et false aboutissent tous a
  `not behind`, donc `state=ready` et texte "synchronized with the guild".
  Probe synthetique avec Evaluate(scope=guild) : missing -> ready,
  error -> ready, false -> ready, true -> degraded.
- Rationale: Un etat inconnu n'est pas une preuve de synchronisation.
  Observation limitee a cette ligne de diagnostic; d'autres checks peuvent
  signaler des problemes et les gardes des mutations restent separees.
  Ce n'est pas une preuve que la guilde accepte des donnees non autorisees.
- References/Dependencies: `SetupAssistant.Evaluate`, helper `call`,
  `Sync.IsSyncBehind` dans [SyncV2](../../src/modules/SyncV2.lua);
  [spec 021](../../specs/021-turnkey-guided-setup/spec.md), resultats et erreurs
  explicites; [test UI](../../tests/integration/setup_assistant_ui_spec.lua).
- Proposed action: Distinguer succes booleen, API indisponible et echec.
  Presenter l'inconnu avec remediation/diagnostic sans inventer un blocage
  metier supplementaire. Tester les quatre cas du probe et absence de trafic
  ou mutation lors de la projection.

<a id="rf-0011"></a>
## RF-0011 - ExecuteAction : frontiere des mutations du setup

- Status: KEEP
- Confidence: HIGH
- Risk: HIGH
- Source: [SetupAssistant.lua](../../src/ui/SetupAssistant.lua) - `SetupAssistant.ExecuteAction`
- Evidence: Whitelist ACTIONS, validation du payload, controle de disponibilite
  puis delegation a `Dibs.ProtectedActions.Execute(actionId,actor,payload)`.
  Source "setup-assistant" ajoutee au payload, pas ecriture directe du ledger.
  [setup_assistant_ui_spec](../../tests/integration/setup_assistant_ui_spec.lua)
  couvre les appels du setup et ses resultats.
- Rationale: Ne pas fusionner la projection de readiness avec l'execution
  comptable/politique. La verification de cette delegation ne certifie pas
  toutes les implementations des services proteges.
- References/Dependencies: [ProtectedActions](../../src/modules/ProtectedActions.lua),
  Permissions, whitelist ACTIONS; Readiness et DryRun ont d'autres contrats.
  Revue exhaustive des callers et gardes du service : a poursuivre.
- Proposed action: Conserver la delegation et les codes d'erreur; toute future
  simplification du setup doit garder les mutations dans les services existants.

<a id="rf-0012"></a>
## RF-0012 - applyTargetCorrection : transfert partiel non recupere

- Status: FIXED (reconfirme en session 4, 2026-10-20)
- Confidence: HIGH
- Risk: HIGH
- Source: [Disputes.lua](../../src/modules/Disputes.lua) - `applyTargetCorrection`
- **Reclassification session 4** : l'`Evidence` et le `Proposed action` ci-dessous
  decrivent la voie de correction **anterieure** a la specification
  [026](../../specs/026-canonical-idempotent-corrections/spec.md). Cette voie
  n'existe plus. La section « Evidence » est conservee telle quelle comme
  trace de l'etat observe au moment de la fiche ; la section
  « Resolution appliquee » ci-dessous decrit l'etat actuel verifie.
- Evidence (etat observe a la creation de la fiche, **avant** la spec 026):
  - `applyTargetCorrection` appelle deux fois
    `ProtectedActions.Execute("ledger.adjust")`, d'abord pour inverser l'ancien
    joueur, ensuite pour crediter la cible. Les deux appels transmettent
    `source="dispute-center"`, la meme `correctionKey` et le meme `evidenceId`;
    ils ne fixent aucun `transactionId`.
  - Si le second appel est rejete, la fonction tente une compensation de
    l'ancien joueur, change `correctionKey` en `key .. ":rollback"`, ignore le
    resultat de `Execute`, ne garde pas l'identifiant de cette tentative, puis
    retourne l'erreur du second appel. `state.corrections` n'est pas renseigne
    sur cette branche; la demande reste reessayable.
  - Dans `Ledger`, l'ajout local verifie les doublons par `transactionId` et
    compare le contenu canonique; la cle `correctionKey` n'est qu'une metadonnee
    integree au contenu canonique. `Dibs.NewId("tx")` utilise l'heure en
    secondes et un suffixe aleatoire. Les reprises ne reutilisent donc pas
    l'identifiant d'une tentative precedente. `evidenceTransactions[evidenceId]`
    est un index simple affecte a chaque append; ce n'est pas un garde de
    unicite et les deux jambes avec le meme `evidenceId` se remplacent dans cet
    index.
  - `ProtectedActions.Execute` appelle `Permissions.Evaluate` avant le
    dispatch. `buildAudit` puis `Ledger.compatibilityMutation` conservent
    `correctionKey` dans la transaction locale, mais `CommitLocalTransaction`
    ne l'utilise pas pour la recherche de doublon : seule une valeur
    `transactionId` fournie peut identifier une reprise; en son absence
    `buildDetachedTransaction` cree un nouvel ID. La cle est donc une
    correlation/metadonnee, pas un contrat d'idempotence.
  - Les wrappers `executeLedgerUse` et `executeLedgerRefund` ignorent le code
    d'erreur retourne par Ledger. `executeLedgerAdjust` le capture mais ne le
    restitue specialement que pour `MANUAL_ADMIN`; pour `dispute-center`, le
    resultat d'echec reprend le `reasonCode` de la decision Permissions.
    `applyCorrection`/`applyTargetCorrection` renvoient ensuite ce code ou un
    fallback, pas la cause ledger. Un rejet de mutation peut donc etre
    represente par un resultat faux mais un diagnostic non specifique ou
    trompeur; la proposition jointe au rejet V2 de `DIB_USED` est egalement
    perdue dans les facades simples.
  - Le comportement V2 diverge de l'ajustement manuel canonique: seul
    `source="MANUAL_ADMIN"` appelle `commitCanonicalAdminAdjustment`.
    `dispute-center` passe par `compatibilityMutation` puis
    `CommitLocalTransaction`; le garde V2 observe dans cette derniere fonction
    bloque `DIB_USED`, pas `DIB_ADMIN_ADJUSTMENT`. Le commit canonique ajoute
    une sequence, un hash de chaine et une annonce; cette voie locale ne le
    fait pas.
  - Les controles ne sont pas tous absents: `ProtectedActions.Execute` evalue
    `Permissions`, et `CommitLocalTransaction` exige un ledger approuve
    (`guild-primary` est special-cas). L'appel `localCoordinator` de Governance
    et la construction de `AWARD_COMMIT` restent toutefois propres a la route
    canonique `MANUAL_ADMIN`; ces controles existants ne transforment pas la
    mutation `dispute-center` en commit canonique.
  - `applyCorrection` utilise aussi `source="dispute-center"` sans ID de
    transaction fourni. Les actions qui passent par `ledger.adjust` ou
    `ledger.refund` peuvent donc ajouter un ajustement/remboursement local hors
    chaine canonique V2. La correction `ledger.use` suit un autre chemin: son
    `DIB_USED` est refuse par la garde V2 dans `CommitLocalTransaction`; la
    facade `Ledger.Use` ne restitue pas la proposition jointe au resultat
    rejete. Cette observation ne doit pas etre generalisee a tous les types de
    correction.
  - `SyncV2.BuildLedgerDigest` publie l'etat canonique et le rattrapage demande
    des entites `AWARD_COMMIT`; le chemin de detail renvoie ces commits
    canoniques. Aucun transport generique des transactions ajoutees uniquement
    par `CommitLocalTransaction` n'a ete trouve dans les plages suivies.
    Ainsi, une correction `dispute-center` acceptee en mode V2 peut modifier les
    soldes sur l'instance locale sans faire avancer la racine canonique ni etre
    envoyee aux autres membres. Les commits canoniques suivants peuvent alors
    etre appliques sur des historiques de soldes differents.
  - Le transfert et les recherches de transaction ne passent pas d'ID de
    ledger. `findTransaction` utilise les fonctions Ledger sans argument de
    ledger, et les transactions choisissent le ledger actif. `attachedContext`
    conserve le `seasonId`, mais pas le `ledgerId`. Si le ledger actif a change
    depuis l'ecriture d'origine, le lookup peut ne pas trouver la transaction;
    dans ce cas `transferAmount` est absent, les deux ecritures comptables sont
    sautees, mais la correction d'attribution peut quand meme resoudre le
    dossier. Le contrat attendu pour ce cas reste a confirmer.
  - `MultiLedger.GetActiveLedgerId` impose le ledger de politique s'il existe;
    sans imposition, il retourne le choix actif local. `SetActiveLedger` peut
    changer ce choix tandis que `SetViewLedger` ne change qu'une vue de lecture.
    Les corrections n'utilisent ni l'ID de l'evidence ni celui du ledger
    consulte; un changement de ledger entre la correction et une reprise peut
    donc viser un autre historique. Le comportement de la vue seule n'est pas
    une mutation de scope.
  - Pour une correction simple, `state.corrections[key]` conserve le
    `transactionId`, mais `applyCorrection` ne le recherche que dans
    `Ledger.GetTransactions` du ledger actif. `Disputes.Reopen` efface
    `request.correctionTransactionId` sans effacer cette cle; apres changement
    du ledger actif, une nouvelle resolution de meme action/montant peut ne
    pas retrouver la transaction precedente et en ajouter une autre. Pour une
    correction cible, la branche cachee retourne plutot les IDs memorises sans
    verifier leur presence dans le ledger courant. Ce sont des garanties
    differentes, aucune n'est une preuve de replication ou de coherence
    cross-ledger.
  - La carte persistante `db.disputes.corrections` est ecrite apres les deux
    ajouts et n'est donc pas un journal de reprise des ecritures partielles.
    Une resolution complete normale marque le dossier resolu et les appels
    ulterieurs sont refuses par `Disputes.Resolve`; le test existant verifie
    ce refus, pas une reprise idempotente de l'operation.
- Failure scenarios / consequences:
  - Si la seconde ecriture echoue et la compensation reussit, l'effet net sur
    les soldes est annule, mais trois transactions append-only peuvent rester;
    le dossier demeure ouvert. Une nouvelle tentative produit d'autres IDs.
  - Si la compensation echoue, l'inversion de l'ancien joueur reste sans
    transfert correspondant. Une reprise ulterieure peut inverser encore
    l'ancien joueur avant de crediter la cible; l'effet final ne correspond
    alors plus au transfert unique demande. Le code prouve que le resultat de
    compensation est ignore, mais aucune cause courante et deterministe de son
    rejet n'a ete etablie dans cette trace.
  - Une interruption ou exception entre les appels comptables peut laisser une
    seule jambe. Le code ne fournit pas de transaction englobante ni de
    recuperation au redemarrage; la disponibilite d'un point d'interruption
    normal dans le runtime Retail n'a pas ete demontree.
  - Un rejeu apres echec partiel n'est pas deduplique par la cle: les IDs sont
    regeneres et la table d'operation n'a pas ete enregistree. Les garanties de
    rejeu fondees sur le meme `transactionId` ne s'appliquent pas a un nouveau
    `Dibs.NewId`.
- Rationale: Il existe deux problemes lies mais distincts: l'operation composee
  n'est pas recuperable si une jambe ou sa compensation manque, et les corrections
  de litige hors voie canonique ne sont pas reppliquees sous V2. Le scope
  MultiLedger et le detail des erreurs retournees constituent des incertitudes
  supplementaires a trancher. Les dossiers resolus sans correction comptable ne
  sont pas concernes par le transfert en deux jambes.
- References/Dependencies:
  [ProtectedActions.lua](../../src/modules/ProtectedActions.lua),
  [Ledger.lua](../../src/modules/Ledger.lua),
  [MultiLedger.lua](../../src/modules/MultiLedger.lua),
  [Governance.lua](../../src/modules/Governance.lua),
  [Permissions.lua](../../src/modules/Permissions.lua),
  [SyncV2.lua](../../src/modules/SyncV2.lua),
  [Core.lua](../../src/Core.lua),
  [Backup.lua](../../src/modules/Backup.lua),
  [ImportExport.lua](../../src/modules/ImportExport.lua),
  [RequestDelivery.lua](../../src/modules/RequestDelivery.lua),
  [SavedVariables](../developer/saved-variables.md),
  [spec 009](../../specs/009-officer-audit-dispute-center/spec.md).
- Existing recovery: ledger history and saved snapshots can expose/preserve
  transactions, but no automatic repair was found for a local non-canonical
  adjustment. Backup restore's "keep newer" comparison may preserve a local
  ledger based on canonical progress or transaction count; it does not create
  missing canonical commits or reconcile two different local histories.
- Proposed action: Future Spec Kit work should define one persisted,
  ledger-scoped correction operation with explicit authority and replay
  semantics; every accepted leg must be either canonically replicated or
  explicitly recoverable, and partial outcomes must be observable. The design
  must not assume that SavedVariables writes or a pair of ProtectedActions are
  atomic. Add tests for second-leg rejection, compensation rejection, crash/
  retry boundary, stable replay, V2 coordinator/follower convergence and
  correction with a changed active ledger before implementation.
- **Resolution appliquee (spec 026, T015 / T024 / T027)** — verifie en session 4
  le 2026-10-20 :
  - **Une seule operation canonique, tout-ou-rien.** `applyTargetCorrection`
    et `applyCorrection` ne appellent plus deux fois `ledger.adjust`. Ils
    construisent une charge unique avec un `operationId` stable
    (`"op-" .. key`) et passent par
    `ProtectedActions.Execute("ledger.operation", actor, payload)`. Les deux
    jambes voyagent dans le meme record canonique ; il n'existe plus de
    fenetre ou une jambe est ecrite sans l'autre.
  - **Identite de rejeu stable.** L'identifiant d'operation ne depend plus de
    `Dibs.NewId("tx")` : il est derive de la cle metier stable
    (requestId, evidenceId, action, cible). `Ledger.ReplayAcceptedDisputeOperation`
    restitue le record accepte tel quel, sans reconstruire ni ajouter un
    second commit.
  - **Reprise d'un journal accepte.** `resumeAcceptedCorrection` reconstruit
    les projections manquantes depuis le record canonique accepte, sans
    append. La correction n'est plus « non recuperable » apres une
    interruption posterieure a l'acceptation.
  - **Perimetre de ledger.** Les deux chemins resolvrent le ledger d'origine
    via `MultiLedger.ResolveOriginalTransactionLedger` et transportent
    `originalLedgerId` dans la charge. Le ledger actif n'est plus devine.
  - **Verrou de release.** Le chemin canonique reste **ferme** en production :
    `Dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = false` fait rejeter
    `ledger.operation` avec `FEATURE_DISABLED`, et `applyCorrection` traduit
    ce refus en outcome `BLOCKED` — jamais en application locale hors chaine.
    Une correction n'est donc ni appliquee silencieusement ni repartie sur un
    historique non canonique.
  - **Tests** : `tests/integration/canonical_dispute_operation_spec.lua`
    (24 cas) couvre l'atomicite des deux jambes, le rejet d'une seconde jambe
    invalide, l'absence de transfert partiel apres echec, l'absence de
    double-application apres echec puis reprise, le rejeu exact sans effet,
    le rejet de contenu modifie pour un `operationId` accepte, la reconstruction
    des projections apres interruption, la convergence coordinateur/followeur,
    et le rejet d'une correction dont l'original est hors ledger actif.
  - **Portee restante** : la validation Retail de ce chemin (T041) reste
    `PENDING_MANUAL_VALIDATION`. La correction n'est active en production
    qu'apres ouverture du verrou de release, qui n'est pas modifie ici.

<a id="rf-0013"></a>
## RF-0013 - Installation.Initialize : decouverte legacy partielle traitee comme terminee

- Status: FIXED
- Confidence: HIGH
- Risk: HIGH
- Source: [Installation.lua](../../src/modules/Installation.lua) - `Installation.Initialize`
- Evidence:
  - `HistoricalBaseline.CollectLocalEvidence` construit les listes du ledger et
    de Pre-Dibs, puis appelle `CollectEvidence` deux fois. Chaque appel valide
    et persiste independamment sa copie d'etat. Si le premier (ledger) reussit
    et le second (Pre-Dibs) echoue, l'etat peut contenir une seule source.
    Condition concrete: avec 500 lignes ledger valides et au moins une ligne
    Pre-Dibs, la premiere collecte peut atteindre `MAX_EVIDENCE=500`, puis la
    seconde echoue `EVIDENCE_LIMIT_EXCEEDED`.
  - `Installation.stageLegacyDiscovery` ne recommence pas la collecte des que
    `evidenceCount > 0`. `Installation.GetStatus` definit `hasUncollectedEvidence`
    seulement par `hasRealLegacyData and evidenceCount == 0`; il ne compare pas
    les sources attendues. Une premiere source partiellement persistee peut
    donc faire passer le retry pour "aucune action requise", alors que l'autre
    source manque. `stageBaseline` verifie les findings ouverts, pas que les
    deux sources du scan local existent; une reconciliation ulterieure peut
    donc approuver un baseline ne contenant pas les Pre-Dibs omis.
  - Pour un officier non-GM, le chemin appelle `stageLegacyDiscovery(actor)`
    sans verifier son resultat; il appelle egalement `MultiLedger.ProposeLedger`
    sans lire son resultat si le ledger primaire manque, puis renvoie toujours
    `ok=true, reasonCode="PROPOSAL_CREATED"`. Sur une guilde propre habituelle,
    aucun objet de proposition n'est cree. Le test
    `guided_setup_wizard_spec` attend le code, mais ne verifie aucun objet
    persistant. Les guides officier affirment qu'une proposition est creee,
    tandis que l'architecture indique qu'Installation ne doit pas posseder
    d'etat persistant concurrent.
  - Autre incertitude de portee: `detectRealLegacyData` appelle
    `Ledger.GetAllTransactions()` sans `ledgerId` (donc le ledger actif), alors
    que `HistoricalBaseline.CollectLocalEvidence` lit explicitement
    `guild-primary`. Si ces ledgers different, la detection et la collecte ne
    couvrent pas le meme ensemble. Le contrat pour un setup avant cutover reste
    a confirmer.
  - Le detecteur enveloppe `Ledger.GetAllTransactions` dans `pcall`, mais
    transforme une exception ou un retour non-table en zero transaction sans
    exposer d'erreur. Si aucune evidence Pre-Dibs n'est ensuite comptee,
    `GetStatus` peut classer l'installation comme `CLEAN` et ne pas demander de
    scan; le comportement du code est certain, mais une exception reelle de
    cette API dans Retail n'a pas ete reproduite.
  - La confirmation officier est aussi un faux succes visible: la fonction UI
    `runInstallationAction` affiche une mise a jour si `result.ok` est vrai,
    tandis que la branche officier de `Installation.Initialize` renvoie
    `ok=true` meme lorsque la collecte ou `MultiLedger.ProposeLedger` a echoue.
- Reproduction (2026-10-19, `tests/integration/rf0013_partial_legacy_discovery_spec.lua`):
  - **CONFIRME** — un scan qui n'a persiste que la source ledger expose
    `state=NOT_INITIALIZED` avec pour seul bloqueur `GOVERNANCE_REQUIRED` :
    aucun bloqueur ne mentionne la source Pre-Dibs omise, et le scan n'est
    jamais repris.
  - **CONFIRME** — `PreDibs.GetHistory` non sous `pcall` : une exception se
    propage hors de la projection de statut.
  - **CONFIRME** — la detection lit le ledger actif alors que la collecte lit
    `guild-primary` : les deux portees divergent.
  - **CONFIRME** — la branche officier renvoie `ok=true,
    reasonCode="PROPOSAL_CREATED"` sans objet de proposition persistant.
- Fix applique (2026-10-19, `src/modules/Installation.lua`):
  - Le scan local expose desormais un **manifeste de sources attendues**
    derive de `HistoricalBaseline.GetState().sources` (`LOCAL_SCAN_SOURCES`).
    `HistoricalBaseline` reste le proprietaire unique de l'evidence ; aucune
    seconde source de verite n'est introduite.
  - `stageLegacyDiscovery` **reprend** un scan partiel : il compare les
    sources attendues aux sources collectees, relance la collecte manquante,
    et refuse de declarer le scan termine tant qu'une source reste a collecter
    (`LEGACY_EVIDENCE_SCAN_INCOMPLETE:<sources>`).
  - `GetStatus` calcule `hasUncollectedEvidence` **par source** et expose
    `legacy.missingScanSources`. Le bloqueur `LEGACY_EVIDENCE_SCAN_REQUIRED`
    est present dans tous les etats, pas seulement apres l'adoption de la
    gouvernance.
  - `stageBaseline` refuse d'approuver un baseline tant qu'une source qui
    contient des donnees n'a pas ete collectee.
  - `detectRealLegacyData` lit `guild-primary` (meme portee que la collecte) et
    ne transforme plus une erreur de lecture en source vide : une source
    illisible est signalee `LEGACY_EVIDENCE_SOURCE_UNREADABLE`.
  - La branche officier lit le resultat de la decouverte et celui de la
    proposition ; elle ne renvoie plus `PROPOSAL_CREATED` sans proposition
    verifiable, et propage `LEGACY_EVIDENCE_SCAN_INCOMPLETE` ou
    `LEDGER_PROPOSAL_NOT_CREATED`.
- Fix A1 applique (2026-10-21, session 15, `src/modules/HistoricalBaseline.lua`
  et `src/modules/Installation.lua`) :
  - La collecte est **paginee**. `BATCH_SIZE = 500` est l'unite de
    reprise, `MAX_EVIDENCE_PER_SOURCE = 500` borne un lot d'une source, et
    `MAX_EVIDENCE_PER_CYCLE = 5000` borne un cycle. **La retention n'est
    pas bornee** : une base peut contenir plus de preuves qu'un cycle n'en
    collecte, et **rien n'est jamais supprime** pour faire de la place.
  - Le **curseur est persistant** (`state.collectionProgress[sourceId]` :
    `cursor`, `sourceFingerprint`, `totalSeen`, `state`, `lastReason`,
    `updatedAt`). Il **n'avance qu'apres** l'acceptation du lot qu'il
    couvre : une interruption perd au pire un lot, que la deduplication
    existante rejoue sans effet.
  - L'**empreinte de source** invalide un curseur qui ne decrit plus la
    source : celle-ci est recollectee depuis le debut, et la deduplication
    fait que les enregistrements deja collectes restent uniques
    (`EVIDENCE_SOURCE_CHANGED`).
  - Les etats sont `COMPLETE`, `INCOMPLETE` et `ERROR`.
  - La deduplication n'est **pas reimplementee** : celle de `collectInto`
    (par `evidenceId`, avec `EVIDENCE_ID_CONFLICT`) fait foi.
  - Une source **illisible** conserve son diagnostic explicite
    (`LEGACY_EVIDENCE_SOURCE_UNREADABLE`) et une collecte en cours est
    signalee `LEGACY_EVIDENCE_SCAN_PARTIAL:<source>@<curseur>:<etat>`.
  - Une collecte **incomplete ne peut jamais etre approuvee** comme
    complete : `FinalizeBaseline` refuse avec
    `INCOMPLETE_EVIDENCE_SOURCE_IN_PROGRESS`, **meme** avec
    `acknowledgeIncompleteEvidence = true`. L'aveu d'omission et
    l'etat non termine ne produisent plus le meme resultat.
  - `Installation.GetStatus` expose `legacy.pendingScanSources` avec le
    curseur et l'etat de chaque source en cours.
- Fix B1 applique (2026-10-21, session 15, `src/modules/MultiLedger.lua`) :
  - `MultiLedger.ProposeLedger` est **etendu**, pas remplace : la
    signature publique (`actor`, `name`, `options`) et le contrat
    (`{ ok = true, ledgerId }`) sont conserves.
  - Les **metadonnees sont validees a la creation** : perimetre (liste
    fermee `{ledger, predibs}`), volume (entiers non negatifs), motif
    (liste fermee), sources illisibles, et `scanComplete = true` interdit
    si une source illisible est declaree. Elles sont **reverifiees a
    l'approbation** : une source encore en cours, une source illisible ou
    un volume qui contredit les preuves disponibles **refusent
    l'approbation** (`PROPOSAL_SOURCE_INCOMPLETE`,
    `PROPOSAL_UNREADABLE_SOURCES`, `PROPOSAL_VOLUME_MISMATCH`).
  - **L'unicite est garantie** : une seconde proposition active de meme
    motif et meme perimetre est refusee
    (`DUPLICATE_LEDGER_PROPOSAL`). Un index de propositions
    (`db.ledgerProposals`) a ete cree : il ne contient que des
    **metadonnees**, jamais de transactions, et ne constitue pas un second
    registre de Governance.
  - Une proposition n'est **jamais** conforme parce que son nom est
    "Guild Primary" : `Installation.Initialize` verifie desormais le
    **statut** du ledger primaire et l'existence d'une proposition
    active, plus le nom.
  - La proposition est **reellement persistee** avant tout succes, et
    lisible par `GetProposal` et `ListProposals`. `UpdateProposal` permet
    a l'officier de corriger une proposition refusee sans la perdre.
  - Les permissions sont preservees : l'officier propose
    (`ledger.propose`), le GM approuve (`ledger.approve`). Un membre est
    refuse.
  - L'audit trace les creations, les mises a jour, les approbations et
    les refus (`LEDGER_PROPOSAL_CREATED`, `LEDGER_PROPOSAL_UPDATED`,
    `LEDGER_PROPOSAL_APPROVED`, `LEDGER_PROPOSAL_REJECTED`), en
    complement de la trace d'approbation deja produite par
    `Governance.RecordLedgerApproval`.
  - `PROPOSAL_CREATED` n'est **jamais** annonce sans proposition
    persistee.
- Verification complementaire (2026-10-22, session 16) :
  `tests/integration/rf0013_verification_spec.lua` (13 cas V01 a V13)
  ajoute les garanties que les deux suites precedentes ne demontraient
  pas encore : pagination complete sans perte a la frontiere de lot
  (V01), reprise apres interruption (V02), deduplication (V03), source qui
  change a chaque collecte **sans boucle infinie** (V04), racine
  SavedVariables anterieure qui charge et collecte (V05), collecte
  partielle jamais approuvable (V06), proposition anterieure au contrat
  de metadonnees **non abandonnee** (V07), metadonnees absentes refusees
  (V08), proposition dupliquee refusee (V09), reverification a
  l'approbation (V10), permissions GM/Officier (V11), persistance au
  rechargement (V12), audit des decisions (V13).
- **Defaut reel corrige en session 16** : une proposition ecrite
  **avant** le contrat de metadonnees (un ledger `PROPOSED` sans
  metadonnees et sans entree dans l'index) etait **abandonnee** : elle ne
  pouvait etre ni approuvee (`INVALID_PROPOSAL_PURPOSE`) ni reparee
  (`PROPOSAL_NOT_FOUND`), faute d'identifiant de proposition. La
  proposition **heritee** est desormais adoptee dans l'index lorsqu'elle
  est lue, avec les metadonnees que l'officier fournit, et elle reste
  approvable. L'adoption est idempotente et ne change jamais le statut.
  Discrimination verifiee par reinjection : sans l'adoption, V07 echoue.
- Tests (2026-10-21, session 15) :
  `tests/integration/rf0013_paginated_collection_spec.lua` (12 cas A01 a
  A12) et `tests/integration/rf0013_officer_proposal_spec.lua` (15 cas
  B01 a B15). Les 27 cas passent. Les cas discriminants exiges sont
  couverts : reprise de collecte (A04, A05, A06), doublons (A05),
  source modifiee (A06), source illisible (B07, B09), collecte partielle
  (A08, A09), propositions dupliquees (B03), metadonnees absentes (B14),
  approbation non autorisee (B01, B12), approbation avec preuves
  contradictoires (B08, B10).
- Remaining: aucun. Les deux decisions metier sont tranchees et
  implementees ; RF-0013 peut passer a `FIXED`.
  - L'objet de proposition que l'Officer doit creer n'est pas specifie. Le
    code ne pretend plus avoir cree une proposition inexistante ; la forme
    attendue du resultat reste a decider.
- Rationale: Une erreur de collecte peut laisser une source deja enregistree;
  le test d'avancement base sur le simple nombre d'evidences ne detecte pas
  qu'il manque une autre source. Le chemin officier peut egalement presenter
  un resultat de succes sans proposition verifiable; le detecteur peut aussi
  masquer une erreur de lecture. La sequence et les retours sont certains;
  l'impact exact de l'absence des anciennes demandes Pre-Dibs, la possibilite
  d'une exception en Retail et le scope multi-ledger attendu restent a confirmer.

<a id="rf-0014"></a>
## RF-0014 - CharacterEligibility : un changement de main fusionne deux joueurs sans lien

- Status: FIXED
- Confidence: HIGH
- Risk: HIGH
- Source: [CharacterEligibility.lua](../../src/modules/CharacterEligibility.lua) -
  `Eligibility.RequestMainChange`, `Eligibility.ApproveMainChange`
- Evidence:
  - `RequestMainChange` derive `playerGroupId` de l'**ancien** main
    (`Eligibility.GetPlayerGroup(oldMain, ...)`) mais ne verifie jamais que le
    **nouveau** main appartient a ce meme groupe. Le nouveau main est accepte
    tel quel, quel que soit le joueur qui le possede.
  - `ApproveMainChange` ne revalidait pas non plus l'appartenance des deux
    personnages au moment de l'approbation.
  - Consequence reproduite (2026-10-19) : apres approbation,
    `Eligibility.GetPlayerGroup("Stranger-Realm")` renvoie le groupe du
    demandeur. Le personnage d'un joueur sans lien herite donc du groupe de
    l'autre, ses acquisitions sont comptees dans le meme groupe d'eligibilite,
    et `Eligibility.GetAcquisitions` lui donne acces a l'historique
    d'acquisitions du demandeur. Exposition de donnees entre joueurs et
    fusion d'eligibilite.
  - Le flux legitime « changement de role » (basculer son main vers un autre
    personnage du meme joueur) doit rester possible : un personnage encore
    non rattache (`character:<id>`) est une cible valide, car c'est
    l'approbation qui le rattache au demandeur.
- Fix applique (2026-10-19, `src/modules/CharacterEligibility.lua`):
  - `RequestMainChange` refuse `MAIN_CHANGE_GROUP_MISMATCH` lorsque le
    nouveau main **appartient deja** a un autre groupe de joueur. Un
    personnage encore non rattache reste une cible valide.
  - `ApproveMainChange` revalide l'appartenance au moment de l'approbation,
    ce qui couvre les requetes enregistrees avant le correctif et les
    personnages separes depuis la demande.
  - Aucun changement de persistance : aucun historique n'est reecrit, aucune
    acquisition n'est modifiee, et le flux « changement de role » existant
    reste intact.
- Tests: `tests/integration/rf0014_main_change_group_escape_spec.lua`, 5 cas.
  Chaque garde a ete verifie comme discriminant par reinjection de la cause.
- Remaining: aucun pour la cause racine. La forme exacte de l'objet
  « nouveau personnage » et la procedure d'approbation GM restent une
  decision metier, sans impact sur la garde de groupe.

<a id="rf-0015"></a>
## RF-0015 - Wizard : une verification obligatoire masquee par une verification facultative

- Status: FIXED
- Confidence: HIGH
- Risk: MEDIUM
- Source: [Wizard.lua](../../src/modules/Wizard.lua) -
  `Wizard.GetTurnkeyStatus`
- Evidence:
  - `SetupAssistant.Evaluate` distingue les verifications obligatoires
    (`required == true`, comptees dans `blockingCount` et qui passent le
    rapport en `NEEDS_ATTENTION`) des verifications facultatives.
  - `Wizard.GetTurnkeyStatus` selectionnait la **premiere** verification non
    `ready` du rapport de readiness pour expliquer l'etape et fixer la
    prochaine action, sans regarder le drapeau `required`.
  - Consequence reproduite (2026-10-20) : avec une verification facultative
    degradee placee avant une verification obligatoire bloquee, l'etape
    `readiness` expliquait et recommandait la verification **facultative**.
    L'officier etait dirige vers un element facultatif pendant que le vrai
    bloqueur restait sans explication. L'etat global restait `BLOCKED`, mais la
    cause affichee etait fausse.
- Fix applique (2026-10-19, `src/modules/Wizard.lua`) : la selectionne
  recherche d'abord une verification **obligatoire** non `ready` et non
  `skipped`, et ne retombe sur une verification facultative que si aucune
  verification obligatoire n'est ouverte. Les verifications `ready` et
  `skipped` restent ignorees. Aucun changement de statut global : la
  correction ne porte que sur l'explication et la prochaine action affichees.
- Tests : `tests/integration/rf0015_wizard_blocking_finding_spec.lua`, 4 cas.
  La garde est verifiee comme discriminate par reinjection de la cause.
- Remaining: aucun.

<a id="rf-0016"></a>
## RF-0016 - Readiness : la porte d'attribution live contredit le drapeau du meme resultat

- Status: FIXED
- Confidence: HIGH
- Risk: MEDIUM
- Source: [Readiness.lua](../../src/modules/Readiness.lua) -
  `Readiness.CanProcessLiveAward`
- Evidence:
  - `Readiness.Evaluate` calcule `liveConsumptionAllowed`, vrai seulement quand
    `integrationStatus == "Ready"` **et** `standaloneStatus == "Ready"`.
  - `Readiness.CanProcessLiveAward` ignorait ce drapeau : il ne refusait que
    l'etat `Blocked` et renvoyait `true` pour tout le reste, y compris
    `Degraded`.
  - Consequence reproduite (2026-10-20) : sur un resultat
    `integrationStatus = "Degraded"`, la fonction renvoyait `true` alors que
    le **meme objet resultat** portait `liveConsumptionAllowed = false`. Deux
    reponses contradictoires a la meme question, dans le meme objet.
  - L'impact visible est direct : l'interface RCLootCouncil affiche
    « Live Dibs consumption: blocked or unavailable » d'apres
    `liveConsumptionAllowed`, alors que la fonction de garde autorise. Un
    tiers appelant pourrait s'appuyer sur l'une ou l'autre reponse.
- Fix applique (2026-07-20, `src/modules/Readiness.lua`) : la porte honore
  desormais le drapeau autoritatif `liveConsumptionAllowed`. L'etat
  `Unavailable` reste autorise, car il est attendu hors session live et ne
  doit pas casser le chemin local du callback RC ; c'est deja le contrat
  documente et couvert par `raid_readiness_spec`.
- Tests : `tests/integration/rf0016_readiness_gate_consistency_spec.lua`, 4 cas.
  La garde est verifiee comme discriminate par reinjection de la cause.
- Remaining: aucun.

<a id="rf-0017"></a>
## RF-0017 - CharacterEligibility : un identifiant de groupe de joueur fourni par l'appelant

- Status: FIXED
- Confidence: HIGH
- Risk: HIGH
- Source: [CharacterEligibility.lua](../../src/modules/CharacterEligibility.lua) -
  `Eligibility.DeclareRelationship`, `Eligibility.RecordAcquisition`
- Evidence:
  - Le groupe de joueur est l'autorite qui rattache un personnage a ses
    acquisitions. `Eligibility.GetPlayerGroup` le derive de la relation
    approuvee ou de l'identite du personnage.
  - `DeclareRelationship` acceptait `options.playerGroupId` et
    `RecordAcquisition` acceptait `input.playerGroupId`. Un appelant pouvait
    donc **choisir** le groupe.
  - Consequence reproduite (2026-07-20) :
    - un declarant pouvait choisir un groupe, fusionner deux joueurs sans lien
      dans ce groupe, y placer ses propres acquisitions, et l'autre joueur
      pouvait alors **lire l'historique d'acquisitions** du premier
      (`GetAcquisitions` filtre sur le groupe) ;
    - un officier pouvait enregistrer une acquisition pour son propre
      personnage en la marquant du groupe d'un tiers ; le tiers lisait alors
      cette acquisition et l'objet comptait pour son eligibilite.
  - La correction de RF-0014 avait traite le vecteur du changement de main
    mais pas ces deux vecteurs d'ecriture directe.
- Fix applique (2026-07-20, `src/modules/CharacterEligibility.lua`) : le
  groupe de joueur est **toujours derive du personnage**. Aucun parametre
  d'appelant ne l'influence. Aucun appelant interne ne fournissait de
  `playerGroupId`, donc le flux legitime est inchange ; le flux « changement
  de role » vers un personnage encore non rattache reste possible.
- Tests : `tests/integration/rf0017_player_group_derivation_spec.lua`, 4 cas.
  La garde est verifiee comme discriminate par reinjection de la cause.
- Remaining: aucun.

<a id="rf-0018"></a>
## RF-0018 - Profiles : plusieurs profils restent actifs et GetActive renvoie un profil arbitraire

- Status: FIXED
- Confidence: HIGH
- Risk: MEDIUM
- Source: [Profiles.lua](../../src/modules/Profiles.lua) -
  `Profiles.Activate`, `Profiles.GetActive`
- Note: reprend le constat de RF-0008 (`NEED_UPDATE`), confirme et corrige
  dans cette session. RF-0008 est mis a jour dans cette section.
- Evidence:
  - `Profiles.Activate` marquait le profil active et ecrivait l'index
    `profiles.active[scope:name]`, mais ne retirait jamais le drapeau du profil
    precedemment active.
  - `Profiles.GetActive` parcourait la table des profils avec `pairs()` et
    renvoyait le premier profil trouve, donc l'ordre de parcours, non le
    profil reellement active.
  - Consequence reproduite (2026-07-20) : apres l'activation de A puis de B,
    deux profils restaient `active = true` et `GetActive` renvoyait A, donc
    le profil que l'officier venait d'activer etait ignore. La configuration
    projetee par `db.settings` provenait de B, mais l'interface pouvait
    annoncer A.
- Fix applique (2026-07-20, `src/modules/Profiles.lua`) :
  - `Activate` retire le drapeau `active` et l'index de tous les autres
    profils du meme scope avant de marquer le nouveau. Un seul profil est
    actif par scope, et les scopes `guild` et `local` restent independants.
  - `GetActive` consulte d'abord l'index `profiles.active`, qui fait
    autorite, et ne retombe sur le drapeau stocke que pour un profil enregistre
    avant l'existence de l'index. Le resultat ne depend plus de l'ordre de
    parcours.
  - La suppression d'un profil actif le retire deja de l'index ; le test le
    verifie.
- Tests : `tests/integration/rf0018_single_active_profile_spec.lua`, 4 cas.
  La garde est verifiee comme discriminate par reinjection de la cause.
- Remaining: aucun.
- References/Dependencies:
  [HistoricalBaseline.lua](../../src/modules/HistoricalBaseline.lua),
  [MultiLedger.lua](../../src/modules/MultiLedger.lua),
  [OfficerUI.lua](../../src/ui/OfficerUI.lua),
  [Guided Setup test](../../tests/integration/guided_setup_wizard_spec.lua),
  [Installation test](../../tests/integration/installation_wizard_spec.lua),
  [guide officier FR](../officer/MODE_EMPLOI_GM_OFFICIER.md),
  [architecture Installation V2](../audits/Installation_Initialization_V2_Architecture_Review.md).
- Proposed action: Future Spec Kit work should make local evidence collection
  atomic or resumable per source, determine completion from the expected source
  set, align detection and collection ledger scope, and surface all stage
  failures. Define precisely what `PROPOSAL_CREATED` acknowledges; do not add a
  competing persisted installation state without reconciling the architecture
  contract. Test source-two failure at capacity, retry after partial persistence,
  active-ledger mismatch, officer proposal failure and reload visibility if a
  proposal is meant to persist.

<a id="rf-0019"></a>
## RF-0019 - PlayerUI : le badge d'integration RCLootCouncil applique la precedence des operateurs

- Status: FIXED
- Confidence: HIGH
- Risk: HIGH
- Source: [PlayerUI.lua](../../src/ui/PlayerUI.lua) -
  `Dibs.PlayerUI.GetIntegrationState`
- Evidence:
  - Le badge d'integration etait calcule par
    `integration.availability == "operational" or integration.status == "Ready" and { status = "Ready" } ...`.
    En Lua, `and` lie plus fort que `or` : l'expression valait le booleen
    `true` pour une integration operationnelle, et non la table
    `{ status = "Ready" }`. `GetStatusPresentation(true)` retombait alors
    sur « Dibs temporarily unavailable », si bien que le badge affichait
    « RCLootCouncil: Dibs temporarily unavailable » pour une integration
    saine. Le meme defaut affectait le badge de la fenetre legacy.
  - Le badge RCLootCouncil n'existait que dans la fenetre legacy, elle aussi
    inatteignable : la fenetre live n'affichait aucun etat d'integration
    RCLootCouncil.
- Fix applique (2026-10-20, `src/ui/PlayerUI.lua`) :
  - `Dibs.PlayerUI.GetIntegrationState` remplace la chaine `and`/`or` par
    un mapping explicite qui renvoie toujours une table d'etat, et la
    fenetre live affiche maintenant le badge d'integration RCLootCouncil.
- Tests : `tests/integration/rf0019_player_eligibility_surface_spec.lua`.
  La cause est verifiee comme discriminate par reinjection : l'injection
  de la precedence d'origine fait echouer 2 verifications.
- Remaining: aucun.
- References/Dependencies:
  [RCLootCouncil.lua](../../src/integrations/RCLootCouncil.lua),
  [Midnight.lua](../../src/ui/Midnight.lua),
  [Core.lua](../../src/Core.lua).
- Proposed action: Conserver le test de non-regression.

<a id="rf-0024"></a>
## RF-0024 - PlayerUI : la surface de declaration main/alt est orpheline dans la fenetre atteignable

- Status: FIXED
- Confidence: HIGH
- Risk: HIGH
- Source: [PlayerUI.lua](../../src/ui/PlayerUI.lua) -
  `renderEligibilitySurface`, `createAceWindow`, `createLegacyAceWindow`
- Evidence:
  - La seule implementation des controles « Declare alt » et « Request
    main change » se trouvait dans `createLegacyAceWindow`, une fonction
    locale qui n'est plus appelee depuis le commit `845d478` (« Implement
    B11c player UI redesign »), qui a introduit `createAceWindow`. Or
    `Dibs.PlayerUI.CreateWindow` ne retourne que `createAceWindow` quand
    AceGUI est disponible. La fenetre live n'exposait donc ni la section
    « Main / alt declarations », ni le tableau « Protected-loot status »,
    ni les lignes « Protected-loot group » et « Main-change probation ».
  - Consequence reproduite : un joueur ne pouvait plus declarer un alt ni
    demander un changement de main depuis l'interface. Cela contredit
    FR-012 de la [spec 005](../../specs/005-character-loot-eligibility/spec.md)
    (« The system MUST allow a player to declare a main and related alts »)
    et laisse la tache T012 (« Add Player and Officer modeless
    status/policy/relationship controls ») non realisee pour la fenetre
    atteignable. Le `onRelease` de la fenetre live effacait d'ailleurs
    encore `eligibilityCharacter` et `eligibilityStatus`, deux champs
    qu'elle ne definissait jamais — indice direct de l'orphelinat.
- Fix applique (2026-10-20, `src/ui/PlayerUI.lua`) :
  - La surface « Main / alt declarations » et « Protected-loot status » est
    extraite dans un rendu partage `renderEligibilitySurface`, appele par
    les deux fenetres. Elle lit uniquement le resume player-scoped et
    soumet une declaration en attente ; l'approbation reste reservee a un
    GM/Officier verifie. Aucune autorite ni regle de comptabilite n'est
    modifiee.
  - `GetPlayerName` est appele de facon defensible ; la declaration utilise
    des identites de personnage completes, jamais une valeur nil.
- Tests : `tests/integration/rf0019_player_eligibility_surface_spec.lua`,
  dont un cas verifie de bout en bout qu'une declaration produit une
  relation `pending` avec le bon main et le bon alt. La cause est
  verifiee comme discriminate : neutraliser l'appel dans la fenetre live
  fait echouer 2 verifications.
- Remaining: la surface de revue cote Officier
  (`ListRelationships`, `ListMainChanges`, `ReviewRelationship`,
  `ApproveMainChange`) reste absente de `OfficerUI.lua` : aucune interface
  n'expose encore la revue des declarations par un GM ou un Officier. Ce
  point est couvert par RF-0020.
- References/Dependencies:
  [CharacterEligibility.lua](../../src/modules/CharacterEligibility.lua),
  [Core.lua](../../src/Core.lua),
  [spec 005](../../specs/005-character-loot-eligibility/spec.md),
  [evidence B11c](../audits/B11c_Implementation_Evidence.md).
- Proposed action: Conserver le test de non-regression. Ne pas deplacer
  la surface d'eligibilite vers la fenetre legacy : la fenetre legacy est
  du code mort non appele et doit etre supprimee, pas restauree.

<a id="rf-0025"></a>
## RF-0025 - CharacterEligibility : le meme identifiant de groupe couvre deux fonctions distinctes

- Status: FIXED
- Confidence: HIGH
- Risk: HIGH
- Source: [CharacterEligibility.lua](../../src/modules/CharacterEligibility.lua) -
  `Eligibility.RecordAcquisition`
- Evidence:
  - RF-0017 corrigeait deux emplacements distincts : la declaration de
    relation (`Eligibility.DeclareRelationship`) et l'enregistrement d'une
    acquisition (`Eligibility.RecordAcquisition`). Les deux portaient le
    meme tag `-- @AUDIT RF-0017`.
  - La regle de la competence est explicite : « Un ID RF ne correspond
    qu'a **un** emplacement Lua, jamais deux. Si un meme probleme affecte
    plusieurs fonctions, creer plusieurs RF et les relier dans la
    documentation. » (`references/tags-and-links.md`).
  - Le validateur `validate_audit.py` signale donc « ID RF-0017 duplique »
    sur `src/modules/CharacterEligibility.lua:277` et `:699`.
  - Le defaut de securite lui-meme reste entierement corrige : les deux
    emplacements derivent bien le groupe depuis le personnage
    (`playerGroupId = Eligibility.GetPlayerGroup(characterName, targetSeason)`)
    et ignorent un `playerGroupId` fourni par l'appelant.
- Fix applique (2026-10-20, `src/modules/CharacterEligibility.lua`) :
  - Le second emplacement porte desormais son propre identifiant
    `RF-0025`, et RF-0017 ne designe plus que
    `Eligibility.DeclareRelationship`. Le comportement applicatif n'est
    pas modifie : les deux protections RF-0014 et RF-0017 restent
    inchangees et couvertes par
    `tests/integration/rf0017_player_group_derivation_spec.lua`.
- Tests : `tests/integration/rf0017_player_group_derivation_spec.lua`
  (4 PASS / 0 FAIL) couvre les deux emplacements — declaration et
  acquisition — sans changement de comportement.
- Remaining: aucun.
- References/Dependencies:
  [ProtectedActions.lua](../../src/modules/ProtectedActions.lua),
  [Permissions.lua](../../src/modules/Permissions.lua),
  [rf0017 spec](../../tests/integration/rf0017_player_group_derivation_spec.lua),
  [SKILL.md](../../.github/skills/lua-code-audit/SKILL.md),
  [tags-and-links.md](../../.github/skills/lua-code-audit/references/tags-and-links.md).
- Proposed action: Conserver la separation. A chaque nouvelle correction
  qui touche deux fonctions, creer deux identifiants plutot que de
  dupliquer un tag.

<a id="rf-0020"></a>
## RF-0020 - OfficerUI : aucune interface n'expose la revue des declarations main/alt

- Status: FIXED
- Confidence: HIGH
- Risk: MEDIUM
- Source: [OfficerUI.lua](../../src/ui/OfficerUI.lua) - onglet
  « eligibility », `Dibs.OfficerUI.ReviewEligibilityRelationship`,
  `Dibs.OfficerUI.ReviewEligibilityMainChange`
- Evidence:
  - Les services de revue existent et sont proteges :
    `CharacterEligibility.ListRelationships`, `ListMainChanges`,
    `ReviewRelationship`, `ApproveMainChange`, ainsi que les actions
    `eligibility.relationship.review` et `eligibility.main.review` dans
    `ProtectedActions` et `Permissions`.
  - Aucune interface ne les consomme : `grep` sur `src/ui/` ne trouve
    aucune reference a `ListRelationships`, `ListMainChanges`,
    `ReviewRelationship` ou `ApproveMainChange`. L'onglet « Loot
    Eligibility » de `OfficerUI` ne traite que les categories de loot
    (allow/block) et les politiques par famille.
  - Consequence : apres RF-0019, un joueur peut deposer une declaration et
    un changement de main, mais aucun GM ni Officier n'a de surface pour
    les approuver, les rejeter ou les suspendre. Les declarations restent
    donc indefiniment `pending` et la tache T012 de la spec 005 reste a
    moitie realisee (« Player **and Officer** modeless
    status/policy/relationship controls »).
  - La voie `Dibs.CoreAPI.reviewCharacterRelationship` et
    `approveMainChange` existe et passe par `ProtectedActions`, donc
    l'autorite et l'audit sont deja previsibles : il manque la surface, pas
    la logique.
- Rationale: Le defaut est un manque de surface d'interface, pas une
  erreur de regle metier. Le contrat fonctionnel etait **entierement
  defini** par les contrats existants : `ReviewRelationship` accepte
  `approved` / `rejected` / `suspended`, exige une raison pour un refus ou
  une suspension (`REASON_REQUIRED`), journalise en append-only, et
  `ApproveMainChange` impose une duree de probation de 14 jours par
  defaut et revalide le groupe de joueur a l'approbation. Aucune decision
  metier n'a donc du etre inventee.
- Fix applique (2026-10-20, `src/ui/OfficerUI.lua`) :
  - L'onglet « Loot Eligibility » expose desormais une section
    « Main / alt declarations » qui liste les declarations et les
    changements de main **en attente** pour la saison courante, avec les
    colonnes main, alt et date, et un motif de revue.
  - `Dibs.OfficerUI.ReviewEligibilityRelationship` et
    `Dibs.OfficerUI.ReviewEligibilityMainChange` sont les **seuls** points
    de mutation de la surface. Ils passent par
    `ProtectedActions.Execute("eligibility.relationship.review", ...)` et
    `ProtectedActions.Execute("eligibility.main.review", ...)`, donc
    l'autorite GM/Officier, la journalisation et les gardes de groupe de
    RF-0014 / RF-0017 sont herites sans duplication.
  - Un refus ou une suspension transmet le motif saisi ; a defaut de
    motif, le domaine refuse (`REASON_REQUIRED`) et la declaration reste
    `pending`.
  - **Un refus ne modifie aucune donnee protegee** : le groupe de
    l'eligibilite du personnage refuse reste `character:<id>`, et aucun
    groupe de joueur n'est fusionne.
  - Aucune regle de comptabilite, aucun historique de ledger, aucun
    equilibre de Dibs n'est touche : la surface ne fait qu'appeler des
    services deja proteges.
- Tests : `tests/integration/rf0020_officer_relationship_review_spec.lua`,
  6 cas.
  - La surface est verifiee comme discriminate : remplacer l'appel protege
    par un appel direct au domaine fait echouer la verification de motif.
  - La defense en profondeur est verifiee : le domaine porte aussi son
    propre controle d'autorite, donc un contournement d'une seule couche
    reste refuse. Le test verifie qu'un membre sans autorite ne peut ni
    approuver via l'action protegee, ni via la surface.
- Remaining: aucun. La tache T012 de la spec 005 (« Player **and
  Officer** modeless status/policy/relationship controls ») est desormais
  realisee des deux cotes.
- References/Dependencies:
  [CharacterEligibility.lua](../../src/modules/CharacterEligibility.lua),
  [ProtectedActions.lua](../../src/modules/ProtectedActions.lua),
  [Permissions.lua](../../src/modules/Permissions.lua),
  [Core.lua](../../src/Core.lua),
  [spec 005](../../specs/005-character-loot-eligibility/spec.md).
- Proposed action: Traiter dans une iteration Spec Kit dediee. Ne pas
  contourner `ProtectedActions` : toute approbation doit passer par
  `eligibility.relationship.review` et `eligibility.main.review` afin de
  rester attribuee et auditee. Verifier que la surface Officier ne revele
  que des donnees limitees a la guilde (FR-022).

<a id="rf-0021"></a>
## RF-0021 - sync_status_spec : la fixture de test utilise un `lastSeenAt` fige hors de la fenetre de heartbeat

- Status: FIXED
- Confidence: HIGH
- Risk: LOW
- Source: [sync_status_spec.lua](../../tests/integration/sync_status_spec.lua) -
  « uses a recent addon response when the guild roster still reports offline »
- Evidence:
  - Le test ecrivait `lastSeenAt = 1700000000` en dur. L'horloge de
    `tests/helpers/wow_api.lua` avance de 1 a chaque appel de `time()` et
    repart de `baseTime = 1700000000` a chaque `loader.load()`.
  - Mesure (2026-10-20) : `loader.load()` consomme **183 ticks** a lui
    seul. La resolution du membre en consomme 1 de plus, et
    `Sync.GetPeerStatuses` 2 de plus. Au moment de l'assertion,
    `now - lastSeenAt = 186`.
  - La fenetre de detection est `HEARTBEAT * 3 = 180` secondes
    (`src/modules/SyncV2.lua:570`, `HEARTBEAT = 60`). `detected` valait
    donc `false`, `online = rosterOnline or detected` valait `false`, et
    `assert_true(officer.online)` echouait.
  - Le comportement applicatif est **correct** : avec un `lastSeenAt`
    recent, la detection par heartbeat fonctionne (`presenceSource =
    "ADDON_HEARTBEAT"`, `addonDetected = true`).
  - L'echec etait **independant de l'ordre d'execution** : il se
    reproduisait dans le fichier de test seul, et avec un `PlayerUI.lua`
    pristine. `HEARTBEAT` et la logique de detection sont inchanges
    depuis `dc388f9`.
- Fix applique (2026-10-20, `tests/integration/sync_status_spec.lua`) :
  - La fixture derive `lastSeenAt` de l'horloge controlee
    (`local seenAt = time()`) au lieu d'une constante. Le test ne depend
    plus de l'heure reelle ni du nombre de ticks consommes par le
    chargement de l'addon.
  - **La validation temporelle n'est pas affaiblie** : deux cas ont ete
    ajoutes pour couvrir la fenetre de fraicheur avant, pendant et apres
    expiration.
    - « keeps a peer inside the freshness window detected » : `lastSeenAt`
      a 100 s -> `online = true`, `presenceSource = "ADDON_HEARTBEAT"`.
    - « stops detecting a peer once the freshness window expired » :
      `lastSeenAt` a 200 s -> `online = false`,
      `presenceSource = "NONE"`, `addonDetected = false`.
  - La logique de production n'est **pas** modifiee : `HEARTBEAT`, la
    fenetre de 180 s et le calcul de `detected` sont inchanges.
- Tests : `tests/integration/sync_status_spec.lua` passe de 6 a 9 cas,
  **9 PASS / 0 FAIL**.
  - La garde est verifiee comme discriminate : neutraliser la fenetre de
    fraicheur en production (`now - lastSeen <= HEARTBEAT * 3`) fait
    echouer exactement le cas d'expiration.
- Remaining: aucun.
- References/Dependencies:
  [SyncV2.lua](../../src/modules/SyncV2.lua),
  [wow_api.lua](../../tests/helpers/wow_api.lua),
  [load_addon.lua](../../tests/helpers/load_addon.lua).
- Proposed action: Conserver les trois cas (frais, dans la fenetre,
  expire). Ne pas modifier `HEARTBEAT` ni la fenetre de 180 secondes :
  cette valeur est un contrat de synchronisation, pas un parametre de
  test.

<a id="rf-0022"></a>
## RF-0022 - LootPipeline : la voie de repli contourne l'interdiction de Pre-Dibs publics

- Status: FIXED
- Confidence: HIGH
- Risk: HIGH
- Source: [LootPipeline.lua](../../src/modules/LootPipeline.lua) -
  `Dibs.LootPipeline.RequestDibFromContext`
- Evidence:
  - La fonction tentait `PreDibs.CreatePublic` et, **seulement si les
    Pre-Dibs publics etaient desactives**, se repliait sur
    `PreDibs.Create`.
  - `PreDibs.Create` ne consulte pas `IsPublicEnabled` : il cree une
    requete au statut `pending` et l'inscrit dans le store. La politique
    publique n'etait donc appliquee que sur un seul des deux chemins.
  - Consequence reproduite (2026-10-20) : avec
    `db.settings.allowPublicPreDibs = false`,
    `LootPipeline.RequestDibFromContext` renvoyait une requete non
    `nil`, de statut `pending`, et `PreDibs.GetHistory()` contenait une
    entree. Un joueur pouvait donc enregistrer une requete alors que les
    Officiers avaient ferme la voie publique.
  - Cela contredit le **scenario 3 de l'User Story 1 de la spec 002** :
    « Given public Pre-Dibs are disabled, When a player submits a public
    request, Then the request is rejected with a clear reason and **no
    state is added** ». La meme politique est deja appliquee et deja
    testee au niveau du service par `tests/unit/public_predibs_spec.lua`
    et par `EncounterJournal.CanPreDib`, qui renvoie deja
    `PUBLIC_PRE_DIBS_DISABLED`.
  - Les trois appelants de production (`PlayerUI.submitPublicPreDib`,
    `EncounterJournal.SubmitPreDib`, `RCLootCouncilOptions` en mode DEV)
    passent par ce point d'entree : le contournement etait donc
    accessible par l'interface joueur et par l'Adventure Guide.
- Fix applique (2026-10-20, `src/modules/LootPipeline.lua`) :
  - La politique publique est desormais honoree sur **tous** les chemins.
    Quand `IsPublicEnabled()` vaut `false`, la fonction renvoie
    `nil, "PUBLIC_PRE_DIBS_DISABLED"` et n'ecrit aucun etat.
  - Le chemin de developpement (`context.isTest == true`) est inchange et
    reste isole du ledger de production.
  - La regle metier n'est pas modifiee : le correctif aligne le chemin de
    repli sur une politique deja etablie, deja documentee et deja testee.
- Tests : `tests/integration/rf0022_public_predibs_policy_spec.lua`, 4 cas.
  Le defaut est reproduit par la version d'origine (2 echecs sur 4) et
  absent apres correctif. La cause reinjectee fait de nouveau echouer 2
  verifications.
- Remaining: aucun.
- References/Dependencies:
  [PreDibs.lua](../../src/modules/PreDibs.lua),
  [EncounterJournal.lua](../../src/integrations/EncounterJournal.lua),
  [PlayerUI.lua](../../src/ui/PlayerUI.lua),
  [public_predibs_spec](../../tests/unit/public_predibs_spec.lua),
  [spec 002](../../specs/002-predibs-encounter-journal/spec.md).
- Proposed action: Conserver le test de non-regression. Verifier en
  validation Retail que la fermeture des Pre-Dibs publics par un Officier
  refuse bien la soumission depuis l'interface joueur et depuis
  l'Adventure Guide, sans creation d'etat.

<a id="rf-0023"></a>
## RF-0023 - validate_audit.py : le vocabulaire de statuts est plus etroit que la convention du code

- Status: FIXED
- Confidence: HIGH
- Risk: LOW
- Source: [Disputes.lua](../../src/modules/Disputes.lua) -
  `replayStoredOperation` (annotation `@AUDIT` portee par le code) ;
  l'outil concerne est
  [validate_audit.py](../../.github/skills/lua-code-audit/scripts/validate_audit.py)
  - `STATUS = 'KEEP|TO_REMOVE|NEED_UPDATE|COULD_MERGE|RENAME_CANDIDATE'`
- Evidence:
  - Le validateur n'accepte que cinq valeurs de statut pour une
    annotation `-- @AUDIT RF-XXXX status=...`. Le code applicatif utilise
    depuis longtemps deux valeurs de plus : `FIXED` et
    `PARTIALLY_FIXED`.
  - Etat avant la session 5 : 8 fiches deja couvertes par cette
    convention — RF-0008 (`FIXED`), RF-0012 (`FIXED`), RF-0013
    (`PARTIALLY_FIXED`), RF-0014 a RF-0018 (`FIXED`).
  - Mesure de la baseline (2026-10-20) : sur une copie de reference
    prealable a la session 5 (18 fiches, 9 annotations reconnues), le
    validateur echoue deja avec **18 erreurs**, dont 9 « Tag mal forme »
    et 9 « fiche INDEX.md sans annotation Lua associee ». Le defaut est
    donc **anterieur a la session 5** et n'est pas introduit par elle.
  - Etat apres la session 5 : 12 tags « mal formes » (10 anterieurs +
    RF-0019 et RF-0022, qui suivent la meme convention deja etablie) et
    12 fiches « sans annotation associee », pour la meme cause racine.
  - Les annotations des sessions precedentes sont bien formees : elles
    respectent exactement la structure attendue
    (`-- @AUDIT RF-XXXX status=<statut> doc=docs/code-audit/INDEX.md#rf-xxxx`
    en fin de ligne). Seul le vocabulaire du statut est refuse.
  - Le skill prevoit des statuts de refactorisation, pas des statuts de
    correction (`KEEP`, `TO_REMOVE`, ...). Le code a etendu le vocabulaire
    pour distinguer une fiche corrigee d'une fiche encore ouverte, ce qui
    est un besoin legitime et non une faute de forme.
- Rationale: Defaut de l'outil d'audit, pas du code applicatif. Aucun
  impact metier : les annotations sont informatives et le controle
  d'integrite reellement utile (`audit_guard.py verify`) reste operationnel
  et ne signale **aucun** fichier sous `libs` ni aucune violation de zone
  protegee.
- Fix applique (2026-10-20) :
  - Le vocabulaire autorise est etabli a partir des usages **reels** du
    depot, releves dans les trois sources de verite : les fiches
    `INDEX.md`, la colonne de statut du tableau de synthese, et les tags
    Lua `@AUDIT`. Les six valeurs employees sont `KEEP`, `TO_REMOVE`,
    `NEED_UPDATE`, `FIXED`, `PARTIALLY_FIXED` et `OPEN`. Les deux
    valeurs d'origine jamais employees (`COULD_MERGE`,
    `RENAME_CANDIDATE`) restent acceptees : elles sont documentees par la
    competence et peuvent legitimement apparaitre plus tard.
  - `STATUS` accepte donc les huit valeurs, et `STATUS_REQUIRING_TARGET`
    remplace le test code en dur pour que `COULD_MERGE` reste le seul
    statut exigeant `target=RF-XXXX`. **Toute autre valeur reste
    refusee** : le validateur n'est pas rendu permissif.
  - `SKILL.md` documente desormais `FIXED`, `PARTIALLY_FIXED` et `OPEN`
    avec leur semantique, afin que le vocabulaire de la competence et
    celui du code convergent.
- Tests : la validation est verifiee par ses propres cas.
  - Positif : les 20 tags Lua du depot sont reconnus, et les 23 fiches
    `INDEX.md` sont acceptees.
  - Negatif : un statut hors vocabulaire reste refuse, et une fiche sans
    annotation Lua reste signalee. La coherence entre le statut du tag Lua
    et celui de la fiche `INDEX.md` reste verifiee.
  - Resultat apres correctif : **0 erreur** (contre 24 avant, et 18 sur
    la baseline pre-session-5 mesuree sur une copie de reference).
- Remaining: aucun.
- References/Dependencies:
  [SKILL.md](../../.github/skills/lua-code-audit/SKILL.md),
  [tags-and-links.md](../../.github/skills/lua-code-audit/references/tags-and-links.md),
  [audit_guard.py](../../.github/skills/lua-code-audit/scripts/audit_guard.py),
  [INDEX.md](INDEX.md).
- Proposed action: Conserver les six statuts documentes. Ne pas
  modifier les annotations applicatives pour satisfaire le validateur :
  `FIXED` est la convention etablie du depot et distingue utilement une
  fiche corrigee d'une fiche ouverte.

<a id="rf-0026"></a>
## RF-0026 - Ledger : la reconstruction des projections diverge du chemin incremental et vide les soldes

- Status: FIXED
- Confidence: HIGH
- Risk: HIGH
- Source: [Ledger.lua](../../src/modules/Ledger.lua) -
  `Ledger.ClassifyCanonicalRecovery`, `Ledger.RebuildLedgerProjections`
- Evidence:
  - Trois defauts independants dans la meme zone, decouverts par
    comparaison directe entre le chemin incremental (`appendValidated` /
    `getCurrentBalance`) et le chemin de reconstruction (`applyRow`).
  - **Defaut 1 - verification du hash par mauvaise forme de commit.**
    `ClassifyCanonicalRecovery` verifiait **tous** les commits avec
    `canonicalOperationCommitHash`, qui est le hash d'un
    `LEDGER_OPERATION_COMMIT`. Un `AWARD_COMMIT` est hashe par
    `canonicalCommitHash`. Le chain canonique melange les deux formes,
    donc toute chaine contenant un commit d'attribution etait classee
    `CANONICAL_COMMIT_HASH_MISMATCH` et la reconstruction etait refusee.
    `verifyCanonicalCursor` dispatchait deja correctement sur
    `recordClass` : la verification de reprise ne lancait pas.
  - **Defaut 2 - allocation lue dans un champ inexistant.** `applyRow`
    faisait `memberState.allocation + (tonumber(transaction.allocation) or 0)`.
    Une transaction ne porte **pas** de champ `allocation`. L'allocation
    restait donc a 0 apres une reconstruction, alors que le chemin
    incremental ajoute `tx.amount` a l'allocation pour une
    `SEASON_ALLOCATION`.
  - **Defaut 3 - schema de forme different.** `applyRow` ecrivait
    `playerStates[seasonId].members[memberKey]`, alors que la forme
    canonique du module est `playerStates[seasonId][memberKey]`
    (`ensurePlayerState`, `getCurrentBalance`, `GetPlayerState`,
    `GetBalance`). Apres une reconstruction, **aucun lecteur ne trouvait
    plus l'etat d'un joueur**.
  - Consequence reproduite (2026-10-20) : sur un ledger V2 contenant une
    allocation de saison, `RebuildLedgerProjections` renvoyait
    `CANONICAL_COMMIT_HASH_MISMATCH` et le solde du joueur passait de 5 a
    0, avec un etat de joueur vide. Un rechargement ou une reprise pouvait
    donc **effacer un solde de Dibs**.
- Fix applique (2026-10-20, `src/modules/Ledger.lua`) :
  - La verification de reprise dispatche sur `recordClass`, comme
    `verifyCanonicalCursor` le fait deja.
  - `applyRow` applique exactement la semantique du chemin incremental :
    une `SEASON_ALLOCATION` alimente l'allocation et n'alimente pas le
    solde ; toute autre transaction alimente le solde.
  - `applyRow` ecrit la forme canonique `playerStates[seasonId][memberKey]`,
    et le tri final des transactions a ete aligne sur cette forme.
  - Aucun changement de regle metier : le calcul de solde, la chaine de
    hash et le format des enregistrements sont inchanges.
- Tests : `tests/integration/rf0026_projection_rebuild_allocation_spec.lua`,
  3 cas (allocation, octroi, reconstructions repetees). La suite existante
  `canonical_dispute_operation_spec.lua` couvre toujours la reconstruction
  de l'historique mixte.
- Remaining: aucun.
- References/Dependencies:
  [MultiLedger.lua](../../src/modules/MultiLedger.lua),
  [Governance.lua](../../src/modules/Governance.lua),
  [Disputes.lua](../../src/modules/Disputes.lua),
  [SyncV2.lua](../../src/modules/SyncV2.lua),
  [canonical_dispute_operation_spec](../../tests/integration/canonical_dispute_operation_spec.lua).
- Proposed action: Conserver les deux suites. Toute nouvelle forme de
  commit canonique doit etre ajoutee au dispatch par `recordClass` de la
  verification de reprise.

<a id="rf-0027"></a>
## RF-0027 - Ledger : le hachage canonique suppose un instantane d'identite present

- Status: FIXED
- Confidence: HIGH
- Risk: HIGH
- Source: [Ledger.lua](../../src/modules/Ledger.lua) - `canonicalSnapshot`,
  `canonicalContent`
- Evidence:
  - `canonicalSnapshot(snapshot)` lisait `snapshot.memberKey`,
    `snapshot.displayName` et `snapshot.guidWitness` sans verifier que
    `snapshot` existe. Une transaction migree depuis un schema ancien ne
    porte ni `identitySnapshot` ni `actorSnapshot`.
  - Consequence reproduite (2026-10-20) : le hachage d'une telle ligne
    levait `attempt to index a nil value (local 'snapshot')` a
    `src/modules/Ledger.lua:199`. L'erreur remontait jusqu'a
    `Dibs.Initialize` (via `ClassifyCanonicalRecovery`) et **interrompait
    le demarrage complet de l'addon** : une guilde ayant un ancien
    commit d'attribution ne pouvait plus demarrer.
  - Le defaut etait **anterieur a la session 7** : il se reproduisait
    avec et sans la correction RF-0026, et `migration_spec.lua` echouait
    dans les deux cas. RF-0026 l'a rendu visible en le faisantKIP
    atteindre le chemin de hachage d'un `AWARD_COMMIT`.
- Fix applique (2026-10-20, `src/modules/Ledger.lua`) :
  - Un instantane absent est projete comme une identite vide
    (`memberKey`, `displayName`, `guidWitness` a `nil`). Le hash reste
    calculable.
  - **Aucune identite n'est inventee** : l'enregistrement conserve
    exactement les champs qu'il portait, et le test verifie qu'aucun
    `identitySnapshot` n'est fabrique pour une ligne historique.
- Tests : `tests/integration/rf0027_legacy_identity_snapshot_spec.lua`,
  3 cas. La cause est verifiee comme discriminate : la reinjection de
  l'indexation directe fait echouer les 3 verifications.
- Remaining: aucun.
- References/Dependencies:
  [Core.lua](../../src/Core.lua),
  [migration_spec](../../tests/integration/migration_spec.lua),
  [Persistence.lua](../../src/modules/Persistence.lua).
- Proposed action: Conserver le test. Le chemin de hachage canonique ne
  doit jamais supposer la presence d'un instantane d'identite.

<a id="rf-0028"></a>
## RF-0028 - Le contournement de la politique publique des Pre-Dibs subsiste sur trois autres routes

- Status: FIXED
- Confidence: HIGH
- Risk: HIGH
- Source: [Core.lua](../../src/Core.lua) - `HandleSlashCommand`, action
  `pre` ; [EncounterJournal.lua](../../src/integrations/EncounterJournal.lua) -
  `SubmitPreDib` ; [PlayerUI.lua](../../src/ui/PlayerUI.lua) -
  `submitPublicPreDib`
- Evidence:
  - RF-0022 a corrige la **meme cause fondamentale** dans
    `LootPipeline` : une route qui se repliait sur `PreDibs.Create` quand
    la voie publique etait fermee. `PreDibs.Create` ne consulte pas
    `IsPublicEnabled`, donc une requete `pending` etait quand meme
    ecrite.
  - La meme cause existait sur **trois autres routes**, non couvertes par
    RF-0022 :
    - `Core.HandleSlashCommand("pre ...")` : meme repli.
    - `EncounterJournal.SubmitPreDib` : meme repli.
    - `PlayerUI.submitPublicPreDib` (repli local) : meme repli.
  - Consequence reproduite (2026-10-20) : avec
    `db.settings.allowPublicPreDibs = false`, la commande
    `/dibs pre 12345 TestItem` créait une requete `pending` (`0 -> 1`).
  - Cela contredit le **scenario 3 de l'User Story 1 de la spec 002** :
    « Given public Pre-Dibs are disabled, When a player submits a public
    request, Then the request is rejected with a clear reason and **no
    state is added** ».
- Fix applique (2026-10-20) :
  - `src/Core.lua` : la commande slash renvoie
    `PUBLIC_PRE_DIBS_DISABLED` et n'ecrit aucun etat.
  - `src/integrations/EncounterJournal.lua` : le repli est supprime ;
    `CreatePublic` refuse deja avec la bonne raison.
  - `src/ui/PlayerUI.lua` : le repli local est supprime.
  - `src/modules/LootPipeline.lua` : le chemin sans getter de politique
    echoue maintenant **ferme** au lieu d'ecrire via `PreDibs.Create`.
  - Aucune regle metier n'est modifiee : c'est le meme contrat public que
    RF-0022, applique a toutes les routes.
- Tests : `tests/integration/rf0028_public_predibs_routes_spec.lua`,
  5 cas qui couvrent **les quatre routes** plus le cas nominal ou la
  voie publique est ouverte. La cause est verifiee comme discriminate :
  la reinjection du repli dans `Core.lua` fait echouer le cas de la
  commande slash.
- Remaining: aucun. La regle « aucune route ne cree un Pre-Dib public
  pendant que la voie publique est fermee » est desormais verifiee en un
  seul endroit.
- References/Dependencies:
  [PreDibs.lua](../../src/modules/PreDibs.lua),
  [LootPipeline.lua](../../src/modules/LootPipeline.lua),
  [public_predibs_spec](../../tests/unit/public_predibs_spec.lua),
  [rf0022 spec](../../tests/integration/rf0022_public_predibs_policy_spec.lua),
  [spec 002](../../specs/002-predibs-encounter-journal/spec.md).
- Proposed action: Conserver les deux suites. Toute nouvelle route de
  creation de Pre-Dib doit passer par `CreatePublic` et ne doit jamais
  appeler `PreDibs.Create` en repli.
<a id="rf-0029"></a>
## RF-0029 - EncounterJournal : la route Adventure Guide contournait la politique publique

- Status: FIXED
- Confidence: HIGH
- Risk: HIGH
- Source: [EncounterJournal.lua](../../src/integrations/EncounterJournal.lua) -
  `Dibs.EncounterJournal.SubmitPreDib`
- Evidence: Meme cause fondamentale que RF-0022 et RF-0028. Quand la
  voie publique etait fermee, `SubmitPreDib` se repliait sur
  `PreDibs.Create`, qui ne consulte pas `IsPublicEnabled` et creeait donc
  une requete `pending`. Le repli est supprime : `CreatePublic` refuse
  deja avec `PUBLIC_PRE_DIBS_DISABLED`.
- Fix applique (2026-10-20, `src/integrations/EncounterJournal.lua`) :
  le repli `PreDibs.Create` est supprime. Aucune regle metier n'est
  modifiee.
- Tests : `tests/integration/rf0028_public_predibs_routes_spec.lua`, cas
  « refuses the Adventure Guide route and writes no request ».
- Remaining: aucun.
- References/Dependencies:
  [PreDibs.lua](../../src/modules/PreDibs.lua),
  [spec 002](../../specs/002-predibs-encounter-journal/spec.md).
- Proposed action: Conserver le cas de test.

<a id="rf-0030"></a>
## RF-0030 - PlayerUI : le repli local contournait la politique publique

- Status: FIXED
- Confidence: HIGH
- Risk: HIGH
- Source: [PlayerUI.lua](../../src/ui/PlayerUI.lua) -
  `submitPublicPreDib`
- Evidence: Meme cause fondamentale que RF-0022 et RF-0028. Le repli
  local de `submitPublicPreDib` appelait `PreDibs.Create` quand la voie
  publique etait fermee, sans consulter `IsPublicEnabled`, et donc
  creait une requete `pending`.
- Fix applique (2026-10-20, `src/ui/PlayerUI.lua`) : le repli est
  supprime et la route echoue avec la meme raison que les autres.
  Aucune regle metier n'est modifiee.
- Tests : `tests/integration/rf0028_public_predibs_routes_spec.lua`, cas
  « refuses the Player UI route and writes no request ».
- Remaining: aucun.
- References/Dependencies:
  [PreDibs.lua](../../src/modules/PreDibs.lua),
  [spec 002](../../specs/002-predibs-encounter-journal/spec.md).
- Proposed action: Conserver le cas de test.

<a id="rf-0031"></a>
## RF-0031 - Ledger : une proposition terminale conservait sa reservation de Dib

- Status: FIXED
- Confidence: HIGH
- Risk: HIGH
- Source: [Ledger.lua](../../src/modules/Ledger.lua) -
  `Ledger.GetPendingDibReservations`
- Evidence:
  - Un award passe par une proposition de gouvernance. La proposition porte
    un statut qui evolue : `PENDING_RECONCILIATION` (ouverte),
    `COMMITTED` (reussie), puis `STALE` ou `REJECTED` (issues terminales).
  - `Governance.MarkAwardProposalCommitted` liberait deja la reservation
    au moment du commit, mais `Governance.ResolveAwardProposal` (chemin
    `STALE` / `REJECTED`) ne le faisait pas.
  - `Ledger.GetPendingDibReservations` comptait toute proposition dont le
    statut n'etait pas `COMMITTED`, donc **aussi** les issues terminales.
    Comme
    `GetAvailableBalance = max(0, GetBalance - GetPendingDibReservations)`,
    un award refuse ou devenu obsolete laissait une **reservation
    fantome** qui reduisait definitivement le solde disponible, sans
    mouvement comptable pour l'expliquer.
  - `SyncV2.BuildAwardReservationDigest` propageait la meme erreur : une
    proposition terminale etait diffusee comme `PENDING` a tous les pairs,
    ce qui **propageait** la reservation fantome dans toute la guilde.
    `SyncV2.GetSynchronizationStatus` comptait egalement ces propositions
    terminales dans `pendingAwardProposals`, affichant une file
    d'attente jamais vide.
  - Cause reproduite (2026-10-21) : une proposition `REJECTED` pour un
    joueur de solde 5 laissait `GetPendingDibReservations = 5` et
    `GetAvailableBalance = 0`, alors que la transaction n'a jamais existe.
- Fix applique (2026-10-21) :
  - `Ledger.GetPendingDibReservations` n'exclut plus que les statuts
    reellement terminaux (`COMMITTED`, `STALE`, `REJECTED`) via
    `holdsReservation`.
  - `Governance.ResolveAwardProposal` appelle
    `Dibs.Sync.ClearAwardReservation(proposalId, nil)`, exactement comme
    le chemin `COMMITTED` : la reservation est tombee et la generation de
    reservation du joueur est invalidee.
  - `SyncV2.BuildAwardReservationDigest` ne diffuse plus une proposition
    terminale comme `PENDING`.
  - `SyncV2.GetSynchronizationStatus` ne compte plus une proposition
    terminale dans `pendingAwardProposals`.
  - **Aucune regle metier modifiee** : le solde, la chaine canonique et
    l'historique des transactions sont inchanges. Seule la reservation
    fantome disparaait.
- Tests : `tests/integration/rf0031_dib_reservation_release_spec.lua`,
  7 cas (refus, `STALE`, solde inchange, reservation maintenue tant que la
  proposition est ouverte, liberation unique, absence de diffusion
  `PENDING`, absence de comptage dans le statut de synchronisation).
- Remaining: aucun.
- References/Dependencies:
  [Governance.lua](../../src/modules/Governance.lua),
  [SyncV2.lua](../../src/modules/SyncV2.lua),
  [Governance spec](../../specs/007-governance-ledger/spec.md).
- Proposed action: Conserver les cas de test. Toute evolution du
  vocabulaire de statut d'une proposition doit reexaminer
  `holdsReservation` et le digest de reservation, sous peine de recreer
  une reservation fantome.

<a id="rf-0032"></a>
## RF-0032 - MultiLedger : les protections canoniques s'appliquent aux Secondary Ledgers

- Status: KEEP
- Confidence: HIGH
- Risk: HIGH
- Source: [MultiLedger.lua](../../src/modules/MultiLedger.lua) -
  `MultiLedger.SetActiveLedger`
- Evidence:
  - L'hypothese de la session 7 etait : le verrou `v2Enforced` pourrait
    etre **par ledger**, laissant un Secondary Ledger hors du chemin
    canonique. **L'hypothese est refutee.** `Governance.IsV2Enforced()`
    est un etat **de guilde**, pas de ledger : un Secondary Ledger suit
    exactement le meme chemin canonique que le Primary Ledger.
  - Chemins verifies sur le code applicatif reel :
    - `Ledger.CommitDibUse` teste `isApprovedLedger(ledgerId)` puis
      `v2Enforced()`, dans cet ordre : un Secondary Ledger approuve passe
      par la branche canonique et rend `CANONICAL_COMMITTED`.
    - `Ledger.localCoordinator` refuse un emetteur non coordinateur avec
      `LOCAL_COORDINATOR_REQUIRED`, y compris sur un Secondary Ledger.
    - `Ledger.ApplyAwardCommit` compare `declaredLedgerId` a la ledger
      cible et refuse un commit destine a une autre ledger avec
      `LEDGER_SCOPE_MISMATCH`.
    - `MultiLedger.isLocallyApproved` refuse une ledger archivee ou non
      approuvee ; `MultiLedger.SetActiveLedger` refuse
      `GUILD_ACTIVE_LEDGER_IMPOSED` quand la guilde impose une autre
      ledger ; `MultiLedger.SetViewLedger` est une consultation en lecture
      seule et ne change jamais la cible comptable.
    - `MultiLedger.ProposeLedger` exige `ledger.propose`, donc un membre
      sans autorite est refuse avec `GUILD_ADMIN_REQUIRED`.
  - Les soldes des deux ledgers restent separes : `GetBalance` prend le
    `ledgerId` en compte, et une operation sur un Secondary Ledger ne
    modifie pas le solde du Primary Ledger.
  - Aucune deviation constatee : la Hypothese ne justifie donc **aucune**
    correction de code.
- Rationale: Le verrou de conformite est bien de niveau guilde, ce qui est
  le comportement attendu. Les protections sont donc communes, et un
  Secondary Ledger n'ouvre pas de second chemin d'ecriture contournant la
  chaine canonique.
- Tests : `tests/integration/rf0032_secondary_ledger_protection_spec.lua`,
  8 cas qui **verrouillent** le comportement observe (chemin canonique,
  ledger non approuvee, ledger archivee, emetteur non coordinateur,
  commit destine a une autre ledger, separation des soldes, ledger de
  consultation, membre sans autorite).
- Remaining: aucun.
- References/Dependencies:
  [Ledger.lua](../../src/modules/Ledger.lua),
  [Governance.lua](../../src/modules/Governance.lua),
  [MultiLedger spec](../../specs/010-multi-ledger/spec.md).
- Proposed action: Conserver. Si le verrou `v2Enforced` devenait
  par ledger, ce serait un changement de contrat a traiter dans une
  feature dediee, pas une correction d'audit.

<a id="rf-0033"></a>
## RF-0033 - ImportExport : un import complet annulait un ledger local plus recent

- Status: FIXED
- Confidence: HIGH
- Risk: HIGH
- Source: [ImportExport.lua](../../src/modules/ImportExport.lua) -
  `ImportExport.Apply`
- Evidence:
  - L'import de portee `full` fusionne d'abord les transactions du paquet
    dans la table vivante `db.ledger` (`targetLedger`), puis executesait
    ensuite, dans la meme fonction :
    `for key, value in pairs(package.payload) do db[key] = clone(value) end`.
  - Cette boucle **remplacait** `db.ledgers` par le clone exporte. La
    table vivante `db.ledger` (que le code vient de modifier) et
    `db.ledgers[active]` (le clone) devenaient **deux tables
    divergentes**.
  - Consequence reproduite (2026-10-21) : un joueur dont le solde etait
    passe de 5 a 16 par une allocation **posterieure a l'export** se
    retrouvait a 11 apres import, sans qu'aucune transaction ne soit
    supprimee : le solde etait recalcule a partir de la mauvaise table.
    C'est une **annulation silencieuse** d'une donnee comptable plus
    recente, contraire a la spec 007 FR-011.
  - Effet secondaire : les transactions locales absentes du paquet
    disparaissaient de `db.ledgers[active]` alors qu'elles subsistaient
    dans `db.ledger`, produisant deux etats de joueur incoherents entre
    la table lue et la table ecrite.
  - Le meme remplacementolesale ecraseait aussi `db.ledger` lui-meme par
    un clone, ce qui cassait l'identite de table attendue par
    `MultiLedger.activateLedger` et par leslecteurs de l'etat vivant.
- Fix applique (2026-10-21, `src/modules/ImportExport.lua`) :
  - La boucle de remplacement exclut desormais `ledger`, `preDibs` et
    `ledgers`.
  - La fusion se fait **par ledger** : `db.ledgers[ledgerId]` est fusionne
    avec le contenu vivant, les transactions locales absentes du paquet
    sont conservees, les `playerStates` locaux sont conserves et
    l'allocation retenue est la plus elevee des deux etats.
  - `db.ledger = db.ledgers[db.activeLedgerId or "guild-primary"]` est
    reetabli pour garantir que la table vivante et la table de la carte
    designent **le meme objet**.
  - Le refus `CANONICAL_LEDGER_IMPORT_UNAVAILABLE` (design B03) et le
    refus `OPERATION_ID_CONFLICT` sont inchanges : une transaction
    canonique locale ne peut toujours pas etre importee comme un second
    chemin d'ecriture durable.
- Tests : `tests/integration/rf0033_full_import_ledger_rollback_spec.lua`,
  4 cas (allocation posterieure a l'export conservee, identite de table
  `db.ledger` / `db.ledgers[active]`, transactions locales conservees,
  refus d'import d'une transaction canonique).
- Remaining: aucun.
- References/Dependencies:
  [MultiLedger.lua](../../src/modules/MultiLedger.lua),
  [Backup.lua](../../src/modules/Backup.lua),
  [spec 007](../../specs/007-governance-ledger/spec.md).
- Proposed action: Conserver les cas de test. Un import ne doit jamais
  remplacer wholesale une table de ledger vivante ; la fusion doit rester
  par ledger et par etat de joueur.

<a id="rf-0034"></a>
## RF-0034 - SyncV2 : une reservation diffusee n'est jamais liberee chez les pairs

- Status: FIXED
- Confidence: HIGH
- Risk: HIGH
- Source: [SyncV2.lua](../../src/modules/SyncV2.lua) -
  `Sync.ClearAwardReservation`
- Evidence:
  - Meme cause racine que RF-0031, mais sur le **chemin pair** et non sur
    le chemin local du coordinateur.
  - `specs/017-guild-sync-reliability/spec.md` FR-011 impose de retirer
    la reservation « when the matching canonical commit is applied ».
  - Le coordinateur annonce un `AWARD_RESERVATION_DIGEST` a la guilde
    quand une proposition est enregistree. Le pair stocke l'entree dans
    `state.awardReservations` et la compte dans
    `Ledger.GetPendingDibReservations`, ce qui reduit le **solde
    disponible** du joueur.
  - Le pair ne retirait l'entree que si le **commit canonique** arrivait
    (`reservationHasCanonicalCommit`). Or une proposition peut se terminer
    **sans** commit canonique : `Governance.ResolveAwardProposal` conclut
    l'essai en `STALE` ou `REJECTED` sans aucune transaction.
  - Le digest est une liste de **remplacement** des reservations en cours,
    pas un delta. Le coordinateur, une fois la proposition terminale, ne
    la diffuse plus : le pair ne peut donc **pas deduire** du digest
    suivant que l'entree doit disparaitre.
  - Aucun tombeau `RELEASED` n'etait diffuse : le tombeau n'etait ecrit que
    localement par `Sync.ClearAwardReservation`.
  - Consequence reproduite (2026-10-21, clients distincts avec leurs
    propres SavedVariables) : apres un refus du coordinateur, le
    coordinateur était a 0 reservation pendante mais le pair **restait a 1
    reservation fantome**, ce qui reduisait definitivement le solde
    disponible du joueur chez tous les clients non-coordinateur, sans
    mouvement comptable pour l'expliquer.
- Fix applique (2026-10-21) :
  - `Sync.AnnounceAwardReservationRelease` diffuse un message
    `AWARD_RESERVATION_RELEASE` (canal `GUILD`) portant un tombeau
    `RELEASED`. Seule l'autorite courante annonce : un pair n'est pas
    l'autorite de la reservation et ne MUST NOT pas rediffuser.
  - `Sync.ClearAwardReservation` appelle cette annonce apres avoir ecrit
    le tombeau local.
  - `Governance.ResolveAwardProposal` construit le tombeau a partir de la
    proposition elle-meme (le chemin terminal n'a pas de commit canonique
    dont le derive le `memberKey` du joueur) ; sans cela la liberation
    locale echouait aussi.
  - La reception valide l'expediteur (GM ou Officier), resout le joueur
    contre le roster local, refuse une liberation d'un membre inconnu, et
    refuse un tombeau plus ancien que celui deja connu.
  - **Aucune regle metier modifiee** : le solde, la chaine canonique et
    l'historique des transactions sont inchanges. Seule la reservation
    fantome du pair disparaait.
- Rationale: Le digest `AWARD_RESERVATION_DIGEST` est, par construction,
  une liste de remplacement des reservations en cours. Il ne peut donc
  pas transporter une liberation : un pair qui ne recoit pas de
  message dedie ne peut pas distinguer « reservation levee » de
  « reservation jamais annoncee ». Une liberation explicite est le
  seul moyen de faire converger les clients, et elle doit venir de
  l'autorite de la reservation, pas d'un pair.
- Tests : `tests/integration/rf0034_peer_reservation_release_spec.lua`,
  5 cas sur deux clients distincts possedant leurs propres
  SavedVariables (reservation recue comptee, liberation au refus,
  liberation au `STALE`, reservation encore ouverte conservee, digest
  tardif ne ressuscitant pas une reservation liberee).
  Discrimination verifiee par reinjection : la désactivation de
  l'annonce fait echouer les 2 cas de liberation ; la désactivation de
  l'ecriture du tombeau cote pair fait echouer le cas de reordonnancement.
- Remaining: aucun.
- References/Dependencies:
  [Governance.lua](../../src/modules/Governance.lua),
  [Ledger.lua](../../src/modules/Ledger.lua),
  [spec 017](../../specs/017-guild-sync-reliability/spec.md).
- Proposed action: Conserver les cas de test. Une reservation terminee
  sans commit canonique doit toujours etre annoncee explicitement : le
  digest seul ne peut pas la transporter.

<a id="rf-0035"></a>
## RF-0035 - SyncV2 : le transfert de coordinateur ne converge jamais chez les pairs

- Status: FIXED
- Confidence: HIGH
- Risk: HIGH
- Source: [SyncV2.lua](../../src/modules/SyncV2.lua) -
  `Sync.Receive`, `requestLedgerBatch`, `clearResolvedLedgerGap`
- Evidence:
  - Meme cause fonctionnelle que l'audit de la session precedente, mais
    sur le **chemin de transfert de coordinateur** et non sur le chemin
    local. Le chemin local etait correct ; c'est la **convergence entre
    clients** qui etait rompue.
  - Trois causes distinctes, chacune reproduite sur deux clients
    independants possedant leurs propres SavedVariables :
  - **Cause 1 - la requete de detail de gouvernance ne nomme pas la
    revision deja posee.** Le pair qui detecte un ecart de gouvernance
    demande le registre manquant sans indiquer la revision qu'il
    possede deja. Le repondeur redemarre alors la chaine a la revision 1 et
    renvoie **tous** les registres, y compris ceux que le pair a deja
    appliques. Ces registres plus anciens sont refuses avec
    `GOVERNANCE_PARENT_MISMATCH`, et le registre manquant n'est
    **jamais atteint**. Le pair conserve donc l'ancienne autorite,
    l'ancienne epoch et l'ancien coordinateur.
  - **Cause 2 - la fermeture de predecessor n'est jamais annoncee.**
    `Governance.BeginHandoff` passe l'autorite en `HANDOFF_CLOSING` mais
    n'emet **rien**. La fermeture n'atteint les pairs que si un battement
    de cycle de vie survient *entre* la fermeture et l'adoption du
    successeur. Si le GM adopte immediatement, le signal
    `HANDOFF_CLOSING` n'est **jamais** emis, le pair ne peut jamais
    satisfaire `HANDOFF_CLOSURE_REQUIRED`, et la transfert echoue
    silencieusement. Le resultat dependait donc du **timing**.
  - **Cause 3 - un verrou mortel.** `Governance.authorityContent`
    refusait toute adoption d'autorite tant que `IsSyncBehind()` etait
    vrai. Or le pair applique le registre de gouvernance **precisement
    parce qu'il est en retard** : il a detecte l'ecart, s'est marque
    « behind », puis s'est refuse le registre qui resout l'ecart. Le
    pair ne pouvait donc jamais converger, quel que soit le moment.
  - Consequence reproduite (2026-10-21) : apres un transfert de
    coordinateur, le pair restait en epoch 7 avec l'ancien coordinateur
    alors que le coordinateur etait en epoch 8. Les transactions de
    l'epoch fermee appliquees par le pair etaient refusees a tort, et le
    pair ne pouvait jamais adopter la nouvelle autorite.
- Fix applique (2026-10-21) :
  - La requete de detail de gouvernance nomme la revision que le
    recepteur possede deja (`parentRevision`), et le repondeur n'envoie
    que les registres manquants. Le recepteur qui ne le nomme pas
    recoit une reponse utilisable : le repondeur s'arrete au premier
    registre manquant au lieu de renvoyer des registres refuses.
  - `Sync.AnnounceAuthorityHandoff` annonce la fermeture de predecessor
    des `Governance.BeginHandoff`, sans attendre un battement de cycle de
    vie. Seule l'autorite courante annonce ; un pair n'est pas
    l'autorite de la fermeture.
  - `Sync.IsSyncBehindExceptGovernance` distingue le retard **du
    registre de gouvernance en cours d'adoption** d'un vrai retard. Le
    verrou d'adoption n'exclut plus le motif `GOVERNANCE_PARENT_MISSING`
    ni `AUTHORITY_DETAIL_MISSING`, qui sont resolus par le registre
    lui-meme. Un ecart de ledger, une politique manquante, un catalogue
    de saisons manquant, un detail de coffre manquant ou un detail de
    demande manquant **continuent de bloquer** l'adoption.
  - **Aucune regle metier modifiee** : le calcul de solde, la chaine
    canonique, les sequences, le verrou de hash et l'historique des
    transactions sont inchanges. Seule la **convergence entre clients**
    etait rompue.
  - Le contrat de fermeture reste intact : un pair dont la chaine
    fermee est incomplete (la sequence de fermeture ne correspond pas a
    sa position) refuse toujours d'adopter l'epoch du successeur, avec
    `HANDOFF_SEQUENCE_MISMATCH`.
- Rationale: Le chemin local du coordinateur etait deja correct, ce qui
  masquait la divergence. Les trois causes portent sur le **transport**
  et sur le **verrou** d'adoption, pas sur la regle metier du transfert.
- Tests : `tests/integration/rf0035_canonical_gap_recovery_spec.lua`
  (8 cas) et `tests/integration/rf0035_coordinator_handoff_spec.lua`
  (12 cas), sur deux clients independants possedant leurs propres
  SavedVariables, leur propre ledger, leur propre etat SyncV2 et leur
  propre etat Governance.
  Discrimination verifiee par reinjection, une cause a la fois :
  l'absence de `parentRevision` fait echouer 5 cas, l'absence
  d'annonce de fermeture 5 cas, le verrou mortel 3 cas.
- Remaining: aucun.
- References/Dependencies:
  [Governance.lua](../../src/modules/Governance.lua),
  [Ledger.lua](../../src/modules/Ledger.lua),
  [spec 017](../../specs/017-guild-sync-reliability/spec.md).
- Proposed action: Conserver les cas de test. Un registre de gouvernance
  doit nommer la revision posee par le recepteur, la fermeture de
  predecessor doit etre annoncee a l'instant ou elle est decidee, et le
  verrou d'adoption ne doit pas refuser le registre qui resout l'ecart
  qu'il a lui-meme detecte.

<a id="rf-0036"></a>
## RF-0036 - SyncV2 : une reservation liberee ne ressuscite pas apres reconnexion

- Status: KEEP
- Confidence: HIGH
- Risk: HIGH
- Source: [SyncV2.lua](../../src/modules/SyncV2.lua) -
  `Sync.ApplyAwardReservationRelease`
- Evidence:
  - Verification du **scenario critique** de la liberation distribuee
    (RF-0034) : une reservation est creee, le client B se deconnecte, la
    reservation est liberee, une autre reservation est creee, le client B
    se reconnecte.
  - Le mecanisme de RF-0034 est **correct** sur ce scenario :
    - le pair conserve le **tombeau** `RELEASED` de la reservation
      liberee ;
    - un **digest tardif** qui porte encore la proposition **ne la
      ressuscite pas** : le tombeau est plus recent que l'enregistrement,
      donc l'entree est ignoree ;
    - la **nouvelle** reservation est conservee ;
    - les **soldes comptables** convergent (une reservation ne touche
      jamais le solde) ;
    - un pair **ne rediffuse pas** une liberation qu'il a recue : seule
      l'autorite courante annonce, un pair n'est pas l'autorite de la
      reservation.
  - Aucun defaut confirme sur ce chemin : les quatre comportements sont
  - verifies par test et **aucune correction de production n'a ete
  necessaire**. La suite verrouille le comportement observe.
- Rationale: Le chemin de liberation distribuee ne doit pas etre modifie
  sans preuve d'un nouveau defaut. La suite RF-0034 et RF-0036 le
  verrouille des deux cotes du protocole (annonceur et recepteur).
- Tests : `tests/integration/rf0036_reservation_reconnection_spec.lua`,
  4 cas sur deux clients independants (reservation liberee non ressuscitee,
  digest tardif sans effet, liberation annoncee recue par le pair, pair
  qui ne rediffuse pas).
- Remaining: aucun.
- References/Dependencies:
  [SyncV2.lua](../../src/modules/SyncV2.lua),
  [Governance.lua](../../src/modules/Governance.lua),
  [spec 017](../../specs/017-guild-sync-reliability/spec.md).
- Proposed action: Conserver les cas de test. Toute evolution du
  protocole de reservation doit conserver la separation entre le
  contenu du digest (liste de remplacement) et le tombstone de liberation
  (evenement explicite).

<a id="rf-0037"></a>
## RF-0037 - SyncV2 : le rattrapage d'un Secondary Ledger est verifie

- Status: KEEP
- Confidence: HIGH
- Risk: HIGH
- Source: [SyncV2.lua](../../src/modules/SyncV2.lua) -
  `requestLedgerBatch`, `clearResolvedLedgerGap`
- Evidence:
  - Verification du rattrapage d'un **Secondary Ledger**, demandee par le
    brief de la session.
  - Scenarios verifies sur deux clients independants :
    - un Secondary Ledger approuve **se replique** chez les pairs
      (statut `APPROVED`, chaine canonique presente) ;
    - apres une **deconnexion** pendant deux commits, le pair **rattrape**
      la chaine du Secondary Ledger a la reconnexion (meme `nextSeq`,
      meme `rootHash`, meme solde) ;
    - les soldes du Primary et du Secondary Ledger **restent separes** :
      une operation sur le Secondary Ledger ne modifie pas le solde du
      Primary ;
    - un commit du Secondary Ledger applique au Primary Ledger est
      refuse avec `LEDGER_SCOPE_MISMATCH` ;
    - un Secondary Ledger **non approuve** refuse tout commit avec
      `LEDGER_NOT_APPROVED`.
  - Aucun defaut confirme : le chemin est sain, aucune correction de
  - production n'a ete necessaire. La suite verrouille le comportement.
- Rationale: Le rattrapage d'une ledger secondaire passe par le meme
  `requestLedgerBatch` que la ledger principale, mais avec un `ledgerId`
  different dans la requete. Le verrouiller par test empeche qu'un
  changement futur ne fasse cibler la mauvaise ledger.
- Tests : `tests/integration/rf0037_secondary_ledger_catchup_spec.lua`,
  5 cas sur deux clients independants.
- Remaining: aucun.
- References/Dependencies:
  [MultiLedger.lua](../../src/modules/MultiLedger.lua),
  [Ledger.lua](../../src/modules/Ledger.lua),
  [spec 010](../../specs/010-multi-ledger/spec.md).
- Proposed action: Conserver les cas de test.

<a id="rf-0038"></a>
## RF-0038 - Ledger : un snapshot canonique corrompu est accepte comme valide

- Status: FIXED
- Confidence: HIGH
- Risk: HIGH
- Source: [Ledger.lua](../../src/modules/Ledger.lua) -
  `Ledger.ClassifyCanonicalRecovery`
- Evidence:
  - Le brief demande qu'un **snapshot incorrect ne puisse pas ecraser un
    historique comptable local valide**, et qu'une reception invalide
    echoue **sans mutation comptable**.
  - Deux ecarts entre le **chemin d'ecriture** et le **chemin de
    reconstruction** :
  - **Ecart 1 - une chaine vide n'etait jamais verifiee.** Le controle
    du `rootHash` compare le hash du dernier commit au `rootHash`
    enregistre. Sur une chaine **vide** il n'y a aucun commit : le
    controle n'est donc **jamais** execute, et le `rootHash` pouvait
    etre remplace par une valeur arbitraire sans que la chaine soit
    signalee. Or la racine d'une chaine vide est, par contrat, le
    **baseline d'autorite** : c'est la seule preuve que la chaine
    descend du baseline approuve. `verifyCanonicalCursor` (le chemin
    d'ecriture) appliquait deja ce contrat ; le chemin de reconstruction
    ne l'appliquait pas, et les deux chemins **donnaient des verites
    differentes** sur le meme etat.
    Consequence reproduite (2026-10-21) : une chaine vide dont le
    `rootHash` ne vaut pas le baseline d'autorite etait classee
    `VALID`, et `RebuildLedgerProjections` **reconstruisait** les
    projections a partir de cet etat corrompu.
  - **Ecart 2 - un commit au-dela de la sequence suivante n'etait pas
    detecte.** `verifyCanonicalCursor` refuse un commit de l'epoch
    courante dont la sequence est `>= nextSeq` (`LEDGER_GAP`), et
    refuse un commit d'une **epoch future** (`STALE_EPOCH`).
    `ClassifyCanonicalRecovery` ne refusait ni l'un ni l'autre : une
    chaine portant une position que l'epoch active ne possede pas
    pouvait etre classee `VALID` et reconstruite.
  - Le refus est **sans mutation comptable** : ni le solde, ni la
    sequence, ni le `rootHash` ne bougent quand la reconstruction est
    refusee.
- Fix applique (2026-10-21, `src/modules/Ledger.lua`) :
  - `ClassifyCanonicalRecovery` verifie desormais la racine d'une chaine
    vide contre le **baseline d'autorite** et classe `WRONG_ROOT` /
    `CANONICAL_ROOT_MISMATCH` si elle ne correspond pas.
  - `ClassifyCanonicalRecovery` refuse un commit de l'epoch courante dont
    la sequence est `>= nextSeq` (`CANONICAL_SEQUENCE_GAP`) et un commit
    d'une **epoch future** (`STALE_EPOCH`), exactement comme le chemin
    d'ecriture.
  - **Aucune regle metier modifiee** : le calcul de solde, la chaine
    canonique et l'historique des transactions sont inchanges. Seule la
    **detection** d'un etat corrompu etait absente.
  - Les deux chemins — reconstruction et ecriture — donnent maintenant la
    meme verite sur le meme etat.
- Rationale: Le chemin de reconstruction est la voie de reprise apres
  interruption. Il doit etre aussi strict que le chemin d'ecriture :
  un etat qu'ecriture refuserait ne doit pas pouvoir etre reconstruit.
- Tests : `tests/integration/rf0038_canonical_snapshot_spec.lua`,
  10 cas (chaine valide, chaine vide au baseline, chaine vide de racine
  etrangere refusee, historique local preserve apres refus, sequence
  manquante refusee, `rootHash` errone refuse, commit d'epoch future
  refuse, snapshot d'un Secondary Ledger separe, ledger inconnue refusee,
  import canonique refuse comme second chemin d'ecriture).
  Discrimination verifiee par reinjection : la verification de la racine
  d'une chaine vide absente fait echouer 2 cas, le controle de sequence
  absent fait echouer 1 cas.
- Remaining: aucun.
- References/Dependencies:
  [ImportExport.lua](../../src/modules/ImportExport.lua),
  [HistoricalBaseline.lua](../../src/modules/HistoricalBaseline.lua),
  [spec 026](../../specs/026-canonical-idempotent-corrections/spec.md).
- Proposed action: Conserver les cas de test. Le chemin de reconstruction
  et le chemin d'ecriture doivent appliquer le meme contrat sur la racine
  d'une chaine vide et sur les positions hors sequence.

<a id="rf-0039"></a>
## RF-0039 - Ledger : la reconstruction apres interruption est verifiee

- Status: KEEP
- Confidence: HIGH
- Risk: HIGH
- Source: [Ledger.lua](../../src/modules/Ledger.lua) -
  `Ledger.RebuildLedgerProjections`
- Evidence:
  - Verification du chemin de **reconstruction apres interruption**,
    demandee par le brief de la session.
  - Scenarios verifies :
    - une chaine valide se reconstruit vers les **memes lignes, soldes,
      allocations, references de transactions, sequence et `rootHash`** ;
    - une reconstruction **repetee** produit des **identifiants
      identiques** et le meme solde, le meme allocation et le meme
      `rootHash` ;
    - une **ligne d'attribution** absente parce que l'execution
      interrompue ne l'a pas ecrite est **restauree** a partir du commit
      lui-meme : la ligne d'un `AWARD_COMMIT` est derivee du commit, donc
      elle n'est pas perdue ;
    - une **ligne historique locale** qu'aucun commit canonique ne
      possede est **conservee** et comptee une fois comme historique
      legacy.
  - Le contrat `INCOMPLETE_PROJECTION` s'applique aux
    `LEDGER_OPERATION_COMMIT`, dont les lignes sont derivees des
    **signedEntries** du commit et non du commit lui-meme : la
    verification qu'une ligne existe est faite dans
    `ClassifyCanonicalRecovery` (`CANONICAL_PROJECTION_INCOMPLETE`).
  - Aucun defaut confirme : aucune correction de production n'a ete
  - necessaire. La suite verrouille le comportement observe.
- Rationale: Le chemin de reconstruction est la voie de reprise apres
  interruption. Le verifier sur un historique reel (allocation +
  consommation) plutot que sur une chaine vide est ce qui rend la
  preuve utile : c'est le cas ou une divergence de solde apparaitrait.
- Tests : `tests/integration/rf0039_projection_rebuild_interruption_spec.lua`,
  4 cas sur un client a autorite V2 active.
- Remaining: aucun.
- References/Dependencies:
  [Ledger.lua](../../src/modules/Ledger.lua),
  [spec 026](../../specs/026-canonical-idempotent-corrections/spec.md).
- Proposed action: Conserver les cas de test.

<a id="rf-0040"></a>
## RF-0040 - ImportExport : l'importation complete est verrouillee

- Status: KEEP
- Confidence: HIGH
- Risk: HIGH
- Source: [ImportExport.lua](../../src/modules/ImportExport.lua) -
  `ImportExport.Preview`, `ImportExport.Apply`
- Evidence:
  - Verification des **25 scenarios d'importation** (A01 a A25) du brief,
    sur des environnements a SavedVariables distincts.
  - L'invariant central est **respecte** : une importation invalide ne
    modifie aucune donnee comptable. Le refus
    `CANONICAL_LEDGER_IMPORT_UNAVAILABLE` reste en place et verifie
    (A19).
  - Scenarios verifies : import valide, meme fichier importe deux fois,
    ledger different, autre guilde, contexte de guilde absent,
    `ledgerId` incorrect, transactions dupliquees, commits contradictoires,
    `rootHash` invalide, sequence incoherent, epoch incompatible,
    identites absentes, references invalides, paquet incomplet, paquet
    corrompu, ledger local plus recent, transactions recentes absentes du
    paquet, transactions anciennes deja presentes, operations
    canoniques, donnees legacy, Secondary Ledger, ledger archive, ledger
    non approuve, utilisateur non autorise, et changement d'etat local
    entre le preview et l apply.
  - Deux **hypotheses** de la session ont ete **refutees** par la
    reproduction :
    1. « Une importation complete echoue toujours » : **faux**. Le
       contrat B03 refuse une ligne `LOCAL_CANONICAL` que la cible ne
       possede pas deja, ce qui est le comportement voulu ; une cible
       qui possede deja les lignes les importe sans duplication.
    2. « La garde peut distinguer une ligne bootstrap d'une operation
       canonique » : **hors contrat**. `CANONICAL_LEDGER_IMPORT_UNAVAILABLE`
       est le contrat verrouille par RF-0033, et il porte sur **toute**
       ligne `LOCAL_CANONICAL`. Une modification qui l'assouplirait
       aurait casse le test RF-0033 ; elle a donc ete **abandonnee** et
       le code de production restaure a l'identique.
  - Aucun defaut confirme : **aucune correction de production**.
- Rationale: Le chemin d'importation est couvert par 26 cas qui
  verrouillent le contrat B03, la separation des ports, la rejection des
  paquets invalides et la protection du ledger local plus recent.
- Tests : `tests/integration/rf0040_import_export_hardening_spec.lua`,
  26 cas.
- Remaining: aucun.
- References/Dependencies:
  [Backup.lua](../../src/modules/Backup.lua),
  [Ledger.lua](../../src/modules/Ledger.lua),
  [spec 026](../../specs/026-canonical-idempotent-corrections/spec.md).
- Proposed action: Conserver les cas de test. Ne pas assouplir
  `CANONICAL_LEDGER_IMPORT_UNAVAILABLE` sans decision metier explicite.

<a id="rf-0041"></a>
## RF-0041 - Backup : une restauration ne validait pas l'instantane

- Status: FIXED
- Confidence: HIGH
- Risk: HIGH
- Source: [Backup.lua](../../src/modules/Backup.lua) -
  `Backup.Restore`, `Backup.PreviewRestore`
- Evidence:
  - Verification des **20 scenarios de sauvegarde et restauration**
    (B01 a B20) du brief.
  - **Defaut confirme** : `Backup.Restore` **ne validait pas
    l'instantane** avant d'ecrire. Le chemin `full` vide la base de
    donnees vivante (`for k in pairs(db) do db[k] = nil end`) puis y
    copie le payload de l'instantane. Trois instantanes damages were
    donc **appliques** :
    1. un instantane **incomplet** (payload absent) : le payload vide
       **effacait** l'historique local ;
    2. un instantane **corrompu** (package dechiffre) : le contenu
       remplace etait accepte sans verification ;
    3. un instantane **d'une autre guilde** : le contenu d'une autre
       guilde etait melange a la base locale.
  - Le snapshot portait `checksum = package.checksum`, mais le **package
    encode** n'etait pas conserve : le checksum couvre l'enveloppe
    complete et ne pouvait donc pas etre recalcule a partir du seul
    payload. Une corruption etait **indetectable**.
  - Consequence reproduite (2026-10-21) : une restauration depuis un
    instantane incomplet **supprimait** les transactions locales sans
    aucun motif diagnostique.
- Fix applique (2026-10-21, `src/modules/Backup.lua`) :
  - `validateSnapshot` verifie, **avant toute mutation** : la presence
    et la forme du payload, la presence du contexte de guilde, et
    l'appartenance de l'instantane a la guilde courante
    (`CROSS_GUILD_RESTORE_BLOCKED`).
  - Le snapshot conserve desormais le **package encode**
    (`snapshot.packageText`). Le checksum est donc verifiable : le
    package est re-decode et son checksum compare a celui de
    l'instantane (`SNAPSHOT_CHECKSUM_MISMATCH`).
  - `Backup.PreviewRestore` applique la **meme** validation : un
    instantane damage n'est jamais propose comme applicable.
  - **Aucune regle metier modifiee** : le contrat de restauration
    (remplacement, chaine partagee, instantane de securite) est
    inchange.
- Rationale: Une restauration est la seule operation qui **remplace**
  l'etat comptable. Elle doit donc etre la plus stricte du systeme, et
  sa validation doit preceder l'instantane de securite comme l'ecriture.
- Tests : `tests/integration/rf0041_backup_restore_hardening_spec.lua`,
  21 cas (B01 a B20 plus B20b). Discrimination verifiee par reinjection :
  la validation absente fait echouer 3 cas (instantane incomplet,
  corrompu, d'une autre guilde).
- Remaining: aucun.
- References/Dependencies:
  [ImportExport.lua](../../src/modules/ImportExport.lua),
  [Ledger.lua](../../src/modules/Ledger.lua),
  [spec 026](../../specs/026-canonical-idempotent-corrections/spec.md).
- Proposed action: Conserver les cas de test. Toute nouvelle voie de
  restauration doit valider l'instantane avant d'ecrire.

<a id="rf-0042"></a>
## RF-0042 - HistoricalBaseline : un paquet contradictoire etait applique

- Status: FIXED
- Confidence: HIGH
- Risk: HIGH
- Source: [HistoricalBaseline.lua](../../src/modules/HistoricalBaseline.lua) -
  `HistoricalBaseline.CommitRecoveryPackage`
- Evidence:
  - Verification des **20 scenarios de paquet de recovery** (C01 a C20)
    du brief.
  - **Defaut confirme** : un paquet carrying **le meme identifiant
    legacy** qu'une preuve deja stockee, mais avec un **contenu
    different**, etait **commite**. L'identifiant de preuve
    (`evidenceId`) inclut le hash de l'enregistrement source
    (`sourceRecordHash`), donc la meme transaction legacy avec un montant
    different produisait un **second** identifiant de preuve au lieu
    d'un conflit sur le premier. La contradiction etait donc invisible
    a `collectInto`, qui ne compare que les enregistrements qui partagent
    deja un identifiant.
  - Consequence reproduite (2026-10-21) : deux preuves
    contradictoires coexistaient pour la meme transaction historique
    (`legacy-tx-1`, montants 4 et 99), et le commit etait rapporte
    `RECOVERY_COMMITTED`. Le conflit etait bien signale par
    `rebuildFindings` (`LEGACY_ID_CONTENT_CONFLICT`), mais le commit ne
    verifiait **aucun** constat, et la preuve contradictoire entrait
    dans l'etat historique.
  - L'identite legacy (`legacyIdHash`) est la cle **stable** d'un
    enregistrement historique : c'est la seule qui permet de detecter
    la contradiction.
- Fix applique (2026-10-21, `src/modules/HistoricalBaseline.lua`) :
  - `CommitRecoveryPackage` compare, avant toute mutation, chaque
    preuve du paquet a la preuve deja stockee qui porte le **meme**
    `legacyIdHash`. Un contenu different est un conflit et le paquet est
    refuse avec `LEGACY_ID_CONTENT_CONFLICT`.
  - Le constat `LEGACY_ID_CONTENT_CONFLICT` de `rebuildFindings` et le
    verrou de la baseline (`RECONCILIATION_DECISION_REQUIRED`) restent
    inchanges : la contradiction exige toujours une decision explicite.
  - **Aucune regle metier modifiee** : le rejet des paquets
    contradictoires ne fait qu'appliquer le constat que le module
    produisait deja.
- Rationale: Le module detectait deja la contradiction ; c'est
  l'application qui ne la consultait pas. La correction porte sur le
  point de decision, pas sur la regle.
- Tests : `tests/integration/rf0042_historical_recovery_hardening_spec.lua`,
  20 cas. Discrimination verifiee par reinjection : la comparaison
  absente fait echouer le cas contradictoire.
- Remaining: aucun.
- References/Dependencies:
  [Governance.lua](../../src/modules/Governance.lua),
  [Backup.lua](../../src/modules/Backup.lua),
  [spec 001](../../specs/001-dibs-core/spec.md).
- Proposed action: Conserver les cas de test. Un paquet de recovery ne
  doit jamais appliquer une preuve qui contredit une preuve deja
  stockee sous la meme identite legacy.

<a id="rf-0043"></a>
## RF-0043 - SyncV2 : le scenario global a quatre clients converge

- Status: KEEP
- Confidence: HIGH
- Risk: HIGH
- Source: [SyncV2.lua](../../src/modules/SyncV2.lua) -
  `Sync.Receive`, `Sync.AnnounceLedgerDigest`,
  `Sync.AnnounceAwardReservationDigest`
- Evidence:
  - Execution du **scenario global** du brief avec **quatre clients
    independants** : A coordinateur, B officier, C membre, D deconnecte.
    Chaque client a son environnement Lua, ses SavedVariables, son
    ledger, son etat SyncV2, son etat MultiLedger et son etat Governance.
    Les messages passent par une simulation de transport qui respecte les
    frontieres de serialisation et de reception ; **aucune table d'etat
    applicative n'est partagee**.
  - Scenario execute : les quatre clients sont synchronises, une
    transaction est creee, le client D se deconnecte, trois transactions
    supplementaires sont creees, une reservation est creee puis liberee,
    le coordinateur change, le client D se reconnecte, un snapshot ancien
    est recu, un commit ancien est rejoue, et les mecanismes de rattrapage
    s'executent.
  - Verifie : **convergence** des etats canoniques attendus, **aucune
    duplication comptable**, **aucune perte de transaction**, **aucune
    resurrection de reservation**, **aucun mauvais ledger**, **aucun
    ecrasement d'un etat plus recent**, **aucun contournement des
    permissions**, diagnostics appropries.
  - Deux **hypotheses** de la session ont ete **refutees** :
    1. « Un commit de l'epoch fermee rejete comme un rejeu
       idempotent » : **faux**. Le client est sur la nouvelle epoch, le
       commit est sur l'ancienne : le refus correct est `STALE_EPOCH`.
       Un rejeu de l'epoch **courante** est bien un no-op idempotent, et
       les deux comportements sont verifies.
    2. « La fixture de transport livrait les messages en boucle » :
       **confirme, et corrige dans la fixture** (pas dans le code
       applicatif). Un paquet dont un destinataire est hors ligne etait
       remise en file a chaque tour, ce qui produisait 388 livraisons
       pour 39 paquets et ne laissait jamais la boucle se calmer. La
       fixture livre desormais les messages aux destinataires en ligne,
       retient les autres pour la reconnexion, et ne les redonne pas dans
       le meme appel.
  - Aucun defaut confirme dans le code applicatif : **aucune correction
  - de production**.
- Rationale: Le scenario global est le seul qui enchaene deconnexion,
  changement de coordinateur, liberation de reservation et rejeu. Il
  constitue la preuve d'integration la plus large du protocole.
- Tests : `tests/integration/rf0043_four_client_global_scenario_spec.lua`,
  5 cas.
- Remaining: aucun.
- References/Dependencies:
  [Governance.lua](../../src/modules/Governance.lua),
  [Ledger.lua](../../src/modules/Ledger.lua),
  [spec 017](../../specs/017-guild-sync-reliability/spec.md).
- Proposed action: Conserver les cas de test.

<a id="rf-0044"></a>
## RF-0044 - Governance : l'exception de retard de l'adoption est limitee

- Status: KEEP
- Confidence: HIGH
- Risk: HIGH
- Source: [Governance.lua](../../src/modules/Governance.lua) -
  `Governance.authorityContent`
- Evidence:
  - Le brief exige que l'exception de gouvernance introduite par RF-0035
    soit **strictement limitee** au registre necessaire a l'adoption, et
    qu'elle n'autorise pas indirectement une adoption quand un autre
    composant obligatoire est en retard.
  - Le garde de RF-0035 est dans `authorityContent`, qui valide
    l'**enregistrement d'autorite en cours de creation**. Les motifs
    exclus sont `GOVERNANCE_PARENT_MISSING` et
    `AUTHORITY_DETAIL_MISSING` ; tout autre motif reste bloquant.
  - Verifie, motif par motif : un ecart de **ledger**
    (`LEDGER_GAP`), un ecart de **politique**
    (`POLICY_PARENT_MISSING`), un ecart de **saisons**
    (`SEASON_CATALOG_PARENT_MISSING`), un ecart de **coffre**
    (`VAULT_DETAIL_MISSING`), un ecart de **demande**
    (`MISSING_DETAIL`) et un ecart d'**application du ledger**
    (`LEDGER_ENFORCEMENT_MISSING`) bloquent tous l'adoption avec
    `SYNC_BEHIND`.
  - Verifie aussi que l'exception ne s'ouvre pas par **effet de bord** :
    un ecart de ledger **accompagnant** l'ecart de gouvernance bloque
    toujours l'adoption.
  - Un point de contrat a ete clarifie : le chemin d'adoption d'un pair
    passe par `Governance.ApplyRecord`, qui ne porte **pas** de garde de
    retard ; le garde protege la **creation** de l'enregistrement
    d'autorite, c'est-a-dire le chemin du GM et la construction de
    l'autorite successeur par un pair. L'exception a donc ete verifiee
    sur ce chemin la, qui est celui que RF-0035 corrigeait.
  - Aucun defaut confirme : **aucune correction de production**.
- Rationale: Une exception de securite doit rester etre la plus etroite
  possible. La liste des motifs exclus est explicite, et chaque motif
  bloquant est verifie individuellement.
- Tests : `tests/integration/rf0044_governance_adoption_guard_spec.lua`,
  8 cas sur deux clients independants.
- Remaining: aucun.
- References/Dependencies:
  [SyncV2.lua](../../src/modules/SyncV2.lua),
  [spec 017](../../specs/017-guild-sync-reliability/spec.md).
- Proposed action: Conserver les cas de test. Toute nouvelle raison de
  retard qui doit bloquer l'adoption ne doit pas etre ajoutee a la liste
  des motifs exclus.

<a id="rf-0045"></a>
## RF-0045 - PreDibs : une demande etait copiee dans un second ledger

- Status: FIXED
- Confidence: HIGH
- Risk: HIGH
- Source: [PreDibs.lua](../../src/modules/PreDibs.lua) -
  `PreDibs.UpsertFromSync`
- Evidence:
  - Verification des **20 scenarios de demande de Pre-Dibs** (A01 a A20)
    du brief : creation locale, identite du proprietaire, autorite
    verifiee, deduplication, revision monotone, transition de statut,
    portee de ledger, rechargement, perimetre public, et chemin verifie
    de synchronisation.
  - **Defaut P1 confirme et reproduit** : `PreDibs.UpsertFromSync`
    cherchait la demande **uniquement dans le ledger nomme par
    l'enregistrement recu**. Une mise a jour nommant un **autre**
    ledger n'etait donc pas trouvee, tombait dans la **branche de
    creation**, et **copiait la demande dans ce second ledger**.
    Reproduit : le ledger primaire comptait 1 demande et l'autre
    ledger en comptait aussi 1, pour le meme `requestId`.
  - Le risque n'est pas qu'un simple doublon d'affichage : la copie
    cree une **seconde autorite** sur la meme demande. Une confirmation
   lee dans un ledger et un report lu dans l'autre divergent, et le
    decompte des demandes par joueur n'est plus derivable d'une source
    unique.
  - Le journal de la demande (`revision`, `status`) etait ecrit dans le
    mauvais store : le ledger nomme dans l'enregistrement ne decorrAIT
    plus de l'etat reel de la demande.
- Fix applique (2026-10-21, `src/modules/PreDibs.lua`) :
  - La recherche de la demande existante est faite **dans tous les
    ledgers**.
  - Une demande trouvee dans un autre ledger est **refusee**
    (`LEDGER_SCOPE_MISMATCH`) au lieu d'etre dupliquee.
  - `ledgerId` est **exclu du jeu de champs modifiables** : un
    enregistrement recu ne peut pas deplacer une demande d'un ledger a
    l'autre.
  - **Aucune regle metier modifiee** : le cycle de vie de la demande
    (creation, confirmation, annulation, invalidation, execution) est
    inchange, et les verifications de proprietaire, d'identite, de
    revision et de transition restent en place.
- Rationale: Une demande porteuse de droits (un Pre-Dib confirme est
  consume par un gain) ne peut pas avoir deux emplacements. La portee de
  ledger doit etre une **propriete de la demande**, pas une propriete
  de l'enregistrement recu.
- Tests : `tests/integration/rf0045_predibs_request_integrity_spec.lua`,
  20 cas. Discrimination verifiee par reinjection : la suppression du
  controle de portee fait echouer A13.
- Remaining: aucun.
- References/Dependencies:
  [MultiLedger.lua](../../src/modules/MultiLedger.lua),
  [Disputes.lua](../../src/modules/Disputes.lua).
- Proposed action: Conserver les cas de test. Une requete recue ne doit
  jamais creer une seconde occurrence d'une demande existante.

<a id="rf-0046"></a>
## RF-0046 - Backup : une sauvegarde valide ne pouvait plus etre restauree

- Status: FIXED
- Confidence: HIGH
- Risk: HIGH
- Source: [Backup.lua](../../src/modules/Backup.lua) -
  `Backup.validateSnapshot`, `Backup.Create`
- Evidence:
  - La validation d'instantane ajoutee par **RF-0041** verifiait le
    **package encode** au travers de `ImportExport.Decode`, et
    exigeait sa presence. Or le decodeur est un **garde d'importation**,
    pas un lecteur de sauvegarde.
  - **Defaut 1 - une sauvegarde legitime ne pouvait plus etre
    restauree.** `ImportExport.Decode` refuse un paquet plus grand que
    `MAX_PACKAGE_SIZE` (250 000 octets) avec `INVALID_PACKAGE_SIZE`.
    Une sauvegarde est ecrite avec `allowOversize = true` et peut donc
    legitinement atteindre `MAX_BACKUP_SIZE` (32 MiB). Reproduit : une
    sauvegarde de **1 905 722 octets** a ete refusee par sa propre
    validation (`INVALID_PACKAGE_SIZE`), et n'a donc jamais pu etre
    previsualisee ni restauree. Toute guilde dont l'historique depasse
    250 Ko perdait ainsi son chemin de recuperation.
  - **Defaut 2 - une sauvegarde qui porte du texte joueur echouait.**
    `ImportExport.Decode` applique le filtre de contenu d'importation
    (`containsUnsafe`) qui refuse `/run`, `loadstring` et `RunScript`.
    Un rapport de litige ou une note de joueur legitimement containu
    l'un de ces jetons rendait la sauvegarde **inrestaurable**
    (`UNSAFE_CONTENT`). Reproduit : un rapport contenant
    « do not type /run this in chat » suffisait.
  - **Defaut 3 - une sauvegarde anterieure a RF-0041 etait refusee.**
    RF-0041 a ajoute `snapshot.packageText`. Une sauvegarde ecrite
    avant cette version porte un `checksum` mais **pas** de package
    encode : la validation exigeait le package et refusait
    systematiquement (`SNAPSHOT_PACKAGE_MISSING`). Toutes les
    sauvegardes existantes devenaient inutilisables.
  - **Defaut 4 (integrite des donnees, P0) - le payload applique n'etait
    pas atteste.** La restauration applique `snapshot.payload`, mais le
    checksum verifiait le **package encode**, un autre artefact. Une
    modification du seul tableau `payload` etait donc **appliquee sans
    verification** : reproduit, un montant de transaction modifie de
    `1` a `9999` et une raison reecrite ont ete restaures tels quels.
    La corruption du payload n'etait **pas detectable**.
- Fix applique (2026-10-21, `src/modules/Backup.lua`) :
  - L'instantane **atteste le payload qu'il restaure**. Deux
    attestations sont calculees sur les artefacts stockes :
    `snapshot.payloadChecksum` sur le tableau `payload` applique, et
    `snapshot.packageChecksum` sur le texte de package conserve.
  - Le package n'est plus decode par le **garde d'importation** : une
    sauvegarde peut depasser la limite portable et porter du texte
    joueur. Un snapshot **sans** attestation de package reste
    restaurable, et le `checksum` d'enveloppe historique reste verifie
    quand le garde peut lire le paquet — seule une **contradiction
    reelle** de checksum est refusee (`SNAPSHOT_CHECKSUM_MISMATCH`).
  - Un instantane **incomplet**, **d'une autre guilde** ou au
    **payload altere** reste refuse avant toute ecriture.
  - **Aucune regle metier modifiee** : le contrat de restauration
    (remplacement, chaine partagee, instantane de securite) est
    inchange, et aucune transaction n'est reecrite.
- Rationale: Une sauvegarde est le dernier recours de recuperation. Une
  validation qui la rend **inutilisable** est aussi grave qu'une
  validation absente : la premiere supprime la capacite de
  recuperation, la seconde autorise une restauration non verifiee. La
  validation doit porter sur **l'artefact reellement applique**.
- Tests : `tests/integration/rf0046_backup_restore_compatibility_spec.lua`,
  12 cas (C01 a C12). Discrimination verifiee par reinjection :
  le retour du decodeur d'importation fait echouer C01, C06, C09, C10
  et C12 ; la suppression de l'attestation du payload fait echouer
  C11. Le fichier de production a ete restaure **identique octet pour
  octet** apres chaque reinjection
  (`5954860F3EA9703F87C278D86DED2B7D14370682C146D75D7386FC3EE9BA4984`).
- Remaining: aucun.
- References/Dependencies:
  [ImportExport.lua](../../src/modules/ImportExport.lua),
  [RF-0041](#rf-0041),
  [saved-variables.md](../../docs/developer/saved-variables.md).
- Proposed action: Conserver les cas de test. Une sauvegarde doit
  toujours etre restaurable par l'addon qui l'a ecrite, et le payload
  applique doit toujours etre atteste.

<a id="rf-0047"></a>
## RF-0047 - Backup : la validation d'instantane n'etait pas exercee par la restauration

- Status: FIXED
- Confidence: HIGH
- Risk: HIGH
- Source: [rf0047_backup_restore_revalidation_spec.lua](../../tests/integration/rf0047_backup_restore_revalidation_spec.lua) -
  `Backup.Restore`
- Evidence:
  - La qualite d'un test ne se mesure pas a son nombre d'assertions mais
    a sa capacite a **detecter** une regression. Cette capacite a ete
    verifiee experimentalement en session 12 par **mutation controlee** :
    chaque defaut historique a ete reinjecte dans la source, la suite
    supposed le couvrir a ete reexecutee, et la source a ete restauree
    et reverifiee par empreinte.
  - **Faux positif demontre** : la suite RF-0041 affirmait que la
    restauration refusait un instantane damage, mais elle n'exercait que
    le refus de l'**apercu**. La restauration etait ensuite appelee avec
    l'identifiant litteral `"none"` et renvoyait `PREVIEW_NOT_FOUND` :
    l'assertion passait **pour la mauvaise raison**. La validation
    propre de `Backup.Restore` n'etait donc **jamais executee**.
  - **Preuve** : la mutation qui retire `validateSnapshot` de
    `Backup.Restore` laisse la suite RF-0041 **entierement verte**
    (`failed=0`). La meme mutation echoue **4 tests** de la suite
    RF-0047, et **1 test** de chacune des mutations de
    `payloadChecksum` et de `CROSS_GUILD_RESTORE_BLOCKED`.
  - Le risque reel n'etait pas le defaut de production — la validation
    existe et s'execute — mais la **faiblesse de la preuve** : un
    changement de code aurait pu la supprimer sans qu'aucun test ne le
    signale.
- Fix applique (2026-10-21, `tests/integration/rf0047_backup_restore_revalidation_spec.lua`) :
  - **Aucune modification de production n'a ete necessaire** : la
    validation de `Backup.Restore` etait deja correcte. Le correctif est
    dans la **preuve**.
  - Six cas (D01 a D06) qui exercent la restauration **apres** que
    l'apercu a ete emis : l'instantane est damage **entre** l'apercu et
    la restauration (payload absent, package corrompu, autre guilde,
    payload altere), et la restauration doit refuser **avant toute
    mutation**, avec le diagnostic de validation.
  - D05 verifie qu'un instantane intact reste restaure : la suite ne
    peut pas passer en refusant tout.
  - D06 verifie le refus lorsque l'apercu est reemis sur un instantane
    damage.
  - L'etat comptable est compare avant et apres chaque refus
    (`assertAccountingUnchanged`) : le refus ne doit rien changer.
- Rationale: Une garantie non exercee par un test n'est pas une
  garantie, seulement une intention. La suite doit atteindre le point
  ou la mutation est detectee, sinon elle ne prouve rien.
- Tests : `tests/integration/rf0047_backup_restore_revalidation_spec.lua`,
  6 cas. Discrimination verifiee par reinjection : 3 mutations distinctes
  detectees (1, 1 et 4 echecs).
- Remaining: aucun.
- References/Dependencies:
  [Backup.lua](../../src/modules/Backup.lua),
  [RF-0041](#rf-0041), [RF-0046](#rf-0046).
- Proposed action: Conserver les cas de test. Toute nouvelle garantie
  de restauration doit etre exercee **apres** l'apercu, et non seulement
  refusee par lui.
