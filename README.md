# RCLootCouncil_dibs

RCLootCouncil_dibs est un addon World of Warcraft pour la gestion des Dibs de guilde, avec:
- saisons,
- allocations par rang,
- historique comptable,
- pré-réservations,
- intégration optionnelle avec RCLootCouncil,
- synchronisation de structure de données entre raids.

L’objectif principal est simple :

> RCLootCouncil gère la session locale de loot. RCLootCouncil_dibs gère le livre de comptes des Dibs de guilde.

## Fonctionnalités livrées

- gestion d’une saison courante,
- règle d’allocation par rang,
- calcul du solde déduit du ledger,
- historique des transactions,
- création de pré-Dibs,
- commandes slash /dibs,
- panneau joueur,
- panneau officier,
- support d’intégration RCLootCouncil et Encounter Journal,
- stockage SavedVariables versionné.

## Utilisation

### Commandes slash

- /dibs help
- /dibs balance
- /dibs ui
- /dibs officer
- /dibs grant <joueur> <montant>
- /dibs use <joueur> <montant>
- /dibs pre <itemID> [nom]
- /dibs season create [nom]
- /dibs season set <id>
- /dibs season list
- /dibs rank set <index> <montant> [nom]
- /dibs rank list

### Panneaux

- panneau joueur : état de saison, solde et pré-Dibs actifs,
- panneau officier : saisons, historique des transactions et règles de rang.

## Structure du dépôt

- src/Core.lua : point d’entrée et initialisation,
- src/modules : moteur de logique métier,
- src/integrations : connecteurs optionnels,
- src/ui : interfaces joueur/officier,
- locales : fichiers de localisation,
- docs : documentation du projet et architecture.

## Notes de design

- le ledger est la source de vérité,
- les transactions sont immuables,
- les intégrations UI ne doivent pas porter la logique métier,
- le noyau reste fonctionnel sans RCLootCouncil.

## Licence

MIT.
