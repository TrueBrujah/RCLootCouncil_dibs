# Retail campaign A — procedure operateur

Statut : **PREPARED — NOT EXECUTED**

Cette procedure est la **campagne A** de la campagne Retail. Elle couvre
les 13 scenarios de la campagne A identifies dans
`RETAIL-TEST-MATRIX-RECONCILED.md` — ceux que la campagne T041 **ne
couvre pas** : installation, declaration main/alt, Pre-Dibs, attribution
et reservation de Dib, sauvegarde et restauration, synchronisation,
compatibilite RCLootCouncil, mode independant, interface reelle.

Elle est **distincte** de la campagne T041 (`rf-0012-retail-test-runbook.md`),
qui teste le chemin canonique sur une version de prevalidation.

**Aucune observation ne peut devenir `MANUAL_PASS` sans une execution
reelle par un operateur dans WoW Retail.** Ce document est la procedure ;
il n'est pas un resultat.

---

## 0. Ce que cette campagne exige de l'operateur

| Element | Exigence |
|---|---|
| Temps | une seance de 2 a 3 heures |
| Guild | une guilde de test dediee, avec au moins 4 membres reels |
| Comptes | 4 comptes distincts, ou 4 repertoires de jeu distincts |
| Build | la **version candidate** `0.8.10` (chemin canonique **ferme**) |
| Sauvegarde | une sauvegarde complete avant la premiere action |
| Tenue | un fichier de notes, ou chaque observation est ecrite **en direct** |

**Regle de discipline.** Les notes se remplissent **en observant**, pas
apres coup. Une observation notee apres coup « d'apres le code » ne
vaut rien : c'est precisement ce que la campagne doit empecher.

---

## 1. Preparation de l'environnement

### 1.1 Guilde et roster

Creer une guilde de test dediee avec au moins quatre personnages :

| Emplacement | Rang requis | Role dans la campagne |
|---|---|---|
| A — Coordinateur | Maitre de guilde | Seul client autorise a modifier la chaine canonique |
| B — Officier | Officier (index de rang 1) | Propose, ne modifie **rien** localement |
| C — Joueur | Membre | Consomme les gains, ne voit aucun dossier d'officier |
| D — Joueur deconnecte | Membre | Se deconnecte, manque des messages, se reconnecte |

Verifier le roster **dans le jeu** : l'officier doit etre un vrai
officier (index de rang 1), le coordinateur un vrai Maitre de guilde
(index 0). Un role revendique n'est pas une autorite : l'addon lit le
roster vivant.

### 1.2 Comptes distincts

Chaque personnage doit avoir son **propre compte** (ou son propre
repertoire de jeu), sinon les quatre clients partagent un seul fichier
SavedVariables et les observations de convergence n'ont aucun sens.

### 1.3 Construction de la version candidate

Suivre `RELEASE-CANDIDATE-PROCEDURE.md`. La version candidate garde le
chemin canonique **ferme** : `CANONICAL_OPERATIONS_RELEASE_ENABLED = false`
et `DISPUTE_OPERATION_WRITES_ENABLED = false`.

**La campagne A ne teste pas le chemin canonique.** Elle teste le
livrable tel qu'il sera publie. La campagne T041 est separee et necessite
une version de prevalidation (voir `RF-0012-PREVALIDATION-PLAN.md`).

### 1.4 Sauvegarde prealable des SavedVariables

**Obligatoire avant toute action.** Pour chaque client :

```powershell
# Exemple pour un client Windows
$wtf = 'C:\Games\World of Warcraft\_retail_\WTF\Account\<ACCOUNT>\<REALM>\SavedVariables'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = "C:\DibsRetailBackup\$stamp"
New-Item -ItemType Directory -Path $backup -Force | Out-Null
foreach ($name in @('RCLootCouncil_dibs.lua','RCLootCouncil_dibsLocalDB.lua','RCLootCouncil_dibsSandboxDB.lua')) {
    $src = Join-Path $wtf $name
    if (Test-Path $src) { Copy-Item $src (Join-Path $backup $name) -Force }
}
```

