# Feature Specification: Roster saisonnier et inscriptions aux raids

**Feature Branch**: `029-seasonal-raid-roster`

**Created**: 2026-11-03

**Status**: Planning revision — unified seasonal lifecycle; no production implementation authorized by this spec revision yet

**Input**: User direction: manage a raid season from draft through registration, officer review, Dibs allocation, activation, completion, and archive as one lifecycle; preserve player signup, read-only roster, Main/Alt identity, audit, and statistics.

## Clarifications

### Session 2026-11-03

- Q: Comment traiter les champs « Dibs Used » et « Raid Token » du classeur dans cette feature? → A: Les omettre pour le moment.
- Q: À qui appartiennent les Dibs lors d’un changement de Main? → A: À la personne, pas au personnage; son solde courant suit son nouveau Main.
- Q: Quand un Main et ses alts possèdent déjà des soldes Dibs distincts, comment établir le solde unique de la personne? → A: Le GM ou l’officier examine les soldes liés et conserve celui du Main sélectionné; les autres soldes ne sont pas additionnés et toute correction est inscrite au ledger.
- Q: Que déclenche la fin des inscriptions par rapport à l’archive? → A: Elle ferme les inscriptions seulement. La saison reste consultable pendant toute sa durée et devient une archive en lecture seule sept jours après sa fin. Si aucune fin n’a été planifiée, un GM/officier termine explicitement la saison; le délai d’archive commence alors.
- Q: Quelles dates l’officier configure à la création d’une saison? → A: Le début de saison et le début des inscriptions sont requis dans l’interface; la fin des inscriptions et la fin prévue de la saison sont facultatives. Une fin d’inscription ne termine ni n’archive la saison.
- Q: Comment représenter les choix « AotC », « Core Raider » et « Casual » du classeur? → A: AotC correspond au statut saisonnier **Raider**. Les statuts et leurs explications sont présentés au joueur pendant l’inscription; les GM/officiers peuvent les ajouter ou les modifier avec un historique de versions par saison.
- Q: Que signifie la remise à zéro des rangs pour un nouveau raid? → A: Les désignations saisonnières de raid sont réévaluées pour chaque nouvelle saison. La feature ne modifie pas automatiquement les rangs natifs de la guilde WoW.

### Session 2026-11-07 — refonte du cycle de saison

- La saison de raid devient l’unique identité fonctionnelle; roster, règles, allocations de rang, réconciliation, ledger et synchronisation utilisent son même `seasonId`. Les enregistrements peuvent rester dans leurs modules/domaines actuels, mais aucun second identifiant de saison ne doit demander une liaison manuelle.
- Un GM/officier prépare la saison complète en brouillon. Créer ou modifier un brouillon ne change pas le ledger Dibs actif. Un officier active explicitement la saison après prévisualisation et résolution des blocages.
- Les inscriptions proposent une voie Core Raider pour signaler l’objectif de participer à la progression du jeudi. Le joueur commence comme Raider/candidat; la promotion réelle en Core Raider est accordée par un GM/officier selon une règle configurée et versionnée pour la saison.
- La règle de promotion Core Raider peut être configurée par saison. Le seuil exact et la méthode de suivi des présences restent à décider; la première livraison ne présume pas d’un suivi automatique et permet une décision manuelle auditée.
- Les règlements de raid visibles par les joueurs et éditables par les GM/officiers sont versionnés par saison. Ils sont distincts des paramètres Dibs que l’addon peut appliquer techniquement.
- Les allocations Dibs restent configurées par rang de guilde pour chaque saison, conformément à la constitution. Elles ne sont calculées que pour les personnes/personnages approuvés dans le roster de la saison; les statuts Core/Raider ne changent pas à eux seuls les allocations.
- La réconciliation de saison est distincte du rapprochement Main/Alt des soldes historiques. Elle compare les participants approuvés à l’allocation de cette saison, montre un aperçu avant écriture et ne réécrit jamais les transactions existantes.
- Une saison brouillon n’est pas active. L’activation associe le roster approuvé et sa révision aux règles, allocations et ledger du même `seasonId`; un échec ne doit pas laisser un état partiellement actif.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Un joueur s’inscrit à la saison (Priority: P1)

Comme joueur, je veux inscrire mes personnages et mes choix de raid pour la saison afin que les GM et officiers puissent préparer les équipes à partir d’une liste commune.

**Why this priority**: L’inscription individuelle remplace le processus manuel fondé sur le classeur et constitue la donnée de base du roster.

**Independent Test**: Un joueur crée puis modifie sa propre inscription à une saison ouverte; ses changements sont visibles dans sa fiche et la liste du roster sans modifier les inscriptions des autres.

**Acceptance Scenarios**:

1. **Given** une saison où les inscriptions sont ouvertes, **When** un joueur inscrit un personnage et choisit sa voie demandée, sa spécialisation principale, son deuxième choix et son ou ses rôles, **Then** l’inscription est enregistrée une seule fois pour ce personnage et cette saison avec un statut initial Raider/candidat.
2. **Given** qu’un joueur a une inscription, **When** il la modifie, **Then** ses choix les plus récents sont affichés et l’historique conserve l’auteur et la date de la modification.
3. **Given** que les inscriptions sont fermées ou que le module est désactivé, **When** un joueur tente de créer ou modifier une inscription, **Then** l’action est refusée avec une explication et aucune donnée n’est modifiée.
4. **Given** un personnage non membre de la guilde, **When** son joueur l’inscrit, **Then** il peut être ajouté sans supposer une appartenance à la guilde ni associer des personnages par ressemblance de nom, classe ou compte Battle.net.
5. **Given** une saison offrant plusieurs voies et statuts de participation, **When** le joueur s’inscrit, **Then** il choisit sa voie souhaitée et commence comme Raider/candidat; il voit les explications publiées et AotC est présenté comme Raider.

