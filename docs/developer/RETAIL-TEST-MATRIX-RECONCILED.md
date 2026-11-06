# Retail test matrix — reconciled

Statut global : **MANUAL_PENDING**

Cette matrice reconcilie les trois sources de la campagne Retail :

| Source | Volume | Reference |
|---|---|---|
| Matrice de scenarios produit | **89 scenarios** | `RETAIL-TEST-MATRIX.md` |
| Campagne T041 (runbook) | **14 scenarios** (S1–S14) | `rf-0012-retail-test-runbook.md` |
| Observations T041 | **20 observations** | `rf-0012-retail-validation.md` |

**Aucune de ces trois series ne couvre automatiquement les autres.** Les
correspondances ci-dessous sont **explicites** et verifiablees : chaque
scenario T041 est rattache a la ou aux observations qu'il produit, et
chaque scenario de la matrice produit est rattache a un scenario T041
lorsqu'il existe.

Regles de statut :

| Statut | Signification |
|---|---|
| `AUTOMATED_PASS` | Exerce en simulation ; le chemin de production est couvert. Ne remplace pas l'execution Retail. |
| `MANUAL_PENDING` | Doit etre execute dans WoW Retail. Aucun resultat enregistre. |
| `MANUAL_PASS` | Execute dans WoW Retail, resultat conforme. |
| `MANUAL_FAIL` | Execute dans WoW Retail, resultat non conforme. |
| `BLOCKED` | Impossible dans l'etat actuel (verrou, dependance, environnement). |

**Aucun scenario ne peut etre marque `MANUAL_PASS` sans execution reelle
dans le client.**

---

## 1. Correspondance T041 : 14 scenarios, 20 observations

Cette table est la **cle de reconciliation**. Elle reproduit la table du
runbook (§3) et y ajoute la correspondance avec les scenarios de la
matrice produit.

| T041 | Scenario T041 | Client | Observations | Scenario de la matrice produit |
|---|---|---|---|---|
| S1 | Authority and permission check | All | 1 | 2.1, 2.2, 2.3, 2.4 |
| S2 | Officer proposes a correction | Officer | 2 | 8.2, 8.3 |
| S3 | Coordinator accepts the correction | Coordinator | 3, 4, 5, 6, 7 | 8.4, 5.5, 5.6, 5.7, 8.5 |
| S4 | Follower receives the commit | Follower | 8, 9 | 6.1, 6.4, 6.5 |
| S5 | Incompatible client stays behind | Stable client | 14 | 6.5, 6.8 |
| S6 | Gap and catch-up | Reconnecting | 10, 11, 12 | 6.2, 6.3, 14.2, 14.3 |
| S7 | Duplicate delivery is idempotent | Follower | 9 | 6.4 |
| S8 | Conflicting operation is refused | Coordinator | 16 | 5.3, 5.4, 8.6 |
| S9 | Unverifiable original is refused | Coordinator | 17 | 8.2, 8.7 |
| S10 | Stale epoch and wrong ledger are refused | Coordinator | 15 | 5.2, 6.8, 8.7 |
| S11 | Reload recovery and projection rebuild | Coordinator | 12, 13 | 1.4, 14.1, 14.2, 14.3, 14.4 |
| S12 | Historical report is read-only | Coordinator | 18 | 14.4, 8.8 |
| S13 | Officer UI status and reason | Officer | 19 | 8.6, 12.5, 12.6 |
| S14 | Guild and privacy isolation | All | 20 | 2.4, 8.8, 10.6, 12.6 |

### Ce que cette table prouve, et ce qu'elle ne prouve pas

- Les **20 observations** sont couvertes : 1 (S1), 2 et 3 (S2), 3 a 7 et
  17 (S3), 8 et 9 (S4), 14 (S5), 10, 11 et 12 (S6), 9 (S7), 16 (S8), 17
  (S9), 15 (S10), 12 et 13 (S11), 18 (S12), 19 (S13), 20 (S14).
- **L'observation 3 est produite par deux scenarios** (S2 et S3) : elle
  verifie a la fois que l'officier ne change rien et que le coordinateur
  accepte. Elle doit donc etre cochee **une seule fois**, apres S3.
