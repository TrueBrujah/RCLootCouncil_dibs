# Audit runtime, mémoire, architecture et intégrité — 28 octobre 2026

## Suivi des correctifs — 28 octobre 2026

Après présentation des constats, trois correctifs ciblés ont été appliqués :

- **RA-16 corrigé** : l'initialisation de capacité crée toujours le cadre
  officier caché, mais diffère son premier rendu; celui-ci arrive au premier
  affichage. Un appel UI explicite conserve le rendu immédiat. Les tests
  confirment zéro lecture du catalogue au démarrage et une projection au premier
  affichage. Fermeture/réouverture et routes explicites sont couvertes.
- **RA-15 corrigé** : LootRules.GetAuthoritySnapshot lit le getter scalaire
  Seasons.GetCatalogRevision, puis conserve la copie du seul record courant.
  La décision et les 40 passes du watcher passent sans copie de l'historique.
- **RA-01 partiellement corrigé** : chaque PREDIB_INDEX reçu lit l'historique
  local une fois puis l'indexe par requestId, après validation de toutes les
  entrées. Révisions, hashes et règles d'ownership restent vérifiés. Les tests
  à 50/60 participants synthétiques réduisent les lectures de 980/1180 à 49/59.
  Copies et validations résiduelles, autres types de message et index émis
  restent à mesurer et à traiter séparément.
- **Rafraîchissement RC pendant la détection des modules corrigé** : la boucle
  de disponibilité, bornée à 120 essais, rappelait l'installation du hook de
  loot chaque seconde. Si le hook existait déjà, cette fonction recalculait
  toute la projection du loot. Les tentatives réutilisent maintenant le hook
  sans recalcul; les mises à jour de loot et les rafraîchissements explicites
  gardent leur comportement.

Résultat actuel : 82 tests ciblés PASS, 0 FAIL, dans dix fichiers :
startup_catalog_work_audit_spec.lua, rc_startup_work_audit_spec.lua,
sync_guild_scale_audit_spec.lua, retail_navigation_spec.lua,
b07_capability_isolation_spec.lua, predibs_sync_recovery_spec.lua et
multi_ledger_sync_spec.lua, rclootcouncil_hook_retry_work_spec.lua,
rclootcouncil_buttons_spec.lua et rclootcouncil_capability_spec.lua. Cela
valide les chemins simulés; ce n'est pas une mesure CPU, heap ou réseau de WoW.
Les
changements locaux antérieurs ont été préservés. Aucun commit, publication,
effacement de données ou changement de bibliothèque tierce n'a été effectué.

### Vérification Retail après déploiement — 29 octobre 2026

Les captures fournies montrent Dibs et RCLootCouncil actifs. Une capture indique
**Current CPU 100 %, 1,2 FPS et warning RC Count 5**; la suivante indique
**Current CPU 0,02 % et 140,8 FPS**, tandis que la moyenne de session (29 %) et
le pic (100 %) persistent. Cette paire est cohérente avec un blocage bref, pas
une charge constante. Les moyennes par addon de 2 % Dibs et 17 % RC n'excluent
pas un callback ponctuel trop long.

Le test ciblé rclootcouncil_hook_retry_work_spec.lua a d'abord échoué sur la
projection répétée, puis passe après correction. La source
integrations/RCLootCouncil.lua installée correspond maintenant au SHA256 de la
source du dépôt. Cela confirme la copie, pas encore l'effet en jeu après
rechargement. L'avertissement nomme RC comme propriétaire d'exécution, mais ne
donne pas le hook déclencheur. L'exécution « insecure » désigne le contexte de
script addon et son budget de temps; elle ne démontre pas une action sécurisée
interdite ou une attaque.

## Passage à l'échelle : 50–60 membres en ligne et travail d'objets au démarrage

L'utilisateur indique 50–60 membres souvent connectés et demande d'examiner
les lectures joueurs/objets et synchronisations regroupées. Le nombre de clients
utilisant effectivement Dibs n'a pas été mesuré. Les API de roster sont lues
avec GetNumGuildMembers(true); le parcours peut donc inclure les membres hors
ligne et dépasser les 50–60 personnages connectés.

### Synchronisation active et amplification de RA-01

- [SyncV2](../../src/modules/SyncV2.lua), OnLifecycle 2873–2935 : au démarrage,
  les annonces sont groupées en trois échéances locales (immédiate, +1 s, +2 s).
  Le heartbeat est fixé à 60 s, lignes 2866–2872, sans dispersion aléatoire.
  OnRosterChanged 3078–3093 regroupe les notifications dans un timer de 1 s;
  OnLifecycle évite les cycles roster séparés de moins de 5 s. Ces protections
  existent et ne doivent pas être présentées comme absentes. Pump/reminders
  précèdent toutefois cette condition de coalescence.
- Chaque cycle appelle AnnounceAllRequestIndexes, lignes 1409–1420 : pour chaque
  ledger approuvé, BuildRequestIndex 1356–1387 parcourt l'historique, calcule les
  empreintes, trie, puis limite le résultat à 500 entrées. La limite de sortie
  ne borne pas le nombre initial de demandes parcourues ou triées. BuildManifest
  1390–1403 produit ensuite un index complet et son empreinte. Les index sont
  rediffusés même quand ils n'ont pas changé.