| Fichier | Contenu | Role |
|---|---|---|
| `RCLootCouncil_dibs.lua` | donnees de guilde (ledger, saisons, litiges, governance) | **essentiel** a sauvegarder |
| `RCLootCouncil_dibsLocalDB.lua` | presentation locale par personnage | a restaurer pour revenir a l'etat initial |
| `RCLootCouncil_dibsSandboxDB.lua` | store du bac a sable developpeur | facultatif, sans effet sur la production |

La sauvegarde doit etre **hors du repertoire du jeu** et **hors du
depot**, pour qu'un nettoyage de l'un ne supprime pas l'autre.

### 1.5 Installation isolee de la candidate

```powershell
# Exemple pour un client Windows
$source = 'C:\Users\<user>\RCLootCouncil_dibs-candidate-<stamp>\RCLootCouncil_dibs'
$target = 'C:\Games\World of Warcraft\Interface\AddOns\RCLootCouncil_dibs'
if (Test-Path $target) { Move-Item $target "$target.aside-$(Get-Date -Format 'yyyyMMdd-HHmmss')" }
New-Item -ItemType Directory -Path $target | Out-Null
Copy-Item -Path (Join-Path $source '*') -Destination $target -Recurse -Force
```

L'ancien dossier est **deplace**, pas supprime : il permet un retour
en arriere immediat. Rien n'est deploye automatiquement ; la copie est
faite a la main, puis le client est lance a la main.

### 1.6 Verification du chargement

Sur **chaque** client, avant tout scenario :

1. Verifier que le journal de chat ne contient **aucune** erreur Lua
   (`/console scriptErrors 1` pour rendre les erreurs visibles).
2. Verifier que l'onglet Joueur s'ouvre et affiche l'etat de la saison.
3. Verifier que la fenetre Officier s'ouvre pour A et B, et **qu'elle
   n'expose pas** les actions de configuration de guilde pour B.
4. **Ecrire** le resultat dans le fichier de notes.

Un client qui ne charge pas correctement **bloque** la campagne : le
diagnostiquer d'abord, ou corriger la cause et recommencer la campagne
depuis 1.4.

---

## 2. Creation des donnees de test

**Regle absolue : les SavedVariables reelles ne sont jamais editees a
la main.** Toutes les donnees de test sont creees par le parcours de
l'addon lui-meme.

| # | Etape | Client | Resultat attendu | Observation |
|---|---|---|---|---|
| 2.1 | Verifier la saison active | A | La saison affichee est la saison de test creee pour la campagne | saison affichee |
| 2.2 | Verifier l'allocation de saison | A | Chaque membre test a une allocation de saison non nulle | allocation par membre |
| 2.3 | Creer une allocation de test pour C | A, via le parcours **Officer → Saison** | C a une allocation positive | solde de C avant |
| 2.4 | Noter le solde initial de C | tous | Le solde est note **avant** toute operation | solde, nombre de transactions |

L'allocation doit etre faite par le **parcours de l'interface**, pas
par un fichier. Cela verifie au passage que la surface de configuration
fonctionne.

---

## 3. Declaration main/alt (scenario 3.8)

| # | Etape | Client | Resultat attendu | Observation |
|---|---|---|---|---|
| 3.1 | B (ou C) declare une relation main/alt via la surface joueur | B | Une demande de declaration est creee, au statut **en attente** | identifiant de la declaration, statut |
| 3.2 | Verifier qu'aucune **donnee** n'a bouge | B | Solde, transactions, groupes inchanges | solde, nombre de transactions |
| 3.3 | La declaration apparait dans l'onglet d'eligibilite de l'officier | A | La declaration est **listee** | capture de l'onglet |
| 3.4 | A approuve la declaration | A | Statut **approuve** ; le groupe est cree | statut, identifiant de groupe |
| 3.5 | Verifier la portee du groupe | A, B | Le groupe couvre **exactement** les deux caracteres concernes | membres du groupe |
| 3.6 | Verifier l'absence de fuite | C | C ne voit **aucun** dossier de la declaration | ce que C voit |
| 3.7 | A **refuse** une seconde declaration avec un motif | A | Statut **refuse**, motif visible, **aucune** donnee comptable modifiee | motif, solde avant/apres |
| 3.8 | A tente de refuser **sans** motif | A | Le refus est **refuse** ; la declaration reste en attente | message |