### User Story 2 — Les joueurs consultent le roster et sa composition (Priority: P1)

Comme membre, je veux consulter les inscriptions et la composition prévue en lecture seule afin de savoir qui participe et quels rôles ou classes sont représentés.

**Why this priority**: La liste commune remplace le partage de feuilles et donne aux joueurs une vue cohérente de la préparation de saison.

**Independent Test**: Un membre qui n’a pas de droits administratifs peut ouvrir la liste, filtrer ou parcourir les inscriptions et consulter les totaux sans modifier une inscription ou voir des notes réservées aux GM/officiers.

**Acceptance Scenarios**:

1. **Given** une saison avec des inscriptions, **When** un joueur consulte le roster, **Then** il voit les champs de participation destinés aux membres et ne peut pas modifier les inscriptions d’autrui.
2. **Given** des inscriptions dont les personnages principaux ont plusieurs rôles, classes, types d’armure et catégories, **When** les statistiques sont affichées, **Then** chaque total correspond aux inscriptions admissibles et la somme par catégorie peut être vérifiée contre la liste filtrée.
3. **Given** un joueur ayant plusieurs personnages liés, **When** les statistiques de composition sont calculées, **Then** un seul personnage principal par joueur contribue au total de composition et un alt n’est pas compté comme un joueur supplémentaire.
4. **Given** une inscription annulée, retirée ou exclue selon les règles de saison, **When** la liste ou les statistiques sont actualisées, **Then** l’état courant est reflété sans effacer son historique administratif.

### User Story 3 — GM et officiers préparent une saison (Priority: P1)

Comme GM ou officier autorisé, je veux créer une saison, définir ses paramètres et gérer les inscriptions afin de préparer le roster sans éditer un classeur externe.

**Why this priority**: Le processus exige une autorité claire sur les périodes, les choix disponibles et les corrections du roster.

**Independent Test**: Un GM/officier prépare un brouillon sans toucher au ledger actif, configure dates, règles, statuts et allocations, puis vérifie qu’il peut publier l’inscription et examiner les demandes avec une trace d’audit.

**Acceptance Scenarios**:

1. **Given** un GM ou officier vérifié, **When** il crée une saison, **Then** il obtient un brouillon complet avec dates, horaires, règlement, statuts de participation, règles de promotion et allocations Dibs sans changer la saison active.
2. **Given** une saison configurée, **When** l’autorité change son état d’inscription, **Then** les joueurs voient si l’inscription est ouverte ou fermée et les nouvelles écritures respectent cet état.
3. **Given** un GM ou officier vérifié, **When** il ajoute, corrige, retire ou annule une inscription, **Then** l’action enregistre qui l’a faite, quand et pourquoi lorsque la donnée d’un joueur est modifiée administrativement.
4. **Given** une personne qui n’est pas GM ou officier de la guilde courante, ou un roster de guilde périmé ou indisponible, **When** elle tente une action d’administration, **Then** l’action est refusée; être chef de raid, assistant, maître du butin ou membre du conseil RCLootCouncil ne suffit pas.
5. **Given** une saison terminée et une nouvelle saison créée, **When** le nouveau roster est préparé, **Then** les inscriptions et paramètres historiques de la saison terminée restent consultables et inchangés.
6. **Given** la date de fin des inscriptions, **When** elle est atteinte, **Then** les inscriptions joueur se ferment sans archiver la saison ni masquer son roster.
7. **Given** une saison avec une date de fin, **When** sept jours se sont écoulés après cette date, **Then** la saison devient archivée en lecture seule; sans date de fin, seul un GM/officier peut la terminer et le même délai de sept jours commence à cet instant.
8. **Given** un catalogue de statuts déjà publié, **When** un GM/officier ajoute ou modifie un statut, **Then** une nouvelle version traçable est créée sans altérer le libellé ni l’explication associés aux inscriptions historiques.
9. **Given** une nouvelle saison de raid, **When** les inscriptions commencent, **Then** chaque joueur choisit de nouveau son statut saisonnier et aucun ancien statut n’est reconduit comme décision confirmée sans nouvelle inscription.
10. **Given** un brouillon incomplet, **When** un officier le consulte ou l’édite, **Then** la saison Dibs actuelle et ses soldes restent inchangés.
11. **Given** les valeurs de la saison précédente, **When** un officier choisit de les réutiliser comme point de départ, **Then** seuls les réglages sont copiés; inscriptions, approbations, allocations courantes et transactions ne le sont pas.

### User Story 4 — Un joueur déclare ses personnages et demande un changement de Main (Priority: P2)

Comme joueur, je veux déclarer mes personnages et demander un changement de Main; comme GM ou officier, je veux examiner ces demandes afin que le statut Main/Alt soit explicite et traçable.

**Why this priority**: Les inscriptions peuvent inclure des personnages hors guilde et la politique Dibs doit suivre les relations déclarées sans inventer d’identités.

