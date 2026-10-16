# Public Roadmap

Revue documentaire : 2026-10-16. Cette page distingue le code implemente,
les validations Retail restantes et les idees non approuvees. Un statut termine
ne signifie pas une certification Retail ni une publication de tous les
changements locaux ; voir les [versions et telechargements](../README.md#downloads).
Les resultats automatises historiques ne sont pas de nouveaux tests executes
lors de cette revue documentaire.

## Fonctionnalites actuelles a retrouver dans les guides

- Plusieurs ledgers de guilde, approbation GM et sessions Independent Raid
  isolees : [guide Officer](officer/MODE_EMPLOI_GM_OFFICER.md).
- Configuration guidee en trois etapes, publication des Loot Rules et
  reconciliation positive des allocations : [configuration](officer/configuration.md).
- Recherche d'historique, statistiques descriptives, revue de sante et export
  d'audit anonymise : [guide Officer](officer/MODE_EMPLOI_GM_OFFICER.md).
- Signalements prives avec file persistante, reception distincte de la
  resolution, suivi et archivage conserve : [guide joueur](player/MODE_EMPLOI_JOUEUR.md)
  et [contrat de livraison](../specs/025-request-followup-delivery/spec.md).
- Icone de mini-carte deplacable/redimensionnable : publiee en 0.8.9.

Le passage automatique des anciens dossiers partages vers un nouveau
coordinateur/epoch n'est pas implemente : le verrouillage reste explicite.
La livraison multi-client, les acquisitions Vault automatiques et les
parcours UI/proteges exigent toujours leurs controles manuels Retail.

## Statuts

- [x] **Terminee** : implementation et validation automatisee disponibles.
- [~] **Partiellement terminee** : une partie fonctionne, mais un element important reste a faire ou a valider.
- [ ] **A faire** : idee encore non implementee.

## Phase 1 - Core - [x] Terminee
Season model, rank allocations, immutable ledger, balance derivation, permissions foundation.

## Phase 2 - Pre-Dibs - [x] Terminee
Pre-Dib request lifecycle, player UI, Encounter Journal adapter where supported.

## Phase 3 - RCLootCouncil - [x] Terminee
Optional local raid integration and finalized Dib award handling.

## Phase 4 - Distributed Sync - [~] Partiellement terminee
Officer backbone, relay model, reconnect recovery, deduplication, reconciliation.

## Phase 5 - Audit UI - [x] Terminee
Player history, complete officer/GM ledger views, and read-only descriptive player activity statistics by date range.

## Phase 6 - Protected Loot Governance - [~] Partiellement terminee
Curio and Tier Set progression across linked characters, configurable seasonal
policies, Officer-reviewed main/alt relationships, and bounded main-change
probation.

## Plan finalise - 7 ameliorations operationnelles

Ce plan complete les fondations deja presentes dans les phases precedentes. Il
ne remplace pas les regles du ledger, les permissions existantes ou la source
de verite Dibs. Chaque fonctionnalite doit rester guild-scoped, auditable et
utilisable sans RCLootCouncil lorsque cela est pertinent.

### Ordre de livraison

#### Etape 0 - Fondation Great Vault et synchronisation - [~] Partiellement terminee

> Les acquisitions manuelles, les etats de verification, l'idempotence et la synchronisation sont implementes. L'adaptateur de detection automatique est egalement implemente, mais depend des signaux exposes par l'API Retail ; sa validation Retail reste a faire.

Cette etape est la dependance technique de l'indicateur de synchronisation.
L'addon enregistre les acquisitions manuelles avec `/dibs vault` et correle,
lorsque l'API le permet, une reclamation, la reception exacte de l'objet et la
fin des recompenses disponibles. Le reset et la source `GREAT_VAULT` servent
a l'idempotence. Sans preuve fiable, utilisez le parcours manuel et conservez
son statut de verification ; ouvrir le Coffre ne suffit pas.

Les acquisitions Vault sont incluses dans le protocole de synchronisation
avec validation de la guilde, de l'identite du personnage, de la saison et de
la revision. Les donnees ne sont pas envoyees vers GitHub ni vers un service
central; elles restent dans les SavedVariables et les messages addon de la
guilde.

Critere de sortie: une acquisition Vault confirmee apparait une seule fois
chez les clients autorises, une relecture ne cree aucun doublon, et une donnee
non verifiable ne peut pas bloquer silencieusement un joueur.

#### Etape 1 - Assistant de premiere installation - [x] Terminee

> Assistant, dry-run, controles d'autorite et tests de contrat/integration disponibles. La verification visuelle Retail reste une validation de maintenance.

L'assistant guide le GM ou l'Officer a travers la verification de RCLootCouncil,
des permissions, de la saison, des regles de rang, des canaux et des types de
loot. Il propose un test local avant le premier raid et indique clairement
ce qui reste a faire.

Critere de sortie: une nouvelle guilde peut atteindre un etat `Pret pour le
raid` sans modifier manuellement les SavedVariables.

#### Etape 2 - Tableau de sante - [x] Terminee

> Le tableau de sante, les diagnostics de synchronisation, migrations, version et etat RCLootCouncil sont exposes et couverts par les tests.

Une page de diagnostic synthetise la version, la saison active, l'etat de
RCLootCouncil, la derniere sauvegarde, les migrations, la synchronisation et
les avertissements de donnees. Les actions dangereuses restent dans les
outils existants et demandent leurs confirmations habituelles.

Critere de sortie: un GM peut identifier la cause d'un etat `Degrade`,
`Bloque` ou `Non disponible` sans ouvrir les fichiers de donnees.

#### Etape 3 - Notifications joueur - [x] Terminee

> Les notifications locales sont dedoublonnees, persistantes, desactivables et protegees contre l'exposition de donnees d'un autre joueur.

Les notifications couvrent les changements utiles: Pre-Dib accepte ou
annule, attribution finalisee, Dib consomme, demande resolue et acquisition
Vault enregistree. Elles sont discretes, localisees et desactivables pour le
personnage ; elles n'affichent pas l'historique prive d'un autre joueur.

Critere de sortie: chaque notification est idempotente, liee a un evenement
auditable et n'apparait pas plusieurs fois apres une reconnexion.

#### Etape 4 - Recherche et filtres avances - [x] Terminee

> La recherche et les filtres sont disponibles sur les vues d'historique Player et Officer existantes, y compris le Great Vault et l'apercu RCLootCouncil. Les resultats respectent le perimetre et les autorisations de chaque vue et ne correspondent qu'aux metadonnees enregistrees.

Les vues Player et Officer filtrent l'historique selon les champs effectivement
disponibles sur chaque page : joueur, objet, raid, boss, saison, date, statut et
source. Les filtres Officer restent proteges par les memes controles d'acces
que les donnees affichees.

Critere de sortie: un Officer peut retrouver une attribution ou une acquisition
Vault dans un historique volumineux sans parcourir manuellement toute la liste.
Les tests automatises couvrent les filtres et les etats; les scenarios manuels
dans Retail restent a verifier sur un client de jeu.

#### Etape 5 - Centre de sante des donnees et migration - [~] Partiellement terminee

> Le centre de revue Officer est livre pour les references de saison invalides, les acquisitions Vault incompletes ou en double, les acquisitions a verifier et les conflits resolubles dans Vault Review. Les apercus restent en lecture seule; un export de sante distinct ne contient que des compteurs agreges.

Il reste a relier les avertissements de migration et de synchronisation aux
sources qui peuvent les verifier, ainsi qu'a fournir des parcours audites pour
les corrections encore prises en charge. Toute action destructive devra garder
un apercu, une sauvegarde et une confirmation. Les transactions append-only ne
seront jamais reecrites.

Critere de sortie: chaque anomalie prise en charge peut etre examinee, puis
corrigee par son flux audite existant ou exportee pour investigation, avec une
trace appropriee de l'acteur, de la raison et du resultat.

#### Etape 6 - Export d'audit anonymise - [x] Terminee

> Un export d'audit anonymise distinct est disponible dans les Diagnostics Officer. Son contrat et son interface sont couverts par les tests automatises.

Cet export est distinct des packages complets et exclut les identites, notes
privees, permissions et transactions executables. Il fournit une projection
bornee des faits d'audit pris en charge, sans permettre leur reimportation
comme donnees de guilde.

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

## À spécifier - approuvé
- [ ] **Rangs WoW, paliers Dibs et règle main/alt par lockout** : associer les
  rangs WoW à des paliers Dibs sans dupliquer les rangs, faire partager le
  palier et les droits de loot au groupe main/alt approuvé, et exiger le main
  pour les loots protégés pendant une période de raid définie. Prévoir une
  exception de composition limitée demandée par le RL ou le GM pour un alt utile
  à un boss. La spécification doit trancher si l'exception autorise seulement
  la présence ou aussi un loot, et quelle est sa portée temporelle.

## Backlog proposé - Historique et éligibilité avancée
- Deja implemente pour les catalogues et politiques pris en charge : synchroniser
  les options communes de la guilde avec un snapshot de
  configuration versionné : révision, auteur, date, autorisation GM/officier,
  détection des conflits et mise à jour automatique des clients reconnectés.
- Deja implemente : revue de l'historique local RCLootCouncil avec apercu,
  preuve et confirmation Officer avant debit. Une reconstruction automatique
  ou une fusion de l'historique d'une autre guilde n'est pas promise.
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
- [ ] **Rappel des Dibs au Ready Check** : détecter un Ready Check avec Dibs
  autonome, puis afficher les Pre-Dibs actifs connus du client avec l'item et
  le joueur-realm concernés. Regrouper plusieurs Dibs dans une seule fenêtre,
  éviter les répétitions pour un même Ready Check et prévoir un affichage
  personnel, officier ou raid. DBM et BigWigs resteraient optionnels pour une
  intégration supplémentaire au pull ou aux avertissements de boss.

- [~] Profils de règles par raid, boss, difficulté et type de token.
- [~] Mode simulation avant le pull pour afficher les joueurs qui seraient éligibles.
- [x] Gestion des personnages principaux, alts et personnages liés.
- [x] File d'attente hors ligne pour les changements et les récompenses à resynchroniser.
- [~] Détection et résolution des conflits lorsque plusieurs officiers modifient une
  règle en même temps.
- [x] Journal d'audit avec une raison obligatoire pour chaque décision importante.
- [x] Export, import et sauvegarde de l'historique de guilde.
- [ ] Statistiques comparatives d'équité : loots reçus/refusés, priorités et temps d'attente. La page Officer actuelle compte l'activité Dibs par joueur et période, sans score ni classement de l'équité du loot.
- [~] Alertes lorsqu'une règle laisse trop peu de joueurs éligibles.
- [~] Exceptions temporaires pour remplaçants, trials, nouveaux joueurs ou absences.
- [x] Aperçu de l'éligibilité directement dans la fenêtre RCLootCouncil avant le vote.
- [x] Système d'appel ou de contestation d'une décision.
- [x] Interface de diagnostic expliquant pourquoi un joueur est ou n'est pas éligible.
- Tableau de bord web optionnel pour les GM et officiers.
- [x] Assistant de première configuration avec modèles de règles prêts à utiliser.
- [x] Permissions personnalisées par rang ou par officier.
- Explication détaillée de la raison pour laquelle un joueur est éligible ou non.
- [~] Indication de la fraîcheur des données d'inventaire.
- [~] Expiration automatique des anciennes données d'inventaire.
- [x] Archivage et réinitialisation propre à chaque saison.
- [~] Élection automatique d'un relais lorsqu'il y a plusieurs raids actifs.
- [x] Détection des versions RCLootCouncil incompatibles ou trop anciennes.
- [x] Mode test/sandbox pour simuler un loot sans modifier l'historique.
- Import de données provenant d'un rapport de raid ou d'un export.
- Support amélioré des noms inter-royaumes et des personnages de factions différentes.
- [x] Notifications discrètes pour les changements de règles ou les demandes de validation.
- [x] Mode confidentialité pour limiter l'affichage des informations d'inventaire.
- [~] Traductions et personnalisation des messages affichés.
- [x] Système de récupération après corruption des SavedVariables.
- [x] Tests automatisés de scénarios complets : raids multiples, officiers hors ligne,
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
- Statistiques comparatives par joueur et période pour étudier l'équité du loot. La vue actuelle se limite aux comptes descriptifs d'activité Dibs.
- Import et export des règles pour tester une nouvelle politique.
- Protection contre les changements de règles pendant un vote actif.
- Permission de consulter l'historique sans permission de modifier les règles.
- Désactivation temporaire de Dibs pour un raid spécial.
- Consentement des joueurs concernant l'utilisation des données d'inventaire.

### Amélioration de l'information et de l'aide à l'écran à classer
- Ajouter un preset de thème **Minimal** au système existant : surfaces plus
  épurées et hiérarchie visuelle inspirée de la maquette Minimal, avec choix
  persistant par profil et sans changement de navigation ou de comportement
  métier. À valider avant implémentation.
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
