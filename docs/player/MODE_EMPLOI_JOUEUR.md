# Mode d'emploi joueur

Ce guide explique l'utilisation quotidienne de RCLootCouncil_dibs pour un joueur.

## A quoi sert Dibs ?

Dibs est un registre saisonnier de priorite de butin gere par la guilde. Il
affiche votre solde, conserve les demandes Pre-Dib et ajoute un debit lorsqu'un
gain eligible est valide.

Dibs ne fait pas les choses suivantes :

- il ne remplace pas le vote RCLootCouncil ;
- il ne garantit pas qu'un joueur gagnera un objet ;
- il ne depense pas un Dib lors de la creation d'une demande ;
- il ne permet pas a un joueur de modifier le ledger ou les regles ;
- il ne partage pas les votes, candidats ou reponses live avec un autre raid.

> **Attention :** un Master Looter RCLootCouncil n'a pas automatiquement les
> droits d'administration Dibs. Le GM et les Officers verifies restent les
> autorites pour les regles et les corrections.

![Ecran Joueur et solde Dibs](../assets/guides/screenshots/fr/player/player-overview.png)

_Placeholder de capture : `docs/assets/guides/screenshots/fr/player/player-overview.png`_

## 1. Ouvrir l'interface

Commandes principales :

```text
/dibs ui          Ouvre la fenetre Joueur
/dibs balance     Affiche votre solde
/dibs requests    Affiche vos demandes Pre-Dibs
/dibs vault <itemID> [difficulte]  Enregistre manuellement un objet du Grand Coffre
/dibs help        Affiche l'aide des commandes
```

Vous pouvez aussi utiliser `/dibs options`, puis les boutons de lancement des fenetres Joueur et Demandes.

## Installation et premier lancement

1. Installez le dossier `RCLootCouncil_dibs` dans `Interface/AddOns/`.
2. Activez l'addon sur l'ecran de selection du personnage.
3. Faites `/reload` apres une installation ou une mise a jour.
4. Demandez au GM ou a un Officer de confirmer la saison et les regles actives.
5. Lancez `/dibs ui` et verifiez la saison, le solde et l'etat de l'integration.

RCLootCouncil est optionnel. En mode Standalone, Dibs gere le registre et les
demande localement ; en mode RCLootCouncil, RCLootCouncil gere le vote et la
finalisation du butin.

## 2. Comprendre les Dibs

Un Dib est une unite de priorite definie par la guilde pour la saison active.

- Votre solde est propre a la guilde et a la saison.
- Une nouvelle saison peut avoir de nouvelles allocations.
- Un changement de grade ne reecrit pas l'historique passe.
- Avoir le plus de Dibs ne garantit pas de gagner un objet.
- Le GM et les Officers definissent les regles et les allocations.

Dans la fenetre Joueur, verifiez :

- la saison active ;
- votre solde disponible ;
- vos derniers mouvements ;
- vos demandes Pre-Dibs actives ;
- l'etat de l'integration RCLootCouncil, si elle est utilisee.

## 3. Faire une demande Pre-Dib

Une demande Pre-Dib signale que vous souhaitez un objet. Elle ne depense aucun Dib au moment de sa creation.

### Depuis l'interface

1. Ouvrez l'Adventure Guide ou la ligne de butin RCLootCouncil.
2. Selectionnez un objet eligible.
3. Cliquez sur l'action Dibs ou Pre-Dib.
4. Verifiez l'objet, la difficulte et la saison.
5. Confirmez la demande.

### Depuis une commande

```text
/dibs pre <itemID> [nom de l'objet]
```

La commande depend de la configuration de la guilde et de la saison active.

Une meme demande active pour le meme joueur, objet, saison et difficulte n'est pas dupliquee.

## 4. Suivi du Grand Coffre

La fenetre Joueur affiche les acquisitions du Grand Coffre avec l'objet, la
source, la semaine de reset, l'etat de verification, l'explication
d'eligibilite et l'etat de synchronisation. Ouvrir le coffre ou regarder un
choix ne constitue pas une acquisition confirmee.

Si le client Retail ne fournit pas de signal fiable, utilisez :

```text
/dibs vault <itemID> [difficulte]
```

L'enregistrement manuel reste `MANUAL_RECORDED` jusqu'a la revue d'un Officer.
Une acquisition du Grand Coffre est une preuve d'eligibilite et ne depense
jamais de Dib. L'historique est propre a la guilde actuelle, ou au personnage
lorsqu'il est sans guilde.