**Condition PASS** : la declaration est listee, approuvable, refusable
avec motif, refusable sans motif refuse, et aucune donnee comptable ne
bouge. **Condition FAIL** : la declaration est invisible dans
l'interface, ou une approbation modifie une donnee comptable, ou une
fuite vers un autre joueur.

---

## 4. Pre-Dibs (scenarios 4.1 a 4.6)

### 4.1 Pre-Dibs publics desactives

| # | Etape | Client | Resultat attendu | Observation |
|---|---|---|---|---|
| 4.1.1 | A desactive les Pre-Dibs publics (parcours **Officer → Pre-Dibs**) | A | Le mode public est **desactive** | mode affiche |
| 4.1.2 | C tente de soumettre une demande publique | C | La soumission est **refusee** avec un motif clair | motif verbatim |
| 4.1.3 | Verifier qu'**aucune** demande n'a ete creee | C | Le compteur de demandes est **inchange** | nombre de demandes avant/apres |

**C'est l'observation la plus importante de la section** : le refus doit
etre accompagne d'une **absence d'ecriture**. Une demande creee et
refusee apres coup serait un defaut.

### 4.2 Pre-Dibs publics activees

| # | Etape | Client | Resultat attendu | Observation |
|---|---|---|---|---|
| 4.2.1 | A reactive les Pre-Dibs publics | A | Le mode public est **active** | mode affiche |
| 4.2.2 | C soumet une demande publique | C | La demande est creee, statut **en attente** | identifiant, statut, item |
| 4.2.3 | Verifier la portee de la demande | C | La demande porte **le** joueur C et **son** item | identite et item |

### 4.3 Pre-Dibs prives

| # | Etape | Client | Resultat attendu | Observation |
|---|---|---|---|---|
| 4.3.1 | C cree une demande privee | C | Demande creee, statut **en attente** | identifiant, statut |
| 4.3.2 | C annule sa demande | C | Statut **annule** | statut, nombre de demandes actives |
| 4.3.3 | D tente d'annuler la demande de C | D | Refus ; la demande de C est **intacte** | motif, statut de la demande de C |

### 4.4 Integrite de la portee de ledger

| # | Etape | Client | Resultat attendu | Observation |
|---|---|---|---|---|
| 4.4.1 | Verifier le ledger de la demande de C | C | La demande est dans **un seul** ledger, jamais dupliquee | nombre de demandes par ledger |

---

## 5. Attribution et reservation de Dib (scenarios 5.1 a 5.7)

| # | Etape | Client | Resultat attendu | Observation |
|---|---|---|---|---|
| 5.1 | A attribue un objet a C dans un contexte de test | A | L'evenement d'attribution est enregistre | item, identifiant d'attribution |
| 5.2 | Verifier la reservation | C | Le solde **disponible** est inferieur au solde brut d'une reservation | solde brut, reservations, solde disponible |
| 5.3 | La reservation est liberee (proposition terminale) | A | Le solde disponible **revient** a la valeur brute | solde disponible avant/apres |
| 5.4 | Verifier qu'une reservation ne ressuscite pas | A, C | Apres reconnexion, la reservation reste liberee | solde disponible apres reconnexion |
| 5.5 | C consomme un Dib sur une attribution | C | Le solde diminue d'**exactement** un | solde avant/apres, nombre de transactions |
| 5.6 | Un joueur sans solde ne peut pas consommer | C | La consommation est refusee | motif |
| 5.7 | Le solde ne devient jamais negatif | C | Solde **>= 0** a chaque etape | solde a chaque observation |

**Condition PASS** : la reservation est visible, sa liberation est
reversible une seule fois, la consommation est exacte, et le solde ne
devient jamais negatif. **Condition FAIL** : une reservation fantome,
une double liberation, une double consommation, ou un solde negatif.

---

## 6. Sauvegarde, restauration et importation (scenario 7.11)

