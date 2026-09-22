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

## Plan finalise - 7 ameliorations operationnelles

Ce plan complete les fondations deja presentes dans les phases precedentes. Il
ne remplace pas les regles du ledger, les permissions existantes ou la source
de verite Dibs. Chaque fonctionnalite doit rester guild-scoped, auditable et
utilisable sans RCLootCouncil lorsque cela est pertinent.

### Ordre de livraison

#### Etape 0 - Fondation Great Vault et synchronisation

Cette etape est la dependance technique de l'indicateur de synchronisation.
L'addon sait deja enregistrer une acquisition Vault manuellement avec
`/dibs vault`; cette etape ajoutera la detection de reclamation lorsque
l'API Retail le permet, un identifiant de reset pour l'idempotence et une
source `GREAT_VAULT`. Si l'API ne permet pas une confirmation fiable, l'entree
restera etiquetee comme manuelle ou a verifier par un Officer.

Les acquisitions Vault seront ensuite ajoutees au protocole de synchronisation
avec validation de la guilde, de l'identite du personnage, de la saison et de
la revision. Les donnees ne seront pas envoyees vers GitHub ni vers un service
central; elles resteront dans les SavedVariables et les messages addon de la
guilde.

Critere de sortie: une acquisition Vault confirmee apparait une seule fois
chez les clients autorises, une relecture ne cree aucun doublon, et une donnee
non verifiable ne peut pas bloquer silencieusement un joueur.

#### Etape 1 - Assistant de premiere installation

L'assistant guidera le GM ou l'Officer a travers la verification de RCLootCouncil,
des permissions, de la saison, des regles de rang, des canaux et des types de
loot. Il proposera un test local avant le premier raid et indiquera clairement
ce qui reste a faire.

Critere de sortie: une nouvelle guilde peut atteindre un etat `Pret pour le
raid` sans modifier manuellement les SavedVariables.

#### Etape 2 - Tableau de sante

Une page de diagnostic synthetisera la version, la saison active, l'etat de
RCLootCouncil, la derniere sauvegarde, les migrations, la synchronisation et
les avertissements de donnees. Les actions dangereuses resteront dans les
outils existants et demanderont leurs confirmations habituelles.

Critere de sortie: un GM peut identifier la cause d'un etat `Degrade`,
`Bloque` ou `Non disponible` sans ouvrir les fichiers de donnees.

#### Etape 3 - Notifications joueur

Les notifications couvriront les changements utiles: Pre-Dib accepte ou
annule, attribution finalisee, Dib consomme, demande resolue et acquisition
Vault enregistree. Elles seront discretes, localisees et desactivables par
profil; elles ne devront jamais afficher l'historique prive d'un autre joueur.

Critere de sortie: chaque notification est idempotente, liee a un evenement
auditable et n'apparait pas plusieurs fois apres une reconnexion.

#### Etape 4 - Recherche et filtres avances

Les vues Player et Officer pourront filtrer l'historique par joueur, objet,
raid, boss, saison, date, statut et source. Les filtres Officer resteront
proteges par les memes controles d'acces que les donnees affichees.

Critere de sortie: un Officer peut retrouver une attribution ou une acquisition
Vault dans un historique volumineux sans parcourir manuellement toute la liste.

#### Etape 5 - Centre de sante des donnees et migration

Ce centre controlera les doublons, references de saison invalides, acquisitions
incompletes, anciennes versions et conflits de synchronisation. Il affichera
un apercu avant correction et creera une sauvegarde avant toute operation
destructive. Les transactions append-only existantes ne seront jamais reecrites.

Critere de sortie: une anomalie peut etre corrigee, ignoree ou exportee pour
revision avec une trace de l'acteur, de la raison et du resultat.

#### Etape 6 - Export d'audit anonymise

Un export distinct des packages complets supprimera les noms, identites,
notes privees et donnees inutiles. Il conservera les dates, types d'evenements,
objets, saisons, decisions et resultats necessaires a l'analyse d'un probleme.

Critere de sortie: un rapport anonymise ne contient aucune identite de joueur,
aucune permission et aucune transaction executable, tout en restant lisible
pour un support ou une revue de guilde.

### Regles de livraison communes

- Chaque etape aura une specification, des tests unitaires et un scenario
  Retail manuel lorsque l'API ou l'interface protege est impliquee.
- Les nouvelles donnees auront une migration SavedVariables et une politique
  d'idempotence avant d'etre synchronisees.
- Les donnees Vault, d'inventaire et de relations main/alt resteront limitees
  a la guilde et au personnage autorises; aucune base distante publique ne sera
  creee.
- Une information seulement detectee localement restera distinguee d'une
  acquisition confirmee par un award ou par un Officer.
- Chaque phase pourra etre livree independamment, mais l'Etape 0 doit preceder
  l'indicateur de synchronisation fiable et l'evaluation Vault de l'eligibilite.
- Le backlog ci-dessous reste reserve aux idees non approuvees et ne doit pas
  etre implemente sans une nouvelle decision de perimetre.

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