**Independent Test**: Déclarer un Main et ses alts, faire approuver une demande de changement, vérifier le statut de probation pendant 14 jours, puis soumettre un autre changement après la fin de la période.

**Acceptance Scenarios**:

1. **Given** un joueur inscrit, **When** il déclare ses personnages et en propose un comme Main, **Then** ces relations restent déclaratives et sont reliées aux identités canoniques existantes sans inférence fondée sur le nom ou le compte.
2. **Given** une demande de changement de Main, **When** un GM ou officier l’approuve, **Then** le nouveau Main est soumis à la pénalité Dibs de 14 jours demandée, la date d’échéance et l’approbateur sont visibles, et le changement est audité.
3. **Given** que la période de 14 jours est écoulée, **When** le joueur soumet une nouvelle demande, **Then** la nouvelle demande peut être examinée et, si elle est approuvée, démarre une nouvelle période de 14 jours.
4. **Given** un groupe Main/Alt existant dans `CharacterEligibility`, **When** le roster saisonnier est activé, **Then** il réutilise ces relations et conserve les données existantes; il ne crée pas une seconde source de vérité Main/Alt.
5. **Given** une période de probation Main/Alt, **When** l’éligibilité est utilisée dans RCLootCouncil, **Then** seule la réponse ou priorité Dibs applicable au personnage candidat est touchée; les autres réponses et boutons RCLootCouncil restent inchangés.
6. **Given** qu’un joueur change de Main après approbation, **When** son nouveau Main devient actif, **Then** son solde courant reste celui de la même personne, sans création ni consommation de Dibs, et l’historique conserve le personnage concerné pour chaque transaction passée.
7. **Given** que le Main et des alts liés ont des soldes Dibs distincts avant leur regroupement, **When** le GM ou l’officier rapproche les soldes, **Then** un solde de personne est établi et toute correction nécessaire est auditée sans réécrire les transactions existantes.

### User Story 5 — Le GM active le module sans perdre son historique (Priority: P2)

Comme GM, je veux activer ou désactiver le module depuis System > Modules afin de contrôler si les inscriptions saisonnières sont utilisées.

**Why this priority**: Le module doit respecter le contrôle des fonctionnalités existant sans rendre la désactivation destructive ni contournable.

**Independent Test**: Désactiver le module, vérifier que ses pages et toutes ses voies d’écriture refusent les actions tout en conservant les saisons; le réactiver et vérifier que les données réapparaissent.

**Acceptance Scenarios**:

1. **Given** un GM autorisé, **When** il désactive le module, **Then** les écritures de roster sont bloquées, les pages indiquent que le module est désactivé et les données historiques sont conservées.
2. **Given** que le module est désactivé, **When** une action est tentée par une autre page, commande, intégration ou message reçu, **Then** aucune voie secondaire ne peut créer ou modifier des données de roster.
3. **Given** que le module est réactivé, **When** une saison encore consultable est ouverte, **Then** ses données et son historique sont disponibles sans réinitialisation.

### User Story 6 — Les joueurs choisissent une voie et consultent les règles de saison (Priority: P1)

Comme joueur, je veux lire les règles publiées et indiquer que je vise la progression Core Raider du jeudi; comme officier, je veux pouvoir ajuster ces règles pour chaque saison.

**Independent Test**: Publier une révision de règlement et des options d’inscription dans un brouillon, ouvrir les inscriptions, puis vérifier l’affichage côté joueur, la capture de la révision consultée et l’absence de promotion Core automatique.

**Acceptance Scenarios**:

1. **Given** les inscriptions ouvertes, **When** un joueur s’inscrit, **Then** il peut choisir la voie Core Raider (intention de progression du jeudi) ou une autre voie configurée, et comprend que ce choix ne lui accorde pas encore le statut Core.
2. **Given** un joueur inscrit sur la voie Core, **When** il consulte le roster, **Then** son état est présenté comme Raider/candidat Core jusqu’à une promotion explicite d’un GM/officier.
3. **Given** un GM/officier modifie le règlement ou la règle de promotion, **When** il publie la modification, **Then** une nouvelle version saisonnière est créée et les saisons précédentes gardent leur texte et leur règle historiques.
4. **Given** un critère de promotion sans méthode de mesure automatisée, **When** un officier évalue un candidat, **Then** il peut enregistrer sa décision et son motif sans que l’addon prétende avoir mesuré présence, ponctualité ou performance.

### User Story 7 — Les officiers prévisualisent et activent une saison complète (Priority: P1)

Comme GM/officier autorisé, je veux examiner les inscriptions approuvées, les identités Main/Alt, les allocations et les écarts avant d’activer la saison afin de démarrer un seul ledger Dibs cohérent.

**Independent Test**: Préparer une saison avec Main/Alt, participants hors guilde, rangs et soldes historiques distincts; vérifier les blocages et l’aperçu, puis activer et vérifier l’identifiant commun, les allocations et la conservation du ledger précédent.

**Acceptance Scenarios**:

1. **Given** des inscriptions ouvertes ou non révisées, **When** un officier demande l’activation, **Then** l’interface affiche les éléments à résoudre et ne change pas le ledger actif.
2. **Given** un roster prêt, **When** l’officier prévisualise les allocations, **Then** seuls les participants approuvés sont inclus, chaque personne est comptée une seule fois et les alts ne reçoivent pas une seconde allocation.
3. **Given** un personnage participant hors guilde sans rang WoW, **When** l’aperçu est calculé, **Then** l’allocation applicable est explicite et configurée; aucune valeur de rang n’est inventée.
4. **Given** des soldes Main/Alt historiques non rapprochés, **When** l’activation ferait fusionner ces soldes, **Then** l’activation est bloquée jusqu’à l’examen approuvé du GM/officier qui conserve le solde du Main, sans addition automatique.
5. **Given** l’activation validée, **When** elle est confirmée, **Then** le même `seasonId` identifie saison, roster, allocations et ledger actif; le ledger précédent reste archivé et lisible.
6. **Given** une erreur pendant l’activation ou un rejeu de la même opération, **When** le client retente, **Then** aucune demi-activation ni double allocation n’est produite.

### User Story 8 — Les officiers réconcilient les allocations d’une saison (Priority: P1)

Comme GM/officier autorisé, je veux comparer l’allocation attendue au ledger de la saison sélectionnée et appliquer seulement les corrections approuvées afin que la réconciliation ne balaie pas tous les membres historiques de la guilde.

**Independent Test**: Réconcilier une saison avec un petit roster actif au milieu de nombreux personnages inactifs, vérifier les lignes en retard/en trop, puis appliquer une correction auditée avec contrôle de version.

**Acceptance Scenarios**:

1. **Given** une saison active, **When** l’officier demande l’aperçu, **Then** la réconciliation utilise les participants approuvés et le rang/allocation applicables à cette saison, pas le roster complet de guilde par défaut.
2. **Given** une allocation ou un rang modifié, **When** l’aperçu est recalculé, **Then** les valeurs attendues et réelles, la raison de l’écart et la révision utilisée sont visibles avant toute écriture.
3. **Given** un aperçu inchangé et approuvé, **When** l’officier applique une correction avec motif, **Then** un événement append-only est ajouté au ledger de la même saison et un rejeu ne duplique pas l’ajustement.
4. **Given** une saison historique, **When** un officier la consulte, **Then** sa réconciliation ne modifie ni ne remplace le ledger de la saison active.

### Edge Cases

