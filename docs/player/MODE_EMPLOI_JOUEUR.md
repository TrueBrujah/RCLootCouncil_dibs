# Mode d'emploi joueur

Ce guide explique l'utilisation quotidienne de RCLootCouncil_dibs pour un joueur.

Il decrit le code actuel. Consultez les [versions et telechargements](../../README.md#downloads)
avant l'installation : le deplacement et la taille de l'icone ont ete ajoutes
dans la version publiee 0.8.9. Les chemins de captures en attente
inventorient des images Retail manquantes, pas des preuves de validation.

## A quoi sert Dibs ?

Dibs est un registre saisonnier de priorite de butin gere par la guilde. Il
affiche votre solde, conserve les demandes Pre-Dib et ajoute un debit lorsqu'un
gain eligible est valide.

Dibs ne fait pas les choses suivantes :

- il ne remplace pas le vote RCLootCouncil ;
- il ne garantit pas qu'un joueur gagnera un objet ;
- il ne depense pas un Dib lors de la creation d'une demande ;
- il ne permet pas a un joueur de modifier le registre Dibs de guilde ou les regles ;
- il ne partage pas les votes, candidats ou reponses live avec un autre raid.

> **Attention :** un Master Looter RCLootCouncil n'a pas automatiquement les
> droits d'administration Dibs. Le GM et les Officers verifies restent les
> autorites pour les regles et les corrections.

_Capture Retail en attente : vue Joueur, solde, saison, selecteur de ledger et
Preferences de mini-carte — `docs/assets/guides/screenshots/fr/player/player-overview.png`._

## 1. Ouvrir l'interface

Commandes principales :

```text
/dibs ui          Ouvre la fenetre Joueur
/dibs balance     Affiche votre solde
/dibs requests    Ouvre vos signalements (page Signalements)
/dibs vault <lien|[Nom]|itemID> <LFR|Normal|Heroic|Mythic>  Enregistre manuellement un objet du Grand Coffre
/dibs minimap show|hide  Affiche ou masque l'icone Dibs sur la mini-carte
/dibs minimap scale <50-200>  Regle la taille de l'icone (en %)
/dibs minimap reset  Remet l'icone a sa position et sa taille par defaut
/dibs help        Affiche l'aide des commandes
```

Glissez l'icone Dibs avec le clic gauche pour la deplacer autour de la mini-carte. La taille se regle aussi dans **Joueur > Preferences**; ces choix sont enregistres pour ce personnage.

Vous pouvez aussi utiliser `/dibs options`, puis les boutons de lancement des fenetres Joueur et Demandes.

Apres la connexion, le clic gauche sur l'icone Dibs ouvre/ferme la vue Officer
si autorise, sinon la vue Joueur. Le clic droit ouvre/ferme la vue Joueur.
Elle ne donne aucun droit d'Officer ou de GM : c'est seulement un
raccourci. Vous pouvez aussi l'afficher ou la masquer dans **Joueur >
Preferences**. Ce choix est enregistre pour le personnage et l'icone est
affichee par defaut.

## Installation et premier lancement

1. Installez le dossier `RCLootCouncil_dibs` dans `Interface/AddOns/`.
2. Activez l'addon sur l'ecran de selection du personnage.
3. Faites `/reload` apres une installation ou une mise a jour.
4. Demandez au GM ou a un Officer de confirmer la saison et les regles actives.
5. Lancez `/dibs ui` et verifiez la saison, le solde et l'etat de l'integration.

RCLootCouncil est optionnel. En mode Standalone, Dibs gere le registre et les
demande localement ; en mode RCLootCouncil, RCLootCouncil gere le vote et la
finalisation du butin.

## Regles de butin de guilde

Avec DIBS 0.8.x, le maitre de guilde adopte explicitement les regles de butin
de guilde et publie leurs modifications. Les officiers verifies peuvent
modifier un brouillon local et appliquer le preset Dibs, mais seul le GM peut
adopter ou publier les regles de guilde. Les anciennes valeurs locales ne
constituent pas une autorite de guilde. Raid Readiness distingue les etats suivants :

- `GUILD_LOOT_RULES_READY` : une version de guilde valide est presente ;
- `LOCAL_LEGACY_ONLY` : les anciennes regles restent un repli local avant
	adoption, pas une decision partagee ;
- `GUILD_LOOT_RULES_NOT_CONFIGURED` : le GM n'a pas encore adopte les regles ;
- `GUILD_LOOT_RULES_SYNC_BEHIND` : conservez la derniere version recue et
	laissez la synchronisation se retablir ;
- `GUILD_LOOT_RULES_INCOMPATIBLE` : mettez DIBS a jour avant d'utiliser les
	regles partagees ;
- `UNAVAILABLE` : les types de butin pris en charge n'ont pas pu etre charges.

La synchronisation exige la famille 0.8.x des deux cotes. Les clients en
0.7.x doivent passer en 0.8.x pour se synchroniser avec la guilde.

## Allocations par rang

Votre allocation de depart est enregistree pour la saison. Si votre rang de
guilde change, un Officer peut valider un complement lorsque la nouvelle
allocation attendue est superieure. Une allocation attendue plus faible ne
retire jamais les Dibs deja attribues, ne cree aucune dette et ne modifie pas
votre solde par un ajustement negatif. Contactez un Officer si votre allocation
de depart semble incorrecte.

## 2. Comprendre les Dibs

Un Dib est une unite de priorite definie par la guilde pour la saison active.

- Votre solde est propre a la guilde et a la saison.
- Une nouvelle saison peut avoir de nouvelles allocations.
- Un changement de grade ne reecrit pas l'historique passe.
- Avoir le plus de Dibs ne garantit pas de gagner un objet.
- Le GM et les Officers definissent les regles et les allocations.

Dans la fenetre Joueur, verifiez :

- la saison active et le ledger sélectionné (menu déroulant en haut du tableau si la guilde gère plusieurs rosters) ;
- votre solde disponible ;
- vos derniers mouvements ;
- vos demandes Pre-Dibs actives ;
- l'etat de l'integration RCLootCouncil, si elle est utilisee.

Utilisez la recherche et les filtres de l'historique pour retrouver les objets,
les details de rencontre enregistres, la source, le statut et les dates.
Saisissez les dates au format `YYYY-MM-DD`; les dates de debut et de fin sont
inclusives. La recherche ne porte que sur les metadonnees presentes dans
l'enregistrement : un ancien enregistrement sans raid ni boss ne correspondra
pas a une valeur de remplacement. Effacer un filtre conserve les autres; tout
effacer restaure le perimetre initial de la page. La recherche est en lecture
seule et n'expose ni les donnees d'autres joueurs ni les preuves privees des
Officers.

### Raids Indépendants et PUGs

Si vous participez à un raid indépendant mené par un Master Looter avec Dibs :
- Vous avez seulement besoin de l'addon RCLootCouncil standard.
- Cliquer sur le bouton "DIB" dans la fenêtre de vote RCLootCouncil consomme un point de la session temporaire du raid.
- Ces attributions n'affectent pas votre solde de guilde habituel (sauf réconciliation ultérieure par un officier).

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

Ouvrez `/dibs ui`, puis **Grand coffre**. Cette page en lecture seule affiche
vos objets enregistres, toutes saisons confondues dans le perimetre de guilde
actuel, du plus recent au plus ancien, avec 10 entrees par page. Les colonnes
montrent la date, l'objet, la difficulte et la verification; survolez une ligne
pour la source, la semaine de reset, la synchronisation et l'explication des
preuves. Les preuves privees des officiers ne sont pas affichees.

La fenetre Joueur affiche les acquisitions du Grand Coffre avec l'objet, la
source, la semaine de reset, l'etat de verification, l'explication
d'eligibilite et l'etat de synchronisation. Ouvrir le coffre ou regarder un
choix ne constitue pas une acquisition confirmee.
La detection automatique exige le choix effectivement reclame, la reception
du meme objet par votre personnage et la fin de disponibilite des recompenses.
Elle doit etre active avant le retrait; elle ne reconstruit pas les retraits
passes a partir du chat ou du contenu des sacs. Si une de ces preuves manque,
utilisez le secours manuel ci-dessous. La validation sur client Retail reste
en attente.
Les filtres de l'historique du Grand Coffre portent sur l'objet, la source, le
statut et les dates enregistres. Les dates `YYYY-MM-DD` sont inclusives. Une
metadonnee absente ne correspond pas a une valeur de remplacement; effacer un
filtre conserve les autres. Les resultats restent limites a votre perimetre de
guilde/personnage et n'incluent pas les preuves privees des Officers.

Si le client Retail ne fournit pas de signal fiable, utilisez :

```text
/dibs vault <lien | [Nom de l'objet] | itemID> <LFR | Normal | Heroic | Mythic>
```

Avec le lien complet seul (Maj-clic), Dibs lit l'infobulle de cette variante exacte :

- Un objet de **raid** garde son origine **Raid Finder (LFR)**, **Normal**, **Heroic** ou **Mythic**, meme
  si sa piste d'amelioration est superieure : **Heroic** avec **Mythe 5/6** reste **Heroic**.
  **Raid Finder** sur la piste **Veteran** est enregistre comme **LFR**.
- Un objet de **donjon** (marque **Mythic+**, ou **Mythic** sur la piste Champion
  pour un Mythique 0, ou **Heroic** sur la piste Veteran) suit sa piste :
  un objet de donjon **Heroic** sur **Veteran** reste **Heroic** ;
  **Champion** = Normal, **Heros** = Heroic,
  **Mythe** = Mythic. **Mythic+** avec **Heros 6/6** donne Heroic.
- Une piste inferieure a **Veteran**, des lignes contradictoires ou une combinaison
  origine/piste inattendue ne sont pas classees automatiquement.

L'ilvl et le niveau de l'activite du coffre ne sont pas utilises. Si le client ne
fournit aucun classement lisible via `C_TooltipInfo.GetHyperlink`, la difficulte est obligatoire
(`LFR`/`Raid Finder`, `Hero`/`Heroique` et `Myth`/`Mythique` sont acceptes) ; sans difficulte valide, rien n'est enregistre et l'aide s'affiche.
Un nom tape entre crochets, par exemple `[Nom de l'objet] Heroic`, doit etre
connu du client ; sinon utilisez le lien (Maj-clic) ou l'ID.

L'enregistrement manuel reste `MANUAL_RECORDED` jusqu'a la revue d'un Officer.
Pour conserver la variante exacte, tapez `/dibs vault `, faites Maj-clic sur
l'objet dans vos sacs ou votre equipement pour inserer son lien complet,
Ajoutez ` LFR`, ` Mythic`, ` Heroic` ou ` Normal` seulement pour un classement manuel
explicite ; une difficulte saisie explicitement est prioritaire. La detection automatique
utilise la meme regle et exige toujours la preuve du retrait effectif.
Si aucune difficulte ne peut etre classee (par exemple un objet de donjon Aventurier),
rien n'est enregistre automatiquement ; utilisez la commande avec une difficulte
explicite pour une revue manuelle. Une difficulte absente ne devient jamais Normal par defaut.
Les classements deja enregistres ne sont pas reecrits.
Les noms d'objets et les textes de verification reviennent a la ligne au lieu
d'etre coupes. Survolez le nom pour afficher l'infobulle ou cliquez pour ouvrir
le lien. La date est compacte ; l'aide de ligne conserve l'heure complete.
Un lien de base marque **reference d'objet** ne prouve pas la variante acquise.
Une saisie par identifiant seul charge le nom mais ne retrouve pas la variante
acquise. Si une seule variante de cet ID est equipee ou dans les sacs, un
**apercu possede** affiche son infobulle sans modifier l'enregistrement ni prouver
son origine Grand Coffre. Plusieurs variantes differentes laissent la variante
exacte indisponible. Ressaisir la commande ne remplace pas une acquisition existante.
Pour invalider une saisie erronee, un Officer peut la rejeter dans Vault Review
avec une raison. L'entree et la trace de revue sont conservees; il ne s'agit
pas d'une suppression definitive ni d'une annulation libre par le joueur.
Une acquisition du Grand Coffre est une preuve d'eligibilite et ne depense
jamais de Dib. L'historique est propre a la guilde actuelle, ou au personnage
lorsqu'il est sans guilde.

_Capture Retail en attente : historique et statut du Grand Coffre —
`docs/assets/guides/screenshots/fr/player/player-vault-history.png`._

## Drop-Dib : quand l'objet tombe

Le Drop-Dib est le debit lie a un gain finalise, et non la demande initiale.

1. L'objet est propose dans la session de butin.
2. Les joueurs et Officers utilisent le workflow de vote configure.
3. Le Master Looter valide le gain dans RCLootCouncil, si l'integration est active.
4. Dibs verifie l'objet, le gagnant, la reponse, l'autorite et l'identite de la session.
5. Un seul debit est ajoute au ledger si toutes les conditions sont valides.

Un objet gagne en mode test, un callback incomplet, un doublon ou un objet exclu
ne doit pas reduire le solde.

_Capture Retail en attente : action Pre-Dib ou Drop-Dib —
`docs/assets/guides/screenshots/fr/player/player-loot-action.png`._

## 4. Gerer ses demandes

Dans **My Dibs** (Pre-Dibs actifs, Pre-Dibs gagnes et Pre-Dibs passes), vous pouvez :

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

## Signalements et suivi (0.8.8)

La page **Signalements** (`/dibs requests`) est distincte des réservations Pre-Dib, qui restent sur **My Dibs**.
Signalez uniquement votre propre problème. L'enregistrement ne prouve pas la
réception : les détails indiquent **En attente d'envoi**, **Envoyée ; réception
attendue**, **Reçue** ou **Erreur de livraison**. Reçue ne signifie pas résolue.
Un destinataire hors ligne ou ancien ne reçoit aucun chuchotement ; la demande
reste enregistrée après rechargement. La livraison nécessite un coordinateur
vérifié compatible et les deux clients connectés.

Répondez à une question de l'officier dans le même fil. Ses réponses publiques
et la conclusion restent visibles, mais pas les preuves administratives internes.
**Réessayer la livraison** reprend le travail en attente ; une réponse devenue
obsolète utilise la dernière révision reçue. Un changement d'autorité bloque
la reprise automatique pour éviter les doubles corrections.

Les rappels de suivi fonctionnent uniquement lorsque WoW est ouvert et respectent
la préférence locale de notifications. Reporter le rappel ne concerne que ce
personnage. Les étapes Résolue/Rejetée, Clôturée, puis Archivée conservent le
dossier et ne modifient jamais le solde.

## Solde et historique

Le solde est calcule a partir des transactions du ledger pour la saison active.
L'historique indique notamment le type d'operation, la quantite, la raison, la
date et la reference du gain quand elle existe.

La fenetre Joueur est en lecture seule pour les soldes et les regles de guilde.
Vous pouvez envoyer ou annuler vos propres demandes Pre-Dib; un GM ou un
Officer autorise doit effectuer toute correction de solde.

Une correction ne supprime pas l'operation originale : elle ajoute une nouvelle
operation auditee. Ne comparez donc pas seulement le solde; ouvrez l'historique
lorsque le resultat semble inattendu.

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

Ouvrez **Signalements** dans la fenetre Joueur, ou utilisez `/dibs requests`, puis remplissez **Signaler un probleme** : type de probleme (par exemple debit incorrect ou objet/joueur incorrect), entree du registre concernee si possible, et note. Depuis **Historique**, les details d'une entree proposent aussi **Signaler un probleme sur cette operation**, qui preselectionne la transaction. Vos signalements apparaissent ensuite dans **Mes demandes de revision**.

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
