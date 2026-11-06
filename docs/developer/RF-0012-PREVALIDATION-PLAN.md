# RF-0012 — Plan de version de prevalidation

Statut : **PLAN ONLY — NOT BUILT — NOT AUTHORIZED**

Ce document est un **plan**. Il ne contient **aucune modification** du
code, **aucune construction**, **aucune activation**. La version de
prevalidation decrite ici **n'existe pas** et ne sera pas construite
sans une autorisation distincte et explicite.

Objectif : permettre a l'operateur de tester les **operations
canoniques** avec plusieurs clients Retail de test, dans un build
strictement isole, sans que le build publie ne soit affecte.

---

## 1. Pourquoi une version separee est necessaire

Le chemin canonique est doblement verrouille, a deux niveaux
independants :

| Verrou | Emplacement | Role |
|---|---|---|
| `Dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = false` | `src/Core.lua:94` | gate de la **surface protegee** : `ProtectedActions.executeLedgerOperation` refuse la correction si le drapeau n'est pas a `true` |
| `local DISPUTE_OPERATION_WRITES_ENABLED = false` | `src/modules/Ledger.lua:23` | gate de l'**ecriture** : `Ledger.CommitDisputeOperation` refuse d'ecrire si le drapeau n'est pas a `true` |

Les deux sont des **constantes compilees**. Il n'existe :

- **aucun** interrupteur d'execution ;
- **aucune** commande slash qui les change ;
- **aucune** valeur de SavedVariables qui les change.

C'est une decision d'architecture, pas un oubli : le commentaire de
`Core.lua:86-93` dit explicitement que « the release owner changes this
one line in the source and ships a new build ».

La consequence pour la campagne : **la version candidate livree ne peut
pas tester le chemin canonique**, et **la version publiee ne doit
jamais** l'ouvrir. Les deux campagnes sont donc, par construction,
distinctes :

| Campagne | Build | Teste |
|---|---|---|
| **A** (`RETAIL-CAMPAIGN-A-PROCEDURE.md`) | version candidate `0.8.10`, verrous **fermes** | le livrable publie |
| **B** (`rf-0012-retail-test-runbook.md`) | version de **prevalidation**, verrous **ouverts** | le chemin canonique |

## 2. Ce que ce plan ne fait PAS

| Interdit | Raison |
|---|---|
| Modifier le code de production | La session 14 ne modifie aucune source |
| Ouvrir un verrou dans le worktree | Les verrous sont la barriere de securite de la production |
| Creer un contournement par SavedVariables | Un drapeau lisible par l'utilisateur n'est pas un verrou ; le legislateur de la constitution l'interdit (une edition manuelle ne doit pas pouvoir activer une ecriture comptable) |
| Creer un contournement par l'interface | Un bouton « activer le mode canonique » serait une edition de texte de donnees ; l'interface ne doit pas pouvoir activer une ecriture comptable |
| Creer un contournement par commande slash | Idem : `/dibs ...` ne doit pas pouvoir activer une ecriture comptable |
| Construire ou distribuer le build | Aucune autorisation |
| Deployer dans WoW | Aucune autorisation |
| Modifier les SavedVariables reelles | Regle permanente |

**Le seul mecanisme de prevalidation admis** est celui que le
commentaire de `Core.lua` decrit deja : **une revision source
examinee, compilee dans un build separe, identifie par un nom et un
numero de version distincts.**

## 3. Ce qu'exige une version de prevalidation

### 3.1 Les deux verrous

| Fichier | Ligne | Valeur de production | Valeur de prevalidation |
|---|---|---|---|
| `src/Core.lua` | 94 | `Dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = false` | `true` |
| `src/modules/Ledger.lua` | 23 | `local DISPUTE_OPERATION_WRITES_ENABLED = false` | `true` |