- Le même personnage tente de s’inscrire deux fois à une saison, ou deux inscriptions concurrentes arrivent pour la même identité.
- Un joueur est membre de guilde sur un personnage et inscrit un autre personnage hors guilde.
- Le personnage change de nom ou de royaume, ou une identité devient ambiguë; aucune fusion automatique ne doit modifier les relations existantes.
- L’autorité de guilde change, le roster de guilde n’est pas chargé, ou la guilde courante change pendant une opération.
- Une inscription est modifiée après fermeture, annulée après son approbation ou restaurée par un administrateur.
- Des horaires, catégories ou rôles sont retirés d’une saison après que des joueurs les ont choisis.
- Un statut saisonnier est renommé, retiré ou voit son explication modifiée après avoir été choisi; l’inscription historique doit rester interprétable avec la version qui était publiée au moment du choix.
- Un joueur possède un Main, plusieurs alts, une demande de Main en attente, une demande rejetée ou une probation active.
- Une demande de changement est présentée après l’expiration de la probation précédente.
- Une saison est archivée, le module est désactivé, ou le joueur change de guilde; l’historique ne doit pas être effacé ni exposé à une autre guilde.
- Une activation échoue entre la publication du roster, des allocations et du ledger; aucun composant ne doit annoncer la saison active avant que le manifeste de révision ne soit cohérent.
- Deux officiers modifient le brouillon ou approuvent la même inscription depuis des révisions différentes; l’opération obsolète doit échouer sans écraser la révision plus récente.
- Des membres hors guilde n’ont pas de rang WoW exploitable; l’allocation doit suivre la règle explicitement publiée de la saison.
- Le joueur demande la voie Core, mais n’a pas encore satisfait ou fait vérifier les critères; l’intention ne doit pas être affichée comme promotion acquise.
- La distribution des données n’est pas disponible, échoue ou retourne des versions incompatibles; l’interface doit indiquer l’état et ne pas afficher un roster partiel comme complet.
- Le classeur contient des formules erronées (`#REF!`) ou des plages bornées; ces défauts ne deviennent pas des règles du produit.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Le produit MUST offrir un cycle de saison complet, du brouillon à l’archive. Roster, règles, allocations et ledger restent des responsabilités de domaine distinctes, mais MUST partager un seul `seasonId` fonctionnel sans liaison manuelle. Le module reste contrôlable dans System > Modules.
- **FR-002**: Le produit MUST conserver les saisons et inscriptions quand le module est désactivé et MUST refuser toutes les actions d’écriture de ce module jusqu’à sa réactivation.
- **FR-003**: Un GM/officier autorisé MUST pouvoir préparer un brouillon de saison comprenant périodes, horaires, règles, statuts de participation, critères de promotion Core configurables et allocations Dibs par rang. La création du brouillon MUST NOT changer le ledger actif.
- **FR-030**: À la création, l’interface GM/officier MUST demander le début de saison et le début des inscriptions. La fin des inscriptions et la fin prévue de la saison MAY être omises; la fin des inscriptions bloque les nouvelles écritures sans archiver la saison.
- **FR-031**: Une saison MUST rester consultable jusqu’à sept jours après sa fin. Une fin prévue atteint ce délai automatiquement; si aucune date de fin n’était définie, un GM/officier MUST pouvoir terminer explicitement la saison. Après sept jours, le roster saisonnier devient en lecture seule sans supprimer son historique.
- **FR-004**: Le produit MUST permettre à un joueur de créer et modifier sa propre inscription à une saison ouverte et MUST empêcher la modification d’une inscription par un autre joueur non autorisé.
- **FR-005**: L’inscription MUST représenter au minimum le joueur, ses personnages/Main proposé pour cette saison, sa voie demandée (dont l’intention Core Raider), son statut saisonnier accordé, la spécialisation principale, un deuxième choix facultatif et le ou les rôles choisis. La voie demandée MUST NOT être traitée comme un statut accordé.
- **FR-032**: La catégorie de roster MUST représenter un statut saisonnier de participation au raid, distinct du rang natif de guilde, du rôle de combat et de la relation Main/Alt.
- **FR-033**: Le produit MUST distinguer les rangs natifs/autorités de guilde (**Guild Master**, raid leader; **Officer**, responsable des politiques et de l’ordre, sans implication Core), les statuts saisonniers accordés (**Raider**, **Core Raider**, **Member**, **Initiate**, **Alt / Officer Alt**) et la voie demandée par le joueur. Les descriptions fournies par la guilde MUST être présentées comme définitions initiales modifiables par saison; un Officer n’est pas automatiquement Core Raider et un alt reste un personnage d’une personne, pas un participant distinct. La définition Core Raider décrit un joueur qui performe, est présent et ponctuel, suit les directives et mécaniques, atteint les attentes de dégâts/soins et aide les autres; ses critères doivent être configurés par saison et son attribution reste une décision GM/officier dans la première version.
- **FR-034**: Dans la migration conceptuelle du classeur de référence, le choix **AotC** MUST être présenté comme le statut saisonnier **Raider** et MUST NOT devenir un statut concurrent distinct, sauf si un GM/officier crée explicitement une autre option pour une saison ultérieure.
- **FR-035**: Un GM ou officier autorisé MUST pouvoir ajouter, renommer, décrire, ordonner, désactiver et remplacer les statuts proposés pour une saison. Une modification publiée MUST créer une nouvelle version avec auteur, date d’effet et motif facultatif; elle MUST NOT réécrire les versions antérieures.
- **FR-036**: Chaque inscription MUST conserver l’identité stable du statut choisi et la version publiée de son nom et de son explication afin qu’une inscription historique reste compréhensible après une modification du catalogue.
- **FR-037**: Les voies et statuts saisonniers MUST être confirmés de nouveau pour chaque nouvelle saison. Le produit MAY proposer la valeur précédente comme aide visuelle, mais MUST NOT la considérer comme confirmée sans action du joueur ou décision administrative auditée, et MUST NOT modifier automatiquement les rangs de guilde WoW.
- **FR-006**: Le produit MUST accepter un personnage qui n’est pas membre de guilde. L’appartenance au roster de guilde MAY faciliter sa recherche, mais MUST NOT être requise pour une inscription.
- **FR-007**: Le produit MUST NOT inférer une relation Main/Alt depuis une ressemblance de nom, de classe ou une identité Battle.net non accessible à l’addon.
- **FR-008**: Le joueur MUST pouvoir consulter la liste des inscrits en lecture seule, avec les seules informations de roster nécessaires à la préparation de la saison.
- **FR-009**: Le produit MUST fournir aux GM et officiers autorisés une interface de gestion distincte de la vue joueur pour examiner, corriger, retirer ou annuler les inscriptions et voir les détails administratifs pertinents.
- **FR-010**: Les écritures de gestion MUST vérifier l’identité et le rôle GM/officier réels dans la guilde courante selon le système de permissions existant; chef de raid, assistant, autorité de butin ou conseil RCLootCouncil ne MUST NOT accorder ce droit.
- **FR-011**: L’autorisation administrative MUST échouer si le roster de guilde est absent, périmé ou ambigu.
- **FR-012**: Chaque saison, inscription, relation Main/Alt, demande de changement et décision administrative MUST posséder une identité stable et conserver un historique traçable des créations, modifications, approbations, rejets, retraits et annulations.
- **FR-013**: Les statistiques MUST présenter la composition des inscriptions par rôle, classe, type d’armure et catégorie de roster, selon les options configurées dans la saison.
- **FR-014**: Les statistiques MUST être calculées sans limite fixe de lignes et MUST être cohérentes avec les inscriptions visibles après application des mêmes filtres.
- **FR-015**: Pour la composition, chaque joueur MUST contribuer au plus une fois via son personnage Main sélectionné; les alts liés ne MUST NOT gonfler les totaux de joueurs.
- **FR-016**: Le produit MUST rendre explicite l’état de chaque inscription, les filtres appliqués, les totaux, les résultats vides, et l’état de disponibilité ou d’actualisation des données.
- **FR-017**: Le parcours Main/Alt MUST réutiliser les relations gérées par `CharacterEligibility`, y compris leurs identités canoniques et leur historique existant, sans créer de relation concurrente.
- **FR-018**: Le produit MUST permettre à un joueur de demander un changement de Main et réserver l’approbation ou le rejet aux GM/officiers autorisés.
- **FR-019**: Toute approbation d’un changement de Main MUST démarrer une pénalité Dibs de 14 jours pour le nouveau Main. Après expiration, un nouveau changement peut être demandé et approuvé, auquel cas une nouvelle pénalité de 14 jours démarre.
- **FR-020**: La probation Main/Alt MUST s’appliquer uniquement aux règles ou boutons Dibs appropriés pour le personnage candidat. Elle MUST NOT altérer les réponses, boutons ou décisions non-Dibs de RCLootCouncil.
- **FR-021**: Une inscription, une approbation ou une promotion Core MUST NOT ajouter, consommer, rembourser ou ajuster des Dibs. L’activation explicite d’une saison MAY initialiser ses allocations Dibs selon les règles de rang de cette saison pour les participants approuvés; elle MUST NOT modifier l’ancien ledger. Chaque transaction historique MUST garder son personnage d’origine.
- **FR-022**: Le solde courant et l’éligibilité Dibs d’une personne MUST suivre son identité de personne approuvée à travers ses personnages liés et son changement de Main; les personnages MUST NOT recevoir chacun un solde indépendant du seul fait qu’ils sont inscrits comme alts.
- **FR-023**: Avant de regrouper les soldes Dibs historiques de personnages reliés, un GM ou officier autorisé MUST les examiner et rapprocher en un solde de personne. Toute différence nécessaire MUST être enregistrée comme ajustement administratif append-only, avec acteur, date et motif; les transactions existantes MUST rester intactes. Le solde regroupé ne MUST NOT être activé avant la fin de ce rapprochement.
- **FR-024**: Les révisions de configuration, règles, roster approuvé et activation MUST être distribuées avec des références de révision/hash compatibles. Un client MUST NOT considérer une saison active ni un roster complet avant d’avoir les dépendances requises; les transferts restent bornés et l’état « en retard » visible.
- **FR-025**: Une inscription partielle, une synchronisation échouée ou une version incompatible MUST être signalée comme telle; un client MUST NOT présenter des données incomplètes comme un roster complet et confirmé.
- **FR-026**: La création, activation, fin, archive ou migration d’une saison MUST NOT effacer ses données ou celles des saisons précédentes. Les conversions d’identifiants historiques MUST être explicites, idempotentes et vérifiables; l’accès reste limité à la guilde propriétaire.
- **FR-027**: Les professions et équipes Mythic+ MUST rester hors de cette feature et ne MUST NOT être ajoutées au formulaire, aux statistiques ou à l’administration du roster saisonnier.
- **FR-028**: Le produit MUST fournir des validations de totaux par rôle, classe, type d’armure et catégorie, incluant plusieurs centaines d’inscriptions, des alts liés, des joueurs hors guilde, des inscriptions retirées et des filtres.
- **FR-029**: Les pages joueur et gestion MUST rester utilisables à différentes tailles de fenêtre; les listes MUST avoir un défilement ou une pagination bornée, et les colonnes et textes MUST rester lisibles sans débordement.
- **FR-038**: Les règlements visibles aux joueurs MUST être modifiables et versionnés dans la saison, avec date d’effet et auteur. Chaque saison conserve le texte qu’elle a publié; un changement ne modifie pas les saisons antérieures.
- **FR-039**: La voie « Core Raider » demandée par un joueur MUST être séparée de son statut accordé. Une inscription dans cette voie signifie une intention de progression du jeudi; elle commence comme Raider/candidat et ne devient Core Raider qu’après décision GM/officier.
- **FR-040**: Les règles de promotion Core Raider MUST être configurables et versionnées par saison. La première livraison MUST permettre une évaluation et une promotion manuelles auditables; elle MUST NOT prétendre mesurer automatiquement présence, ponctualité, performance ou aide apportée.
- **FR-041**: Les règles de raid informatives MUST être distinguées des paramètres que le logiciel applique. L’interface ne MUST NOT annoncer qu’une règle textuelle est imposée si aucun mécanisme vérifiable ne l’applique.
- **FR-042**: Chaque brouillon MUST posséder une identité saisonnière canonique et des révisions concurrentes contrôlées. Toute inscription, règle, allocation, Main saisonnier et ledger MUST référencer ce même `seasonId`; les objets persistants séparés MUST partager cet identifiant et une révision/empreinte d’activation.
- **FR-043**: Un brouillon MUST pouvoir réutiliser des paramètres d’une saison antérieure sans recopier ses inscriptions, décisions, soldes courants ou transactions.
- **FR-044**: Les allocations de rang MUST être configurées par saison et rang WoW, avec une règle explicite pour un participant sans rang WoW. La voie Core/Raider ne change pas l’allocation, sauf règle explicite de cette saison.
- **FR-045**: La prévisualisation des allocations et la réconciliation MUST être limitées aux personnes approuvées du roster sélectionné, regroupées par identité Main/Alt approuvée; les personnages inactifs de la guilde ne MUST NOT être ajoutés simplement parce qu’ils figurent dans le roster complet WoW.
- **FR-046**: La réconciliation MUST distinguer l’initialisation d’une allocation de saison, les écarts de rang/allocation en cours de saison et le rapprochement de soldes historiques Main/Alt. Chaque écriture exige un aperçu révisé, une autorisation, un motif lorsque requis et un événement append-only idempotent.
- **FR-047**: L’activation MUST exiger une prévalidation des dates/règles, inscriptions approuvées, Main/Alt ambigus, rapprochements nécessaires et allocations. Elle MUST être idempotente et échouer sans exposer une activation ou un ledger partiel.
- **FR-048**: L’activation MUST garder l’ancien ledger et son historique consultables; les allocations de la nouvelle saison sont établies selon ses règles et son roster approuvé, sans importer silencieusement les soldes de l’ancienne saison.
- **FR-049**: Une saison MUST suivre les états Brouillon, Inscriptions ouvertes, Révision, Prête, Active, Terminée et Archivée, avec transitions autorisées et historique de l’acteur. L’archive intervient sept jours après la fin de saison, pas sept jours après la fermeture des inscriptions.
- **FR-050**: La migration des saisons existantes MUST préserver chaque saison Dibs, chaque saison roster, ses inscriptions et ses transactions. Toute ancienne liaison roster→Dibs MUST être conservée comme alias historique; la migration MUST NOT deviner un nouveau lien ni fusionner des soldes.