- **Les 89 scenarios de la matrice produit ne sont PAS tous couverts par
  T041.** En particulier, la campagne T041 ne couvre ni l'installation
  (1.1 a 1.3), ni la declaration main/alt (3.1 a 3.9), ni les Pre-Dibs
  (4.1 a 4.6), ni la reservation et la consommation d'un Dib (5.1 a 5.7),
  ni le backup et l'import (7.1 a 7.10), ni le mode independant (13.1 a
  13.3), ni la compatibilite RCLootCouncil reelle (10.5), ni l'interface
  reelle (12.5, 12.6).
- La campagne T041 exige **une version pre-release** qui ouvre le chemin
  canonique (`rf-0012-retail-validation.md` §2a). La version candidate
  **du livrable** garde ce chemin **ferme**. Les deux campagnes sont
  donc **differentes** : T041 valide le chemin canonique, la campagne
  produit valide le livrable verrouille.

## 2. Campagne A — scenarios produit hors T041 (13 scenarios)

Ces 13 scenarios ne sont couverts par **aucun** scenario T041. Ils
doivent etre executes separement.

| # | Scenario | Statut | Prerequis | Clients | Donnees initiales | Resultat attendu | A collecter | PASS / FAIL | Retour arriere |
|---|---|---|---|---|---|---|---|---|---|
| 1.1 | Installation propre | `AUTOMATED_PASS` | Aucun SavedVariable | 1 | Aucun | L'addon se charge, aucun message d'erreur, l'onglet Joueur s'ouvre | La sortie de chat de chargement, une capture | PASS : chargement sans erreur. FAIL : toute erreur Lua 5.1 | Supprimer `WTF/.../RCLootCouncil_dibs.lua` ; reinstaller |
| 1.2 | Upgrade de version | `AUTOMATED_PASS` | Une version anterieure installee | 1 | SavedVariables d'une version anterieure | Les donnees sont conservees, la migration ne signale aucune erreur | Le nombre de transactions avant/apres, la sortie de migration | PASS : compte identique. FAIL : perte ou erreur | Restaurer la sauvegarde des SavedVariables |
| 1.3 | Chargement avec SavedVariables existantes | `AUTOMATED_PASS` | Un ledger legacy | 1 | Ledger legacy | Le ledger est charge, la chaine canonique se.classifie sans erreur | La classification de recovery affichee | PASS : classification stable. FAIL : erreur ou perte | Restaurer la sauvegarde |
| 1.4 | Redemarrage de WoW | `MANUAL_PENDING` | 1.1 reussi | 1 | Etat cree par 1.1 | L'etat est identique apres redemarrage complet | Soldes, transactions, reservations avant/apres | PASS : etat identique. FAIL : divergence | Restaurer la sauvegarde |
| 3.8 | Surface de revue officier (main/alt) | `MANUAL_PENDING` | 3.1 a 3.7 valides | 2 (GM + joueur) | Une declaration en attente | L'onglet d'eligibilite de l'officier **liste** la declaration et permet de l'approuver | Une capture de l'onglet, l'identite de la declaration | PASS : la declaration est listee et l'action aboutit. FAIL : invisible ou inoperante | Refuser la declaration ; l'etat d'approbation est sans effet comptable |
| 6.9 | Synchronisation reelle entre quatre clients | `MANUAL_PENDING` | Campagne T041 S4 a S7 | 4 | Une correction acceptee | Les quatre clients convergent sur le meme etat | Voir section 3 | PASS : les quatre convergent. FAIL : divergence | Restaurer chaque client depuis sa sauvegarde |
| 7.11 | Sauvegarde / restauration / importation reelles | `MANUAL_PENDING` | 7.1 a 7.10 valides | 1 | Un ledger avec historique | Une sauvegarde reelle se restaure et l'historique est retrouve | Identifiant de l'instantane, soldes avant/apres | PASS : historique retrouve. FAIL : perte ou divergence | Restaurer la sauvegarde des SavedVariables |
| 8.8 | Litiges reels | `MANUAL_PENDING` | 8.1 a 8.7 valides | 2 (officier + joueur) | Une demande soumise | La demande, la reponse de l'officier et la decision fonctionnent dans l'interface | Statuts affiches, chronologie | PASS : le parcours complet fonctionne. FAIL : la surface est inoperante | Le litige reste sans effet comptable |
| 9.7 | Campagne Retail T041 (14 scenarios) | `MANUAL_PENDING` | Version pre-release | 4 | Voir le runbook §2 | Les 14 scenarios sont executes et observes | Le fichier d'observations du runbook §9 | PASS : les 20 observations sont remplies. FAIL : une observation est en echec | Restaurer chaque client depuis sa sauvegarde |
| 9.8 | Observations Retail RF-0012 (20 observations) | `MANUAL_PENDING` | 9.7 | 4 | Voir `rf-0012-retail-validation.md` §5 | Les 20 observations sont renseignees avec un **resultat reel** | Le tableau §5 complet | PASS : 20/20. FAIL : une observation en echec | Idem 9.7 |
| 10.5 | Compatibilite RCLootCouncil reelle | `MANUAL_PENDING` | RC installe | 1 + 1 guilde RC | Un vote RC en direct | L'addon lit l'etat RC, un clic DIB refuse reste refuse, le ledger de Dibs n'est pas modifie par RC | Le vote, le resultat du clic, le ledger | PASS : RC est lu sans ecriture. FAIL : le ledger de Dibs bouge | Aucun effet comptable ; rien a restaurer |
| 11.4 | Aucune mutation comptable en combat | `MANUAL_PENDING` | En raid | 1 | Un gain en combat | Aucune ecriture comptable pendant le combat ; les actions differees | Le journal de combat, le ledger | PASS : aucune ecriture. FAIL : une ecriture pendant le combat | Aucun ; le combat se termine seul |
| 12.5 | Navigation reelle | `MANUAL_PENDING` | 11.2 valide | 1 | Aucun | Les deux fenetres s'ouvrent, les onglets commutent, l'aide contextuelle s'affiche | Une capture par onglet | PASS : navigation complete. FAIL : onglet inaccessible | Aucun |
| 12.6 | Rendu des fenetres dans le client | `MANUAL_PENDING` | 12.5 | 1 | Aucun | Aucun element tronque, aucun chevauchement, le vide est explicite | Captures en 1080p et en fenetre etroite | PASS : rendu complet. FAIL : troncature | Aucun |
| 13.3 | Mode independant en raid | `MANUAL_PENDING` | 13.1 valide | 1 | Session independante active | Aucune donnee de production n'est ecrite | Le ledger de production avant/apres | PASS : ledger inchange. FAIL : ecriture en production | Aucun ; le mode independant n'ecrit rien |
| 14.4 | Reprise reelle apres redemarrage force | `MANUAL_PENDING` | 14.1 a 14.3 valides | 1 | Une operation acceptee | Les projections sont reconstruites, **un seul** commit canonique | Le nombre de commits, la sequence, la racine | PASS : un seul commit. FAIL : doublon ou etat incomplet | Restaurer la sauvegarde |

