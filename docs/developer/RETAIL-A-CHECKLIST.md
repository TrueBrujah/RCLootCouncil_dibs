# Checklist operateur — campagne Retail A

Statut : **MANUAL_PENDING** — aucun scenario n'a ete execute.

Cette checklist est directement executable. Elle decoupe la campagne A en
quatre **blocs** prepares dans l'ordre, et precise pour chaque scenario
les ressources qu'il exige, les donnees de test a creer, les preuves a
collecter et la condition de passage.

**Regle absolue : aucun scenario ne peut porter `MANUAL_PASS` sans une
observation ecrite dans le fichier de notes.** La compilation, la suite
automatisee et la lecture du code ne constituent pas une observation.

---

## 0. Inventaire des ressources

### 0.1 Comptes

| Compte | Personnage | Rang | Sert a |
|---|---|---|---|
| **C1** | `A-Coord` | Maitre de guilde (index 0) | Approbation des corrections, proposition de ledger, activation de guilde |
| **C2** | `B-Officier` | Officier (index 1) | Proposition de correction, proposition de ledger, revue des declarations |
| **C3** | `C-Joueur` | Membre (index 3) | Pre-Dibs, attributions, consommation d'un Dib, declaration main/alt |
| **C4** | `D-Joueur` | Membre (index 3) | Deconnexion / reconnexion pendant la synchronisation |

> **Chaque personnage doit avoir son propre compte** (ou son propre
> repertoire de jeu). Quatre personnages sur un seul compte partagent un
> seul fichier SavedVariables et les observations de convergence n'ont
> alors aucun sens.

### 0.2 Guilde de test

| Element | Valeur |
|---|---|
| Nom | `Dibs Retail Test` |
| Realm | le realm de test |
| Effectif | au moins les quatre personnages ci-dessus |
| Le GM doit etre un **vrai** Maitre de guilde | index de rang 0 dans le roster vivant |
| L'officier doit etre un **vrai** officier | index de rang 1 dans le roster vivant |

Un role revendique n'est pas une autorite : l'addon lit le **roster
vivant**. Verifiez les rangs **dans le jeu** avant de commencer.

### 0.3 RCLootCouncil

| Scenario | RCLootCouncil requis |
|---|---|
| 10.5 (compatibilite) | **Oui** — installe et actif |
| Tous les autres | **Non** — la campagne doit aussi demontrer que le coeur fonctionne sans RC |

> Testez la campagne **sans** RC d'abord, puis installez RC pour le
> scenario 10.5. Un scenario qui n'est teste qu'avec RC ne prouve pas
> l'independance.

### 0.4 Build

| Element | Valeur |
|---|---|
| Archive | `RCLootCouncil_dibs-0.8.10-rf0013-candidate-dc388f9df313f1597e5c1a35078bb725c34c7f3e.zip` |
| SHA-256 | `C8AF12BCB46D1C994EA6C3BE9CF5CBC1320614C568A60D3E7466C43C90242E79` |
| Version TOC | `0.8.10` — **verrouillee** |
| Verrous RF-0012 | **fermes** — la campagne A ne teste pas le chemin canonique |

---

## 1. Commandes de diagnostic WoW utiles

| Commande | Usage |
|---|---|
| `/console scriptErrors 1` | Rend les erreurs Lua visibles dans le chat. **A activer sur chaque client avant de commencer.** |
| `/console scriptErrors 0` | A remettre a la fin pour ne pas noyer le chat. |
| `/dibs` | Ouvre la fenetre de l'addon. |
| `/dibs help` | Liste les commandes disponibles. |
| `/dibs status` | Etat general (saison, protocole, autorite). |
| `/dibs sync` | Etat de synchronisation : epoch, sequence, racine, raison d'un retard. |
| `/dibs history` | Historique des transactions du joueur local. |
| `/dibs requests` | Pre-Dibs du joueur local. |
| `/dibs ledger` | Etat du ledger actif. |
| `/dibs setup` | Surface de configuration guilde (GM / officier). |
| `/reload` | Rechargement complet du client — utilise par les scenarios de reprise. |
| `/who` | Verification du roster vivant. |
| `/g` | Liste de guilde et confirmation des rangs. |

> Les commandes exactes disponibles se lisent dans `/dibs help`. Notez
> dans votre fichier de notes la **liste reelle** : elle fait partie de la
> preuve.

### 1.1 Ce qu'il faut capturer

Pour chaque client, une **copie du texte** de `/dibs status` et
`/dibs sync` avant et apres l'action. Un copier-coller du chat suffit ;
une capture d'ecran est un complement, pas un remplacement.

---