![Statut d'acquisition du Grand Coffre](../assets/guides/screenshots/fr/player/player-vault-history.png)

_Placeholder de capture : `docs/assets/guides/screenshots/fr/player/player-vault-history.png`_

## Drop-Dib : quand l'objet tombe

Le Drop-Dib est le debit lie a un gain finalise, et non la demande initiale.

1. L'objet est propose dans la session de butin.
2. Les joueurs et Officers utilisent le workflow de vote configure.
3. Le Master Looter valide le gain dans RCLootCouncil, si l'integration est active.
4. Dibs verifie l'objet, le gagnant, la reponse, l'autorite et l'identite de la session.
5. Un seul debit est ajoute au ledger si toutes les conditions sont valides.

Un objet gagne en mode test, un callback incomplet, un doublon ou un objet exclu
ne doit pas reduire le solde.

![Action Pre-Dib ou Drop-Dib dans le butin](../assets/guides/screenshots/fr/player/player-loot-action.png)

_Placeholder de capture : `docs/assets/guides/screenshots/fr/player/player-loot-action.png`_

## 4. Gerer ses demandes

Dans **Mes demandes**, vous pouvez :

- consulter le statut d'une demande ;
- annuler votre propre demande active ;
- voir l'objet et la difficulte associes ;
- suivre une demande confirmee ou accomplie.

Une demande qui ne gagne pas l'objet reste active sauf si vous l'annulez ou si la politique de la guilde la ferme.

Vous ne pouvez pas annuler la demande d'un autre joueur.

### Statuts d'une demande

- **pending** : demande creee mais pas encore confirmee ;
- **confirmed** : demande active et confirmee ;
- **invalidated** : demande rendue invalide par la politique ou les donnees ;
- **fulfilled** : demande associee a un gain finalise ;
- **cancelled** : demande annulee par son proprietaire ou la politique.

## Solde et historique

Le solde est calcule a partir des transactions du ledger pour la saison active.
L'historique indique notamment le type d'operation, la quantite, la raison, la
date et la reference du gain quand elle existe.

Une correction ne supprime pas la transaction originale : elle ajoute une
nouvelle operation auditee. Ne comparez donc pas seulement le solde ; ouvrez
l'historique lorsque le resultat semble inattendu.

## 5. Quand un Dib est-il depense ?

Un Dib est depense uniquement lorsqu'un gain eligible est finalise et valide.

Ne depensent pas automatiquement de Dib :

- la creation d'une demande Pre-Dib ;
- un objet simplement propose ou vote ;
- un gain de test ;
- un gain invalide, incomplet ou duplique ;
- une acquisition de la Grande chambre forte ;
- un objet personnel ou exclu par la politique.

Avec RCLootCouncil, le Master Looter finalise le gain. Dibs enregistre ensuite le debit si toutes les verifications sont valides.

## 6. Signaler un probleme

Ouvrez **Mes demandes** ou utilisez `/dibs requests`, puis creez un signalement.

Ajoutez si possible :

- l'objet concerne ;
- le joueur concerne ;
- la transaction ou le gain concerne ;
- une explication courte et precise.

Le signalement est prive. Un Officer peut demander des informations supplementaires. Une correction ne supprime pas l'ancien historique : elle ajoute une nouvelle operation auditee.

## 7. Messages courants

- **Aucune saison active** : la guilde doit activer une saison.
- **Objet non eligible** : l'objet n'est pas dans les categories autorisees.
- **Pre-Dibs desactive** : la fonction est desactivee par le GM.
- **Contexte de raid requis** : le mode Encounter exige d'etre dans le raid correspondant.
- **Integration indisponible** : RCLootCouncil est absent, desactive ou pas encore pret. Le mode Standalone peut rester utilisable.
- **En combat** : certaines fenetres protegees s'ouvriront apres la fin du combat.

- **Permission refusee** : les actions d'administration sont reservees au GM et aux Officers.
- **Historique indisponible** : RCLootCouncil est absent, non charge ou ne fournit pas de preuve exploitable.
- **Gain non finalise** : un vote ou une proposition ne suffit pas pour un debit.

## Depannage et FAQ

### Pourquoi ma demande n'apparait-elle pas ?

Verifiez la saison active, la difficulte, la categorie de l'objet et le mode
Pre-Dib. En mode `ENCOUNTER`, vous devez etre dans le raid correspondant.

### Pourquoi mon solde n'a-t-il pas baisse ?

Le gain peut etre en attente, en test, invalide, duplique ou exclu. Demandez a
un Officer de verifier la reference du gain et l'historique.

### Puis-je modifier directement mon solde ?

Non. Contactez un Officer avec le nom de l'objet, l'heure, le joueur gagnant et
la reference RCLootCouncil si disponible.

### Que faire si RCLootCouncil est absent ?

Le mode Standalone peut continuer a afficher les soldes et les demandes. Les
fonctions qui exigent une preuve RCLootCouncil restent indisponibles.

### Que signifie ``Unavailable`` ou ``Blocked`` ?

`Unavailable` indique souvent qu'un contexte optionnel manque. `Blocked` indique
qu'une condition de securite ou de configuration empeche une action. Ne tentez
pas de contourner l'etat ; demandez une verification GM/Officer.

## 8. Bonnes pratiques

- Verifiez l'objet et la difficulte avant de confirmer.
- N'envoyez pas de donnees de guilde ou d'historique dans un canal public.
- Consultez votre historique apres un gain ou une correction.
- Contactez un Officer avec l'heure, l'objet et le contexte si un resultat semble incorrect.