## 3. Collecte de preuves — campagne A, scenario 6.9

Ce scenario exige les **memes** evidences que T041, et doit produire la
meme forme de dossier.

| Element | Ou le lire | Ce qui est note |
|---|---|---|
| Etat de synchronisation | Onglet Synchronisation de l'officier | Le texte d'etat exact, mot pour mot |
| Epoch | Onglet Synchronisation | La valeur chiffree |
| Sequence | Onglet Synchronisation | La valeur chiffree |
| Racine (root hash) | Onglet Synchronisation | La valeur chiffree |
| Soldes | Journal de l'historique du joueur | Le solde avant et apres |
| Reservations | Journal de l'historique | Le nombre de reservations avant et apres |
| Identifiants d'operation | Panneau de resultat de la correction | L'identifiant de proposition, d'operation et de transaction |
| Diagnostics | Panneau de resultat | Le motif **verbatim** de chaque refus |
| Resultats d'interface | Captures | Une capture par etat observe |

**Regle absolue.** Les SavedVariables **reelles** ne sont **jamais**
utilisees pour fabriquer un scenario. Toute donnee de test est creee
par le parcours de l'addon lui-meme. Le scenario « 6.9 » utilise le
**candidat** et des comptes de test ; il ne lit ni n'edite un fichier
SavedVariables a la main.

