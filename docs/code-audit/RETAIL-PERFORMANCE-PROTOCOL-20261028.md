# Mesurer le lag Dibs dans WoW — protocole du 28 octobre 2026

Installation trouvée : E:\Games\World of Warcraft\_retail_\Interface\AddOns.
Dibs 0.8.10 et RC initialement 3.24.0, désormais 3.24.1 sur disque;
produit Retail sur disque 12.1.5.70575. Faire /reload après la mise à jour.
Le fichier Dibs du compte analysé fait 0,345 Mio, sans backups/aperçus persistés.
La priorité est donc la création d'objets et le CPU pendant la session; ces
observations disque ne remplacent pas les relevés ci-dessous.

## Première passe : fenêtres Dibs fermées

Les derniers essais avec RC+Dibs donnent environ 70–100 FPS, contre 120–130
sans Dibs. Pour isoler un troisième addon, tester temporairement uniquement
Dibs+RC au même endroit et relever le démarrage, 60 s et après 120 s. Si ce
couple reste fluide, réintroduire les autres addons par groupes; sinon mesurer
directement ce couple. Ne supprimer ou réinitialiser aucune SavedVariables.
Résultat ensuite fourni : avec seulement Dibs+RC, toujours 70–100 FPS. Cette
configuration minimale suffit donc à reproduire la baisse rapportée; inutile
de rechercher d'abord un troisième addon sans nouvelle preuve.
Le watcher RA-15 s'arrête après environ 30 s et les retries RC sont bornés;
un lag persistant au-delà impose d'examiner d'autres callbacks également.

Le lag est signalé avant l'ouverture de l'interface. Commencer uniquement par
cette passe de 2 à 5 minutes; les scénarios UI et raid viendront ensuite.
Garder la même zone, les mêmes addons, les mêmes réglages graphiques et limite
FPS, sans alt-tab pendant une fenêtre de mesure. Ne modifier aucune donnée Dibs.

1. Après connexion/reload et stabilisation du chargement, relever le build et
   l'initialisation avec la commande A.
2. À 30 s puis 90 s (et à 5 min si possible), exécuter B puis C et noter les
   valeurs. Exécuter D une fois pour compter les objets retenus.
3. Noter si le personnage est seul, en groupe ou en raid, si RCLootCouncil est
   activé, et si le lag est continu ou revient par pics espacés d'environ 60 s.
4. Garder ces relevés avant tout correctif. Les 250 Mo ne sont pas encore
   attribués à un mécanisme précis.

Les commandes font chacune moins de 255 caractères. Les lire individuellement
dans le chat avec /run. C suppose que A affiche un profiler disponible.

### A — Build installé et état de démarrage

    /run print(GetBuildInfo());print("DIBS",Dibs and Dibs.VERSION,"init",Dibs and Dibs.initialized);print("profiler",C_AddOnProfiler and C_AddOnProfiler.IsEnabled())

Un init absent est une donnée utile pour RA-04; ne pas appeler Initialize pour
le faire disparaître pendant la baseline.

### B — Mémoire attribuée et FPS

    /run UpdateAddOnMemoryUsage();for i=1,C_AddOns.GetNumAddOns()do if C_AddOns.GetAddOnInfo(i)=="RCLootCouncil_dibs"then print("DIBS MiB",GetAddOnMemoryUsage(i)/1024,"FPS",GetFramerate())end end

Cette valeur est un échantillon de mémoire attribuée par WoW, pas la taille du
fichier SavedVariables ni la quantité d'objets définitivement retenus. Une
hausse ponctuelle peut inclure des objets temporaires encore non collectés.

### C — Temps CPU récent, pic et compteur de lenteurs

    /run for _,k in ipairs({"RecentAverageTime","PeakTime","CountTimeOver50Ms"})do print(k,C_AddOnProfiler.GetAddOnMetric("RCLootCouncil_dibs",Enum.AddOnProfilerMetric[k]))end

Les temps sont en millisecondes. RecentAverageTime porte sur les 60 derniers
ticks du profiler; PeakTime est un maximum de session et ne doit pas être
interprété comme le pic du seul scénario courant. Comparer la différence du
compteur CountTimeOver50Ms entre deux relevés de la même session.
Ce sont des métriques de traitement addon, pas directement les temps de rendu
GPU ou les durées de chaque image.

### D — Compteurs légers de rétention, sans recopier la base

    /run local d=Dibs and Dibs.db;for _,k in ipairs({"backups","pendingImports","pendingRestores"})do local n=0;for _ in pairs(d and d[k]or{})do n=n+1 end;print(k,n)end

Cette commande lit l'état déjà présent; elle ne demande pas GetDB, de snapshot
ni de sérialisation. Aucun nom de joueur ni contenu d'historique n'est affiché.
Un nombre d'aperçus élevé justifie une analyse du volume; il n'autorise pas
leur suppression.

## Durée des images : sonde temporaire optionnelle de 30 secondes

Cette sonde ajoute un seul OnUpdate, compte sans stocker d'historique, puis se
désactive au bout de 30 secondes. Elle est **absente du TOC et désactivée par
défaut** : seules ces commandes manuelles la créent. Utiliser exactement la
même sonde pour les comparaisons A/B. Ne pas la lancer une deuxième fois avant
la fin/nettoyage de la première.

Créer les compteurs :

    /run DibsAuditFrame=CreateFrame("Frame");local f=DibsAuditFrame;f.t=0;f.n=0;f.p=0;f.s=0;f:Show()

Démarrer :

    /run DibsAuditFrame:SetScript("OnUpdate",function(f,e)f.t=f.t+e;f.n=f.n+1;f.p=math.max(f.p,e);if e>.05 then f.s=f.s+1 end;if f.t>=30 then f:SetScript("OnUpdate",nil);f:Hide();print(f.t,f.n,f.p*1000,f.s)end end)