## 2. Bloc A — Preparation (avant toute action)

| # | Etape | Ressource | Preuve | PASS | FAIL |
|---|---|---|---|---|---|
| A.1 | Sauvegarder les SavedVariables des quatre clients | 4 clients | les 3 fichiers de chaque client, copies hors du jeu | les 12 fichiers presents | un fichier manquant |
| A.2 | Verifier les empreintes de l'archive | — | `Get-FileHash` | l'empreinte correspond | elle ne correspond pas |
| A.3 | Installer la candidate sur C1, C2, C3, C4 | 4 clients | — | — | — |
| A.4 | Verifier le chargement sur chaque client | 4 clients | journal de chat, `/dibs status` | aucune erreur Lua, l'onglet Joueur s'ouvre | une erreur Lua, l'onglet ne s'ouvre pas |
| A.5 | Verifier que la fenetre Officier est **restreinte** pour C2 | C2 | capture de l'onglet | la configuration de guilde est absente | elle est accessible |
| A.6 | Verifier que C3 **ne voit aucun** dossier d'officier | C3 | capture | rien n'est visible | un dossier est visible |
| A.7 | Noter la version affichee | 1 client | `/dibs status` | `0.8.10` | autre version |

> **A.4 bloque la campagne.** Un client qui ne charge pas correctement
> doit etre diagnostique d'abord ; la campagne ne commence qu'a partir
> d'une base saine.

---

## 3. Bloc B — Donnees de test et parcours joueur

### 3.1 Donnees a creer

| Donnee | Qui la cree | Comment | Preuve |
|---|---|---|---|
| Saison de test | C1 | parcours **Officier → Saison** | identifiant de la saison |
| Allocation de saison | C1, pour C3 et C4 | parcours **Officer → Saison** | allocation de chaque membre |
| Pre-Dib prive de C3 | C3 | parcours **Joueur → Pre-Dibs** | identifiant, statut, item |
| Declaration main/alt | C3 ou C2 | parcours joueur | identifiant de la declaration, statut |
| Attribution d'objet | C1 | attribution de test en guilde | item, identifiant d'attribution |

> **Toutes ces donnees sont creees par le parcours de l'addon.** Ne
> modifiez **jamais** un fichier SavedVariables a la main.

### 3.2 Scenarios

| # | Scenario | Ressource | PASS | FAIL | Preuves a collecter |
|---|---|---|---|---|---|
| 2.1 | Saison active affichee | C1 | la saison de test est affichee | autre saison | le texte affiche |
| 2.2 | Allocation non nulle par membre | C1 | chaque membre test a une allocation | une allocation a zero | allocation par membre |
| 2.3 | Allocation de C3 creee | C1, C3 | C3 a une allocation positive | C3 reste a zero | solde avant/apres |
| 2.4 | Solde initial note | 4 clients | le solde est note avant toute operation | — | solde + nombre de transactions par client |
| 4.1.1 | Pre-Dibs publics desactives | C1 | le mode public est desactive | il reste actif | le mode affiche |
| 4.1.2 | Soumission publique refusee | C3 | la soumission est refusee avec un motif | elle est acceptee | le motif **verbatim** |
| 4.1.3 | **Aucune** demande creee | C3 | le compteur de demandes est inchange | une demande existe | nombre de demandes avant/apres |
| 4.2.2 | Pre-Dibs publics actives | C1, C3 | la demande est creee, en attente | elle est refusee | identifiant, statut, item |
| 4.3.1 | Pre-Dib prive | C3 | demande creee, en attente | — | identifiant, statut |
| 4.3.2 | Annulation par le proprietaire | C3 | statut annule | le statut ne change pas | statut, nombre de demandes actives |
| 4.3.3 | Annulation par un tiers refusee | C4 | refus, la demande de C3 est intacte | la demande de C3 a change | motif, statut de la demande de C3 |
| 4.4.1 | Portee de ledger | C3 | la demande est dans **un seul** ledger | elle est dupliquee | nombre de demandes par ledger |
| 3.1 | Declaration main/alt creee | C3 | demande en attente | — | identifiant, statut |
| 3.2 | Aucune donnee bougee | C3 | solde, transactions, groupes inchanges | une valeur a bouge | solde, nombre de transactions |
| 3.3 | Declaration listee chez l'officier | C1 | la declaration apparait | elle est invisible | capture de l'onglet |
| 3.4 | Approbation par l'officier | C1 | statut approuve, groupe cree | refus ou groupe absent | statut, identifiant de groupe |
| 3.5 | Portee du groupe | C1, C2 | le groupe couvre exactement les deux caracteres | il couvre plus | membres du groupe |
| 3.6 | Aucune fuite vers C3 | C3 | C3 ne voit rien | C3 voit le dossier | ce que C3 voit |
| 3.7 | Refus **avec** motif | C1 | statut refuse, motif visible, aucune donnee comptable bougee | une donnee a bouge | motif, solde avant/apres |
| 3.8 | Refus **sans** motif refuse | C1 | le refus est refuse, la declaration reste en attente | le refus passe sans motif | le message |