## 4. Scenario a quatre clients independants (6.9)

### 4.1 Les quatre clients

| Rôle | Client | Ce qu'il fait | Etat initial |
|---|---|---|---|
| **A — Coordinateur** | GM de la guilde | Accepte les corrections, est le seul autorise a modifier la chaine canonique | Authority ACTIVE, epoch 1, sequence au repos |
| **B — Officier** | Officier de guilde | Propose des corrections, ne modifie **rien** localement | Authority en lecture seule |
| **C — Joueur** | Membre simple | Consomme les gains, ne voit aucun dossier d'officier | Authority en lecture seule |
| **D — Joueur deconnecte** | Membre simple | Se deconnecte, manque des messages, se reconnecte | Authority en lecture seule |

### 4.2 Deroulement

1. Les quatre clients sont en ligne dans la guilde de test. Le candidat
   est installee sur les quatre.
2. **A** ouvre Synchronisation et note epoch, sequence, racine.
3. **B** propose une correction sur un litige referencant une transaction
   reelle. **B** ne change **rien** : solde, transactions, sequence et
   racine sont notes avant et apres.
4. **D** se deconnecte du canal de guilde.
5. **A** accepte la correction. Un seul commit canonique est ajoute.
6. **C** recoit le commit et converge : epoch, sequence, racine, solde et
   identifiants de transaction sont notes.
7. Le commit est **redelivre** a **C** (relance du client ou
   re-emission). Rien ne change : c'est le controle d'idempotence.
8. **D** se reconnecte. Les commits manquants sont appliques **dans
   l'ordre** et **D** converge.
9. **A** fait un `/reload`. Les memes valeurs sont presentes, et un seul
   commit canonique existe.
10. **C** tente une operation avec un **epoch perime** et avec un
    **ledger incorrect**. Les deux sont refuses avec un motif explicite,
    et rien n'est ecrit.
11. **A** ouvre le rapport de correction historique. Il **classe** les
    candidats et n'applique **rien** : les quatre valeurs sont
    inchangees.

### 4.3 Ce qui distingue un PASS d'un FAIL

| Element | PASS | FAIL |
|---|---|---|
| Convergence | Les quatre clients ont le **meme** epoch, sequence, racine et solde | Un client diverge |
| Unicite | Exactement **un** commit canonique par correction | Deux commits pour la meme correction |
| Idempotence | Une redelivery ne change **rien** | Un second commit ou un solde modifie |
| Ordre | Les commits manquants sont appliques dans l'**ordre** | Un commit est applique hors sequence |
| Refus | Un epoch perime et un ledger incorrect sont refuses avec un motif | Un enregistrement est applique |
| Immuabilite | La transaction d'origine est inchangee | Une ligne historique est reecrite |
| Lecture seule | Le rapport historique n'applique rien | Un solde bouge |
| Isolation | Aucun dossier n'est lisible par un joueur ; aucune donnee d'une autre guilde | Un fuite |

### 4.4 Retour arriere

Chaque client est restaure depuis **sa propre** sauvegarde, faite
avant la campagne. La procedure complete est dans
`rf-0012-retail-test-runbook.md` §7 (« Returning to the initial state »)
et dans `RELEASE-CANDIDATE-PROCEDURE.md` §6 (etape 3 : sauvegarde des
SavedVariables reelles).

## 5. Recapitulatif

| Statut | Nombre |
|---|---|
| `AUTOMATED_PASS` | 76 |
| `MANUAL_PENDING` | **13** (campagne A) + **1** (T041, regroupant S1 a S14) |
| `MANUAL_PASS` | **0** |
| `MANUAL_FAIL` | **0** |
| `BLOCKED` | **0** |

Le nombre de **lignes a remplir** est de **13 scenarios de campagne A**
plus **20 observations T041**, soit **33 enregistrements**. Les 14
scenarios T041 ne sont que le **procede** des 20 observations.

Aucun de ces 33 enregistrements n'est rempli : le statut global reste
`MANUAL_PENDING` et le projet reste **`READY_FOR_RETAIL_TESTING`**, pas
`READY_FOR_RELEASE`.
