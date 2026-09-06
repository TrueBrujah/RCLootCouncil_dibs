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
- /dibs dev on
- /dibs dev off
- /dibs dev status
- /dibs testitem <itemID>

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

Voir aussi [docs/DEVELOPER_MODE.md](docs/DEVELOPER_MODE.md) pour le flux de test local Developer Mode.

## Autorité et compatibilité RCLootCouncil

RCLootCouncil est une dépendance optionnelle. Le mode d’installation peut être `AUTO`, `STANDALONE` ou `RCLootCouncil`, et il est conservé dans les SavedVariables de la guilde. Dans les deux modes, seul le GM ou un officier vérifié dans le roster de guilde peut modifier les règles, le mode, les saisons, les allocations ou le ledger Dibs. Le statut de conseil, de chef de raid ou d’assistant de raid ne donne aucun droit d’administration Dibs.

La limite des rangs considérés comme officiers est configurable dans les options Dibs (`Highest officer rank index`); le rang 0 est toujours le GM et les rangs 1 à cette limite sont les officiers par défaut.

RCLootCouncil reste responsable de sa propre session de butin. Dans Retail, son Master Looter est le Raid Leader; un Raid Assistant n’est pas automatiquement Master Looter. Le Master Looter peut gérer le butin et finaliser les décisions dans RCLootCouncil. Une décision finalisée dont la réponse est explicitement `DIB` peut déclencher la consommation automatique d’un Dib; cela ne permet pas au Master Looter d’ajouter, retirer ou régler arbitrairement des Dibs. Une installation RCLootCouncil chargée mais incompatible refuse les actions protégées dont l’autorité ne peut pas être vérifiée.

Les commandes `/dibs admin add` et `/dibs admin remove` sont conservées pour l’historique des anciennes installations, mais ces nominations ne confèrent plus de droits à un joueur qui n’est ni GM ni officier.

L’adaptateur actuel est testé contre des surfaces synthétiques correspondant à RCLootCouncil Retail 3.x : instance AceAddon récupérable, indicateur `enabled`, identité `masterLooter`, enregistrement de messages Ace et événement local `RCMLAwardSuccess`. Ces éléments sont détectés comme des capacités, et non considérés comme une API stable. Une version inconnue reste utilisable en standalone seulement si RCLootCouncil est réellement absent ou désactivé; si elle est chargée mais incompatible, les actions protégées sont refusées.

Les attributions finales compatibles sont traduites en transactions Dibs identifiées par une référence idempotente. Les réponses en attente, les échecs et les événements mal formés ne consomment aucun Dib. Le ledger Dibs demeure suffisant pour reconstruire les soldes et l’historique.

La projection du solde et du Pré-Dib des candidats est disponible localement. L’intégration directe dans une surface RCLootCouncil est conditionnée à la détection d’une capacité compatible; sinon, l’interface Dibs locale sert de repli. Les candidats, votes, réponses et données de session ne sont jamais envoyés aux autres raids par la synchronisation.

## Sécurité en combat

Les calculs métier et les écritures ordinaires dans le ledger restent synchrones pendant le combat. Seules les opérations pouvant créer, afficher, déplacer ou reconfigurer une interface protégée sont reportées jusqu’à `PLAYER_REGEN_ENABLED`. L’addon n’automatise aucune action protégée de World of Warcraft et ne remplace pas les fonctions internes de RCLootCouncil.

## État de livraison

Le dépôt contient le modèle d’autorité centralisé, l’administration standalone, l’enregistrement idempotent des attributions, la projection locale des candidats, les limites de synchronisation et les ressources de localisation. La validation complète en client WoW Retail et la certification de nouvelles versions de RCLootCouncil restent des activités de compatibilité continues; consultez le guide de validation de la fonctionnalité 003 avant une publication.

## Workflow Spec-Kit (sans changer de branche)

Spec-Kit est installé une seule fois à la racine du dépôt via `.specify/` et `.github/skills/`.
Il ne doit pas être réinstallé dans chaque dossier `specs/*`.

Pour changer de feature active sans changer de branche Git:

```powershell
pwsh scripts/select-spec.ps1 001-dibs-core
# ou
pwsh scripts/select-spec.ps1 003-rclootcouncil-integration
```

Notes:

- cette commande met à jour `.specify/feature.json` seulement;
- la branche Git courante reste inchangée;
- les commandes `/speckit-*` doivent être lancées depuis Copilot Chat (intégration IDE), pas via un CLI Copilot externe.

## Licence

MIT.