- Chaque message passe synchroniquement par la validation, la construction
  d'enveloppe et la sérialisation avant l'envoi. Sync.Send 1083–1117 utilise
  BULK via [Ace3.SendComm](../../src/integrations/Ace3.lua), lignes 170–194.
  [Le contrat AceComm](https://www.wowace.com/projects/ace3/pages/api/ace-comm-3-0)
  régule l'envoi avec ChatThrottleLib et fragmente/réassemble les messages.
  Ce contrat ne constitue pas un budget de calcul pour le code applicatif en
  amont, ni pour Deserialize/Receive à réception. Aucun débit fixe en octets/s
  n'est supposé pour la version du client.
- OnAddonMessage, lignes 2832–2855, appelle Deserialize puis Receive dans le
  même callback. Pour PREDIB_INDEX, Receive 2497–2530 appelle localRequest par
  entrée; localRequest 1737–1743 relit l'historique et le parcourt. Les détails
  absents sont demandés sous contrôle d'identité/permissions; un index déjà à
  jour impose néanmoins ces parcours et des calculs de hash. Le cache replay
  de 256 messages protège des mêmes IDs, pas des mêmes contenus annoncés par
  des pairs différents ou avec de nouveaux IDs. Le compteur de 6/60 s vu dans
  ce fichier concerne CHANNEL_TEST, pas tous les digests.
- [Identity](../../src/modules/Identity.lua), lignes 140–184 et 196–207,
  possède déjà un roster indexé et invalidé à changement; ce n'est pas un pull
  réseau de toute la liste de joueurs à chaque résolution. Des scans directs
  subsistent dans Permissions (RA-14). [RequestDelivery.Pump](../../src/modules/RequestDelivery.lua),
  lignes 368–420, borne déjà à 4 les envois par passage et à 8 les dossiers
  examinés côté coordinateur; ne pas généraliser une absence de limites.

Tests ciblés nouveaux : [sync_guild_scale_audit_spec.lua](../../tests/integration/sync_guild_scale_audit_spec.lua),
avec une instance locale, 50 puis 60 identités de roster, des messages uniques
attribués aux 49/59 autres pairs, un instant de burst fixe et 20 demandes déjà
identiques. Les messages passent bien OnAddonMessage et aboutissent tous à
DIGEST_CURRENT, sans envoi de DETAIL_FETCH. Ce test ne lance pas 60 processus
WoW, n'émule pas le débit/fragmentation natif et ne mesure pas de temps CPU.

| Participants synthétiques | Index reçus par le client local | Lectures GetHistory | Détails demandés |
|---:|---:|---:|---:|
| 50 | 49 | 980 | 0 |
| 60 | 59 | 1180 | 0 |

Les deux budgets d'au plus une lecture d'historique par message échouent.
Le troisième test confirme deux annonces GUILD d'index inchangé sur deux
heartbeats, avec intervalle 60 s. Résultat : **1 PASS / 2 FAIL**;
[journal](SYNC-GUILD-SCALE-20261028.txt). Les nouvelles régressions précisent
l'ampleur de RA-01 plutôt que de compter une seconde vulnérabilité identique.

Modèle de diffusion, pas mesure réseau : si 60 clients Dibs annoncent chacun
un index par cycle, cela fait 60 annonces et jusqu'à 60×59 = 3540 réceptions
chez les autres clients, avant les autres types et fragments. Un seul client
en reçoit 59, pas 3540. À 50 clients : 2450 réceptions agrégées. Le nombre de
membres en ligne seul ne prouve pas que tous participent à ces échanges.

### RA-16 — Catalogue d'objets construit pour un tableau de bord caché

- **Status FIXED après suivi; confiance HIGH pour le déclenchement; risque P1 de démarrage;
  coût natif, nombre d'objets réellement lus et part des Mo non mesurés.**
- Core crée toujours la fenêtre au démarrage, mais demande maintenant de
  différer son premier rendu. OfficerUI rend la route au premier OnShow; une
  route explicitement demandée garde un rendu immédiat. Un cadre libéré par
  AceGUI est recréé à la prochaine demande.
- Le rendu overview appelle la projection du dashboard, qui appelle
  buildDashboardPreDibBossGroups, lignes 2248–2254 et 2351. Celle-ci demande
  GetLootCatalog avec une limite de 3500, même avec un historique de demandes
  vide. [EncounterJournal.GetLootCatalog](../../src/integrations/EncounterJournal.lua),
  lignes 1113–1133, construit le cache manquant synchroniquement avec
  scanAdventureGuideCatalog 984–1106. Le scan sélectionne tiers/instances/bosses,
  lit le loot, enrichit les objets et trie; ses bornes déclarées sont 20 tiers,
  80 instances, 40 boss, 80 loots et au plus 3500 entrées retenues. Il n'est pas
  découpé en tranches par un ordonnanceur applicatif.
- Il s'agit d'une lecture locale via les API du Journal, distincte des données
  synchronisées entre clients Dibs. Le cache évite un nouveau scan à chaque
  lecture, jusqu'à son invalidation; aucune retransmission du catalogue complet
  par le heartbeat n'est démontrée.
- Le test ciblé compte zéro appel catalogue pendant Initialize, un au premier
  affichage et une nouvelle projection à la réouverture sans nouveau scan du
  Journal déjà caché. Les tests de navigation couvrent routes explicites et
  fermeture/réouverture. Le double ne simule ni les 3500 objets ni leurs
  allocations. Un scan synchronisé au premier affichage demeure possible si le
  cache n'est pas déjà construit.

### Corrections progressives proposées pour cette charge

1. Mesurer les correctifs RA-16 et RA-15 dans WoW : ils diffèrent le rendu
   caché et évitent la copie historique pour une décision. Comparer le même
   démarrage pour CPU/allocation/rétention avec le protocole Retail.
2. Continuer l'optimisation Sync sans casser la réparation. RA-01 réduit
   maintenant les recherches PREDIB_INDEX à une lecture d'historique par
   message. Mesurer les copies restantes, les digests émis et répartir les
   rattrapages en préservant cadence/repair de spec 017.
3. Répartir le travail non critique et les rattrapages avec un budget mesuré par
   tranche, une concurrence bornée et un léger décalage entre clients. Réserver
   les opérations de loot urgentes; différer les tâches non critiques en combat.
   Un heartbeat compact et les détails différentiels nécessitent une évolution
   explicite du protocole pour clients mixtes. Conserver une annonce périodique
   et le rattrapage des nouveaux clients; envoyer seulement lors des changements
   ferait perdre la réparation après message manqué. Le plan 017 exige le
   rattrapage dans la cadence heartbeat existante : la dispersion et les budgets
   doivent respecter cette contrainte et être testés avec pertes/reconnexion.

Pas de réécriture générale, de modification de bibliothèque ou de correctif de
production appliqué. Les chiffres de lectures et les bornes statiques ne sont
pas une preuve de causalité complète pour les 18,94 ms ou les 300 Mo rapportés.

Validation de ce lot : [139 fichiers src comparés, zéro différence](SYNC-SCALE-SOURCE-INTEGRITY-20261028.json),
liens locaux du rapport valides et pas de whitespace ajouté dans les deux tests.
Les contrôles historiques globaux restent en échec :
[46 fiches sans annotations](SYNC-SCALE-DOC-VALIDATION-20261028.txt),
[70 écarts avec l'ancienne baseline](SYNC-SCALE-GUARD-20261028.txt),
[whitespace préexistant](SYNC-SCALE-DIFF-CHECK-20261028.txt). Aucun changement
local n'a été effacé pour masquer ces échecs. Pas de suite complète relancée.

## Premiers échantillons CPU fournis en jeu, vers 20 h

Retour utilisateur suivant : 14 LUA_WARNING « Script from
CooldownManagerCentered has exceeded its execution time limit », pile limitée
à CallbackRegistry.TriggerEvent / GlobalCallbackRegistry, et 10 LUA_WARNING
BugGrabber. Aucun appel Dibs ni nom d'événement n'apparaît dans ces piles;
elles ne démontrent ni un appel direct Dibs→CMC ni une origine commune.
La chronologie exacte et la session de ces erreurs ne sont pas fournies.

Vérification locale ciblée : aucune référence textuelle CooldownManager/CMC
dans les sources Dibs hors bibliothèques, ni RCLootCouncil/Dibs dans les Lua/TOC
de CMC installé (5.9.5). CMC possède plusieurs abonnements EventRegistry,
notamment CooldownViewerSettings.* dans modules/runtime.lua:101–161. La pile
tronquée ne permet pas de sélectionner lequel. Cette recherche de liens
directs n'exclut pas une interaction indirecte via des API ou bibliothèques.

L'utilisateur confirme ensuite avoir réactivé ses autres addons avant ces
alertes. Elles proviennent donc de la session complète. L'isolation antérieure
Dibs+RC à 70–100 FPS reste un retour utilisateur distinct et valide dans les
limites déjà indiquées. Le statut réellement
chargé peut être lu sans mutation avec C_AddOns.IsAddOnLoaded; une erreur
historique affichée ne constitue pas une preuve de chargement dans la session
actuelle. Aucun nouveau défaut tiers n'est déclaré et aucun source modifié.

Le 28 octobre 2026, l'utilisateur transmet trois exécutions de la commande
C_AddOnProfiler.GetAddOnMetric(addon, RecentAverageTime) proposée dans le chat :

| Heure affichée dans le chat | Dibs, ms | RCLootCouncil, ms |
|---|---:|---:|
| 20:00 | 18.939836666667 | 0.00776 |
| 20:00 | 18.939935 | 0.0077733333333333 |
| 20:01 | 0.000215 | 0.0014216666666667 |

Ce sont des mesures API rapportées par l'utilisateur, distinctes des tests
synthétiques. RecentAverageTime porte sur les 60 derniers ticks du profiler,
pas sur le seul appel de la commande et pas directement sur une durée d'image.
Les deux premiers relevés ne sont pas nécessairement des fenêtres temporelles
indépendantes. Ils établissent un épisode de travail attribué à Dibs, puis une
forte baisse dans le dernier échantillon; aucune charge constante ni coût de
18,94 ms par image n'est déduit de ces trois valeurs.

Deux avertissements génériques « There are too many errors in your UI » sont
intercalés. Ils indiquent un problème d'erreurs répétées, sans donner leur
premier message ou fonction. Une relation causale avec le pic CPU reste à
établir. L'état des fenêtres, le délai depuis reload et l'évolution du lag au
troisième relevé ont été demandés; pas de réponse enregistrée à ce stade.

Lecture locale ciblée : General.log contient 4208 lignes [E][Lua], trois
messages distincts : 3843 erreurs Platynator Cache.lua:362 entre 19:02:48 et
19:04:15, 333 avertissements RC entre 19:02:34 et 19:16:40, puis 32 avertissements
BugGrabber à 19:39:19. Ces heures sont les libellés du journal, conservés tels
quels; ce relevé n'inclut pas encore l'épisode du chat vers 20 h et ne confirme
pas une erreur Platynator actuelle après son retrait. Les SavedVariables
BugGrabber sauvegardées à 19:59:53 contiennent une liste errors vide. Aucune
pile d'erreur actuelle n'a donc pu être récupérée dans ces fichiers.

Le journal RC persistant conserve aussi une ancienne erreur de compilation
OfficerUI (>60 upvalues), sans preuve qu'elle concerne le source actuel.
Le compilateur local découvert est Lua 5.4.6 : il ne valide pas ce plafond
Lua 5.1. Aucun nouvel échec de compilation Retail n'est déclaré sur cette base.

## Nouveaux essais utilisateur : coût dès reload avec RC activé

L'utilisateur précise que le dernier essai de lag immédiat utilisait bien
Dibs et RCLootCouncil ensemble. Il rapporte environ 120–130 FPS sans Dibs et
70–100 FPS avec Dibs. Ce sont des relevés utilisateur, sans contrôle indépendant
des conditions ou des durées d'image. Ils renforcent l'association dans cette
configuration; ils n'identifient pas encore la fonction responsable ni un
éventuel troisième addon. Le précédent essai Dibs seul fluide reste pertinent.

**Isolation supplémentaire confirmée par l'utilisateur :** avec uniquement
Dibs et RCLootCouncil activés, fenêtres fermées, il répond « Toujours vers
70–100 FPS » au test au même endroit après reload/attente. Un troisième addon
n'est donc pas nécessaire pour reproduire cette baisse rapportée. Aucun temps
CPU par fonction ni relevé horodaté à deux minutes n'a encore été fourni.

Les nouvelles captures attribuent à Dibs 116/150 Mo dans des infobulles et
301,09/319,54 Mo dans un autre compteur. Instants, unités et outils diffèrent :
aucune courbe de croissance ni fuite retenue ne peut être déduite de ces seules
captures. Elles ne remplacent pas des mesures CPU/allocation par callback.

Deux nouveaux LUA_WARNING mentionnent AccWideUILayoutSelection/AceHook (7)
et !BugGrabber (10). La pile ScrollBox/InvokeInitializers situe un contexte de
construction/défilement de liste, sans désigner un appel Dibs. Le nom du fichier
AceHook ne suffit pas à identifier le propriétaire de chaque hook ni la cause
du dépassement. Les copies sur disque AceHook minor 9 et AceGUI minor 41 de
Dibs, RC et AccWideUILayoutSelection sont respectivement identiques par SHA256;
cela ne révèle pas quelle copie est utilisée en jeu. Aucun de ces addons tiers
n'est déclaré coupable et aucune bibliothèque n'est modifiée.

### RA-15 — Copies de tout le catalogue dans une lecture de règle actuelle

- **Status FIXED après suivi; confiance HIGH sur les copies; risque P1 de travail de fond,
  part de la baisse de FPS et du heap non mesurée.**
- Chemin avant correction : [LootRules.GetAuthoritySnapshot](../../src/modules/LootRules.lua),
  appelée par GetEffectiveValue pour une seule décision, demandait
  Seasons.GetCatalogState puis ne lisait que catalogRevision avant de demander
  le record actuel. Elle appelle maintenant le getter scalaire.
- [Seasons.GetCatalogState](../../src/modules/Seasons.lua), lignes 346–347,
  copie récursivement tout le catalogue, y compris toutes les anciennes
  révisions. Le getter scalaire GetCatalogRevision existe déjà, lignes 350–353;
  GetCatalogRecord, lignes 364–365, fournit séparément la copie du record courant.
- [L'intégration RC](../../src/integrations/RCLootCouncil.lua), lignes
  244–253/282–292 et 1168–1237, consulte les décisions pendant la projection.
  Son watcher, lignes 1537–1563, refait la projection toutes les 0,75 seconde
  jusqu'à 40 passages. Le coût dépend des types pris en charge et du volume
  historique. Le watcher testé s'arrête bien; aucune boucle infinie démontrée.
- [Deux tests ciblés](../../tests/integration/rc_startup_work_audit_spec.lua)
  exercent les fonctions actives avec 50 révisions synthétiques et les vrais
  callbacks du watcher sous doubles RC/timers. La décision est bien résolue
  avec la provenance GUILD; le watcher exécute 40 passages sans nouvelle
  notification, puis s'arrête. Avant correction, une lecture copiait tout le
  catalogue et 40 passages en faisaient **200 copies complètes** dans cette
  fixture. Après correction, les deux tests constatent zéro copie historique.
  Ce ne sont ni des millisecondes ni des mesures de mémoire en jeu. Résultats :
  **0 PASS / 2 FAIL avant**, puis **2 PASS / 0 FAIL après**.
  [Journal](RC-STARTUP-WORK-20261028.txt).
- Données disque déjà analysées et relues sans exécuter de Lua : un scope a
  15 révisions / 281 tables de catalogue, un autre une seule révision. Le scope
  actif dans le client n'est pas établi; la fixture de 50 révisions n'est pas
  présentée comme le contenu de ce compte ni comme sa mesure d'allocation.
- Correctif appliqué dans GetAuthoritySnapshot : lecture de GetCatalogRevision,
  avec GetCatalogRecord et NormalizeSnapshot conservés et sans cache
  d'autorité. Les tests valident la décision actuelle et l'arrêt du watcher à
  40 passages sans copies complètes.
- Validation de cette passe : les 139 fichiers sous src sont identiques à la
  baseline runtime de début d'audit, bibliothèques comprises;
  [relevé](RC-STARTUP-SOURCE-INTEGRITY-20261028.json). Les contrôles globaux
  historiques restent en échec : [46 fiches sans annotations](RC-STARTUP-DOC-VALIDATION-20261028.txt),
  [68 écarts avec l'ancienne baseline](RC-STARTUP-GUARD-20261028.txt),
  [whitespace préexistant](RC-STARTUP-DIFF-CHECK-20261028.txt).
  Aucun fichier utilisateur n'a été restauré ou nettoyé pour les faire passer;
  le worktree entier n'est pas déclaré intact à partir de cette ancienne garde.
- Le watcher seul ne suffit pas à expliquer un ralentissement continu après
  sa fenêtre d'environ 30 secondes. Il reste à mesurer le repos après deux
  minutes, la synchronisation et les autres callbacks. Un test avec uniquement
  Dibs+RC au même endroit a ensuite confirmé une baisse à 70–100 FPS selon
  l'utilisateur; la durée exacte et les callbacks restent à mesurer.

## Complément : Dibs seul et lenteurs des pages

L'utilisateur confirme qu'avec RC désactivé et Dibs réactivé, le jeu est fluide
après reload. Les pages Rank Rules, Loot Rules et System Settings provoquent
en revanche des lenteurs, puis l'utilisateur précise qu'elles varient selon les
pages et leur contenu. Le diagnostic doit donc couvrir deux contextes : travail
déclenché par la présence de RC et travail de construction des pages Dibs sans RC.
Il n'est pas établi que ces contextes aient des causes entièrement distinctes.

### RA-13 — Construction des contrôles sans regroupement des layouts

- **Status OPEN; confiance HIGH pour le mécanisme; risque P1 de réactivité UI,
  temps réel et contribution aux 135 Mo non mesurés.**
- Sources : [AceGUI.lua](../../src/ui/AceGUI.lua), Adapter.Create 677-693,
  RenderOptionsGroup 2027-2247; [OfficerUI.lua](../../src/ui/OfficerUI.lua),
  setupRoutePage 4963-4999, activateRoute 8790-8818 et Loot Rules buildRows/reflow
  7688-7746.
- Le contrat du conteneur AceGUI est AddChild → DoLayout → parcours de tous les
  enfants. La bibliothèque embarquée fournit PauseLayout/ResumeLayout. Il
  s'agit d'un contrat de dépendance consulté, pas d'un défaut imputé à son code.
- Le renderer applicatif ajoute les contrôles un à un sans suspendre le layout
  du conteneur rempli. Pour N enfants, cela peut visiter 1+2+…+N enfants avant
  même les événements de taille natifs. Une activation/Refresh reconstruit aussi
  toute la page.
- Le double GUI historique insère les enfants sans appeler DoLayout. La nouvelle
  reproduction ajoute précisément ce contrat et compte le travail, sans
  prétendre reproduire les tailles, callbacks ni coûts des frames natives.
- Résultat contrôlé : **40 descriptions → 42 layouts et 822 visites d'enfants**.
  Le budget de régression proposé, 160 visites pour ce cas, échoue.
- Proposition minimale : suspendre le layout des conteneurs remplis pendant
  la construction, respecter l'état déjà suspendu et les groupes imbriqués,
  restaurer cet état même après erreur, puis effectuer un layout final.
  Appliquer aussi le regroupement au builder custom Loot Rules et coalescer les
  reflows. Ne pas désactiver les mises à jour ni changer les règles métier.
- Risques : tailles de scroll, contrôles imbriqués, exceptions de getter,
  navigation/redimensionnement et release/pooling. Tester les trois pages,
  les petits/grands contenus et les changements de largeur dans WoW.

### RA-14 — Lectures répétées de rôle/roster dans le rendu

- **Status OPEN; confiance HIGH sur les lectures; impact en jeu non mesuré,
  risque P2 de coût lié à la taille/position dans le roster.**
- Sources : [Permissions.lua](../../src/modules/Permissions.lua), rosterRole
  134-152 et IsOfficer 169-193; getters et disabled de
  [RCLootCouncilOptions.lua](../../src/integrations/RCLootCouncilOptions.lua);
  rendu des options et des guides OfficerUI.
- La sonde utilise 100 membres synthétiques, avec l'Officier local en dernière
  position. Elle force donc une position défavorable explicite, pas le roster
  réel de l'utilisateur. La navigation des pages actuelles atteint :

| Route | Widgets créés | Layouts du modèle | Visites d'enfants | Lectures roster |
|---|---:|---:|---:|---:|
| Rank Rules | 40 | 41 | 542 | 2300 |
| Loot Rules | 98 | 100 | 238 | 3200 |
| Settings | 16 | 17 | 57 | 2300 |

- Aucune de ces trois routes n'appelle GetSizeDiagnostics dans cette
  reproduction. L'ancien suspect de sérialisation globale ne doit donc pas être
  présenté comme leur cause commune. Les cas Data/Health restent distincts.
- Proposition : préparer une projection de lecture des rôles/rangs nécessaire
  à une construction de page et la réutiliser pendant cette construction.
  **Ne pas affaiblir ni mettre arbitrairement en cache l'autorisation des
  mutations** : ProtectedActions doit continuer sa validation au moment de
  l'action; invalidation roster/configuration nécessaire.
- [Tests de travail UI](../../tests/integration/ui_layout_work_audit_spec.lua)
  et [journal](UI-LAYOUT-WORK-20261028.txt) : 1 PASS, 1 FAIL. Le cas passant
  caractérise les routes et leur absence de diagnostic de taille; le cas rouge
  fixe le budget de travail proposé. Aucune durée CPU native n'est déduite de
  ces compteurs.

La prochaine comparaison avant/après doit mesurer le Refresh natif des mêmes
pages, avec le même roster et les mêmes données. Les correctifs sont proposés
mais aucune logique de production n'a été changée pendant l'audit.

## Observations en jeu et isolation A/B fournies ensuite

- La capture du gestionnaire d'addons affiche Dibs 0.8.10 à environ **135 Mo**,
  Average CPU 5 % et Peak CPU 82 %. Une autre capture montre 104 % pour les
  indicateurs courants/moyens. Ces pourcentages de l'interface ne sont pas
  interprétés comme un pourcentage du CPU physique de la machine.
- Un LUA_WARNING indique des dépassements répétés de temps d'exécution attribués
  à RCLootCouncil, avec ErrorHandler.lua:1 comme emplacement affiché et un
  compteur de 72. Le handler RC installé s'abonne à LUA_WARNING : cet emplacement
  ne fournit pas, à lui seul, la fonction qui a consommé le budget.
- Une erreur Platynator Cache.lua:362 sur details=nil avait aussi un compteur
  élevé. L'utilisateur l'a retiré; une capture montre encore Dibs à 135 Mo.
  L'erreur Platynator est donc suivie séparément, sans lui attribuer tous les
  symptômes Dibs.
- **Test A/B confirmé par l'utilisateur :** Dibs désactivé, RCLootCouncil laissé
  actif puis /reload → le lag et les nouveaux dépassements cessent.
  L'activation Dibs est donc un déclencheur dans cette configuration.
  Le test ultérieur Dibs seul est détaillé en tête de rapport.
- Trois suites ciblées de projection/boutons/options RC : **34 PASS, 0 FAIL**.
  [Journal](RUNTIME-RC-INTEGRATION-20261028.txt). Elles utilisent des doubles
  d'intégration et ne reproduisent pas toute la boucle native d'événements,
  timers et AceDB du client; leur succès n'invalide pas le test A/B en jeu.

Priorité immédiate : comparaison Dibs seul/avec RC, puis compteurs et timings
de callbacks natifs. Les hooks de configuration, watchers et retries sont des
pistes à mesurer, pas une boucle infinie déjà démontrée. Aucun correctif
spéculatif ni changement de l'installation n'a été appliqué.

## Mise à jour RCLootCouncil 3.24.1 signalée ensuite

Une nouvelle lecture du TOC installé confirme désormais RCLootCouncil 3.24.1
sur disque. La comparaison d'installation ci-dessous reste un relevé antérieur
en 3.24.0; elle ne prouve pas la version actuellement chargée en mémoire.

La [release officielle](https://github.com/evil-morfar/RCLootCouncil2/releases/tag/3.24.1)
annonce un correctif des valeurs protégées liées aux whispers. La comparaison
GitHub 3.24.0...3.24.1 ne montre qu'un changement Lua : dans
RCLootCouncilML:OnEvent, ml_core.lua:563, un retour anticipé si
addon.Utils:IsSecretValue(msg, sender), avant les comparaisons de message.
Le chemin concerné exige CHAT_MSG_WHISPER, addon.isMasterLooter et
db.acceptWhispers. Le contrôle est également présent dans le fichier installé.

Ce correctif ne démontre pas la résolution du LUA_WARNING de dépassement de
temps d'exécution. Le nouveau signalement utilisateur porte un compteur de 14;
sans session et scénario comparables, il ne démontre pas une amélioration par
rapport au compteur précédent de 72. Les ralentissements des pages Dibs avec
RCLootCouncil désactivé restent un résultat A/B distinct.

Validation suivante : après chargement de 3.24.1 par /reload, refaire le repos
avec les deux addons, puis les mêmes pages, et relever uniquement les nouvelles
occurrences et mesures. Aucun test en jeu de cette version n'a été effectué
par l'audit; aucune production ni bibliothèque tierce n'a été modifiée.

## Mise à jour après communication du chemin de l'installation

Le dossier E:\Games\World of Warcraft\_retail_\Interface\AddOns est accessible.
La vérification finale retrouve **139/139 fichiers identiques** entre src et
RCLootCouncil_dibs installé, sans fichier manquant. Dibs est 0.8.10, RCLootCouncil
3.24.0; le produit Retail installé déclare 12.1.5.70575 dans .build.info.
Il s'agit du build sur disque, pas d'une lecture du heap d'un client lancé.
Voir [la comparaison](INSTALLED-COMPARISON-20261028.json).

Une analyse **de données uniquement**, sans exécution du Lua sauvegardé, donne :

- Fichier Dibs du compte : **361 608 octets, soit 0,345 Mio**, contenant le root
  principal et le sandbox; les fichiers par personnage relevés font moins de
  5 Kio chacun.
- Root principal : 6 scopes de guilde/personnage et 2 450 tables dans le fichier
  parsé; 23 transactions dans les cartes de ledgers au total.
- **Aucune sauvegarde, aucun import/restauration en attente, aucun snapshot de
  migration** dans ces données sauvegardées.
- Sandbox pratiquement vide : 37 octets de table sérialisée, 2 tables.
- Fichier de compte RCLootCouncil relevé : 1 548 969 octets.

Les résultats anonymisés sont dans
[INSTALLED-SAVEDVARIABLES-20261028.json](INSTALLED-SAVEDVARIABLES-20261028.json);
aucun nom de personnage/guilde ni contenu privé n'est reproduit dans ce rapport.
Le parseur est [inspect_savedvariables.py](inspect_savedvariables.py).

**Cela change la priorité du diagnostic utilisateur :** RA-02 est un défaut
reproductible, mais sa rétention n'est pas présente dans le dernier état disque.
Les volumes constatés ne soutiennent pas l'hypothèse de 250 Mo de seules
données persistées Dibs. La taille disque n'est pas convertible directement en
heap Lua; il faut mesurer les objets/allocation créés pendant la session, les
callbacks d'intégration RC et l'attribution mémoire du client. Les copies de
RA-01 restent un coût réel, mais leur contribution avec ce petit historique
n'est pas établie. Aucun nettoyage de SavedVariables ne se justifie sur ces
seules observations.

## Conclusion vérifiable

Le code courant présente des coûts de copie et de parcours reproductibles, des
références persistantes qui échappent à la rétention des sauvegardes, et plusieurs
défauts de cycle de vie et d'intégrité. **La cause exacte des 250 Mo et du lag en
jeu n'est pas encore mesurée.** L'utilisateur précise que le lag précède toute
ouverture de l'interface Dibs : réseau, événements et données rechargées sont
donc prioritaires.

Aucun processus WoW accessible n'a été trouvé. La première passe n'avait pas
localisé l'installation; la mise à jour ci-dessus exploite le chemin fourni
ensuite. Les profils CPU/allocation et la mémoire du client restent inconnus.
Aucun benchmark Fengari n'est présenté comme une mesure du client WoW.

Les sources de production ont été conservées. Les nouveaux tests sont des
reproductions et des contrats de régression en attente de correctif. Les budgets
de copie proposés sont distingués des invariants fonctionnels.

## État audité et périmètre

- HEAD : cb3f12a; source déclarée 0.8.10; TOC 120100, 120105.
- Le checkpoint docs/ai/CHECKPOINT.md et plusieurs fiches historiques citent
  dc388f9 et des corrections absentes de ces chemins actuels. Leurs résultats
  ne sont pas transférés à cette révision.
- Inventaire : **59 Lua applicatifs, dont 58 chargés par le TOC**; Types.lua
  n'est pas chargé. Les 77 fichiers de bibliothèques sont restés en lecture seule.
  Les Lua applicatifs occupent 2 524 785 octets sur disque, les bibliothèques
  818 898 octets. Ces tailles ne sont pas des estimations de heap Lua.
- [Inventaire machine](RUNTIME-INVENTORY-20261028.json) et
  [empreintes de départ](PERFORMANCE-SOURCE-BASELINE-20261028.json).
- Des modifications préexistantes existaient notamment dans OfficerUI.lua et
  quatre tests suivis; de nombreux rapports/tests étaient déjà non suivis.
  Aucun n'a été réinitialisé, supprimé ou commité.

L'inventaire est global; la lecture sémantique cible les chemins actifs de
démarrage, événements, sync, ledger, Pre-Dibs, permissions, import/backup, UI
et sandbox. Les autres sources ont été recherchées pour leurs enregistrements
et dépendances; cette passe ne certifie pas chaque ligne des 58 modules.
Contrats consultés : constitution, specs 007, 020 et artefacts 026/027.
Les tâches 026 contiennent aussi des attentes de fonctionnalités futures :
une API de test absente n'est pas, à elle seule, la preuve d'un exploit.

## Architecture réellement chargée

Le TOC charge embeds.xml, Core, locales, modules, intégrations puis UI.
Core crée le singleton Dibs. Les bibliothèques sont obtenues par LibStub;
les tables publiques des modules partagent ce singleton.

| Surface | Implémentation active / propriétaire |
|---|---|
| Persistance | Core.GetDB sélectionne RCLootCouncil_dibsDB.guilds[guildKey]; schémas root 6 et guilde 7. Le chemin normal possède un raccourci sans copie intégrale à chaque lecture. |
| Préférences locales | RCLootCouncil_dibsLocalDB, par personnage. |
| Sandbox | RCLootCouncil_dibsSandboxDB, distinct mais toujours déclaré SavedVariables. Son contenu peut rester chargé hors mode développeur. Store.Initialize ne clone pas systématiquement la production. |
| Comptabilité | Ledger écrit les transactions/projections; Governance fournit l'autorité. db.ledger est normalement un alias de db.ledgers[activeLedgerId]. |
| Pre-Dibs | Listes par ledger; GetHistory retourne la liste courante sans la copier. |
| Réseau actif | SyncV2 redéfinit Send, Receive, OnAddonMessage, RegisterTransport, BuildManifest, OnRosterChanged et le cycle de vie. |
| Helpers conservés | Sync.lua fournit encore notamment les traces et ContainsForbiddenLiveLootData. Son fallback compact n'est pas le transport actif du TOC. |
| Événements | Ace3.RegisterEvent partage un propriétaire et une case par événement; les consommateurs se remplacent actuellement. |
| Présentation | UI → projections/services → mutations protégées. Des lectures de diagnostic font cependant des copies ou sérialisations intégrales. |

Le test de provenance vérifie les sources des fonctions Sync installées.
L'absence d'AceComm arrête le V2 avec SYNC_UNAVAILABLE et n'émet aucun paquet
compact brut. **L'ancien constat RV-002/SA-003 fondé uniquement sur le corps de
Sync.lua est retiré pour le runtime courant.**

Le loader de test appelle normalement Dibs.Initialize lui-même, masquant le
démarrage réel. Il diffère aussi légèrement du TOC pour la position de
DebugLogsUI.lua; l'ordre des redéfinitions Sync est identique. Les nouvelles
reproductions de démarrage utilisent skipInitialize=true.

## Constats

### RA-01 — Copies du ledger secondaire dans la boucle de réception

- **Status PARTIALLY ADDRESSED après suivi; confiance HIGH; risque P1 de performance.**
- Sources : [SyncV2.lua](../../src/modules/SyncV2.lua), isApprovedLedger 224-230,
  localRequest 1737-1742 et réception des digests 2497-2528;
  [PreDibs.lua](../../src/modules/PreDibs.lua) 154-163, 1420-1424;
  [MultiLedger.lua](../../src/modules/MultiLedger.lua) 265-269.
- Avant correctif, chaque entrée de PREDIB_INDEX recherchait son identifiant en
  reparcourant l'historique. Le chemin actif valide les entrées, lit une fois
  GetHistory(ledgerId) et construit un index local par ID. Les comparaisons de
  hash/révision continuent pour chaque entrée. Une éventuelle copie du ledger
  secondaire subsiste une fois par message dans GetHistory; les autres copies
  de projection n'ont pas été retirées.
- Reproduction historique : digest valide de 20 demandes déjà à jour, ledger
  synthétique de 100 transactions : **21 copies complètes**. La réception
  atteignait vraiment DIGEST_CURRENT.
- Après correctif, les fixtures 50/60 participants exécutent OnAddonMessage et
  atteignent DIGEST_CURRENT : **49/59 lectures d'historique pour 49/59 index**
  de 20 entrées, contre **980/1180** avant. Cette mesure compte les appels Lua,
  pas le temps ni les octets alloués. Le hash reste calculé par entrée; la
  lecture historique est désormais par message.
- Déclencheurs : digests des pairs, heartbeat, roster et rattrapage, sans
  fenêtre ouverte. Le volume réel reste à mesurer.
- Proposition : approbation par métadonnées et accès par requestId construit
  une fois par digest/ledger. Le test propose au plus deux copies par digest
  comme plafond transitoire; vérifier un statut ne devrait normalement copier
  aucune transaction.
- Risques : invalidation d'index et références mutables. Conserver les tests
  d'auteur, conflits, isolation et révision.

### RA-02 — Les annulations conservent paquets et snapshots sans borne

- **Status OPEN; confiance HIGH; risque P1 de mémoire retenue.**
- Sources : [ImportExport.lua](../../src/modules/ImportExport.lua) 354, 419-421;
  [Backup.lua](../../src/modules/Backup.lua) 115-120, 129-132;
  [DataUI.lua](../../src/ui/DataUI.lua), callbacks d'annulation.
- Trois aperçus d'import complet annulés laissent **trois paquets complets**
  dans db.pendingImports. Aucun TTL/nettoyage de ces objets annulés n'a été trouvé.
- Avec une rétention de sauvegardes égale à 1, un aperçu de restauration annulé
  conserve le premier snapshot après qu'un second l'a retiré de db.backups :
  **1 sauvegarde listée + 1 ancien snapshot encore retenu.**
- Ces structures sont dans les SavedVariables. Si enregistrées lors d'une
  précédente session, elles peuvent peser au prochain login avant toute UI.
  Le mécanisme est confirmé; son volume chez l'utilisateur est inconnu.
- Proposition : garder l'audit et les métadonnées utiles, libérer la charge
  d'un aperçu terminal, borner les aperçus abandonnés. Le traitement des objets
  anciens doit être explicite et sauvegardé; aucun nettoyage réel n'a été fait.
- Risques : reprise des aperçus en cours, audit et compatibilité des anciens SV.

### RA-03 — Copie avant exclusion et diagnostic de taille coûteux

- **Status OPEN; confiance HIGH sur le travail; risque P2, impact en jeu non mesuré.**
- Sources : [ImportExport.lua](../../src/modules/ImportExport.lua) 201-205,
  216-253; [Backup.lua](../../src/modules/Backup.lua) 90-108;
  [HealthUI.lua](../../src/ui/HealthUI.lua) 113-121;
  [DataUI.lua](../../src/ui/DataUI.lua) 68-78, 111-120;
  [OfficerUI.lua](../../src/ui/OfficerUI.lua) 2660-2674.
- GetPayload(full) copie toute la DB, y compris backups/aperçus, puis retire
  ces sous-arbres. Le test constate une entrée de copie de la DB entière malgré
  la présence d'un snapshot explicitement exclu du résultat.
- Backup.Create construit un payload, Export en reconstruit un autre, puis
  copie le payload dans le snapshot et le snapshot de retour.
- Pour seulement disponibilité/date/nombre des sauvegardes, HealthUI.Evaluate
  utilise Backup.List, qui recopie leurs payloads :
  **3 snapshots → 3 copies intégrales** dans la reproduction.
- GetSizeDiagnostics sérialise la DB, extrait/copie le payload, sérialise le
  payload et chaque section, encode/checksume le paquet. Ce n'est pas un
  compteur mémoire léger et le résultat n'est pas mis en cache.
- Proposition : exclure avant copie, exposer les métadonnées seules, calculer
  la taille à la demande avec cache par révision. Préserver limites et checksum.
  Ces lectures ne prouvent pas un lag permanent avant UI; la rétention RA-02
  peut cependant amplifier toute copie ultérieure.

### RA-04 — Les abonnements Ace3 remplacent ceux du Core

- **Status OPEN; confiance HIGH; risque P1 de cycle de vie.**
- Sources : [Ace3.lua](../../src/integrations/Ace3.lua) 209-216, 242;
  [Core.lua](../../src/Core.lua) 2234-2240, 2299-2316;
  [EncounterJournal.lua](../../src/integrations/EncounterJournal.lua) 2047-2052;
  [AceGUI.lua](../../src/ui/AceGUI.lua) 2473-2478.
- Adapter.handlers.events[event] = callback écrase le consommateur précédent.
  Les enregistrements utilisent aussi le même propriétaire AceEvent.
- Deux consommateurs d'un événement : seul le second reçoit l'appel.
  Sans l'appel manuel du loader, le callback PLAYER_LOGIN installé après EJ
  laisse Dibs.initialized absent. PLAYER_REGEN_ENABLED possède une collision
  similaire avec AceGUI.
- Proposition : dispatch vers plusieurs abonnés ou propriétaires distincts,
  enregistrement idempotent et désabonnement explicite.
- Risques : double initialisation, callbacks accumulés; tester l'ordre réel
  des événements, pas seulement Initialize direct.

### RA-05 — Signature d'événement incorrecte dans EncounterJournal

- **Status OPEN; confiance HIGH; risque P1 fonctionnel et de travail répété.**
- Sources : [Ace3.lua](../../src/integrations/Ace3.lua) 212-215;
  [EncounterJournal.lua](../../src/integrations/EncounterJournal.lua) 727-737,
  2015-2052.
- L'adaptateur appelle (event, ...), les handlers EJ attendent (_, event, ...),
  comme un OnEvent de frame. Les arguments sont décalés.
- Un ENCOUNTER_START valide ne renseigne pas GetActiveEncounter. Avant
  initialisation, un ADDON_LOADED sans rapport déclenche AddActionIfAvailable.
- Le retry EJ permet 120 tentatives espacées de 0,5 s sans jeton de retry partagé.
  Des bootstraps multiples pourraient multiplier les chaînes; le nombre réel de
  timers n'a pas été mesuré dans WoW.
- Proposition : normaliser la signature et coalescer les retries. Tester login,
  chargement EJ ciblé/non ciblé et début/fin d'encounter.

### RA-06 — Imports : perte de réglages et remplacement des ledgers

- **Status OPEN; confiance HIGH; risque P1 d'intégrité.**
- Sources : [ImportExport.lua](../../src/modules/ImportExport.lua) 277-290,
  317-360, 419-482; [régressions](../../tests/integration/import_apply_atomicity_spec.lua).
- Un paquet à checksum valide avec presentation = 7 ou settings = 7 passe
  Decode/Preview. En replace, la cible est vidée avant l'erreur pairs(7).
  Les tests vérifient l'état après l'exception :
  **theme=nil / allocation=nil, raised=true**.
- Le full import copie payload.ledgers au lieu de préserver la carte locale,
  malgré le traitement séparé de payload.ledger. RF-0033 reproduit la perte
  du grant récent et la rupture d'alias; RF-0040 A16/A17/A25 échouent aussi.
- Proposition : validation/staging avant mutation, préservation des ledgers
  locaux et revalidation de l'état intervenu depuis l'aperçu.
- Risques : secondaires, schémas antérieurs, index evidence/award et projections.

### RA-07 — Restauration sans validation du snapshot courant

- **Status OPEN; confiance HIGH; risque P1 d'intégrité locale.**
- Source : [Backup.lua](../../src/modules/Backup.lua) 115-152.
- Preview/Restore vérifient le rôle, mais pas le checksum courant, la forme
  complète ou guildScope avant application. L'aperçu conserve le snapshot par
  référence.
- Reproduction avec le format créé actuellement : backup local, aperçu valide,
  mutation de payload.presentation.theme, puis confirmation :
  **applied=true, theme=tampered-theme**. Aucun champ packageText n'est requis.
- Des tests existants reproduisent aussi l'acceptation de payload absent et de
  mauvais guildScope. Il s'agit de corruption/modification locale et de
  cloisonnement des restaurations; aucun exploit réseau Restore n'est établi.
- Proposition : validation au preview et juste avant apply, attestation du
  payload effectivement sauvegardé et staging. Le checksum stocké vient d'un
  paquet exporté séparément, avec ses propres métadonnées : ne pas présumer
  qu'il est recalculable depuis le snapshot sans reconstitution exacte.
  Prévoir une compatibilité explicite des anciennes sauvegardes.
- Risques : gros backups, textes légitimes, anciens formats et côté local plus
  récent. Aucun snapshot réel n'a été modifié.

### RA-08 — Un digest rejeté enrichit le cache persistant

- **Status OPEN; confiance HIGH; risque P1 de disponibilité/mémoire.**
- Source : [SyncV2.lua](../../src/modules/SyncV2.lua) 1998-2027, 2497-2501.
- Après validation de l'enveloppe mais avant celle de l'entité, peer.entities
  est écrit dans db.sync.v2.peers. Les clés et contentHash ne sont pas bornés
  à ce stade.
- Un vrai membre de guilde non-officier envoie 20 digests d'entités inconnues :
  **20 rejets INVALID_DIGEST, 20 clés conservées**. Aucune borne/expiration
  trouvée pour peer.entities. Le plafond replay/transfers ne borne pas cette table.
- Frontière réseau : le test traverse OnAddonMessage avec le sérialiseur de
  test. Il ne mesure pas une transmission AceComm réelle.
- Proposition : valider le corps avant conservation, projeter les champs
  autorisés, borner entités par ledger approuvé et chaînes de caractères.
  Vérifier aussi les métadonnées HELLO et les rapports de probe.

### RA-09 — Pas de plafond d'enveloppe avant désérialisation

- **Status OPEN; confiance HIGH sur l'absence de garde; risque P2 de disponibilité.**
- Sources : [SyncV2.lua](../../src/modules/SyncV2.lua) 15, 1784-1787,
  2667-2670, 2832-2836; [Sync.lua](../../src/modules/Sync.lua) 396-407.
- Le plafond 8192 octets protège les transferts de détails, pas l'enveloppe
  reçue avant Deserialize. Le scan récursif des champs interdits n'a pas de
  budget de profondeur/nœuds.
- Une entrée de 1 Mio atteint le désérialiseur une fois dans la reproduction.
  Cela prouve l'ordre de validation, pas le coût d'un vrai réassemblage ni un
  crash client.
- Proposition : plafond compatible avec un index légitime maximal, budget de
  forme/profondeur, limites de champs et débit par expéditeur. Le callback ne
  peut pas annuler la mémoire déjà consommée par le réassemblage AceComm.

### RA-10 — Appels io dans le roster Officer du worktree

- **Status OPEN; confiance HIGH; risque P1 de fonctionnement UI.**
- Source : [OfficerUI.lua](../../src/ui/OfficerUI.lua) 1609-1624.
- Du debug préexistant appelle io.write/io.flush sans garde et ajoute un
  parcours du roster. Sans io, le builder lève une erreur à 1622.
- Proposition : enlever ce debug de console ou utiliser la journalisation
  Dibs bornée et désactivée par défaut. Ce défaut ne suffit pas à expliquer
  le lag avant UI. Le changement utilisateur a été conservé.

### RA-11 — Corrections de dispute et feature 026

- **Status OPEN; confiance HIGH pour B10; portée 026 à revalider; risque P1 d'intégrité.**
- Sources : [Disputes.lua](../../src/modules/Disputes.lua) 757-795, 967-1015;
  [spec 026](../../specs/026-canonical-idempotent-corrections/spec.md).
- Le test B10 reproduit une correction de débit acceptée sans transaction
  d'origine. L'acteur est autorisé : ce n'est pas une élévation de rôle,
  mais la preuve comptable attendue manque.
- B28 attend un verrou de release de la feature 026 et échoue aussi. C'est
  une divergence de contrat/implémentation, pas la preuve d'un franchissement
  réseau d'un verrou existant.
- La correction de cible 872-910 possède encore deux écritures puis une
  compensation dont le résultat est ignoré. Elle exige la reproduction ciblée
  prévue par 026; cette passe n'a pas injecté cet échec de compensation.
- Proposition : validation minimale d'origine et fermeture des chemins
  incomplets selon 026; ne pas reprendre les anciens statuts de correction.

### RA-12 — Les preuves historiques surévaluent la couverture

- **Status OPEN; confiance HIGH; risque MEDIUM d'évaluation erronée.**
- Le helper repack de RF-0040 modifie le payload puis appelle Encode, qui
  **ne recalcule pas le checksum**. Plusieurs tests négatifs peuvent passer
  à CHECKSUM_MISMATCH sans exercer le ledger ou la révision annoncés.
  Le nouveau contrôle montre ce rejet, puis reconstruit correctement le
  paquet et atteint CROSS_GUILD_FULL_BLOCKED.
- Les anciens tests SA-002 comportent des cas qui impriment sans assertion :
  ils ne prouvent pas un contournement.
- Dans la tranche backup, B04/D02 utilisent packageText absent du format
  courant; B14 appelle RebuildLedgerProjections, API absente. C03/C06 ajoutent
  aussi des métadonnées non créées par la production. Ces résultats ne sont
  pas comptés comme cinq vulnérabilités supplémentaires.
- Proposition : fixtures valides, codes de rejet précis et état après échec.
  Distinguer les attentes futures des régressions du build. Les anciens
  fichiers de tests ont été préservés.

## Mémoire et traitements de fond

Les racines chargées incluent toutes les guildes conservées, les backups
utilisateur (5 par défaut, maximum 25), jusqu'à 3 snapshots de migration du root,
les aperçus et éventuellement un clone sandbox sauvegardé. Les snapshots root
excluent les précédents snapshots root mais peuvent contenir les backups de
guilde et les aperçus. Une borne en nombre n'est pas un budget global d'octets.
Les limites de paquet sérialisé ne mesurent pas la taille des tables Lua.

Les alias db.ledger et les listes actives Pre-Dibs ne doublent pas à eux seuls
les objets de heap. Les payloads copiés des snapshots et les transactions
détachées des commits sont en revanche de vrais objets. Leur suppression
nécessiterait de respecter la conservation des preuves comptables.

Bornes présentes : logs diagnostic 300, notifications vues 128, replay V2 256,
transferts 8 avec payload 8192 octets. Les historiques comptables/demandes ont
un rôle de conservation : leur croissance n'est pas automatiquement une fuite,
mais elle amplifie les parcours et copies.

| Déclencheur | Travail / borne | Rapport au lag avant UI |
|---|---|---|
| Démarrage/migration | copie du root si nécessaire; création prévue des fenêtres cachées lors de Initialize | Pics et mémoire de base à mesurer; callback de login perdu dans la reproduction. |
| Heartbeat Sync | 60 s; reconstruction des index de chaque ledger, digests, retries | Peut créer des pics sans UI; les pairs ajoutent leurs propres messages. |
| Roster | timer partagé 1 s; lifecycle coalescé sur 5 s | Coalescence présente; le coût du cycle accepté demeure. |
| Digest Pre-Dibs | index d'historique construit une fois par PREDIB_INDEX reçu; hash par entrée | RA-01 réduit; allocations résiduelles et émissions à mesurer. |
| Config RCLootCouncil | Le watcher de secours fait 40 × 0,75 s si aucun hook `UpdateDB` n'est disponible; les retries runtime restent à 120 × 1 s jusqu'à disponibilité des hooks requis. | À vérifier en jeu si le lag est concentré au démarrage. Les chemins ont été réduits dans le suivi du 29 octobre; pas de boucle infinie démontrée. |
| EncounterJournal | refresh 0,5 s seulement si visible; retries 120 × 0,5 s | Le refresh visible concorde moins avec le symptôme; RA-05 peut provoquer des bootstraps indus. |
| Data/Health/diagnostic | copies et sérialisations à la demande | Freezes possibles à l'ouverture; pas de boucle autonome démontrée. |
| Minimap OnUpdate | seulement pendant drag, puis retiré | Aucun OnUpdate applicatif permanent généralisé trouvé. |

Les mécanismes de release/pooling UI existent. Aucune fuite universelle de
frames n'a été démontrée; les doubles Fengari ne reproduisent pas les pools
natifs, l'attribution mémoire ou le GC de WoW.

La mémoire attribuée peut inclure des bibliothèques partagées ou des allocations
effectuées depuis un callback. Les 250 Mo ne peuvent pas être décomposés sans
métriques et données du client.

## Frontières de sécurité

Les contrôles testés refusent un vrai membre non-officier et un acteur Officer
forgé sur son client. Le V2 vérifie guilde et identité depuis le roster, puis
les branches de mutation vérifient les rôles/coordinations applicables.
Les hashes servent à l'intégrité/conflit, pas à une signature.

Le parseur d'import traite des données; aucun appel applicatif d'exécution de
texte importé n'a été trouvé. Les API publiques Pre-Dibs/tables SV restent
accessibles à du Lua local; cela seul ne prouve pas une attaque inter-client.
RA-08/09 concernent une entrée réseau non fiable; RA-06/07/11 des opérations
locales administratives ou de récupération.

## Validation exécutée

Runner Fengari local déjà installé, DIBS_TEST_FILES explicite. Pas de suite
complète, de déploiement ou de test réseau réel.

| Tranche | Résultat | Artefact |
|---|---|---|
| Sync privacy, B04, permissions, imports RF-0033/RF-0040, atomicité antérieure | 87 PASS / 7 FAIL, 6 fichiers | [baseline](RUNTIME-BASELINE-20261028.txt) |
| Backup RF-0041/0046/0047 | 28 PASS / 14 FAIL, 3 fichiers | [backup](RUNTIME-BACKUP-20261028.txt) |
| Dispute integrity | 28 PASS / 2 FAIL, 1 fichier | [disputes](RUNTIME-DISPUTES-20261028.txt) |
| Nouveaux contrôles runtime et atomicité renforcée | 3 PASS / 15 FAIL, 2 fichiers | [reproductions](RUNTIME-PROBES-20261028.txt) |
| Intégration RC : boutons, projections et options fallback | 34 PASS / 0 FAIL, 3 fichiers | [RC](RUNTIME-RC-INTEGRATION-20261028.txt) |
| Suivi RC : retry projection, watcher conditionnel, boutons et capacités | 34 PASS / 0 FAIL, 4 fichiers | tests locaux, dont [rclootcouncil_hook_retry_work_spec.lua](../../tests/integration/rclootcouncil_hook_retry_work_spec.lua) |

Les tranches se recouvrent : ne pas additionner leurs compteurs. Les 15 échecs
de la dernière sont 13 nouveaux contrats non satisfaits et deux régressions
d'import antérieures renforcées. Les trois contrôles positifs passent :
runtime V2 actif, fixture de checksum correcte et refus d'acteur non autorisé.
Les incohérences de fixtures historiques sont distinguées en RA-12.

### Intégrité du worktree et contrôles documentaires

- Comparaison début/fin des **139 fichiers de src : 0 modification, ajout ou
  suppression**, bibliothèques comprises :
  [RUNTIME-INTEGRITY-20261028.json](RUNTIME-INTEGRITY-20261028.json).
- Les 9 commandes du protocole compilent sous Fengari; longueur maximale
  210 caractères. Ce contrôle de syntaxe n'est pas une exécution dans WoW.
- Les liens locaux des documents d'audit et les espaces de fin de ligne des
  fichiers ajoutés/renforcés ont été vérifiés séparément.
- Le validateur documentaire historique échoue avec **46 fiches RF sans
  annotation source associée**, pour 47 fiches et 1 tag. Ce décalage n'a pas été
  masqué en ajoutant des annotations artificielles :
  [journal](RUNTIME-DOC-VALIDATION-20261028.txt).
- La garde basée sur l'ancienne baseline échoue avec **66 écarts** dans le
  worktree, dont des fichiers de test nouveaux et des différences antérieures
  à cette passe. Elle ne prouve pas une altération effectuée ici; la comparaison
  indépendante début/fin de src est celle utilisée ci-dessus :
  [journal](RUNTIME-HISTORICAL-GUARD-20261028.txt).
- git diff --check signale du whitespace dans les changements préexistants
  OfficerUI/automatic_dibs_log/b05b. Aucun nettoyage non demandé n'a été fait :
  [journal](RUNTIME-DIFF-CHECK-20261028.txt).

## Trois actions prioritaires et plan progressif

1. **Mesurer les deux correctifs de coût local.** RA-16 diffère désormais le
   rendu caché et RA-15 évite les copies historiques pour une décision. Comparer
   le même démarrage en jeu pour CPU/allocation/rétention avec le
   [protocole Retail](RETAIL-PERFORMANCE-PROTOCOL-20261028.md).
2. **Continuer l'optimisation Sync sans casser la réparation.** RA-01 réduit
   maintenant les recherches PREDIB_INDEX à une lecture d'historique par
   message. Mesurer les autres copies, les digests émis et répartir les
   rattrapages en préservant cadence/repair de spec 017.
   Vérifier aussi abonnements/signatures (RA-04/05). Traiter rétention des
   aperçus (RA-02) et diagnostics (RA-03) séparément, sans effacer les données.
3. **Intégrité et entrées bornées.** Staging d'import, validation au Restore,
   métadonnées réseau validées avant stockage, plafond d'enveloppe, puis
   corrections de dispute selon 026. Faire passer les régressions de chaque lot
   tout en conservant les contrôles de permissions et sync.

Les correctifs n'établissent pas que Dibs est optimisé ni qu'ils expliquent la
baisse FPS rapportée. La comparaison avant/après dans WoW Retail reste
nécessaire; aucune mesure en jeu n'a été faite dans cet environnement. Aucun
effacement de données, changement de bibliothèque, commit ou publication n'a
été effectué.

## Suivi de l'intégration RCLootCouncil — 2026-10-29

Lecture en lecture seule de l'installation Retail : RCLootCouncil déclare
3.24.1. Les signatures actuellement utilisées par Dibs concordent avec le code
installé : `LootFrame:Update()` et `LootFrame:OnRoll(entry, button)` dans
`Modules/lootFrame.lua`, `RCVotingFrame:GetColumnIndex(nameOrIndex)` et
`AddColumn(spec, target, position)` dans `Modules/VotingFrame/ColumnAPI.lua`,
ainsi que `RCLootCouncil:ConfigTableChanged(val)`, `Getdb()` et `UpdateDB()`.
La dernière mise à jour RC examinée corrige les valeurs protégées de whispers;
elle n'explique pas à elle seule les avertissements de budget d'exécution.

Le chemin Dibs actif accroche `LootFrame.Update` pour recalculer l'état des
boutons après une mise à jour RC, et garde une garde autour de `OnRoll` pour
refuser une réponse DIB non admissible. Les retries de disponibilité du module
restent bornés à 120, espacés d'une seconde; ils ne reprojettent plus le loot
frame s'il est déjà accroché. L'ancienne intégration lançait aussi 40 scans de
configuration à 0,75 s même lorsque le profil RC et `UpdateDB` étaient déjà
disponibles.

Le suivi Dibs évite maintenant ce watcher redondant seulement quand une base RC
est prête et que le hook postérieur `UpdateDB` est installé; les forks sans
`UpdateDB` conservent le watcher borné. Régression ajoutée pour les deux cas.
Résultat local : 34 tests PASS, 0 FAIL dans quatre fichiers ciblés. Cela ne
mesure ni le temps CPU natif de WoW ni la réduction des avertissements en jeu.
Le fichier d'intégration était synchronisé avec l'installation lors de la
vérification précédente. Le retour utilisateur indique que le coût au reload
semble amélioré; l'effet exact reste une observation en jeu, pas une mesure
isolée.

## Suivi du rendu PlayerUI / OfficerUI — 2026-10-29

Le joueur rapporte maintenant une chute à 6–8 FPS durant environ 3–5 secondes
à l'ouverture ou au changement de page dans les deux interfaces. C'est cohérent
avec un coût synchrone de projection et de construction UI; le temps Lua et la
part exacte de chaque chemin ne sont pas mesurés par ces observations.

Constats confirmés dans le code et le test de travail UI :

- Les routes Officer recalculaient le rapport complet Guided Setup à chaque
  page. `renderSetupPageHelp` interroge maintenant le rapport combiné une fois
  au lieu de faire les scopes Guild et Raid séparément. Le rapport complet
  Wizard est réservé à Guided Setup; les pages ordinaires conservent leurs
  vérifications ciblées.
- Les permissions et les outils de rang rescannaient directement le roster à
  répétition. `Identity.GetRosterMembers` fournit un snapshot copié, rafraîchi
  après invalidation de `GUILD_ROSTER_UPDATE`; OfficerUI met son index de noms
  en cache sur cette génération. Sur le fixture de 100 membres, les routes
  Officer avaient auparavant 300 à 600 appels `GetGuildRosterInfo` après le
  premier correctif; elles en font maintenant zéro après le snapshot initial.
- La projection « Pre-Dibs by boss » ouvrait le catalogue complet du Journal
  même quand aucune demande active n'existait. Le scan est maintenant omis dans
  ce cas et reste effectué lorsqu'une demande pending/confirmed requiert un
  mapping item-boss.
- `AceGUI` construit maintenant chaque route dans un lot de layout et libère
  le layout une fois la page assemblée. Pour 40 contrôles d'option, le double
  de test passe de 42 layouts et 822 visites d'enfants à 2 et 2. Pour les routes
  Officer overview/ranks/lootTypes/settings, les visites passent respectivement
  de 200/542/238/57 à 2/2/56/2. Ce sont des compteurs de doubles UI, pas des
  durées CPU de WoW.
- PlayerUI sépare maintenant la projection History du modèle My Dibs; Reports
  n'effectue pas de résumé de solde inutile. Diagnostics et Reports évitent la
  projection historique générale. Le rendu des pages PlayerUI bénéficie aussi
  du lot de layout.

Tests ciblés : **140 PASS, 0 FAIL, 12 fichiers**, incluant le contrôle de
permissions après invalidation, le rendu des routes, le lot AceGUI et l'absence
de scan du Journal sans demande active. Aucun test ne simule le moteur UI ou
mesure le CPU de Retail. Les fichiers UI/modules et régressions ajoutés dans ce
suivi restent à déployer dans WoW pour une comparaison avant/après en jeu.

### Suivi PlayerUI — My Dibs, Reports et History — 2026-10-29

La lecture de `PlayerUI.Refresh` a trouvé des calculs redondants sur les trois
routes : My Dibs créait aussi la projection complète History sans l'afficher;
History passait par `GetSummary` (solde, Pre-Dibs, acquisitions, éligibilité)
avant de relire les transactions pour son tableau; Reports calculait le même
résumé et interrogeait deux fois la liste des demandes. Le rendu utilise
maintenant un modèle d'historique dédié, omet l'historique caché sur My Dibs,
et construit le contexte de Reports sans charger les projections inutiles.
La liste des rapports est aussi projetée à partir du résultat déjà lu.

Tests ciblés PlayerUI : **53 PASS, 0 FAIL, 4 fichiers** avec les régressions
Officer/Sync/navigation jointes. Le test vérifie une lecture des transactions
par route, zéro modèle History complet sur My Dibs/Reports, et une projection
History dédiée. Cette validation ne prouve pas le temps CPU natif ni que le GUI
en jeu rendra sans pause. Ces changements, comme le snapshot roster, restent
dans la source, non déployés.

### Suivi des pages encore lentes — 2026-10-29

Après le signalement de pauses de 3–5 secondes et du curseur occupé pendant
certaines navigations, une seconde lecture a trouvé que
`renderSetupPageHelp` reconstruisait `Wizard.GetTurnkeyStatus()` sur chaque
route d'aide (`settings`, `ranks`, `integration`, etc.). Ce rapport complet
enchaîne `Wizard.GetStatus`, `computeSteps`, l'évaluation de readiness et
`stepAllocationReconciliation`; ce dernier appelle
`RankRules.GetAllocationReconciliation` sur le roster. Loot Rules invoquait
aussi ce helper depuis sa zone défilante, même si la route était exclue de
l'appel commun. Cela confirme du travail inutile et synchrone lors du rendu,
mais ne quantifie pas sa durée réelle ni ne prouve que cet appel seul cause
les 3–5 secondes.

Le helper conserve les contrôles ciblés `SetupAssistant.Evaluate` et retire
la fusion du rapport complet; Guided Setup conserve son rapport détaillé
via `renderWizardPage`. Le test `ui_layout_work_audit_spec.lua` exige maintenant
zéro appel complet à `Wizard.GetTurnkeyStatus` sur les routes ordinaires.
Exécution isolée : **3 PASS, 0 FAIL**. Sur le fixture, Loot Rules construit
98 widgets et effectue 12 layouts/56 visites d'enfants; Rank Rules 36 widgets
et 2/2; Settings 12 widgets et 2/2. Ce sont des compteurs de mock, pas des
mesures de temps ou FPS en jeu.

Le correctif UI reste dans la source et n'a pas été déployé. Vérification
suivante : comparer ces mêmes pages dans Retail après synchronisation de la
source; relever FPS avant/après navigation, pause du curseur et nouveaux
avertissements Lua. Si une route reste lente, identifier son nom exact et
mesurer son rendu séparément avant d'optimiser un autre chemin.

### Suivi des routes signalées et de Dibs Administration — 2026-10-29

Le joueur a précisé que Guided Setup, Automatic Dibs et Synchronization
restent lentes. Les sources montrent des projections calculées plusieurs fois
par rendu : Guided Setup faisait deux réconciliations roster/ledger via
`GetRankConfigurationSummary` puis `stepAllocationReconciliation`; Automatic
Dibs lisait le roster pour les classes puis le rescannait pour les allocations;
Synchronization reconstruisait les digests locaux (dont manifest, vault et
ledger) pour chaque membre de la liste. Le code réutilise maintenant ces
projections dans chaque navigation. Cela réduit des opérations redondantes;
les durées réelles Retail restent à mesurer.

Le message de Dibs Administration est reproduit par le code local : un bloc
DEBUG dans `BuildDibsAdministrationRoster` faisait un second passage puis
appelait `io.write`/`io.flush`, API absente du sandbox WoW. L'exception
interrompait le rendu avant la table. Le bloc a été retiré; une régression avec
`io=nil` vérifie que les 60 lignes du roster sont rendues avec un seul appel
de lecture par membre.

Le mécanisme Identity existait déjà : il invalide le roster sur
`GUILD_ROSTER_UPDATE` et recharge au prochain accès. Mais plusieurs routes
l'évitaient et `GetRosterMembers` fabriquait une copie complète à chaque appel.
`Identity.GetRosterSnapshot` expose maintenant le tableau trié conservé dans le
cache, documenté en lecture seule; les pages Officer, les règles de rang, les
permissions et la liste de pairs Sync le réutilisent. `GetRosterMembers` garde
son contrat historique de copie défensive pour les consommateurs qui en ont
besoin. La mise à jour reste une reconstruction complète après l'événement
global du jeu, pas un delta par membre : l'API WoW observée ne fournit pas ici
d'événement détaillé de membre modifié.

Validations ciblées : **52 PASS, 0 FAIL, 5 fichiers**. Compteurs du fixture :
un même snapshot est retourné entre événements; après invalidation, il est
remplacé après une seule lecture complète du roster; Dibs Administration et
Synchronization n'interrogent pas de nouveau les API roster; Automatic Dibs
réutilise le snapshot; Guided Setup calcule la réconciliation une fois;
Synchronization construit une fois chacun manifest/vault/ledger pour 60
membres. Ce ne sont pas des mesures de CPU/FPS. Les changements sont encore
dans la source et ne sont pas déployés dans le dossier WoW; aucun test en jeu
n'a confirmé leur effet sur les pauses rapportées.
