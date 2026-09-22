# Mode d'emploi GM / Officer

Ce guide explique la mise en place et l'administration de RCLootCouncil_dibs.

## A quoi sert Dibs ?

Dibs fournit un ledger saisonnier, des demandes Pre-Dib, des controles
d'eligibilite et des preuves d'audit autour du butin de guilde. RCLootCouncil
reste optionnel et, lorsqu'il est installe, reste l'interface de vote et de
finalisation du butin.

Dibs ne remplace pas le vote, ne choisit pas automatiquement le gagnant et ne
reecrit pas l'historique RCLootCouncil. Une demande Pre-Dib n'est pas un debit.
Un Drop-Dib ne produit un debit qu'apres une finalisation valide et idempotente.

![Vue d'ensemble GM et Officer](../assets/guides/screenshots/fr/officer/officer-overview.png)

_Placeholder de capture : `docs/assets/guides/screenshots/fr/officer/officer-overview.png`_

## 1. Roles et securite

Le GM configure la politique de la guilde et les Officers autorises executent les operations prevues par cette politique.

Important :

- le GM et les Officers verifies administrent Dibs ;
- un Master Looter RCLootCouncil n'obtient pas automatiquement les droits Dibs ;
- Raid Leader, Raid Assistant ou membre du conseil ne suffisent pas a donner les droits Dibs ;
- une identite inconnue ou impossible a verifier est refusee ;
- les transactions existantes ne sont jamais reecrites silencieusement.

## 2. Premiere configuration

Ouvrez :

```text
/dibs options
```

Puis configurez dans cet ordre :

1. **Settings** : choisissez `AUTO`, `STANDALONE` ou `RCLootCouncil`.
2. **Seasons** : creez une saison et rendez-la active.
3. **Rank Rules** : definissez les allocations par grade de guilde.
4. **Pre-Dibs** : choisissez `WILD_OPEN` ou `ENCOUNTER`.
5. **Announcements** : choisissez les canaux publics, Officers et raid.
6. **Loot / Eligibility** : definissez les categories d'objets autorisees.
7. **System > Modules** : activez uniquement les fonctions utiles a la guilde.
8. **Overview** : verifiez la saison, les permissions et l'etat des integrations.

Commandes utiles :

```text
/dibs season create [nom]
/dibs season set <id>
/dibs season list
/dibs rank set <index> <montant> [nom]
/dibs rank list
/dibs admin list
/dibs readiness
```

Les commandes `admin add` et `admin remove` conservent l'historique de migration, mais ne remplacent pas la verification reelle du GM ou du grade Officer.

### Installation et premier lancement

1. Installez le ZIP dans `Interface/AddOns/` et activez l'addon.
2. Faites `/reload`, puis ouvrez `/dibs options`.
3. Configurez une saison avant de distribuer des Dibs.
4. Verifiez avec `/dibs readiness` que les services attendus sont disponibles.
5. Faites un dry-run avant le premier raid reel.

![Configuration de la saison et des permissions](../assets/guides/screenshots/fr/officer/officer-setup.png)

_Placeholder de capture : `docs/assets/guides/screenshots/fr/officer/officer-setup.png`_

## 3. Choisir le mode de fonctionnement

### Standalone

Dibs gere les demandes, soldes et debits sans dependre d'une session RCLootCouncil.

### RCLootCouncil

RCLootCouncil gere la session de butin et le vote. Dibs ajoute la reponse DIB, controle l'autorite du Master Looter et enregistre le debit finalise.

### AUTO

Dibs utilise l'integration lorsqu'elle est disponible et conserve le fonctionnement local lorsque RCLootCouncil est absent ou indisponible.

## 4. Avant un raid

Lancez :

```text
/dibs readiness
```

La page **Raid Readiness & Dry-Run** indique notamment :

- la saison et la politique actives ;
- l'etat de RCLootCouncil ;
- l'identite et l'autorite du Master Looter ;
- la disponibilite de la reponse DIB ;
- le contexte de raid ;
- l'etat de synchronisation.

Un etat **Blocked** doit etre resolu avant de compter sur un debit automatique. Un etat **Unavailable** peut simplement signifier qu'aucun raid ou aucune integration live n'est actif.

Le dry-run permet de tester un objet, un joueur, une reponse et un statut de finalisation sans modifier le ledger :

```text
/dibs dryrun <itemID/lien> <joueur> <reponse> <finalized|test|pending> [session]
```

## 5. Gerer les saisons et les soldes

Utilisez **Seasons** pour :

- creer une saison ;
- activer la saison courante ;
- archiver une ancienne saison ;
- verifier l'identifiant et l'etat de la saison.

Utilisez **Rank Rules** pour attribuer les allocations de depart ou periodiques.

Pour les operations de ledger :

```text
/dibs grant <joueur> <montant>
/dibs use <joueur> <montant>
```

Chaque operation doit avoir une raison claire. Les corrections, remboursements et revocations ajoutent une nouvelle transaction ; elles ne modifient pas l'ancienne.

## 6. Workflow Pre-Dibs

1. Le joueur cree une demande pour un objet eligible.
2. Dibs verifie la saison, la difficulte, l'objet et le mode Pre-Dibs.
3. La demande est visible dans **Review Requests** ou **Pre-Dibs**.
4. Le joueur peut l'annuler s'il en est le proprietaire.
5. Apres un gain eligible finalise, la demande peut etre accomplie.
6. Un seul debit est ajoute au ledger, meme si le callback est rejoue.

Le mode `ENCOUNTER` exige que le joueur soit dans le raid correspondant a l'objet. Le mode `WILD_OPEN` permet la demande en dehors de ce contexte selon la politique de la saison.

## 7. Drop-Dib et impact du ledger

Le Drop-Dib est le debit produit par un gain finalise. Avant d'accepter une
operation, verifiez : joueur, objet, difficulte, saison, reponse DIB, identite
de session, Master Looter et statut final.

Les gains normaux, test, failed, pending, incomplets ou dupliques ne doivent pas
consommer de Dib de production. Un callback rejoue doit rester idempotent.

![Historique d'un debit Drop-Dib](../assets/guides/screenshots/fr/officer/officer-ledger.png)

_Placeholder de capture : `docs/assets/guides/screenshots/fr/officer/officer-ledger.png`_

## 8. Workflow RCLootCouncil

Avec RCLootCouncil installe :

1. Ouvrez l'assistant d'installation RCLootCouncil.
2. Choisissez les familles d'objets utilisees par la guilde.
3. Actualisez les boutons Dibs apres toute modification des ensembles de reponses.
4. Lancez une session avec le Master Looter verifie.
5. Controlez que la reponse DIB et la colonne de solde sont visibles.
6. Finalisez le gain dans RCLootCouncil.
7. Verifiez ensuite le debit et la reference dans l'historique Dibs.

Ne supprimez pas une reponse existante pour faire de la place a DIB. L'adaptateur ne doit pas reecrire l'historique RCLootCouncil.

Un gain normal, de test, incomplet, refuse, en attente ou duplique ne depense pas de Dib de production.

## 9. Revoir l'historique et les litiges

### Review Requests

Dans **Review Requests** :

1. Filtrez par statut, joueur ou objet.
2. Ouvrez les preuves associees.
3. Verifiez la transaction, l'objet, la difficulte, le gagnant et la reference RCLootCouncil.
4. Choisissez une resolution.
5. Saisissez toujours une raison.
6. Pour une correction de solde ou de cible, confirmez explicitement l'operation.

Les corrections sont append-only et conservent l'acteur, la date, la raison, les anciennes valeurs, les nouvelles valeurs et les references associees.

### RC History

La page **RC History** sert a examiner d'anciens gains RCLootCouncil :

1. Choisissez la saison cible.
2. Ajoutez si necessaire une plage de dates et des alias de reponse.
3. Lancez la recherche en mode preview.
4. Ouvrez une ligne et verifiez les preuves immuables.
5. Ajoutez une note de transfert.
6. Cliquez une seule fois sur **Confirm as DIB**.

La confirmation est idempotente : rejouer la meme operation ne cree pas un second debit.

## 10. Sauvegardes, profils et import/export

Dans **Data** :

- **Backups** : creez une sauvegarde avant toute operation risquee ; un restore cree aussi une sauvegarde de securite.
- **Profiles** : utilisez des profils locaux pour l'affichage et des profils guilde pour la politique partagee.
- **Import / Export** : choisissez le scope, lisez le preview, verifiez le checksum, puis confirmez.

Les scopes complets peuvent contenir des identites et l'historique des gains. Ne les publiez jamais dans un canal public.

Une importation repete deux fois doit rester sans doublon. Une annulation de preview ne change ni les soldes, ni l'historique, ni les reglages.

## 11. Synchronisation, coordinateur et reconciliation

La synchronisation partage uniquement l'etat Dibs necessaire a la guilde et les metadonnees de recuperation.

### Suivi du Grand Coffre

La vue **Vault Review** affiche les acquisitions de la guilde, les lignes
legacy a migrer et les conflits qui exigent une decision. Une confirmation,
un rejet ou un classement en reference demande une raison et conserve la preuve
originale. Un conflit d'identite n'est jamais resolu par un simple last-write-wins.

Les messages `VAULT_DIGEST`, `VAULT_FETCH`, `VAULT_DETAIL` et `VAULT_ACK` sont
bornes, controles par guilde et filtres par confidentialite. Les candidats,
votes, reponses RCLootCouncil et sessions de butin ne sont jamais transmis.
Une reconnexion peut relancer une demande manquante, sans doublon ni transfert
partiel. Un changement de guilde ne fusionne pas l'ancien historique; un
personnage sans guilde conserve son propre scope local.

![Revue GM/Officer du Grand Coffre](../assets/guides/screenshots/fr/officer/officer-vault-review.png)

_Placeholder de capture : `docs/assets/guides/screenshots/fr/officer/officer-vault-review.png`_

Elle ne partage pas :

- les candidats live ;
- les votes ;
- les reponses RCLootCouncil ;
- les details des sessions de butin d'un autre raid.

Avant de declarer la synchronisation fiable, testez deux clients, une reconnexion, les doublons, les revisions anciennes, les partitions et la reprise du coordinateur.

Surveillez les etats **ACTIVE**, **COORDINATOR_UNAVAILABLE**, **RECOVERY_PENDING**
et **HANDOFF_CLOSING**. Un coordinator indisponible bloque les nouveaux debits
qui exigent une sequence ordonnee ; il ne faut pas contourner ce verrou par une
modification directe des SavedVariables.

La reconciliation compare les preuves historiques, les references de transaction
et le statut final. Faites une preview, inspectez la preuve, saisissez une raison
et confirmez une seule fois. Les confirmations historiques restent auditees et
idempotentes.

![Etat de synchronisation et reconciliation](../assets/guides/screenshots/fr/officer/officer-sync-reconciliation.png)

_Placeholder de capture : `docs/assets/guides/screenshots/fr/officer/officer-sync-reconciliation.png`_

## 12. Modules optionnels

Le GM peut desactiver un module dans **System > Modules**.

- Les donnees conservees ne sont pas supprimees.
- La navigation normale peut masquer le module.
- Une ancienne fenetre ou une commande directe doit etre refusee proprement.
- La reactivation rend les donnees a nouveau accessibles.
- Les services de securite centraux restent actifs.

## 13. Depannage, diagnostics et release checks

Utilisez :

```text
/dibs debug report
/dibs debug rc
```

A verifier en premier :

- la saison active ;
- le grade du personnage ;
- le mode d'installation ;
- la presence et la version de RCLootCouncil ;
- le Master Looter reel ;
- la reponse DIB active ;
- la readiness ;
- le statut du module concerne.

Si le probleme concerne un debit, ne corrigez pas directement les SavedVariables. Ouvrez un litige ou utilisez le workflow de correction afin de conserver une trace auditable.

Avant une publication, verifiez au minimum :

- installation du ZIP propre et version du TOC ;
- absence d'erreur Lua au chargement ;
- readiness en Standalone et avec RCLootCouncil ;
- permissions GM, Officer, joueur et Master Looter ;
- debit Drop-Dib unique et replay idempotent ;
- sauvegarde, restore preview, import checksum et retention ;
- litige et correction append-only ;
- synchronisation a deux clients, partition et recovery ;
- layout joueur/Officer pendant et apres le combat.

## 14. FAQ

### Un Master Looter peut-il administrer Dibs ?

Seulement s'il est aussi GM ou Officer autorise. Sinon son autorite est limitee
au workflow RCLootCouncil et au debit finalise autorise.

### Puis-je supprimer une mauvaise transaction ?

Non. Utilisez une correction, un remboursement ou une revocation avec raison et
confirmation. Le ledger conserve l'operation originale et sa correction.

### Que faire si un module est desactive ?

Verifiez **System > Modules**. Les donnees sont conservees, les routes anciennes
doivent echouer proprement, et la reactivation restaure l'acces.

### Que signifie une reconciliation ``manual review`` ?

La preuve historique est incomplete ou ambigue. Ne confirmez pas sans verifier
l'identite, l'objet, le gagnant, la date, la reponse et la raison.