Les **deux** doivent etre ouverts. Ouvrir un seul ne suffirait pas :
`ProtectedActions` autorise l'appel, puis `Ledger` refuse l'ecriture —
la correction echouerait avec un motif trompeur
(`CANONICAL_DISPUTE_OPERATIONS_DISABLED` au lieu d'un echec reel).

### 3.2 Un numero de version distinct

`src/RCLootCouncil_dibs.toc` porte `## Version: 0.8.10`. La version de
prevalidation doit porter un numero **distinct**, par exemple
`0.8.10-prevalidation.1`, afin que :

- l'operateur puisse voir, dans le client, qu'il ne teste **pas** la
  version publiee ;
- la campagne B ne puisse pas etre confondue avec la campagne A ;
- un retour en arriere soit sans ambiguite.

**La version de production `0.8.10` n'est pas modifiee.** La version de
prevalidation est produite dans une **copie isolee** de la source, jamais
dans le worktree suivi par git.

### 3.3 Un canal de distribution separe

La version de prevalidation ne doit **jamais** etre distribuee par le
workflow de publication. Elle est produite par une procedure manuelle,
distincte de `RELEASE-CANDIDATE-PROCEDURE.md`, avec :

- un **nom d'archive** different
  (`RCLootCouncil_dibs-0.8.10-prevalidation.1-*.zip`) ;
- une **empreinte SHA-256** propre ;
- un **manifeste** propre ;
- un emplacement de stockage **separe** de celui des livrables.

## 4. Conditions necessaires pour tester les operations canoniques

Ces conditions sont **independantes** du build. Le build prevalidation
ouvre la porte ; ces conditions decident si une operation canonique
peut reellement aboutir. Si l'une manque, l'echec est **normal** et
doit etre lu comme tel, pas comme un defaut.

### 4.1 Cote client (chaque client)

| # | Condition | Verifiable par |
|---|---|---|
| C1 | Le client est dans la guilde de test, avec un roster **vivant** | onglet Synchronisation : le nom du coordinateur affiche est le vrai Maitre de guilde |
| C2 | Le client a un **SavedVariables propre** | quatre repertoires de jeu distincts |
| C3 | La version prevalidation est installee et **seule** dans `AddOns` | l'onglet Integration affiche la version |
| C4 | Aucune erreur Lua au chargement | `/console scriptErrors 1`, journal de chat |

### 4.2 Cote guilde (etabli une fois)

| # | Condition | Pourquoi |
|---|---|---|
| G1 | La gouvernance est **adoptee** | `Ledger.CommitDisputeOperation` exige `v2Enforced()` |
| G2 | Le baseline historique est **approuve** | l'ecriture canonique refuse un historique non resolu |
| G3 | Un **coordinateur** est etabli (autorite ACTIVE) | seule l'autorite active accepte |
| G4 | L'epoch du coordinateur est **connue** de tous | un epoch perime est refuse |
| G5 | Les clients sont **a jour** de la chaine canonique | un ecart de sequence est refuse |
| G6 | Le ledger actif est **approuve** | `LEDGER_NOT_APPROVED` refuse l'ecriture |
| G7 | La politique operationnelle est **adoptee** | exigence de la porte de disponibilite |

### 4.3 Pourquoi ces conditions sont une barriere reelle

Elles ne sont pas une checklist de confort. Le code les verifie
**avant** toute mutation :

- `Ledger.CommitDisputeOperation` (`Ledger.lua:1983+`) verifie, dans
  cet ordre : le verrou d'ecriture, la **porte de disponibilite**
  partagee, l'echec de validation, la correspondance de ledger, le
  protocole V2 impose, l'**autorite active**, l'**autorisation** de
  l'acteur, l'**identite** de l'acteur, l'**autorisation par entree**,
  la **suffisance de solde**, le **curseur canonique**, puis l'absence
  de **conflit d'identifiant de transaction**.

Un refus dans cette liste est un **comportement correct**. La campagne
doit le consigner comme tel, avec le motif verbatim.

## 5. Conditions de rejet attendues (et non des defauts)

Pendant la campagne B, les refus suivants sont **normaux** et doivent
etre observes comme des **reussites** de la barriere :

| Motif | Signification | Ce que l'operateur doit faire |
|---|---|---|
| `CANONICAL_DISPUTE_OPERATIONS_DISABLED` | le build n'a pas le verrou ouvert | verifier le build |
| `OPERATION_READINESS_UNKNOWN` | la porte de disponibilite n'a pas repondu | verifier G1 a G7 |
| `V2_ENFORCED_REQUIRED` | la gouvernance n'est pas adoptee | etablir G1 |
| `COORDINATOR_UNAVAILABLE` | aucune autorite active | etablir G3 |
| `PROPOSER_NOT_AUTHORIZED` | l'acteur n'est pas le coordinateur | verifier le roster |
| `LEDGER_NOT_APPROVED` | le ledger actif n'est pas approuve | etablir G6 |
| `LEDGER_SCOPE_MISMATCH` | l'operation ne vise pas le ledger attendu | corriger la cible |
| `INSUFFICIENT_BALANCE` | le solde ne couvre pas la correction | corriger les donnees de test |
| `LEDGER_GAP` | le client a un ecart de sequence | rattraper d'abord |
| `OPERATION_ID_CONFLICT` | l'identifiant d'operation existe avec un contenu different | verifier l'identite |
| `TRANSACTION_ID_CONFLICT` | l'identifiant de transaction existe deja | utiliser un autre jeu de donnees |

## 6. Conditions de refus qui seraient des DEFAUTS

Ceux-ci, a l'inverse, seraient des **defauts** et bloqueraient la
publication :

| Situation | Defaut |
|---|---|
| L'ecriture passe malgre un des verrous | barriere de securite rompue |
| Deux commits pour une meme operation | non-idempotence |
| Un solde modifie alors que l'ecriture est refusee | mutation partielle |
| Une transaction d'origine reecrite | violation de l'append-only |
| Un client applique un enregistrement d'une **autre** guilde | fuite de donnees |
| Un client accepte un epoch **perime** | failover non respecte |
| Le rapport historique applique une correction | lecture non read-only |
| Un joueur voit le dossier d'un autre | fuite de confidentialite |

## 7. Ce que la campagne B ne peut pas valider

Meme avec le build de prevalidation, la campagne B **ne valide pas** :

| Ce qui reste non valide | Pourquoi |
|---|---|
| Le livrable publie | Le build de prevalidation n'est pas le build publie ; la campagne A le teste |
| La compatibilite de donnees d'un **upgrade reel** | La campagne A couvre l'upgrade sur la version candidate |
| La stabilite en production | La prevalidation est un environnement de test a 4 clients, pas une population reelle |
| La performance en charge | Le banc de performance (`DIBS_PERF_BENCH=1`) est automatise ; la campagne ne mesure pas la charge Retail |

## 8. Autorisations requises

Chaque ligne est une **autorisation distincte**. Aucune n'est accordee
par ce document.

| # | Autorisation | Demandee a | Pourquoi |
|---|---|---|---|
| **AUT-1** | Construire une version de prevalidation dans une copie isolee | proprietaire du projet | le build ecrit dans le code de production |
| **AUT-2** | Utiliser le numero `0.8.10-prevalidation.1` | proprietaire du projet | reserve aux livrables publies |
| **AUT-3** | Executer la campagne B sur 4 clients Retail de test | proprietaire du projet | ouvre le chemin canonique en environment reelle |
| **AUT-4** | Etablir la gouvernance, le baseline et l'autorite dans la guilde de test | proprietaire du projet | ecrit dans les SavedVariables de la guilde de test |
| **AUT-5** | Modifier la version TOC de la copie de prevalidation | proprietaire du projet | `## Version:` est une surface de release |
| **AUT-6** | Utiliser un client volontairement incompatible pour le scenario S5 | proprietaire du projet | le client incompatible est une **intention** de test |

**AUT-6 merite une attention particuliere.** Le scenario S5 du runbook
necessite un client qui **refuse** le message d'operation — donc un
client d'une version **differente**. Cela ne se fait **pas** en
desactivant une securite : cela se fait en installant une version
**reellement anterieure** sur ce client, ou une version baclee
volontairement incompatible. Desactiver
`CANONICAL_OPERATIONS_RELEASE_ENABLED` pour simuler l'incompatibilite
**fausserait** l'observation : le client refuserait pour une **autre**
raison que celle qu'on cherche a observer.

## 9. Procedure de preparation (a executer seulement apres AUT-1 a AUT-6)

1. Copier la source dans un repertoire **hors du worktree** et hors du
   depot.
2. Dans cette copie, ouvrir les **deux** verrous (3.1) et poser le
   numero de version de prevalidation (3.2).
3. Executer les **memes portes de verification** que
   `RELEASE-CANDIDATE-PROCEDURE.md` : fichiers requis, ordre du TOC
   (dans les deux sens), bibliotheques intactes, Lua 5.1, declarations
   SavedVariables, `OptionalDeps`. **La porte des verrous est
   inversee** : elle doit constater `true` sur les deux, et c'est la
   seule porte qui differe.
4. Produire l'archive avec un **nom distinct** et une empreinte
   propre (3.3).
5. Installer sur les clients de test, **apres** sauvegarde des
   SavedVariables.
6. Executer `rf-0012-retail-test-runbook.md` §1 a §3, puis les
   scenarios S1 a S14 dans l'ordre, en consignant les 20 observations
   dans `rf-0012-retail-validation.md` §5.
7. A la fin, restaurer les SavedVariables et l'addon de chaque client
   (runbook §7).

## 10. Regles permanentes

Meme apres autorisation :

- La version **publiee** garde `false` sur les deux verrous. La
  prevalidation n'est **jamais** publiee.
- Le numero de version de production n'est **jamais** incremente par
  cette procedure.
- Les SavedVariables **reelles** ne sont **jamais** editees a la main.
- Le worktree suivi par git n'est **jamais** modifie pour cette
  campagne.
- `OfficerUI.lua:3632` reste exclu.
- T041 reste `PENDING_MANUAL_VALIDATION` tant que les 20 observations
  ne sont pas remplies avec des resultats reels.