Les quatre sorties sont : secondes observées, nombre d'images, durée maximale
en millisecondes, nombre d'images dépassant 50 ms. On peut calculer la durée
moyenne par secondes × 1000 / nombre d'images. La sonde ne calcule pas de p95.
Les chargements, alt-tab et ouvertures de fenêtre pendant la période affectent
la mesure et doivent être notés.

Nettoyer ou arrêter immédiatement :

    /run if DibsAuditFrame then DibsAuditFrame:SetScript("OnUpdate",nil);DibsAuditFrame:Hide();DibsAuditFrame=nil end

Un /reload retire aussi cette instrumentation non persistée. Aucun traitement
périodique ni journal continu n'est ajouté aux sources de l'addon.

## Allocation temporaire : mesure ponctuelle optionnelle

Pour les pages qui laggent même sans RC, ouvrir une page Officer puis mesurer
un seul Refresh avec la commande suivante. Elle reconstruit la page courante
comme le fait le code normal; relever séparément Rank Rules, Loot Rules et
Settings avec les mêmes données. C'est une mesure de reconstruction à chaud,
pas du premier chargement. Ne pas la boucler.

    /run local f=DibsOfficerFrame;if f then local r=C_AddOnProfiler.MeasureCall(f.Refresh,f);print("ms",r.elapsedMilliseconds,"alloc",tostring(r.allocatedBytes),"free",tostring(r.deallocatedBytes))end

Cette mesure native peut distinguer le temps passé des seules quantités de
travail synthétiques décrites en RA-13/14.

Après la baseline, hors combat, cette commande mesure une reconstruction de
l'index courant. BuildManifest met à jour l'index local de synchronisation;
elle n'envoie pas le digest et ne change pas les soldes. La commande ajoute
elle-même ce travail : l'isoler du scénario de repos et ne pas la boucler.

    /run local r=C_AddOnProfiler.MeasureCall(Dibs.Sync.BuildManifest);print("ms",r.elapsedMilliseconds,"alloc",tostring(r.allocatedBytes),"free",tostring(r.deallocatedBytes))

Les valeurs alloc/free sont les octets alloués/désalloués pendant l'appel, pas
la croissance définitive du heap ni la rétention future. Pour mesurer les
réceptions réelles, une sonde de fonctions opt-in pourra ensuite agréger
seulement appels, temps total/max et octets, sans payload ni copie de DB.
Cette instrumentation supplémentaire n'a pas été installée pendant l'audit.

## Comparaisons à réaliser après la première passe

| Scénario | Procédure | Ce que cela isole |
|---|---|---|
| Repos 30 s / 90 s / 5 min | Dibs fermé, puis même test dans le groupe habituel | chargement, retries 30–120 s, heartbeat et trafic des pairs |
| Dibs désactivé | même zone/actions/addons, Dibs seul désactivé par l'utilisateur puis reload | contribution de Dibs au temps d'image; aucune réinitialisation SV |
| Dibs seul puis avec RC | activation contrôlée hors activité de loot, même scénario | interaction et attribution de bibliothèques partagées |
| Ledger primaire/secondaire | même contenu et volume comparables, sur environnement de validation | amplification RA-01; ne pas changer le ledger de guilde live pour mesurer |
| Ouverture/fermeture UI | 5 cycles identiques après baseline | allocation initiale, pool réutilisé ou croissance continue |
| Data/Health | une ouverture séparée | copies de snapshots/diagnostics; peut elle-même provoquer un freeze |
| Sync/rattrapage | données synthétiques ou session de validation | temps de réception et croissance du cache sans altérer le live |
| Raid/combat | seulement une fois le problème de repos caractérisé | courbe CPU et temps d'image pendant les événements de loot/roster |

Ne pas utiliser BuildDebugReport/GetSizeDiagnostics comme compteur de la
baseline : ils réalisent justement des copies/sérialisations suspectes.
Aucune boucle de garbage collection forcée n'est proposée. Ne pas nettoyer
les sauvegardes ou les aperçus pour produire artificiellement un meilleur score.

## Relevé à rapporter

| Build WoW / version Dibs / RC | Scénario / durée | MiB début → fin | CPU récent début → fin | Δ ticks >50 ms | Images >50 ms / max | backups / imports / restores |
|---|---|---|---|---|---|---|
| À remplir | Repos, fenêtres fermées | | | | | |

Pour une correction, comparer ces mêmes métriques et les mêmes volumes avant
et après. Ne pas annoncer une amélioration chiffrée sans ces mesures.

## API vérifiées et limites de version

Les commandes utilisent les API du code client Retail public consulté le
28 octobre 2026. Le build de l'utilisateur reste à relever par A; ne pas
supposer que le TOC de développement correspond au client installé.

- Le profiler expose GetAddOnMetric, MeasureCall, les temps en ms et les
  compteurs d'allocation : [documentation générée du client](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/AddOnProfilerDocumentation.lua).
- Sens des métriques RecentAverageTime/PeakTime et seuils :
  [constantes du profiler](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/AddOnProfilerConstantsDocumentation.lua).
- Le code de la barre de performance utilise UpdateAddOnMemoryUsage,
  GetAddOnMemoryUsage, C_AddOns et C_AddOnProfiler :
  [source de PerformanceBar](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_PerformanceBar/PerformanceBar.lua).

Il s'agit d'un miroir du code client, pas d'une exécution dans le client de
l'utilisateur. La procédure n'utilise pas les anciens compteurs CPU
scriptProfile comme fondement de la mesure.
