THIS FILE IS GENERATED.
DO NOT EDIT MANUALLY.

# UI and API Reference

## Guild Ledger status (`guild.ledger.status`)

Category: `setup` | Module: `Installation` | Audience: developer, gm, officer

**English:** Shows whether the shared guild ledger needs setup, historical review, or recovery, or is active. Initialization remains a Guild Master-authorized action.
**Francais:** Indique si le registre partage doit etre configure, si les donnees historiques doivent etre examinees, s'il faut une recuperation ou s'il est actif. Son initialisation exige l'autorite du maitre de guilde.
Source: `src/modules/Installation.lua:85` (`Installation.GetStatus`)

## Dibs season (`guild.season`)

Category: `governance` | Module: `Seasons` | Audience: gm, officer

**English:** A season scopes the active Dibs balance and guild rules. Activating another season does not rewrite earlier history.
**Francais:** Une saison determine le solde Dibs actif et les regles de guilde. Activer une autre saison ne reecrit pas l'historique anterieur.
Source: `src/modules/Seasons.lua:189` (`Dibs.Seasons.Create`)

## Guild Configuration (`guild.setup`)

Category: `setup` | Module: `Installation` | Audience: developer, gm

**English:** Guild Master workflow for Guild Configuration: review existing Dibs data and activate this guild's shared Dibs ledger. Opening this page does not initialize it.
**Francais:** Parcours du maitre de guilde pour la configuration de guilde : examinez les donnees Dibs existantes et activez le registre partage de cette guilde. Ouvrir cette page ne l'initialise pas.
Source: `src/modules/Installation.lua:271` (`Installation.Initialize`)

## Manual Dibs Adjustment (`ledger.adjust`)

Category: `ledger` | Module: `ProtectedActions` | Audience: gm, officer

**English:** Guild Master and authorized Officers can adjust a member's current-season balance. Each change records actor, target, reason, previous balance, and resulting balance in audit history.
**Francais:** Le maitre de guilde et les officiers autorises peuvent ajuster le solde de la saison pour un membre. L'historique conserve l'auteur, la cible, la raison et les soldes avant/apres.
Source: `src/modules/ProtectedActions.lua:278` (`executeLedgerAdjust`)

## Adjustment reason (`ledger.adjust.reason`)

Category: `ledger` | Module: `Ledger` | Audience: gm, officer

**English:** The recorded explanation for this action. Administrative changes require a meaningful reason.
**Francais:** Explication conservee avec cette action. Les changements administratifs exigent une raison pertinente.
Source: `src/modules/Ledger.lua:714` (`Ledger.AdminAdjust`)

## Dibs audit history (`ledger.audit.history`)

Category: `ledger` | Module: `Ledger` | Audience: gm, officer, player

**English:** Shows recorded dates, actions, and available reasons. Older events are evidence, not editable balance controls.
**Francais:** Affiche les dates, actions et raisons disponibles. Les anciens evenements sont des preuves, pas des soldes modifiables.
Source: `src/modules/Ledger.lua:883` (`Ledger.GetHistory`)

## Dib Balance (`ledger.balance`)

Category: `ledger` | Module: `Ledger` | Audience: gm, officer, player

**English:** Your available Dibs are scoped to this guild and season. A qualifying finalized award or authorized adjustment changes the balance.
**Francais:** Vos Dibs disponibles sont propres a cette guilde et a cette saison. Un gain eligible finalise ou un ajustement autorise modifie le solde.
Source: `src/modules/Ledger.lua:817` (`Ledger.GetBalance`)

## Loot eligibility (`loot.eligibility`)

Category: `governance` | Module: `OfficerUI` | Audience: gm, officer, player

**English:** Shows whether a loot category may use Dibs under the active guild policy, and why a category is blocked or needs review.
**Francais:** Indique si une categorie de butin peut utiliser les Dibs selon la politique active, et pourquoi elle est bloquee ou a verifier.
Source: `src/ui/OfficerUI.lua:433` (`Dibs.OfficerUI.GetEligibilityProjection`)

## Request audit timeline (`officer.audit.timeline`)

Category: `ledger` | Module: `Disputes` | Audience: gm, officer, player

**English:** Shows recorded dates, actions, and available reasons. Older events are evidence, not editable balance controls.
**Francais:** Affiche les dates, actions et raisons disponibles. Les anciens evenements sont des preuves, pas des soldes modifiables.
Source: `src/modules/Disputes.lua:1152` (`Disputes.GetTimeline`)

## Officer review requests (`officer.review.requests`)

Category: `ledger` | Module: `Disputes` | Audience: gm, officer

**English:** Shows player reports and their attached Dibs or RCLootCouncil evidence. Opening a request is read-only; Officer resolutions retain an audit reason.
**Francais:** Affiche les signalements des joueurs et leurs preuves Dibs ou RCLootCouncil. Ouvrir une demande est en lecture seule; les decisions des officiers conservent une raison d'audit.
Source: `src/modules/Disputes.lua:614` (`Disputes.ListForOfficer`)

