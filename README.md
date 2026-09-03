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
- /dibs admin list
- /dibs admin add <Nom-Royaume>
- /dibs admin remove <Nom-Royaume>

### Panneaux

- panneau joueur : état de saison, solde et pré-Dibs actifs,
- panneau officier : saisons, historique des transactions et règles de rang.

## Structure du dépôt

- src/Core.lua : point d’entrée et initialisation,
- src/modules : moteur de logique métier,
- src/integrations : connecteurs optionnels,
- src/ui : interfaces joueur/officier,
- src/locales : fichiers de localisation anglais et français chargés depuis la racine de l’addon empaqueté,
- docs : documentation du projet et architecture.

## Notes de design

- le ledger est la source de vérité,
- les transactions sont immuables,
- les intégrations UI ne doivent pas porter la logique métier,
- le noyau reste fonctionnel sans RCLootCouncil.

## Autorité et compatibilité RCLootCouncil

RCLootCouncil est une dépendance optionnelle. Lorsqu’une instance compatible est chargée, activée et possède un maître du butin vérifiable, ce maître du butin est l’autorité exclusive pour toutes les actions Dibs protégées. Une décision négative n’est jamais remplacée par les permissions autonomes. Une installation présente mais incompatible ou incomplètement initialisée échoue de façon fermée et affiche un diagnostic.

En l’absence de RCLootCouncil, seul le maître de guilde est autorisé par défaut. Il peut nommer ou révoquer explicitement des administrateurs Dibs avec les commandes `/dibs admin`. Le statut d’officier, de chef de raid ou d’assistant de raid n’accorde aucun droit Dibs automatiquement. Les nominations et révocations sont conservées dans un historique; l’identité utilise le GUID lorsque le client peut le fournir, avec `Nom-Royaume` comme solution de repli.

L’adaptateur actuel est testé contre des surfaces synthétiques correspondant à RCLootCouncil Retail 3.x : instance AceAddon récupérable, indicateur `enabled`, identité `masterLooter`, enregistrement de messages Ace et événement local `RCMLAwardSuccess`. Ces éléments sont détectés comme des capacités, et non considérés comme une API stable. Une version inconnue reste utilisable en standalone seulement si RCLootCouncil est réellement absent ou désactivé; si elle est chargée mais incompatible, les actions protégées sont refusées.

Les attributions finales compatibles sont traduites en transactions Dibs identifiées par une référence idempotente. Les réponses en attente, les échecs et les événements mal formés ne consomment aucun Dib. Le ledger Dibs demeure suffisant pour reconstruire les soldes et l’historique.

La projection du solde et du Pré-Dib des candidats est disponible localement. L’intégration directe dans une surface RCLootCouncil est conditionnée à la détection d’une capacité compatible; sinon, l’interface Dibs locale sert de repli. Les candidats, votes, réponses et données de session ne sont jamais envoyés aux autres raids par la synchronisation.

## Sécurité en combat

Les calculs métier et les écritures ordinaires dans le ledger restent synchrones pendant le combat. Seules les opérations pouvant créer, afficher, déplacer ou reconfigurer une interface protégée sont reportées jusqu’à `PLAYER_REGEN_ENABLED`. L’addon n’automatise aucune action protégée de World of Warcraft et ne remplace pas les fonctions internes de RCLootCouncil.

## État de livraison

Le dépôt contient le modèle d’autorité centralisé, l’administration standalone, l’enregistrement idempotent des attributions, la projection locale des candidats, les limites de synchronisation et les ressources de localisation. La validation complète en client WoW Retail et la certification de nouvelles versions de RCLootCouncil restent des activités de compatibilité continues; consultez le guide de validation de la fonctionnalité 003 avant une publication.

## Licence

MIT.