| # | Etape | Client | Resultat attendu | Observation |
|---|---|---|---|---|
| 6.1 | A cree une sauvegarde complete (**Officer → Donnees → Sauvegarder**) | A | L'instantane est cree et **liste** | identifiant de l'instantane, taille, empreinte |
| 6.2 | A modifie le ledger (attribution de test) | A | Le ledger bouge | solde, nombre de transactions |
| 6.3 | A restaure l'instantane via l'apercu puis la confirmation | A | L'etat **precedent** est retrouve ; l'instantane de securite est cree | solde apres, nombre de transactions apres |
| 6.4 | Verifier qu'aucune chaine partagee n'a recule | A | Saison, politique, governance : inchanges | revisions avant/apres |
| 6.5 | A tente d'appliquer une sauvegarde d'une autre guilde | A | La restauration est **refusee** | motif |
| 6.6 | A importe un paquet de configuration de guilde | A | La configuration est importee **apres** apercu et confirmation | apercu, resultat |

**Condition PASS** : la restauration est fidele, les chaines partagees ne
reculent pas, la restauration transversale est refusee. **Condition FAIL** :
perte de transaction, recul d'une chaine partagee, ou restauration
transversale acceptee.

---

## 7. Synchronisation (scenario 6.9)

Ce scenario suit la procedure a quatre clients de
`RETAIL-TEST-MATRIX-RECONCILED.md` section 4. Resume :

| # | Etape | Client | Resultat attendu | Observation |
|---|---|---|---|---|
| 7.1 | Noter l'etat de synchronisation des quatre clients | A, B, C, D | epoch, sequence, racine par client | les 12 valeurs |
| 7.2 | B propose une operation sur un element reel | B | Rien ne change **localement** sur B | solde, transactions, sequence avant/apres |
| 7.3 | D se deconnecte du canal de guilde | D | — | — |
| 7.4 | A accepte l'operation | A | Un seul changement canonique | sequence avant/apres, identifiant d'operation |
| 7.5 | C converge | C | epoch, sequence, racine, solde **identiques** a A | les 4 valeurs de C et de A |
| 7.6 | Redelivrer le message a C | C | **Aucun** changement | solde, sequence, nombre de transactions |
| 7.7 | D se reconnecte | D | Les commits manquants sont appliques **dans l'ordre** | epoch, sequence, racine, solde de D |
| 7.8 | A fait un `/reload` | A | Les memes valeurs, un seul commit | sequence, racine, nombre de transactions |
| 7.9 | C tente une operation avec un **epoch perime** | C | **Refus** avec motif | motif verbatim |
| 7.10 | C tente une operation vers un **ledger incorrect** | C | **Refus** avec motif | motif verbatim |
| 7.11 | A ouvre le rapport de correction historique | A | Il **classe** et n'applique **rien** | comptes de classification, solde avant/apres |

**Condition PASS** : les quatre clients convergent, une operation =
un commit, une redelivrance ne change rien, les epoch perimes et
ledgers incorrects sont refuses, et le rapport historique n'applique
rien. **Condition FAIL** : divergence, doublon, application d'un
enregistrement refuse, ou mutation par le rapport.

---

## 8. Compatibilite RCLootCouncil (scenario 10.5)

| # | Etape | Client | Resultat attendu | Observation |
|---|---|---|---|---|
| 8.1 | Verifier la disponibilite de RC (**Officer → Integration**) | A | « operationnel » si RC est installe, « absent » sinon | statut affiche |
| 8.2 | Partager un vote RC de test | A | RC affiche le vote ; l'addon n'ecrit **rien** dans le ledger de Dibs | solde avant/apres, nombre de transactions |
| 8.3 | Cliquer la reponse Dib sur un joueur **non eligible** | C | La reponse est **refusee** | message, solde inchange |
| 8.4 | Verifier que l'addon ne modifie pas l'historique de RC | A | L'historique RC est **inchange** par l'addon | capture avant/apres |

**Condition PASS** : RC est lu sans ecriture, le clic DIB d'un joueur non
eligible est refuse, et aucun historique n'est modifie par l'addon.

---

## 9. Mode independant et interface (scenarios 11.4, 12.5, 12.6, 13.3, 14.4)