## Player raid readiness (`player.readiness`)

Category: `setup` | Module: `Readiness` | Audience: gm, officer, player

**English:** Summarizes whether current guild setup and context are ready for live loot. An unavailable check is not a personal penalty; contact an Officer if the state remains blocked.
**Francais:** Resume si la configuration de guilde et le contexte actuel sont prets pour le butin en direct. Un controle indisponible n'est pas une penalite personnelle; contactez un officier si l'etat reste bloque.
Source: `src/modules/Readiness.lua:200` (`Readiness.Evaluate`)

## Guild Dibs status (`player.status`)

Category: `setup` | Module: `PlayerUI` | Audience: player

**English:** Explains whether your personal Dibs information is available. If features are limited or unavailable, retry later or contact an Officer; RCLootCouncil is optional and Standalone mode can remain available.
**Francais:** Indique si vos informations Dibs personnelles sont disponibles. Si certaines fonctions sont limitees ou indisponibles, reessayez plus tard ou contactez un officier; RCLootCouncil est optionnel et le mode Standalone peut rester disponible.
Source: `src/ui/PlayerUI.lua:408` (`Dibs.PlayerUI.GetStatusPresentation`)

## Announcement channels (`predibs.announcement.channels`)

Category: `predibs` | Module: `PreDibs` | Audience: gm, officer

**English:** Choose destinations for public Pre-Dib notices and Officer-only notices. Availability depends on this character joining the configured channel; test it before live use.
**Francais:** Choisissez les destinations des annonces publiques Pre-Dib et des avis reserves aux officiers. Ce personnage doit rejoindre le canal configure; testez-le avant utilisation.
Source: `src/modules/PreDibs.lua:477` (`Dibs.PreDibs.GetAnnouncementSettings`)

## Encounter Mode (`predibs.encounter.mode`)

Category: `predibs` | Module: `PreDibs` | Audience: gm, officer, player

**English:** Controls when players may submit a Pre-Dib. Encounter mode requires the matching raid and difficulty context; Wild Open may allow requests outside the raid under guild policy.
**Francais:** Determine quand les joueurs peuvent envoyer un Pre-Dib. Le mode Encounter exige le raid et la difficulte correspondants; Wild Open peut autoriser les demandes hors raid selon la politique de guilde.
Source: `src/modules/PreDibs.lua:456` (`Dibs.PreDibs.ValidatePublicRequest`)

## Pre-Dib Request (`predibs.request`)

Category: `predibs` | Module: `PreDibs` | Audience: gm, officer, player

**English:** A Pre-Dib records your interest in eligible loot. It does not award an item or spend a Dib; that happens only after a qualifying award is finalized.
**Francais:** Un Pre-Dib indique votre interet pour un butin eligible. Il n'attribue pas l'objet et ne depense pas de Dib; cela arrive seulement apres un gain eligible finalise.
Source: `src/modules/PreDibs.lua:582` (`Dibs.PreDibs.CreatePublic`)

## Rank Allocation (`rank.allocation`)

Category: `rank-rules` | Module: `ProtectedActions` | Audience: gm, officer

**English:** Starting Dibs assigned to a guild rank for the selected season. Changing the rule does not rewrite older ledger entries.
**Francais:** Dibs attribues au depart a un rang de guilde pour la saison selectionnee. Changer la regle ne reecrit pas les anciennes transactions.
Source: `src/modules/ProtectedActions.lua:155` (`executeRankSet`)

## Rank Allocation Reconciliation (`rank.reconciliation`)

Category: `rank-rules` | Module: `ProtectedActions` | Audience: gm, officer

**English:** Positive differences require an explicit, reasoned top-up through the canonical ledger. Existing allocations are never removed or converted to debt when a member's expected allocation decreases.
**Francais:** Un ecart positif exige un complement explicite, motive et enregistre dans le registre canonique. Une baisse d'allocation attendue ne retire jamais les allocations existantes et ne cree aucune dette.
Source: `src/modules/ProtectedActions.lua:181` (`executeRankReconcile`)

## RCLootCouncil history review (`rclootcouncil.history.reconciliation`)

Category: `ledger` | Module: `RCLootCouncil` | Audience: developer, gm, officer

**English:** Previews recorded awards without changing RCLootCouncil history. Confirm only supported evidence; ambiguous or incomplete rows require review and a reason.
**Francais:** Affiche les gains enregistres sans modifier l'historique RCLootCouncil. Confirmez seulement les preuves suffisantes; les lignes ambigues ou incompletes exigent une revue et une raison.
Source: `src/integrations/RCLootCouncil.lua:3504` (`Dibs.RCLootCouncil.GetHistoryRows`)

## RCLootCouncil response mapping (`rclootcouncil.response.mapping`)

Category: `ledger` | Module: `RCLootCouncilOptions` | Audience: gm, officer

