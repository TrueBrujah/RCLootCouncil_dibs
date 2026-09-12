# Public Roadmap

## Phase 1 - Core
Season model, rank allocations, immutable ledger, balance derivation, permissions foundation.

## Phase 2 - Pre-Dibs
Pre-Dib request lifecycle, player UI, Encounter Journal adapter where supported.

## Phase 3 - RCLootCouncil
Optional local raid integration and finalized Dib award handling.

## Phase 4 - Distributed Sync
Officer backbone, relay model, reconnect recovery, deduplication, reconciliation.

## Phase 5 - Audit UI
Player history and complete officer/GM ledger views.

## Phase 6 - Protected Loot Governance
Curio and Tier Set progression across linked characters, configurable seasonal
policies, Officer-reviewed main/alt relationships, and bounded main-change
probation.

## Later
- localization expansion
- configurable tie-breaking policies
- optional public guild request board

## Backlog proposé - Historique et éligibilité avancée
- Synchroniser les options communes de la guilde avec un snapshot de
  configuration versionné : révision, auteur, date, autorisation GM/officier,
  détection des conflits et mise à jour automatique des clients reconnectés.
- Exploiter l'historique local de RCLootCouncil pour importer les récompenses déjà
  reçues, y compris celles obtenues avant Dibs ou dans une autre guilde lorsque
  l'information est encore disponible sur le client du joueur.
- Combiner cet historique avec le scan local de l'équipement, du sac, de la
  banque, de la warband et de la banque de guilde.
- Afficher dans la fenêtre de vote RCLootCouncil les états `Need`, `Upgrade`,
  `Minor Upgrade`, `Already received` et `Has 4-piece`.
- Ajouter des règles configurables pour Vault, Curios et Tier Set : compte par
  saison/raid, seuil 4 pièces, accès ouvert à tous une fois le seuil atteint,
  et variantes par raid, boss, difficulté ou type de token.
- Conserver la distinction entre une récompense confirmée par l'historique
  Dibs/RCLootCouncil et une information seulement détectée localement.
- Étudier plus tard un service central optionnel pour l'historique, les
  révisions et l'audit, sans lui attribuer la capacité de garantir la vérité
  de l'inventaire local d'un joueur.

## Idées à vérifier et à approuver
Ces idées sont conservées pour discussion uniquement. Elles ne sont pas encore
acceptées et ne doivent pas être implémentées sans validation préalable.

### Idée forte
- **Rappel des Dibs au Ready Check** : détecter un Ready Check avec Dibs
  autonome, puis afficher les Pre-Dibs actifs connus du client avec l'item et
  le joueur-realm concernés. Regrouper plusieurs Dibs dans une seule fenêtre,
  éviter les répétitions pour un même Ready Check et prévoir un affichage
  personnel, officier ou raid. DBM et BigWigs resteraient optionnels pour une
  intégration supplémentaire au pull ou aux avertissements de boss.

- Profils de règles par raid, boss, difficulté et type de token.
- Mode simulation avant le pull pour afficher les joueurs qui seraient éligibles.
- Gestion des personnages principaux, alts et personnages liés.
- File d'attente hors ligne pour les changements et les récompenses à resynchroniser.
- Détection et résolution des conflits lorsque plusieurs officiers modifient une
  règle en même temps.
- Journal d'audit avec une raison obligatoire pour chaque décision importante.
- Export, import et sauvegarde de l'historique de guilde.
- Statistiques d'équité : loots reçus, refusés, priorités et temps d'attente.
- Alertes lorsqu'une règle laisse trop peu de joueurs éligibles.
- Exceptions temporaires pour remplaçants, trials, nouveaux joueurs ou absences.
- Aperçu de l'éligibilité directement dans la fenêtre RCLootCouncil avant le vote.
- Système d'appel ou de contestation d'une décision.
- Interface de diagnostic expliquant pourquoi un joueur est ou n'est pas éligible.
- Tableau de bord web optionnel pour les GM et officiers.
- Assistant de première configuration avec modèles de règles prêts à utiliser.
- Permissions personnalisées par rang ou par officier.
- Explication détaillée de la raison pour laquelle un joueur est éligible ou non.
- Indication de la fraîcheur des données d'inventaire.
- Expiration automatique des anciennes données d'inventaire.
- Archivage et réinitialisation propre à chaque saison.
- Élection automatique d'un relais lorsqu'il y a plusieurs raids actifs.
- Détection des versions RCLootCouncil incompatibles ou trop anciennes.
- Mode test/sandbox pour simuler un loot sans modifier l'historique.
- Import de données provenant d'un rapport de raid ou d'un export.
- Support amélioré des noms inter-royaumes et des personnages de factions différentes.
- Notifications discrètes pour les changements de règles ou les demandes de validation.
- Mode confidentialité pour limiter l'affichage des informations d'inventaire.
- Traductions et personnalisation des messages affichés.
- Système de récupération après corruption des SavedVariables.
- Tests automatisés de scénarios complets : raids multiples, officiers hors ligne,
  reconnexion et conflits de révision.

### Demandes possibles des guildes à classer
- Modèles de règles pour les guildes de progression, casual, alt-friendly,
  trial ou hardcore.
- Priorité configurable selon la présence, l'ancienneté, le rôle, la
  spécialisation ou la participation.
- Règles spécifiques pour le hors-spécialisation, la transmog, la collection
  et l'amélioration réelle.
- Délai de vote avant de passer automatiquement au joueur suivant.
- Gestion claire des joueurs absents ou déconnectés pendant un vote.
- Approbation obligatoire d'un deuxième officier pour les loots importants.
- Annonces automatiques des règles avant le raid et avant un boss.
- Rapport de fin de raid : loot distribué, joueurs ignorés et tokens restants.
- Statistiques par joueur et par période pour démontrer l'équité.
- Import et export des règles pour tester une nouvelle politique.
- Protection contre les changements de règles pendant un vote actif.
- Permission de consulter l'historique sans permission de modifier les règles.
- Désactivation temporaire de Dibs pour un raid spécial.
- Consentement des joueurs concernant l'utilisation des données d'inventaire.

### Amélioration de l'information et de l'aide à l'écran à classer
- Ajouter des tooltips contextuels pour les items, joueurs, boutons, statuts et
  décisions d'éligibilité.
- Afficher clairement les champs `Nom` et `Joueur-realm`, notamment pour
  identifier qui a reçu ou posé un Dibs.
- Expliquer simplement pourquoi une action est recommandée : `Need`,
  `Upgrade`, `Minor Upgrade`, `Already received` ou `Has 4-piece`.
- Améliorer la présentation pour que le joueur trouve rapidement ce qui
  nécessite son attention.
- Ajouter une ligne d'aide au bas des fenêtres avec la commande slash associée
  et un court rappel de son utilisation.
- Prévoir une aide cohérente dans les fenêtres Player, Officer et RCLootCouncil.