---

## 4. Bloc C — Attribution, reservation, sauvegarde, synchronisation

| # | Scenario | Ressource | PASS | FAIL | Preuves a collecter |
|---|---|---|---|---|---|
| 5.1 | Attribution enregistree | C1 | l'evenement est enregistre | rien n'est enregistre | item, identifiant d'attribution |
| 5.2 | Reservation visible | C3 | le disponible < le brut | disponible == brut | brut, reservations, disponible |
| 5.3 | Liberation de la reservation | C1, C3 | le disponible revient au brut | il reste inferieur | disponible avant/apres |
| 5.4 | Pas de resurrection apres reconnexion | C3, C4 | la reservation reste liberee | elle revient | disponible apres reconnexion |
| 5.5 | Consommation exacte d'un Dib | C3 | le solde baisse d'**exactement** un | autre ecart, double consommation | solde avant/apres, nombre de transactions |
| 5.6 | Consommation sans solde refusee | C3 | refus avec motif | la consommation passe | le motif |
| 5.7 | Solde jamais negatif | C3 | solde >= 0 a chaque etape | solde negatif | solde a chaque observation |
| 6.1 | Sauvegarde complete creee | C1 | l'instantane est cree et liste | — | identifiant, taille, empreinte |
| 6.2 | Ledger modifie | C1 | le ledger bouge | — | solde, nombre de transactions |
| 6.3 | Restauration | C1 | l'etat precedent est retrouve, un instantane de securite est cree | perte ou divergence | solde apres, transactions apres |
| 6.4 | Chaines partagees non reculees | C1 | saison, politique, governance inchangees | une chaine a recule | revisions avant/apres |
| 6.5 | Sauvegarde d'une autre guilde refusee | C1 | refus | elle est acceptee | le motif |
| 6.6 | Import de configuration | C1 | apercu puis confirmation, la configuration est importee | l'import passe sans apercu | l'apercu, le resultat |
| 7.1 | Etat de synchronisation des quatre clients | 4 clients | epoch, sequence, racine notes | — | les 12 valeurs |
| 7.2 | Proposition sans effet local | C2 | rien ne change sur C2 | C2 a change | solde, transactions, sequence avant/apres |
| 7.3 | Deconnexion de C4 | C4 | — | — | — |
| 7.4 | Acceptation par le GM | C1 | un seul changement canonique | zero ou deux | sequence avant/apres, identifiant d'operation |
| 7.5 | Convergence de C3 | C3 | epoch, sequence, racine, solde **identiques** a C1 | une valeur diverge | les 4 valeurs de C3 et de C1 |
| 7.6 | Redelivrance sans effet | C3 | aucun changement | un second commit | solde, sequence, transactions |
| 7.7 | Reconnexion de C4 | C4 | commits appliques **dans l'ordre**, convergence | divergence ou trou | epoch, sequence, racine, solde de C4 |
| 7.8 | `/reload` du GM | C1 | memes valeurs, un seul commit | doublon ou perte | sequence, racine, nombre de commits |
| 7.9 | Epoch perime refuse | C3 | refus avec motif | l'enregistrement est applique | le motif **verbatim** |
| 7.10 | Ledger incorrect refuse | C3 | refus avec motif | l'enregistrement est applique | le motif **verbatim** |
| 7.11 | Rapport historique en lecture seule | C1 | il classe et n'applique rien | un solde bouge | comptes de classification, solde avant/apres |

---

## 5. Bloc D — Cas particuliers

| # | Scenario | Ressource | PASS | FAIL | Preuves a collecter |
|---|---|---|---|---|---|
| 1.4 | Redemarrage complet de WoW | 1 client | l'etat est identique apres redemarrage | divergence | soldes, transactions, reservations avant/apres |
| 8.8 | Litiges reels | C2, C3 | soumission, reponse, decision fonctionnent | la surface est inoperante | statuts affiches, chronologie |
| 10.5 | Compatibilite RCLootCouncil | RC installe | RC est lu sans ecriture, un clic DIB non eligible est refuse, aucun historique n'est modifie | le ledger de Dibs bouge | solde avant/apres, transactions, capture avant/apres |
| 11.4 | Aucune mutation en combat | en raid | l'action est differee, aucune ecriture | une ecriture en combat | le journal de combat, le ledger |
| 12.5 | Navigation reelle | 1 client | chaque onglet s'ouvre, l'aide s'affiche | un onglet est inaccessible | une capture par onglet |
| 12.6 | Rendu des fenetres | 1 client | aucun element tronque, aucun chevauchement | troncature ou chevauchement | captures etroit et large |
| 13.3 | Mode independant en raid | 1 client | aucune donnee de production ecrite | une ecriture | solde de production avant/apres |
| 14.4 | Reprise apres redemarrage force | 1 client | projections reconstruites, **un seul** commit | doublon ou etat incomplet | sequence, racine, nombre de commits |