**English:** Maps a RCLootCouncil response to Dibs meaning. Review the mapping with your guild before live loot; this does not change RCLootCouncil history.
**Francais:** Associe une reponse RCLootCouncil a une action Dibs. Verifiez la correspondance avant le butin en direct; l'historique RCLootCouncil reste inchange.
Source: `src/integrations/RCLootCouncilOptions.lua:491` (`buildButtonSetMappingText`)

## Raid Readiness (`setup.assistant.readiness`)

Category: `setup` | Module: `SetupAssistant` | Audience: gm, officer

**English:** Raid Readiness answers whether DIBS is ready for this raid and lists blocking checks with their next actions.
**Francais:** La preparation au raid indique si DIBS est pret pour ce raid et liste les controles bloquants avec leurs prochaines actions.
Source: `src/ui/SetupAssistant.lua:117` (`SetupAssistant.Evaluate`)

## Historical Reconciliation (`setup.reconciliation`)

Category: `setup` | Module: `Installation` | Audience: developer, gm, officer

**English:** Review detected historical Dibs entries before the Guild Master initializes the shared ledger. Keep uncertain evidence unresolved until it is understood.
**Francais:** Examinez les entrees Dibs historiques detectees avant que le maitre de guilde initialise le registre partage. Laissez les preuves incertaines sans decision.
Source: `src/modules/Installation.lua:172` (`Installation.GetReconciliationView`)

## Coordinator (`sync.coordinator`)

Category: `governance` | Module: `Governance` | Audience: developer, gm, officer

**English:** The authorized Dibs client that applies canonical guild-ledger updates. It is normally selected during Guild Configuration.
**Francais:** Client Dibs autorise a appliquer les mises a jour canoniques du registre de guilde. Il est normalement choisi pendant la configuration.
Source: `src/modules/Governance.lua:435` (`Governance.GetAuthorityState`)

## Synchronization peer status (`sync.peer.status`)

Category: `synchronization` | Module: `SyncV2` | Audience: gm, officer

**English:** Peer status is based on the latest response observed by this client; an offline or unresponsive member may show stale synchronization details.
**Francais:** L'etat d'un membre depend de sa derniere reponse observee; un joueur absent ou sans reponse peut afficher des donnees de synchronisation anciennes.
Source: `src/modules/SyncV2.lua:372` (`Sync.GetPeerStatuses`)

## SyncV2 Protocol State (`sync.protocol.state`)

Category: `protocol` | Module: `SyncV2` | Audience: developer

**English:** Diagnostics may show protocol state such as V2_ENFORCED, ledgerEpoch, and hashes. These identifiers help troubleshooting; ordinary setup uses the status and next action.
**Francais:** Les diagnostics peuvent afficher des etats de protocole comme V2_ENFORCED, ledgerEpoch et les empreintes. Ils servent au depannage; la configuration normale utilise les statuts et actions indiquees.
**Technical reference:** SyncV2 may report LEGACY_LOCAL before cutover, CUTOVER_PREPARED while writer compatibility is prepared, or V2_ENFORCED after approved enforcement. ledgerEpoch identifies the active canonical ledger generation; legacyBaselineHash identifies the approved legacy baseline.
Source: `src/modules/SyncV2.lua:623` (`Sync.SetProtocolState`)

## Raid Relay service (`sync.raid.relay`)

Category: `synchronization` | Module: `RaidRelay` | Audience: developer

**English:** This service uses guild synchronization for bounded Dibs state and raid reminders. It does not transfer loot, votes, live candidates, or ledger ownership.
**Francais:** Ce service utilise la synchronisation de guilde pour l'etat Dibs borne et les rappels de raid. Il ne transfere ni butin, ni votes, ni candidats en direct, ni propriete du registre.
Source: `src/modules/RaidRelay.lua:74` (`Dibs.RaidRelay.Broadcast`)

## Raid reminder (`sync.raid.reminder`)

Category: `synchronization` | Module: `RaidRelay` | Audience: gm, officer

**English:** Sends the configured reminder to the current raid chat. Guild permission and raid-chat availability are required; this does not record a loot award or change Dibs.
**Francais:** Envoie le rappel configure dans le canal du raid actuel. Une autorisation de guilde et un canal disponible sont requis; cela n'enregistre aucun gain et ne modifie pas les Dibs.
Source: `src/modules/RaidRelay.lua:105` (`Dibs.RaidRelay.SendReminder`)

## Synchronization (`sync.status`)

Category: `synchronization` | Module: `SyncV2` | Audience: gm, officer, player

**English:** Shows whether this client can exchange current guild Dibs state. Unavailable or behind clients may be unable to apply canonical updates.
**Francais:** Indique si ce client peut echanger l'etat Dibs actuel de la guilde. Un client indisponible ou en retard peut ne pas appliquer les mises a jour canoniques.
Source: `src/modules/SyncV2.lua:343` (`Sync.GetStatus`)
