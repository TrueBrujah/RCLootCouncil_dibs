# Mode d'emploi GM / Officer

Ce guide explique la mise en place et l'administration de RCLootCouncil_dibs.

Il decrit le code actuel ; consultez les [versions publiee et locale](../../README.md#downloads).
Les libelles sont localises et les modules desactives peuvent masquer leurs
pages. Les chemins de captures en attente inventorient les images Retail
manquantes ; ils ne constituent pas une validation du client actuel.

## A quoi sert Dibs ?

Dibs fournit un ledger saisonnier, des demandes Pre-Dib, des controles
d'eligibilite et des preuves d'audit autour du butin de guilde. RCLootCouncil
reste optionnel et, lorsqu'il est installe, reste l'interface de vote et de
finalisation du butin.

Dibs ne remplace pas le vote, ne choisit pas automatiquement le gagnant et ne
reecrit pas l'historique RCLootCouncil. Une demande Pre-Dib n'est pas un debit.
Un Drop-Dib ne produit un debit qu'apres une finalisation valide et idempotente.

_Capture Retail en attente : navigation Officer groupee et tableau de bord —
`docs/assets/guides/screenshots/fr/officer/officer-overview.png`._

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
/dibs officer
```

Ouvrez **Guild Setup > Guided Setup** (Configuration guidee) :

1. **Choisir** : Raid de progression, Butin standard ou Personnalise/avance.
2. **Configurer** : lisez l'apercu avant **Appliquer cette configuration**.
   Un Officer prepare les actions permises ; les approbations GM restent
   explicitement en attente.
3. **Verifier** : suivez les boutons de correction des blocages rouges.
   Le mode personnalise conserve les reglages existants.

Les blocages et alertes des setups/checks indiquent les etapes de correction.
Survolez leur statut ou bouton de correction pour afficher la cause et l'aide.
La page d'arrivee identifie ses problemes actuels dans **Points a verifier sur
cette page**, meme en arrivant par la navigation normale. Apres correction,
**Verifier de nouveau** retire les problemes resolus. L'aide ne modifie aucun
reglage et ne contourne aucune confirmation. Hors raid, le check du Master
Looter attend le contexte du raid voulu ; changer les roles de guilde ne le
corrigera pas.

Les pages avancees restent disponibles : **Guild Rules > Seasons / Rank Rules /
Loot Rules / Loot Eligibility / Pre-Dibs Settings / Announcements**,
**Guild Setup > Guild Ledgers** (Ledgers de guilde), **System > Settings /
Modules**, et **Integrations > RCLootCouncil**.
Le GM adopte/publie les regles et approuve l'activation du ledger canonique ;
un brouillon local ne suffit pas. **Automatic Dibs** gere les complements
d'allocation positifs avec raison et confirmation, jamais une reprise apres
retrogradation. `/dibs options` reste la surface de configuration et de lancement.

L'icone Dibs a cote de la mini-carte est un raccourci vers la vue Joueur ou
Officer appropriee. Elle n'accorde jamais de permission : les controles
d'autorite habituels restent appliques.

Dans **Announcements**, **Activer les annonces publiques** et **Activer les
annonces d'officiers** desactivent ou reactivent chaque type d'annonce. La
desactivation publie le canal None dans la politique ; la reactivation restaure
le canal choisi precedemment (Guilde ou Officier par defaut).

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
2. Faites `/reload`, puis ouvrez `/dibs officer` > **Guild Setup > Guided Setup**.
3. Choisissez un profil, examinez/appliquez les actions permises, puis verifiez.
4. Ouvrez **Guild Setup > Guild Setup Checks** (Verifications de la guilde) pour
   la configuration ponctuelle de la guilde et la synchronisation, puis
   **Overview > Raid Readiness** et `/dibs readiness` avant chaque raid.
   L'absence de contexte de raid n'est pas un echec de configuration Standalone.
5. Faites un dry-run avant le premier raid reel.

_Capture Retail en attente : Choisir/Configurer/Verifier, blocages et liens de
correction — `docs/assets/guides/screenshots/fr/officer/officer-setup.png`._

## 3. Choisir le mode de fonctionnement

### Standalone

Dibs gere les demandes, soldes et debits sans dependre d'une session RCLootCouncil.

### RCLootCouncil

RCLootCouncil gere la session de butin et le vote. Dibs ajoute la reponse DIB, controle l'autorite du Master Looter et enregistre le debit finalise.

### AUTO

Dibs utilise l'integration lorsqu'elle est disponible et conserve le fonctionnement local lorsque RCLootCouncil est absent ou indisponible.

### Multi-Ledger de guilde (Plusieurs rosters / splits)

Dibs permet de maintenir plusieurs registres indépendants au sein de la même guilde afin de gérer différents groupes de raid ou des runs séparés :

- **Isolation des soldes** : chaque ledger possède son propre journal de transactions et ses soldes de joueurs (`guild-primary` est le ledger par défaut).
- **Proposition par un officier** : tout officier vérifié peut proposer un nouveau ledger (`/dibs options` ou via `MultiLedger.ProposeLedger`).
- **Approbation obligatoire par le GM** : un ledger proposé reste inactif jusqu'à ce que le Maître de Guilde le valide (`MultiLedger.ApproveLedger` ou dans **Guild Setup > Guild Ledgers**).
- **Ledger actif de guilde** : dans **Guild Setup > Guild Ledgers**, le GM ou un officier choisit le ledger, clique sur **Activer pour la guilde...**, puis sur **Confirmer activation et sync de guilde**. La selection seule ne change rien; annuler conserve le ledger actif. La confirmation publie ce choix dans la politique operationnelle synchronisee et l'impose a tous les membres : Pre-Dibs, propositions d'attribution et reservations l'utilisent. Si l'envoi de sync echoue apres l'activation locale, un avertissement explicite propose de confirmer de nouveau pour reessayer. Un envoi reussi ne signifie pas que tous les membres l'ont deja recu. Les membres ne peuvent pas contourner ce choix. Tant qu'un membre n'a pas recu le ledger impose via le catalogue, la creation de Pre-Dibs et d'attributions est bloquee. Le ledger impose ne peut pas etre archive. La commande avancee `/dibs ledger set <id>` reste disponible.
- **Consultation des autres ledgers** : tout le monde, GM/Officiers inclus, peut consulter un autre ledger approuve en lecture seule via le menu « Voir le ledger » (`/dibs`, Officier > Tableau de bord, Officier > Historique, ou `/dibs ledger view <id>`). L'envoi de Pre-Dib est desactive pendant cette consultation. Chaque fenetre affiche le ledger actif (marque « (Actif) »), la version et l'etat de sync dans sa barre de statut. Cliquez sur cette barre pour consulter un ledger (les autres sont marques « (Lecture seule) »). Ni le dashboard ni la barre de statut ne changent le ledger actif. Le bouton **Gerer les ledgers** du dashboard ouvre l'interface de confirmation.
- **Version requise** : tous les membres doivent utiliser la 0.8.10 ou plus récente dès qu'un ledger actif de guilde est défini ; les anciens clients ne peuvent pas appliquer ce nouveau champ et leur chaîne de politique cesse de se mettre à jour.
- **Catalogue synchronisé** : le catalogue des ledgers approuvés (`LEDGER_CATALOG`) est répliqué automatiquement entre tous les membres de la guilde.
- **Suppression définitive** : seul le GM peut supprimer définitivement un ledger non par défaut après son archivage. L’interface exige une seconde confirmation, conserve une trace d’audit de gouvernance et synchronise un tombstone idempotent à toute la guilde. Le ledger par défaut, actif ou approuvé ne peut pas être supprimé.

### Autonomie de configuration des Officiers

Les officiers vérifiés peuvent initialiser la configuration de Dibs, configurer les saisons, ajuster les règles de rangs et suivre le Guided Setup sans bloquant fatal réservé au GM :

- Une initialisation par un officier crée une proposition de configuration (`PROPOSAL_CREATED`).
- Les politiques opérationnelles et nouveaux ledgers restent clairement marqués en attente de validation par le GM.

### Configuration guidee cle en main

La page **Configuration guidee** regroupe les verifications techniques en trois
etapes principales :

1. **Choisir** : selectionnez Raid de progression, Butin standard ou
   Personnalise/avance. Chaque profil explique a quelle guilde il convient,
   pourquoi il est utile et ce qu'il ne modifiera pas.
2. **Configurer** : examinez les actions prevues, leur resultat, les donnees
   conservees et les approbations GM reportees avant de cliquer sur
   **Appliquer cette configuration**.
3. **Verifier** : DIBS relit l'etat officiel de la guilde et affiche seulement
   les corrections encore necessaires.

Un resultat rouge **Bloquant** doit etre corrige avant de compter sur la
comptabilite du raid. Il indique ce qui manque, pourquoi c'est important,
l'impact et un bouton direct vers la bonne page. Un avertissement orange doit
etre examine, mais il peut representer un contexte non bloquant, par exemple
l'absence de raid actif. Un resultat facultatif n'empeche pas le fonctionnement
autonome de DIBS.

Le parcours ne supprime ni ne reecrit les transactions, soldes, historiques ou
preuves existantes. Le mode Personnalise n'applique aucun changement
automatique et conserve l'acces aux pages avancees.
- L'administration courante (création de saison, attribution des points de rangs) reste pleinement accessible en l'absence du GM.

### Raids Indépendants (PUG / Raids sans guilde)

Pour les raids organisés avec des joueurs hors-guilde ou en PUG, le Master Looter peut démarrer une session de **Raid Indépendant** (Officier > Intégrations > Raid Indépendant) :

- **Comptabilité locale éphémère** : la session attribue un nombre de points de départ local sans impacter les ledgers de guilde.
- **Inhibition stricte du réseau** : aucun message n'est envoyé sur les canaux d'addon de guilde, d'officiers ou de raid pendant toute la durée de la session indépendante.
- **Intégration RCLootCouncil avec réponse DIB** : les membres du raid n'ont besoin que de l'addon RCLootCouncil standard. Cliquer sur le bouton "DIB" consomme les points de la session locale. Les attributions gratuites (hors DIB) ne coûtent aucun point.
- **Réconciliation post-raid** : après le raid, les officiers peuvent consulter les attributions de la session et réconcilier facultativement un objet dans un ledger de guilde approuvé.

## 4. Avant un raid

Lancez :

```text
/dibs readiness
```

La page **Guild Setup > Guild Setup Checks** (Verifications de la guilde) verifie
une seule fois la configuration de la guilde : saison, politique, Rank Rules,
autorite, installation, etat local, Loot Rules, types de butin, services locaux
et etat de synchronisation. Elle ne demande pas de contexte de raid ; l'etape
finale de Guided Setup utilise ces verifications.

La page **Overview > Raid Readiness** indique, pour le raid courant :

- un element **Configuration de la guilde** qui resume les verifications de la
  guilde ;
- l'etat de RCLootCouncil ;
- l'identite et l'autorite du Master Looter ;
- la disponibilite de la reponse DIB ;
- le contexte de raid et les canaux ;
- l'etat de synchronisation ;
- **Membres du raid avec DIBS** : les membres en ligne sans DIBS ou avec une
  version a mettre a jour sont nommes. C'est un avertissement, pas un blocage :
  ils peuvent recevoir du butin, mais ne voient ni n'envoient de Dibs.

Un etat **Blocked** doit etre resolu avant de compter sur un debit automatique. Un etat **Unavailable** peut simplement signifier qu'aucun raid ou aucune integration live n'est actif.

### Regles de butin de guilde

Les Loot Rules sont une autorite de guilde distincte des Rank Rules et de
OperationalPolicy. Le GM examine le brouillon complet pour tous les types de
butin, puis choisit **Adopt reviewed Loot Rules** une seule fois. Les
modifications suivantes restent locales jusqu'a la reussite de **Publish Loot
Rules changes**. En cas d'echec, la revision precedente du catalogue reste
effective ; ne presentez pas le changement comme actif avant le message de
reussite.

Les officiers verifies peuvent modifier le brouillon local et appliquer le
preset de politique Dibs. Ils ne peuvent pas adopter ni publier les regles de
guilde; ces actions restent reservees au GM. Les anciennes valeurs locales
sont conservees mais ne remplacent pas le snapshot publie. Les cles disponibles
proviennent dynamiquement de RCLootCouncil ; les memes valeurs de guilde
controlent l'eligibilite Adventure Guide et les boutons Dibs.

Raid Readiness affiche l'etat exact des Loot Rules. `GUILD_LOOT_RULES_READY`
indique un snapshot valide ; `GUILD_LOOT_RULES_NOT_CONFIGURED` et
`LOCAL_LEGACY_ONLY` ne sont pas une readiness de guilde ;
`GUILD_LOOT_RULES_SYNC_BEHIND` conserve le dernier snapshot recu pendant la
reprise ; `GUILD_LOOT_RULES_INCOMPATIBLE` exige une mise a jour ; `UNAVAILABLE`
signifie que la source dynamique des types n'a pas pu etre chargee. SyncV2
refuse les clients 0.7.x face a la famille 0.8.x. Demandez leur mise a jour au
lieu de compenser en modifiant les valeurs locales.

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

Utilisez **Rank Rules** pour definir l'allocation de chaque grade pour la saison
selectionnee. Modifier la regle ne reecrit pas les anciennes transactions;
verifiez separement le rapprochement des membres deja presents. Dans Guided
Setup, **Rank Rules** et **Allocation Reconciliation** sont deux etapes
distinctes.

Desactivez les Dibs pour les rangs qui ne doivent pas recevoir d'allocation de
depart. Leurs membres sont exclus des avertissements de rapprochement; les
allocations deja inscrites au ledger sont conservees.

Ouvrez **Automatic Dibs** pour comparer le rang actuel de chaque membre a son
allocation saisonniere deja attribuee. Un ecart positif exige une confirmation
explicite et une raison obligatoire. Si l'action vient d'un client non
coordinateur, elle reste en attente jusqu'au commit canonique du coordinateur.
**Reconcile All** traite chaque membre independamment et presente les resultats
commis, en attente, perimes, ignores ou refuses.

Si le rapprochement est indisponible, la page affiche la raison au lieu d'un
bouton inactif (par exemple **Synchro en retard** si ce client est en retard
sur la synchronisation de guilde). Utilisez **Reparer la synchronisation**
depuis cette page, puis recommencez.

Un ecart negatif est informatif : une retrogradation ne retire pas les Dibs
deja attribues, meme s'ils ont ete depenses. Il n'y a ni reprise, ni ajustement
negatif du solde, ni dette. L'ancienne option Assignments reste disponible et
utilise le meme service de rapprochement protege.

Pour les operations de ledger :

```text
/dibs grant <joueur> <montant>
/dibs use <joueur> <montant>
```

Chaque operation doit avoir une raison claire. Les corrections, remboursements et revocations ajoutent une nouvelle transaction ; elles ne modifient pas l'ancienne.

Dans **Dibs Administration**, choisissez le personnage et l'action Add/Remove
pour son solde de la saison active. Une raison et une confirmation sont
obligatoires. L'historique conserve l'auteur, la cible, l'ancien solde, le
nouveau solde et la raison; l'operation originale reste intacte.

## 6. Workflow Pre-Dibs

1. Le joueur cree une demande pour un objet eligible.
2. Dibs verifie la saison, la difficulte, l'objet et le mode Pre-Dibs.
3. La demande est visible dans **Requests > Pre-Dib Requests**.
   **Guild Rules > Pre-Dibs Settings** configure la politique, pas les signalements.
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

_Capture Retail en attente : debit finalise et correction append-only liee —
`docs/assets/guides/screenshots/fr/officer/officer-ledger.png`._

## 8. Workflow RCLootCouncil

Avec RCLootCouncil installe :

1. Utilisez **Guild Setup > Guided Setup** pour la configuration initiale, puis
   **Guild Rules > Loot Rules** pour le brouillon des familles d'objets.
2. Faites adopter/publier les regles par le GM. Le brouillon ne suffit pas.
3. Verifiez les modeles et la projection dans **Integrations > RCLootCouncil**
   apres une modification des ensembles de reponses.
4. Lancez une session avec le Master Looter verifie.
5. Controlez que la reponse DIB et la colonne de solde sont visibles.
6. Finalisez le gain dans RCLootCouncil.
7. Verifiez ensuite le debit et la reference dans l'historique Dibs.

Ne supprimez pas une reponse existante pour faire de la place a DIB. L'adaptateur ne doit pas reecrire l'historique RCLootCouncil.

Un gain normal, de test, incomplet, refuse, en attente ou duplique ne depense pas de Dib de production.

## 9. Revoir l'historique et les litiges

### Requests : signalements

Dans **Requests > Requests** (`/dibs review`, anciennement **Review Requests**) :

1. Filtrez par statut, joueur ou objet.
2. Ouvrez les preuves associees.
3. Verifiez la transaction, l'objet, la difficulte, le gagnant et la reference RCLootCouncil.
4. Choisissez une resolution.
5. Saisissez toujours une raison.
6. Pour une correction de solde ou de cible, confirmez explicitement l'operation.

Les corrections sont append-only et conservent l'acteur, la date, la raison, les anciennes valeurs, les nouvelles valeurs et les references associees.

### Suivi privé des signalements (0.8.8)

Dans les détails existants, envoyez une **Réponse publique**, choisissez **Me
l'attribuer** ou un officier de guilde vérifié, puis planifiez/replanifiez le
suivi. La file filtre les demandes À suivre, Mes attributions, En attente du
joueur, Conclues et Archivées. La responsabilité et la dernière activité sont
affichées. Les raisons d'audit internes ne sont pas des réponses publiques.

Les demandes livrées sont modifiables uniquement sur le client du coordinateur
actuel vérifié ; les autres officiers compatibles reçoivent des copies privées
en lecture seule (au plus 16 pairs officiers connectés par cycle borné).
Un changement d'époque ou de coordinateur non prouvé bloque l'ancien dossier.
Une demande locale modifiée avant sa première liaison au coordinateur conserve
son audit, mais son envoi reste bloqué avec `REQUEST_LOCAL_DOSSIER_CHANGED`.

Après Résolue ou Rejetée, utilisez **Clore la demande**, puis **Archiver la
demande**, avec une raison revue explicitement. La recherche conserve le
dossier, les réponses, les références et les raisons d'audit. Aucun solde n'est
modifié par le fil ou l'archivage. Une compensation liée ne peut pas être
réappliquée par réouverture. Les limites de 500 dossiers et 120 événements
bloquent les écritures supplémentaires sans supprimer l'historique.
Les transferts trop volumineux restent en erreur, source conservée.
Les rappels personnels fonctionnent en ligne, au plus une fois par heure et
par demande ; le report ne change pas l'échéance commune. Certification Retail
multi-client et changement de coordinateur encore requise.

### RC History

Le parcours **RC History** (`/dibs reconcile`) sert a examiner d'anciens gains
RCLootCouncil ; ce n'est plus une entree principale de navigation :

1. Choisissez la saison cible.
2. Ajoutez si necessaire une plage de dates et des alias de reponse.
3. Lancez la recherche en mode preview.
4. Ouvrez une ligne et verifiez les preuves immuables.
5. Ajoutez une note de transfert.
6. Cliquez une seule fois sur **Confirm as DIB**.

La confirmation est idempotente : rejouer la meme operation ne cree pas un second debit.

### Recherche dans les historiques

Les controles de recherche et de filtre des pages Officer existantes
(historique du ledger, Pre-Dibs, Grand Coffre et RCLootCouncil) permettent de
retrouver les enregistrements par joueur, objet, details raid/boss disponibles,
date, statut et source lorsque ces champs existent. Saisissez les dates au
format `YYYY-MM-DD`; les bornes sont inclusives. Une metadonnee absente ne
correspond pas a un texte de remplacement. Effacer un filtre conserve les
autres; tout effacer restaure le perimetre initial de la page. La recherche
est en lecture seule et ne modifie ni les soldes, ni les demandes, ni les
acquisitions du Grand Coffre, ni les preuves RCLootCouncil. Les autorisations
Officer et les limites de confidentialite existantes restent appliquees.

### Statistiques d'activite par joueur

Ouvrez **Dibs > Statistics** et saisissez au besoin des dates `YYYY-MM-DD`.
Les bornes sont inclusives; laissez-les vides pour toute la saison selectionnee.
Le tableau presente des comptes descriptifs par joueur : transactions du
registre, attributions, Dibs accordes/utilises et corrections. La vue est en
lecture seule; elle ne modifie pas le registre et ne consomme pas de Dibs. Ce
n'est ni un score ni un classement de l'equite du butin et les loots hors du
registre Dibs ne sont pas comptes. Si des transactions sans date sont exclues
par le filtre, la couverture des joueurs concernes est indiquee comme partielle.

## 10. Sauvegardes, profils et import/export

Dans **Data** :

- **Backups** : creez une sauvegarde avant toute operation risquee ; un restore cree aussi une sauvegarde de securite. Les sauvegardes Officer survivent a `/dibs factoryreset CONFIRM`. Un restore ne fait jamais reculer les donnees partagees avec la guilde : si la gouvernance, les regles, le catalogue de saisons ou un ledger local est plus recent que la sauvegarde, la copie locale est conservee (indiquee dans le resultat) et la sync rattrape le reste.
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

_Capture Retail en attente : revue Officer du Grand Coffre —
`docs/assets/guides/screenshots/fr/officer/officer-vault-review.png`._

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

### Reparer un client en retard

La page de synchronisation liste toutes les raisons enregistrees pour lesquelles
le client est en retard (trou dans le ledger, detail de Pre-Dib manquant, conflit
de racine canonique, etc.). Ses outils ne modifient jamais le ledger :

- **Reparer la synchronisation** reverifie les donnees locales, efface les
  raisons resolues et redemande aux pairs en ligne ce qui manque encore, par
  lots bornes ;
- **Verifier de nouveau** reverifie seulement les donnees locales ;
- **Forcer la remise a zero...** (GM ou Officer, avec confirmation et raison)
  efface l'indicateur local ; les pairs le remettront si des donnees manquent
  encore. A reserver aux raisons bloquees qui ne peuvent pas etre verifiees ;
- **Sonder le pair** demande ses diagnostics a un personnage en ligne, et
  **Afficher le rapport** montre sa reponse ;
- **Reparer le pair** (GM/Officier) demande a un client a jour et en ligne
  d'annoncer ses donnees disponibles et de recuperer ce qui manque ;
- **Resynchroniser la guilde** (GM/Officier) lance la meme recuperation non
  destructive sur les clients de guilde a jour et en ligne.
  Commandes : `/dibs sync repair Nom-Royaume` ou `/dibs sync repair guild`.

Une reponse **STARTED** confirme le demarrage, pas la fin ; **BLOCKED** indique
un blocage. Utilisez **Afficher le rapport** pour cette reponse, puis **Sonder
le pair** de nouveau apres les transferts pour verifier son etat actuel.
Combat, sandbox, raid independant, transport indisponible et ancien addon
peuvent bloquer l'operation. Une demande par minute et par cible ; un demarrage
par minute chez chaque destinataire. Les absents rattrapent a leur reconnexion ;
un addon absent ou incompatible doit d'abord etre installe ou mis a jour.

Les revisions des regles et saisons sont recuperees dans l'ordre jusqu'a la
cible annoncee. Les transactions exigent toujours le coordinateur verifie ;
une revision plus haute ne permet ni de sauter un parent ni d'ecraser un conflit.
Gardez le GM et le coordinateur en ligne pour les donnees exigeant leurs droits.
Aucune generation de reset, suppression de ledger ou remise a zero des
revisions n'est effectuee.

Si aucun GM ni redacteur autorise n'est en ligne, un membre en retard peut
adopter la gouvernance, les regles ou le catalogue de saisons des que **3
membres differents** annoncent la meme revision et le meme hash. Les revisions
sont recuperees aupres de l'un d'eux et appliquees seulement quand toute la
chaine se raccorde a l'etat local ; chaque revision doit toujours nommer le GM
ou un redacteur autorise comme auteur. Un hash different pour la meme revision
reste un conflit visible, et une majorite plus ancienne est ignoree. Ce n'est
pas une signature : trois personnages complices pourraient relayer une fausse
revision, qui deviendra un conflit visible quand le vrai auteur se reconnecte.
Les transactions de ledger exigent toujours le coordinateur verifie.

Les copies valides disponibles permettent de recuperer des donnees manquantes.
Un Officier peut notamment renvoyer a un joueur ses **propres** Pre-Dibs perdus,
sans les demandes des autres joueurs ni les metadonnees reservees aux Officiers.
Cette restauration ne cree et ne consomme aucun Dib. Sans source valide, les
donnees perdues ne peuvent pas etre recreees : examinez une sauvegarde ou un
import disponible avec le processus existant de preview et confirmation.

La reconciliation compare les preuves historiques, les references de transaction
et le statut final. Faites une preview, inspectez la preuve, saisissez une raison
et confirmez une seule fois. Les confirmations historiques restent auditees et
idempotentes.

_Capture Retail en attente : synchronisation et reconciliation historique —
`docs/assets/guides/screenshots/fr/officer/officer-sync-reconciliation.png`._

## 12. Modules optionnels

Le GM peut desactiver un module dans **System > Modules**.

- Les donnees conservees ne sont pas supprimees.
- La navigation normale peut masquer le module.
- Une ancienne fenetre ou une commande directe doit etre refusee proprement.
- La reactivation rend les donnees a nouveau accessibles.
- Les services de securite centraux restent actifs.

## 13. Depannage, diagnostics et release checks

Dans **System > Diagnostics**, le centre de sante liste les references de
saison invalides, les acquisitions Great Vault incompletes ou en double, les
acquisitions a verifier et les conflits Vault. Les apercus ne modifient pas les
donnees; les decisions Vault passent par la revue auditee existante.

**Exporter le rapport de sante** ne partage que le statut, la disponibilite des
sources et les compteurs d'anomalies. **Exporter l'audit anonymise** est un
rapport distinct et borne; il exclut les noms, identifiants d'acteur, raisons,
identifiants de saison et transactions executables. Verifiez le texte avant de
le partager.

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
