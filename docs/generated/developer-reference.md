THIS FILE IS GENERATED.
DO NOT EDIT MANUALLY.

# Developer Documentation Reference

Addon version: 0.8.0

## Guild Ledger status

- **ID:** `guild.ledger.status`
- **Category:** `setup`
- **Audience:** developer, gm, officer

**English:** Shows whether the shared guild ledger needs setup, historical review, or recovery, or is active. Initialization remains a Guild Master-authorized action.
**Francais:** Indique si le registre partage doit etre configure, si les donnees historiques doivent etre examinees, s'il faut une recuperation ou s'il est actif. Son initialisation exige l'autorite du maitre de guilde.

Scope: `guild` | Audit: `false` | Reason required: `false`
Source: [src/modules/Installation.lua:85](../../src/modules/Installation.lua#L85) - `Installation.GetStatus`

## Dibs season

- **ID:** `guild.season`
- **Category:** `governance`
- **Audience:** gm, officer

**English:** A season scopes the active Dibs balance and guild rules. Activating another season does not rewrite earlier history.
**Francais:** Une saison determine le solde Dibs actif et les regles de guilde. Activer une autre saison ne reecrit pas l'historique anterieur.

Scope: `guild-season` | Audit: `false` | Reason required: `false`
Source: [src/modules/Seasons.lua:181](../../src/modules/Seasons.lua#L181) - `Dibs.Seasons.Create`

## Guild Configuration

- **ID:** `guild.setup`
- **Category:** `setup`
- **Audience:** developer, gm

**English:** Guild Master workflow for Guild Configuration: review existing Dibs data and activate this guild's shared Dibs ledger. Opening this page does not initialize it.
**Francais:** Parcours du maitre de guilde pour la configuration de guilde : examinez les donnees Dibs existantes et activez le registre partage de cette guilde. Ouvrir cette page ne l'initialise pas.

Scope: `guild` | Audit: `true` | Reason required: `false`
Source: [src/modules/Installation.lua:271](../../src/modules/Installation.lua#L271) - `Installation.Initialize`

## Manual Dibs Adjustment

- **ID:** `ledger.adjust`
- **Category:** `ledger`
- **Audience:** gm, officer

**English:** Guild Master and authorized Officers can adjust a member's current-season balance. Each change records actor, target, reason, previous balance, and resulting balance in audit history.
**Francais:** Le maitre de guilde et les officiers autorises peuvent ajuster le solde de la saison pour un membre. L'historique conserve l'auteur, la cible, la raison et les soldes avant/apres.

Scope: `guild-season` | Audit: `true` | Reason required: `true`
Permission: `ledger.adjust`
Source: [src/modules/ProtectedActions.lua:277](../../src/modules/ProtectedActions.lua#L277) - `executeLedgerAdjust`

## Adjustment reason

- **ID:** `ledger.adjust.reason`
- **Category:** `ledger`
- **Audience:** gm, officer

**English:** The recorded explanation for this action. Administrative changes require a meaningful reason.
**Francais:** Explication conservee avec cette action. Les changements administratifs exigent une raison pertinente.

Scope: `guild-season` | Audit: `true` | Reason required: `true`
Permission: `ledger.adjust`
Source: [src/modules/Ledger.lua:686](../../src/modules/Ledger.lua#L686) - `Ledger.AdminAdjust`

## Dibs audit history

- **ID:** `ledger.audit.history`
- **Category:** `ledger`
- **Audience:** gm, officer, player

**English:** Shows recorded dates, actions, and available reasons. Older events are evidence, not editable balance controls.
**Francais:** Affiche les dates, actions et raisons disponibles. Les anciens evenements sont des preuves, pas des soldes modifiables.

Scope: `guild-season` | Audit: `false` | Reason required: `false`
Source: [src/modules/Ledger.lua:801](../../src/modules/Ledger.lua#L801) - `Ledger.GetHistory`

## Dib Balance

- **ID:** `ledger.balance`
- **Category:** `ledger`
- **Audience:** gm, officer, player

**English:** Your available Dibs are scoped to this guild and season. A qualifying finalized award or authorized adjustment changes the balance.
**Francais:** Vos Dibs disponibles sont propres a cette guilde et a cette saison. Un gain eligible finalise ou un ajustement autorise modifie le solde.

Scope: `guild-season` | Audit: `false` | Reason required: `false`
Source: [src/modules/Ledger.lua:767](../../src/modules/Ledger.lua#L767) - `Ledger.GetBalance`

## Loot eligibility

- **ID:** `loot.eligibility`
- **Category:** `governance`
- **Audience:** gm, officer, player

**English:** Shows whether a loot category may use Dibs under the active guild policy, and why a category is blocked or needs review.
**Francais:** Indique si une categorie de butin peut utiliser les Dibs selon la politique active, et pourquoi elle est bloquee ou a verifier.

Scope: `guild-season` | Audit: `false` | Reason required: `false`
Source: [src/ui/OfficerUI.lua:400](../../src/ui/OfficerUI.lua#L400) - `Dibs.OfficerUI.GetEligibilityProjection`

## Request audit timeline

- **ID:** `officer.audit.timeline`
- **Category:** `ledger`
- **Audience:** gm, officer, player

**English:** Shows recorded dates, actions, and available reasons. Older events are evidence, not editable balance controls.
**Francais:** Affiche les dates, actions et raisons disponibles. Les anciens evenements sont des preuves, pas des soldes modifiables.

Scope: `guild` | Audit: `false` | Reason required: `false`
Source: [src/modules/Disputes.lua:1152](../../src/modules/Disputes.lua#L1152) - `Disputes.GetTimeline`

## Officer review requests

- **ID:** `officer.review.requests`
- **Category:** `ledger`
- **Audience:** gm, officer

**English:** Shows player reports and their attached Dibs or RCLootCouncil evidence. Opening a request is read-only; Officer resolutions retain an audit reason.
**Francais:** Affiche les signalements des joueurs et leurs preuves Dibs ou RCLootCouncil. Ouvrir une demande est en lecture seule; les decisions des officiers conservent une raison d'audit.

Scope: `guild` | Audit: `false` | Reason required: `false`
Source: [src/modules/Disputes.lua:614](../../src/modules/Disputes.lua#L614) - `Disputes.ListForOfficer`

## Player raid readiness

- **ID:** `player.readiness`
- **Category:** `setup`
- **Audience:** gm, officer, player

**English:** Summarizes whether current guild setup and context are ready for live loot. An unavailable check is not a personal penalty; contact an Officer if the state remains blocked.
**Francais:** Resume si la configuration de guilde et le contexte actuel sont prets pour le butin en direct. Un controle indisponible n'est pas une penalite personnelle; contactez un officier si l'etat reste bloque.

Scope: `player` | Audit: `false` | Reason required: `false`
Source: [src/modules/Readiness.lua:200](../../src/modules/Readiness.lua#L200) - `Readiness.Evaluate`

## Guild Dibs status

- **ID:** `player.status`
- **Category:** `setup`
- **Audience:** player

**English:** Explains whether your personal Dibs information is available. If features are limited or unavailable, retry later or contact an Officer; RCLootCouncil is optional and Standalone mode can remain available.
**Francais:** Indique si vos informations Dibs personnelles sont disponibles. Si certaines fonctions sont limitees ou indisponibles, reessayez plus tard ou contactez un officier; RCLootCouncil est optionnel et le mode Standalone peut rester disponible.

Scope: `guild` | Audit: `false` | Reason required: `false`
Source: [src/ui/PlayerUI.lua:372](../../src/ui/PlayerUI.lua#L372) - `Dibs.PlayerUI.GetStatusPresentation`

## Announcement channels

- **ID:** `predibs.announcement.channels`
- **Category:** `predibs`
- **Audience:** gm, officer

**English:** Choose destinations for public Pre-Dib notices and Officer-only notices. Availability depends on this character joining the configured channel; test it before live use.
**Francais:** Choisissez les destinations des annonces publiques Pre-Dib et des avis reserves aux officiers. Ce personnage doit rejoindre le canal configure; testez-le avant utilisation.

Scope: `guild` | Audit: `false` | Reason required: `false`
Source: [src/modules/PreDibs.lua:477](../../src/modules/PreDibs.lua#L477) - `Dibs.PreDibs.GetAnnouncementSettings`

## Encounter Mode

- **ID:** `predibs.encounter.mode`
- **Category:** `predibs`
- **Audience:** gm, officer, player

**English:** Controls when players may submit a Pre-Dib. Encounter mode requires the matching raid and difficulty context; Wild Open may allow requests outside the raid under guild policy.
**Francais:** Determine quand les joueurs peuvent envoyer un Pre-Dib. Le mode Encounter exige le raid et la difficulte correspondants; Wild Open peut autoriser les demandes hors raid selon la politique de guilde.

Scope: `guild-season` | Audit: `false` | Reason required: `false`
Source: [src/modules/PreDibs.lua:456](../../src/modules/PreDibs.lua#L456) - `Dibs.PreDibs.ValidatePublicRequest`

## Pre-Dib Request

- **ID:** `predibs.request`
- **Category:** `predibs`
- **Audience:** gm, officer, player

**English:** A Pre-Dib records your interest in eligible loot. It does not award an item or spend a Dib; that happens only after a qualifying award is finalized.
**Francais:** Un Pre-Dib indique votre interet pour un butin eligible. Il n'attribue pas l'objet et ne depense pas de Dib; cela arrive seulement apres un gain eligible finalise.

Scope: `guild-season` | Audit: `false` | Reason required: `false`
Source: [src/modules/PreDibs.lua:582](../../src/modules/PreDibs.lua#L582) - `Dibs.PreDibs.CreatePublic`

## Rank Allocation

- **ID:** `rank.allocation`
- **Category:** `rank-rules`
- **Audience:** gm, officer

**English:** Starting Dibs assigned to a guild rank for the selected season. Changing the rule does not rewrite older ledger entries.
**Francais:** Dibs attribues au depart a un rang de guilde pour la saison selectionnee. Changer la regle ne reecrit pas les anciennes transactions.

Scope: `guild-season` | Audit: `false` | Reason required: `false`
Permission: `rank.set`
Source: [src/modules/ProtectedActions.lua:154](../../src/modules/ProtectedActions.lua#L154) - `executeRankSet`

## Rank Allocation Reconciliation

- **ID:** `rank.reconciliation`
- **Category:** `rank-rules`
- **Audience:** gm, officer

**English:** Positive differences require an explicit, reasoned top-up through the canonical ledger. Existing allocations are never removed or converted to debt when a member's expected allocation decreases.
**Francais:** Un ecart positif exige un complement explicite, motive et enregistre dans le registre canonique. Une baisse d'allocation attendue ne retire jamais les allocations existantes et ne cree aucune dette.

Scope: `guild-season` | Audit: `true` | Reason required: `true`
Permission: `rank.reconcile`
Source: [src/modules/ProtectedActions.lua:180](../../src/modules/ProtectedActions.lua#L180) - `executeRankReconcile`

## RCLootCouncil history review

- **ID:** `rclootcouncil.history.reconciliation`
- **Category:** `ledger`
- **Audience:** developer, gm, officer

**English:** Previews recorded awards without changing RCLootCouncil history. Confirm only supported evidence; ambiguous or incomplete rows require review and a reason.
**Francais:** Affiche les gains enregistres sans modifier l'historique RCLootCouncil. Confirmez seulement les preuves suffisantes; les lignes ambigues ou incompletes exigent une revue et une raison.

Scope: `guild-season` | Audit: `false` | Reason required: `false`
Source: [src/integrations/RCLootCouncil.lua:3433](../../src/integrations/RCLootCouncil.lua#L3433) - `Dibs.RCLootCouncil.GetHistoryRows`

## RCLootCouncil response mapping

- **ID:** `rclootcouncil.response.mapping`
- **Category:** `ledger`
- **Audience:** gm, officer

**English:** Maps a RCLootCouncil response to Dibs meaning. Review the mapping with your guild before live loot; this does not change RCLootCouncil history.
**Francais:** Associe une reponse RCLootCouncil a une action Dibs. Verifiez la correspondance avant le butin en direct; l'historique RCLootCouncil reste inchange.

Scope: `guild` | Audit: `false` | Reason required: `false`
Source: [src/integrations/RCLootCouncilOptions.lua:245](../../src/integrations/RCLootCouncilOptions.lua#L245) - `buildButtonSetMappingText`

## Raid Readiness

- **ID:** `setup.assistant.readiness`
- **Category:** `setup`
- **Audience:** gm, officer

**English:** Raid Readiness answers whether DIBS is ready for this raid and lists blocking checks with their next actions.
**Francais:** La preparation au raid indique si DIBS est pret pour ce raid et liste les controles bloquants avec leurs prochaines actions.

Scope: `guild` | Audit: `false` | Reason required: `false`
Source: [src/ui/SetupAssistant.lua:117](../../src/ui/SetupAssistant.lua#L117) - `SetupAssistant.Evaluate`

## Historical Reconciliation

- **ID:** `setup.reconciliation`
- **Category:** `setup`
- **Audience:** developer, gm, officer

**English:** Review detected historical Dibs entries before the Guild Master initializes the shared ledger. Keep uncertain evidence unresolved until it is understood.
**Francais:** Examinez les entrees Dibs historiques detectees avant que le maitre de guilde initialise le registre partage. Laissez les preuves incertaines sans decision.

Scope: `guild` | Audit: `false` | Reason required: `false`
Source: [src/modules/Installation.lua:172](../../src/modules/Installation.lua#L172) - `Installation.GetReconciliationView`

## Coordinator

- **ID:** `sync.coordinator`
- **Category:** `governance`
- **Audience:** developer, gm, officer

**English:** The authorized Dibs client that applies canonical guild-ledger updates. It is normally selected during Guild Configuration.
**Francais:** Client Dibs autorise a appliquer les mises a jour canoniques du registre de guilde. Il est normalement choisi pendant la configuration.

Scope: `guild` | Audit: `false` | Reason required: `false`
Source: [src/modules/Governance.lua:423](../../src/modules/Governance.lua#L423) - `Governance.GetAuthorityState`

## Synchronization peer status

- **ID:** `sync.peer.status`
- **Category:** `synchronization`
- **Audience:** gm, officer

**English:** Peer status is based on the latest response observed by this client; an offline or unresponsive member may show stale synchronization details.
**Francais:** L'etat d'un membre depend de sa derniere reponse observee; un joueur absent ou sans reponse peut afficher des donnees de synchronisation anciennes.

Scope: `guild` | Audit: `false` | Reason required: `false`
Source: [src/modules/SyncV2.lua:280](../../src/modules/SyncV2.lua#L280) - `Sync.GetPeerStatuses`

## SyncV2 Protocol State

- **ID:** `sync.protocol.state`
- **Category:** `protocol`
- **Audience:** developer

**English:** Diagnostics may show protocol state such as V2_ENFORCED, ledgerEpoch, and hashes. These identifiers help troubleshooting; ordinary setup uses the status and next action.
**Francais:** Les diagnostics peuvent afficher des etats de protocole comme V2_ENFORCED, ledgerEpoch et les empreintes. Ils servent au depannage; la configuration normale utilise les statuts et actions indiquees.

**Technical reference:** SyncV2 may report LEGACY_LOCAL before cutover, CUTOVER_PREPARED while writer compatibility is prepared, or V2_ENFORCED after approved enforcement. ledgerEpoch identifies the active canonical ledger generation; legacyBaselineHash identifies the approved legacy baseline.
**Reference technique:** SyncV2 peut indiquer LEGACY_LOCAL avant le changement, CUTOVER_PREPARED pendant la preparation de compatibilite des ecrivains, ou V2_ENFORCED apres activation approuvee. ledgerEpoch identifie la generation active du registre canonique; legacyBaselineHash identifie la base historique approuvee.

Scope: `guild` | Audit: `false` | Reason required: `false`
Source: [src/modules/SyncV2.lua:498](../../src/modules/SyncV2.lua#L498) - `Sync.SetProtocolState`

## Raid Relay service

- **ID:** `sync.raid.relay`
- **Category:** `synchronization`
- **Audience:** developer

**English:** This service uses guild synchronization for bounded Dibs state and raid reminders. It does not transfer loot, votes, live candidates, or ledger ownership.
**Francais:** Ce service utilise la synchronisation de guilde pour l'etat Dibs borne et les rappels de raid. Il ne transfere ni butin, ni votes, ni candidats en direct, ni propriete du registre.

Scope: `guild` | Audit: `false` | Reason required: `false`
Source: [src/modules/RaidRelay.lua:74](../../src/modules/RaidRelay.lua#L74) - `Dibs.RaidRelay.Broadcast`

## Raid reminder

- **ID:** `sync.raid.reminder`
- **Category:** `synchronization`
- **Audience:** gm, officer

**English:** Sends the configured reminder to the current raid chat. Guild permission and raid-chat availability are required; this does not record a loot award or change Dibs.
**Francais:** Envoie le rappel configure dans le canal du raid actuel. Une autorisation de guilde et un canal disponible sont requis; cela n'enregistre aucun gain et ne modifie pas les Dibs.

Scope: `guild` | Audit: `false` | Reason required: `false`
Source: [src/modules/RaidRelay.lua:105](../../src/modules/RaidRelay.lua#L105) - `Dibs.RaidRelay.SendReminder`

## Synchronization

- **ID:** `sync.status`
- **Category:** `synchronization`
- **Audience:** gm, officer, player

**English:** Shows whether this client can exchange current guild Dibs state. Unavailable or behind clients may be unable to apply canonical updates.
**Francais:** Indique si ce client peut echanger l'etat Dibs actuel de la guilde. Un client indisponible ou en retard peut ne pas appliquer les mises a jour canoniques.

Scope: `guild` | Audit: `false` | Reason required: `false`
Source: [src/modules/SyncV2.lua:251](../../src/modules/SyncV2.lua#L251) - `Sync.GetStatus`