### Faits de référence et limites de portée

- Le classeur `Raid Team Planner For 12.1.xlsx` présente une feuille « Week Raid » avec inscription/catégorie, joueur, classe ou spécialisation, deuxième choix, rôle, type d’armure, champs « token », « Dibs Used » et « Raid Token », et des totaux de composition. Ces éléments sont des exemples de contenu observé, pas des règles automatiques approuvées.
- Le classeur contient également des feuilles Profession et Mythic+ Teams, explicitement exclues de cette feature.
- Certaines formules du classeur sont cassées ou reposent sur des plages bornées. La nouvelle fonction doit valider les résultats avec les lignes réelles du roster et ne pas reproduire ces limites.
- Les exigences d’inscription, de gestion saisonnière, d’accès hors guilde, de lecture seule et de pénalité Main de 14 jours proviennent de la demande utilisateur et prévalent sur toute interprétation du classeur.
- L’architecture actuelle inclut un service `CharacterEligibility` pour les relations et la probation Main/Alt, `Permissions` pour l’autorité fondée sur la guilde, et des interfaces Player/Officer. Le transport des nouvelles données n’est pas confirmé et doit être étudié pendant le plan.

### Règlements initiaux de raid — configurables par saison

Les exemples suivants sont des valeurs initiales demandées par la guilde, pas des règles codées en dur. Les GM/officiers peuvent les modifier, les publier et les versionner pour une saison. Les textes informatifs sont séparés des paramètres réellement appliqués par l’addon.