---

## 6. Fiche de resultat

Une ligne par scenario. **Aucune ligne ne peut porter `MANUAL_PASS` avant
l'observation ecrite.**

| # | Scenario | Statut | Resultat observe | Preuve jointe | Note |
|---|---|---|---|---|---|
| A.1 | Sauvegarde des SavedVariables | `MANUAL_PENDING` | | | |
| A.2 | Empreinte de l'archive | `MANUAL_PENDING` | | | |
| A.3 | Installation sur 4 clients | `MANUAL_PENDING` | | | |
| A.4 | Chargement sans erreur | `MANUAL_PENDING` | | | |
| A.5 | Fenetre officier restreinte | `MANUAL_PENDING` | | | |
| A.6 | Aucune fuite vers le joueur | `MANUAL_PENDING` | | | |
| A.7 | Version affichee | `MANUAL_PENDING` | | | |
| 1.4 | Redemarrage de WoW | `MANUAL_PENDING` | | | |
| 2.1 a 2.4 | Donnees de test | `MANUAL_PENDING` | | | |
| 3.1 a 3.8 | Declaration main/alt et revue officier | `MANUAL_PENDING` | | | |
| 4.1.1 a 4.1.3 | Pre-Dibs publics desactives | `MANUAL_PENDING` | | | |
| 4.2.1 a 4.2.3 | Pre-Dibs publics actives | `MANUAL_PENDING` | | | |
| 4.3.1 a 4.4.1 | Pre-Dibs prives | `MANUAL_PENDING` | | | |
| 5.1 a 5.7 | Attribution, reservation, consommation | `MANUAL_PENDING` | | | |
| 6.1 a 6.6 | Sauvegarde, restauration, import | `MANUAL_PENDING` | | | |
| 7.1 a 7.11 | Synchronisation quatre clients | `MANUAL_PENDING` | | | |
| 8.8 | Litiges reels | `MANUAL_PENDING` | | | |
| 9.7 | Campagne T041 (14 scenarios) | `MANUAL_PENDING` | | | |
| 9.8 | 20 observations RF-0012 | `MANUAL_PENDING` | | | |
| 10.5 | Compatibilite RCLootCouncil | `MANUAL_PENDING` | | | |
| 11.4 | Aucune mutation en combat | `MANUAL_PENDING` | | | |
| 12.5 | Navigation reelle | `MANUAL_PENDING` | | | |
| 12.6 | Rendu des fenetres | `MANUAL_PENDING` | | | |
| 13.3 | Mode independant en raid | `MANUAL_PENDING` | | | |
| 14.4 | Reprise apres redemarrage force | `MANUAL_PENDING` | | | |

Les 20 observations T041 se remplissent dans
`rf-0012-retail-validation.md` §5, qui est le **dossier officiel**.

---

## 7. Retour a l'etat initial

En cas d'echec, ou a la fin de la campagne :

```powershell
# 1. Fermer le jeu completement sur chaque client.
# 2. Restaurer les SavedVariables de chaque client depuis la sauvegarde
#    de l'etape A.1.
# 3. Restaurer l'addon installe (l'ancien dossier a ete deplace, pas
#    supprime, lors de l'installation).
```

La procedure complete est dans `rf-0012-retail-test-runbook.md` §7.

---

## 8. Regles que l'operateur ne peut pas enfreindre

1. Ne **jamais** editer un fichier SavedVariables a la main.
2. Ne **jamais** modifier l'addon installe pour forcer un etat.
3. Ne **jamais** ouvrir le chemin canonique : la campagne A teste la
   version candidate **verrouillee**.
4. Ne **jamais** incrementer la version TOC.
5. Ne **jamais** declarer un scenario `MANUAL_PASS` sans l'avoir observe
   dans le client.
6. Un echec est un **resultat** : il se note, il ne se corrige pas sur le
   build teste. La correction se fait dans la source selon les cinq
   conditions du gel fonctionnel, puis la candidate est reconstruite.