| # | Etape | Client | Resultat attendu | Observation |
|---|---|---|---|---|
| 9.1 | Activer le mode independant, jouer un Evenement | C | **Aucune** donnee de production n'est ecrite | solde de production avant/apres |
| 9.2 | En combat : tenter une action bloquante | C | L'action est **differee**, jamais executee en combat | message |
| 9.3 | Naviguer dans les deux fenetres, tous les onglets | A, C | Chaque onglet s'ouvre, l'aide contextuelle s'affiche | une capture par onglet |
| 9.4 | Redimensionner la fenetre en etroit et en large | A | Aucun element tronque, aucun chevauchement | captures |
| 9.5 | Forcer une interruption entre l'acceptation canonique et la projection, puis `/reload` | A | Les projections sont **reconstruites**, **un seul** commit | sequence, racine, nombre de commits |

---

## 10. Retour a l'etat initial

A la fin de la campagne, ou apres un echec :

```powershell
# 1. Fermer le jeu completement sur chaque client.
# 2. Restaurer les SavedVariables de chaque client.
$wtf   = 'C:\Games\World of Warcraft\_retail_\WTF\Account\<ACCOUNT>\<REALM>\SavedVariables'
$from  = 'C:\DibsRetailBackup\<stamp>'
foreach ($name in @('RCLootCouncil_dibs.lua','RCLootCouncil_dibsLocalDB.lua','RCLootCouncil_dibsSandboxDB.lua')) {
    $src = Join-Path $from $name
    if (Test-Path $src) { Copy-Item $src (Join-Path $wtf $name) -Force }
}
# 3. Restaurer l'addon installe.
Move-Item 'C:\Games\World of Warcraft\Interface\AddOns\RCLootCouncil_dibs.aside-<stamp>' 'C:\Games\World of Warcraft\Interface\AddOns\RCLootCouncil_dibs'
```

La procedure detaillee est dans `rf-0012-retail-test-runbook.md` §7.

---

## 11. Fiche de resultat

Une ligne par scenario. **Aucune ligne ne peut porter `MANUAL_PASS`
avant l'observation ecrite.**

| # | Scenario | Statut | Resultat observe | Preuve jointe | Note |
|---|---|---|---|---|---|
| 1.4 | Redemarrage de WoW | `MANUAL_PENDING` | | | |
| 3.8 | Surface de revue officier | `MANUAL_PENDING` | | | |
| 6.9 | Synchronisation quatre clients | `MANUAL_PENDING` | | | |
| 7.11 | Sauvegarde / restauration / import | `MANUAL_PENDING` | | | |
| 8.8 | Litiges reels | `MANUAL_PENDING` | | | |
| 10.5 | Compatibilite RCLootCouncil | `MANUAL_PENDING` | | | |
| 11.4 | Aucune mutation en combat | `MANUAL_PENDING` | | | |
| 12.5 | Navigation reelle | `MANUAL_PENDING` | | | |
| 12.6 | Rendu des fenetres | `MANUAL_PENDING` | | | |
| 13.3 | Mode independant en raid | `MANUAL_PENDING` | | | |
| 14.4 | Reprise apres redemarrage force | `MANUAL_PENDING` | | | |
| 9.7 | Campagne T041 (14 scenarios) | `MANUAL_PENDING` | | | |
| 9.8 | 20 observations RF-0012 | `MANUAL_PENDING` | | | |

Les 20 observations T041 se remplissent dans
`rf-0012-retail-validation.md` §5, qui est le **dossier officiel**.

---

## 12. Regles que l'operateur ne peut pas enfreindre

1. Ne **jamais** editer un fichier SavedVariables a la main.
2. Ne **jamais** modifier l'addon installe pour forcer un etat (ni
   version, ni constante, ni fichier).
3. Ne **jamais** ouvrir le chemin canonique en production : la campagne A
   teste la version candidate **verrouillee**.
4. Ne **jamais** declarer un scenario `MANUAL_PASS` sans l'avoir observe
   dans le client.
5. Un echec est un **resultat** : il se note, il ne se corrige pas sur le
   build teste. La correction se fait dans la source, puis la campagne est
   **reprise** depuis 1.4.