- Communication pendant les pulls : instructions par le raid leader ou les personnes désignées; limiter le bavardage pendant les pulls; garder les échanges constructifs.
- Besoin, cupidité/transmog et passe : Need pour équiper en spécialisation principale, option Greed/Transmog pour hors-spécialisation, et passe pour les autres cas avant AotC, selon la règle publiée.
- Dibs : un appel par personne par saison, priorité Need++, appels avant le pull, et consommation seulement par le gagnant lorsque plusieurs personnes appellent.
- Pièces de set : une pièce par personne jusqu’à ce que toutes les personnes admissibles du groupe de jetons en aient une, toutes difficultés incluses.
- Alts : accès après AotC et priorité hors-spécialisation, avec exception lorsqu’un officier demande un changement de personnage pour combler un rôle ou une classe manquante.
- Changement de Main : approbation GM/officier, seuil d’écart d’ilvl configurable — 10 actuellement selon la règle fournie —, probation de deux semaines et règle de butin associée configurable, avec exception de rôle si elle est approuvée.

Une règle non automatisable ou non vérifiable dans WoW reste un règlement publié; le produit ne prétend pas l’imposer. Le joueur peut toujours voir la version applicable à la saison choisie.

### Key Entities *(include if feature involves data)*

- **Saison**: identité canonique, cycle de vie, calendrier, révisions des règles, roster, allocations et ledger associé.
- **Règles de saison**: règlement informatif et paramètres appliqués, chacun versionné et clairement distingué.
- **Manifeste d’activation**: révisions/empreintes exactes du règlement, roster approuvé, allocations et ledger rendus actifs ensemble.
- **Catalogue de statuts saisonniers**: ensemble versionné des niveaux de participation proposés pour une saison, avec identité stable, nom, explication, ordre, état actif, auteur et date d’effet.
- **Inscription saisonnière**: joueur/personne, personnages, Main saisonnier, voie demandée, statut accordé, spécialisation, rôles, révision de règle et historique d’approbation.
- **Évaluation Core Raider**: candidat, règle saisonnière applicable, décision manuelle, motif, auteur, date et version.
- **Allocation saisonnière**: règle par rang de guilde et état/solde attendu par personne approuvée, avec cas sans rang.
- **Réconciliation saisonnière**: aperçu versionné d’écarts entre roster approuvé, allocation attendue et ledger réel, puis décision auditée.
- **Personne**: identité canonique à laquelle appartiennent les relations de personnages, l’éligibilité et le solde courant de Dibs.
- **Relation Main/Alt**: association déclarée entre une personne et ses personnages, statut de revue, Main courant et historique des changements.
- **Demande de changement de Main**: ancien et nouveau Main, demandeur, décision, approbateur, dates d’effet et de fin de probation, motif et audit.
- **Rapprochement initial des soldes**: soldes historiques examinés par un GM/officier autorisé, solde de personne approuvé et audit de tout ajustement append-only nécessaire avant regroupement.
- **Roster publié**: projection des inscriptions autorisées à la consultation des membres, distincte des données administratives privées.
- **Statistiques de composition**: agrégats cohérents avec les inscriptions admissibles et la saison sélectionnée.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Un joueur peut compléter, modifier et consulter sa propre inscription à une saison ouverte sans qu’une inscription d’un autre joueur soit modifiée.
- **SC-002**: Dans un scénario de validation contenant au moins 1 000 inscriptions, 100 % des inscriptions admissibles apparaissent dans la liste paginée ou filtrée et les statistiques concordent avec les lignes correspondantes.
- **SC-003**: Pour chaque scénario de validation, les totaux par rôle, classe, armure et catégorie égalent le nombre d’inscriptions admissibles selon la règle de comptage et n’ajoutent aucun alt comme joueur supplémentaire.
- **SC-004**: 100 % des tentatives d’écriture par un joueur non autorisé, une personne hors guilde, ou avec un roster d’autorité indisponible sont refusées sans changement de données.
- **SC-005**: Toutes les approbations de changement de Main appliquent une échéance de probation à 14 jours; les demandes suivantes sont autorisées à être examinées après cette échéance et une approbation recommence la période.
- **SC-006**: La désactivation du module bloque chaque voie de création et de modification testée sans supprimer les saisons, puis la réactivation rend ces mêmes données accessibles.
- **SC-007**: L’inscription ou l’administration générale du roster ne produit aucune mutation Dibs ou loot; un changement de Main approuvé conserve exactement le solde courant de la personne et ne réécrit aucune transaction historique.
- **SC-008**: Les joueurs peuvent parcourir le roster en lecture seule et les GM/officiers peuvent effectuer les tâches de gestion sans exposition de champs privés dans la vue publique.
- **SC-009**: La validation en jeu vérifie l’inscription d’un personnage hors guilde, la consultation par un joueur, le refus des permissions non valides, l’actualisation après synchronisation, et les interfaces aux tailles de fenêtre prises en charge.
- **SC-010**: Dans 100 % des scénarios de modification d’un statut publié, les nouvelles inscriptions utilisent la nouvelle version tandis que les inscriptions historiques continuent d’afficher le nom et l’explication de la version choisie initialement.
- **SC-011**: Lors d’une nouvelle saison, aucune désignation saisonnière antérieure n’est comptée comme inscription confirmée sans une nouvelle action du joueur ou une décision administrative auditée.
- **SC-012**: Créer et éditer un brouillon, fermer les inscriptions ou publier un règlement ne modifie jamais l’identifiant ou le solde du ledger actif.
- **SC-013**: L’activation validée référence un seul `seasonId` et des révisions cohérentes pour règlement, roster approuvé, allocations et ledger; une erreur injectée ou un rejeu ne crée ni demi-activation ni double allocation.
- **SC-014**: Dans un test de saison contenant 30 participants approuvés et au moins 900 membres/personnages historiques non inscrits, l’aperçu et la réconciliation ne calculent/affichent que les 30 participants, avec une ligne par personne Main/Alt.
- **SC-015**: Un candidat inscrit sur la voie Core reste Raider/candidat jusqu’à une promotion explicite auditée; une modification de la règle de promotion ne change pas les décisions passées.
- **SC-016**: Les règlements historiques restent affichables dans la langue disponible et identiques à la révision publiée pour chaque saison, même après modification de la saison active.

## Assumptions

- Une inscription appartient à une saison, une personne canonique et un personnage; un joueur peut inscrire plusieurs personnages, mais un seul Main contribue aux statistiques de composition par saison.
- Les catégories et horaires trouvés dans le classeur restent configurables. `AotC` est interprété comme le statut `Raider`; `Sunday` décrit une équipe ou un horaire plutôt qu’un niveau d’autorité; `Casual` peut rester un statut configurable si le GM le souhaite.
- Les descriptions fournies pour Guild Master, Officer, Core Raider, Raider, Member, Initiate et Alt / Officer Alt constituent le catalogue initial demandé, pas des règles immuables. Une politique d’inactivité de cinq mois ou des avantages de banque/réparation restent informatifs tant qu’une feature distincte ne les automatise pas explicitement.
- Les champs « Dibs Used » et « Raid Token » sont omis de cette feature pour le moment.
- L’inscription et les approbations ne mutent pas le ledger. L’activation crée un nouvel espace d’allocation par saison; les soldes ne sont pas reportés implicitement de la saison précédente. Le solde d’une personne est distinct de son personnage affiché; les transactions historiques restent append-only.
- Les allocations restent fondées sur les rangs WoW par saison selon la constitution. Le roster approuvé limite les personnes ciblées; la demande de voie Core et le statut Core Raider accordé ne sont ni une permission ni un facteur d’allocation automatique.
- Un participant hors guilde reçoit l’allocation « sans rang » explicitement définie par saison; aucun rang ou identité Battle.net n’est inféré.
- La saison logique peut continuer à utiliser des stockages/synchronisations distincts par domaine. Un manifeste d’activation et un identifiant canonique garantissent leur cohérence sans devoir transférer le roster entier dans chaque message.
- La période de probation est exactement 14 jours à compter de l’approbation, sauf clarification ultérieure; l’application de cette pénalité suit les règles Dibs existantes et ne désactive pas globalement le personnage dans RCLootCouncil.
- Les données historiques restent conservées lorsqu’une saison se termine, quand un module est désactivé ou lorsque le joueur change de guilde; leur visibilité reste limitée à leur guilde d’origine et aux accès autorisés.
- Le plan doit confirmer les limites des API WoW Retail et du transport addon-à-addon disponibles avant de choisir comment distribuer le roster, particulièrement pour les personnages hors guilde.
