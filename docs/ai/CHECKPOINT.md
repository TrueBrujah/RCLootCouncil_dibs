# RCLootCouncil_Dibs — Persistent Project Checkpoint

## Candidat 0.9.0 — 2026-11-18

- Décision utilisateur explicite : passer le candidat de travail 0.8.12 à
  **0.9.0**. Numéro aligné dans Core/TOC, README, guides FR/EN, notes du candidat
  et documentation générée. Stable publiée toujours indiquée 0.8.11. Aucun tag,
  publication, fusion vers dev/main ou nouveau déploiement WoW.
- La règle de compatibilité major/minor existante reste inchangée : un pair
  annonçant 0.8.11/0.8.12 est refusé par 0.9.x avec `ADDON_UPDATE_REQUIRED`, sans
  effet sur le ledger. Les variations patch/dev de la famille 0.9.x restent
  acceptées. Mettre à jour les clients ensemble. Aucun changement de schéma de
  données ou de format du protocole n'est ajouté par ce renumérotage.
- Les preuves d'installation 0.8.12 restent historiques dans la fiche Retail,
  dont le nom de fichier est conservé pour les liens existants; sa campagne
  courante est explicitement 0.9.0. Les verrous canoniques restent false et les
  tâches 026 T041/T042/T043/T047–T050 ne sont pas closes par le numéro de version.
- Validation : suites complètes **2 190 PASS / 0 FAIL sur 274 fichiers, sous chacun
  de Lua 5.1.5 et Lua 5.4**; **25/25 sur trois suites ciblées Fengari** (compatibilité,
  verrouillage et candidat); compilation **112/112 Lua 5.1**; préflight addon
  **121 fichiers**; documentation Check PASS, Pester documentation **26/26**, sorties
  PowerShell 5.1/7 **8/8 MATCH**, whitespace PASS. Aucun fichier vendor modifié.
- Les optimisations identifiées lors de la revue performance restent à faire :
  vérification périodique de navigation joueur, coût de récupération au démarrage
  et construction complète du rapport historique. Les essais Retail et la
  récupération externe vierge restent distincts. Pas de certification runtime.

## Commit et synchronisation avec dev — 2026-11-17

- Autorisation utilisateur explicite : commit, synchronisation et PR vers `dev`.
  Commit du lot local : `24ef5ad`. Intégration de `origin/dev` à `52e9419`, avec
  résolution des conflits et préservation des corrections du candidat 0.8.12.
  Les réglages locaux de VS Code et la suppression locale du skill restent hors
  commit. Pas de fusion de PR, tag, release, installation WoW ou reset réel.
- Changements indépendants de dev conservés : migration additive guild 7→8 /
  disputes 2→3 et ses tests représentatifs, CI Fengari par lots, noms de package
  sûrs pour les branches contenant `/`, références stables 0.8.11 et manifeste
  qui ne déclare plus des validations non exécutées.
- Governance/ProtectedActions : une proposition conserve son epoch et son
  coordinateur; retry/acceptation refusés si cette autorité change. Le protected
  `ledger.use` restitue le vrai code de refus du Ledger. T014 ne repose plus sur
  quatre assertions vides : six tests passent par le vrai store (identités après
  reload, retry, lectures détachées, bornes, autorité périmée). Le contrat actuel
  de proposition reste le seul propriétaire; le transport/ACK de l'ancien contrat
  n'est pas réintroduit comme second chemin. T048 reste explicitement ouvert.
- Qualification finale sur fichiers figés : **2 189 PASS / 0 FAIL, 274 fichiers,
  sur chacun de Lua 5.1.5 et Lua 5.4**; **186/186 sur 18 suites ciblées Fengari**;
  **47/47 Pester**; compilation Lua 5.1 **112/112**; préflight addon **121 fichiers**;
  docs **29 concepts, 0 erreur, 10 avertissements hérités**, huit sorties générées
  identiques sous PowerShell 5.1/7. Contrôle whitespace hors vendors PASS.
- Manifeste des 447 fichiers source/test validés, SHA-256 :
  `E6111A2DDD8BE58CF452D6D7A3E82B7639AF9DD40F27F7A3439695C7CEEFCE49`.
  Audit guard : **exit 1, 238 différences applicatives, zéro différence protégée**.
  Baseline conservée, SHA-256
  `226B67846909BA10FC59C12F6D6F59ED8EA7920115AEEEBFD26D6212284E3871`.
  Les octets du vendor approuvé sont conservés lors du staging.
- Restent les observations Retail et les matrices 026 T047–T050, dont le relais
  typé des propositions et l'autorité de récupération externe vierge. Les deux
  verrous canoniques source restent false. Aucun résultat hors jeu ne certifie WoW.

## Reprise des 190 échecs automatisés — 2026-11-17

- Demande : corriger les échecs restants, sans nouvelle approbation pour le
  travail ordinaire. Mode CHANGE, spécifications existantes conservées. Aucun
  commit/push, bump, publication ou nouveau déploiement; le candidat installé
  décrit plus bas ne contient pas ces sources.
- Suites complètes Lua 5.1.5 et Lua 5.4 : **2 181 PASS / 0 FAIL chacune,
  274 fichiers**. Les 190 échecs
  du checkpoint précédent sont traités; **12 cas supplémentaires** couvrent
  rapport, états après reload, langue FR, propositions invalides et scan partiel.
  Fengari : **767 PASS / 0 FAIL sur 65 fichiers ciblés**, pas une suite complète.
  La dernière passe 5.1 a aussi exposé un `load(string)` incompatible dans le
  simulateur de livraison privée : chargement adapté via `loadstring`/`setfenv`,
  environnement vide conservé, puis **17/17** sur les trois runtimes et nouvelle
  suite complète 5.1 verte. Les sources addon sont restées figées pendant ces
  passes. Empreinte du manifeste source SHA-256 :
  `AB0BAE11A096D815EF17E610D361940C05B039AD0E109A436074FA266B1AE13E`.
- Réintégration ciblée des deltas approuvés de `d0728ef` pour
  HistoricalBaseline, Installation et MultiLedger, après lecture du diff et de
  RF-0013 : collecte paginée persistante, refus des sources incomplètes,
  propositions et approbations vérifiées. Corrections supplémentaires : scopes
  non denses refusés sans écriture, validation avant adoption d'une proposition
  ancienne, identifiant de liaison conservé, aucune collecte incomplète masquée
  par une collecte complète. Le statut Installation utilise son vrai indicateur
  de données ledger, pas un global inexistant. Pas de modification des vendors.
- Governance annonce immédiatement la clôture du coordinateur; adoption du
  successeur seulement sur epoch/séquence/racine correspondant à la chaîne
  locale. La récupération du registre en cours peut résoudre son propre retard;
  tous les autres retards restent bloquants. RF-0035/RF-0043 et RF-0044 validés
  ensemble; les fixtures B05b/B06 fournissent désormais une clôture réelle.
- Disputes/OfficerUI/locales : rapport historique en lecture seule, accessible
  depuis Diagnostics, cinq classes distinctes, pagination 20 lignes et refus
  pour un membre. Les débits ordinaires ne deviennent pas des corrections.
  Résultats de correction visibles en EN/FR; le détail distingue acceptation en
  session, observation exacte après reload, projection manquante, retard et
  incompatibilité. La clôture sans correction reste une décision non comptable.
- ProtectedActions refuse les opérations canoniques fermées avant d'interpréter
  une proposition; les contrôles d'autorité restent actifs dans le candidat
  isolé ouvert. Les tests de corrections avancées passent par les vrais intents,
  propositions et commits; aucun retour au chemin `ledger.use` historique.
  Les deux verrous source restent **false**. Readiness refuse les intégrations
  dégradées; Wizard montre le blocage obligatoire avant un avertissement optionnel.
- Tests d'interface : fixture de guilde configurée explicite, fondation et
  publication réelles, reload sous le rôle testé. Le chargeur par défaut garde
  l'installation vierge et les tests de progression restent actifs. Pas de
  relâchement des guards pour ouvrir artificiellement des pages. Snapshot de
  roster partagé pour les rangs et navigation réutilisée lors de la sélection.
  Ledger ne lit plus le global indéfini `ledgerId` pour son cache de résumé.
- Contrôles déjà terminés : compilation Lua 5.1 **112/112**, préflight addon
  **121 fichiers**, empreintes approuvées **7/7**, génération/check docs PASS
  (**29 concepts, 0 erreur, 10 avertissements hérités**), comparaison PowerShell
  5.1/7 des huit fichiers générés **8/8 MATCH**, diff-check PASS. Les diagnostics
  IDE de champs dynamiques et annotations `@doc` restent; aucun global indéfini
  détecté dans les trois fichiers revérifiés Installation/Ledger/OfficerUI.
- Audit guard exécuté : **exit 1, 234 différences applicatives, zéro différence
  de bibliothèque protégée**. Ce résultat n'est pas un PASS global d'intégrité;
  il inclut le travail déjà présent dans la branche. Baseline non remplacée.
  T066 de 012, T031 de 017 et T016/T029/T030/T040 de 026 clos pour leur périmètre
  hors jeu; T047–T050 de 026 restent ouverts pour leur matrice complète.
- À reprendre : déploiement puis campagne Retail N02/N07 et N20–N22; T026/T030
  Retail 017 restent ouverts. Les exigences de release 026 et la décision
  d'autorité de récupération externe vierge (007 T036 / 026 T049) restent
  distinctes de la suite automatisée désormais verte. Aucun essai WoW inventé.

## Régressions corrigées et tâches restantes — 2026-11-17

- Autorisation : corriger les problèmes puis identifier les autres tâches, sans
  redemander les opérations ordinaires. Aucun commit/push/publication, installation
  supplémentaire ou changement de version. **Les sources corrigées ci-dessous
  diffèrent du candidat installé dans la section suivante.**
- Roster : initialiser la révision de fixture par le service réel; créer un vrai
  historique pour la route désactivée et vérifier l'état vide dirigé vers Wizard.
  Deux échecs reproduits avant correction; slice roster/navigation **42/42**.
  Préconditions de tests corrigées, aucune règle roster/chronologie changée.
- Pre-Dibs : Core, LootPipeline, PlayerUI et EncounterJournal délèguent au service
  public et ne se rabattent plus sur le créateur interne. L'absence du service ne
  contourne pas la politique. PreDibs refuse une même identité de demande dans un
  autre ledger avant toute initialisation du store revendiqué; source historique,
  erreurs de ledger non approuvé et données existantes conservées. Quatre cas
  de scope couvrent les deux sens et les deux chemins Sync avec hashes avant/après;
  deux cas supplémentaires protègent le tagging paresseux des anciennes demandes
  non étiquetées quand le store secondaire a un alias dans `root.requests`.
- Réservations : Governance/Ledger/SyncV2 excluent les propositions terminales
  des totaux en attente. Libérations optionnelles séparément hashées dans le
  digest existant, pagination commune, autorité acteur/coordinateur et scope
  immuable vérifiés avant application; tombstones bornées conservées après reload
  et perte de message, sans rediffusion des libérations reçues. **17 nouveaux cas**
  couvrent refus atomiques, sept champs immuables, arrays invalides, réordonnancement,
  nouvelle réservation après déconnexion et pagination. L'ancien champ `records`
  reste PENDING-only; anciens émetteurs acceptés, convergence des anciens récepteurs
  non revendiquée. Capacité `awardReservationReleases` annoncée. Contrat/plan 017
  alignés avant implémentation; aucune écriture comptable ou gate release ajoutée.
- Fixture guild-active-ledger réalignée sur le vrai statut `PENDING_RECONCILIATION`,
  avec cas terminaux exclus et attentes de partition inchangées; aucun service
  rendu permissif pour faire réussir ce test.
- Validation finale : **383/383 sur 36 suites sous Lua 5.1.5 et Fengari**.
  Suite globale Lua 5.4 : **1 979 PASS / 190 FAIL, 274 fichiers**, comparée au
  relevé frais initial **1 934 / 209, 273 fichiers** : **19 échecs retirés,
  zéro nouveau nom d'échec** et 26 nouveaux cas. Lua 5.1.5 : **112/112 sources**
  compilées. Compilateur reconstruit sous `%TEMP%/dibs-lua51-validation-20261117`
  depuis [Lua 5.1.5 officiel](https://www.lua.org/ftp/), SHA-256 vérifié, sans
  toucher aux bibliothèques du dépôt. Pas de suite globale 5.1/Fengari dans ce lot.
- Documentation régénérée via le script existant : huit fichiers, Check PASS;
  29 concepts, zéro erreur et dix avertissements hérités. Graphe addon **121 fichiers**;
  sept empreintes du calendrier approuvé inchangées; diff-check PASS. Diagnostics
  IDE non globalement propres : champs dynamiques et annotations @doc restent,
  ainsi que le global `ledgerId` déjà signalé dans Ledger. Les tests modifiés et
  Core/SyncV2/Governance/LootPipeline/EncounterJournal sont sans diagnostic au contrôle.
- Suivi : 002 T058, 020 T042, 029 T067 et 017 T029 terminées hors jeu; 017 T030
  et [Retail N20/N21](../audits/0.8.12-TESTS-RETAIL-FR.md) ouverts. Les 190 échecs
  globaux ne sont pas clos par ce lot. N19/T053, T026 Retail et gates 026 inchangées.
- Tâches admissibles suivantes : **012 T066** (qualifier/adapter les fixtures UI
  post-setup sans contourner les guards réels); **026 T016/T029/T030/T040 rouvertes**
  (helpers d'issues/opérations et rapport historique absents du code courant,
  anciennes mentions PASS conservées comme historiques); **017 T031** (qualifier
  handoff/epoch et convergence RF-0035/RF-0043). RF-0013 collecte/propositions,
  RF-0042 C13 de récupération contradictoire et les autres familles globales
  restent à qualifier. La décision humaine d'autorité pour récupération externe
  vierge reste en attente et ne bloque que son périmètre dépendant.

## Installation du candidat Retail — 2026-11-17

- Reprise autorisée par l'utilisateur depuis la campagne Retail. Installation via
  [deploy.ps1](../../scripts/deploy.ps1), version 0.8.12, build `41623970f2b3-dirty`.
  Aucun changement du code applicatif, commit, push ou publication dans ce lot.
- Précontrôle sources/installé : **121 fichiers requis**; comparaison de livraison :
  **150/150 fichiers** (SHA-256, TOC comparé hors métadonnée de build ajoutée).
- Validation fraîche : **45/45 sur quatre suites sous Lua 5.4** (bornes des dates,
  brouillon guidé service/UI, capture du coffre); compilation **63/63 fichiers Lua
  applicatifs**, hors bibliothèques tierces. Lua 5.1 et suite globale non relancés;
  leurs limites précédentes restent applicables.
- WoW était ouvert pendant la copie. **Redémarrage complet non observé**; aucun
  résultat Retail ajouté. Suite : quitter complètement WoW, relancer, noter le
  build chargé, reprendre N02 puis N07 de la [campagne](../audits/0.8.12-TESTS-RETAIL-FR.md).
  V01–V05 restent prioritaires avant une prise de récompense disponible.

## Bornes des dates d’inscription — 2026-11-16

- Décisions utilisateur : ouverture strictement avant le début de saison;
  clôture au plus tard à la fin de saison si les deux fins sont définies.
  [FR-058](../../specs/029-seasonal-raid-roster/spec.md) et T066 mis à jour.
- Fichiers : [SeasonalRoster](../../src/modules/SeasonalRoster.lua),
  [Wizard](../../src/modules/Wizard.lua), [OfficerUI](../../src/ui/OfficerUI.lua),
  locales FR/EN, contrat/plan/tâches 029, changelog et campagne Retail N19.
  Validation stricte de création, sauvegarde de brouillon et publication;
  comparaison des timestamps complets, fins facultatives et fins égales permises.
  Mode historique du validateur inchangé, sans migration ni réécriture des hashes,
  révisions ou reçus d’opérations. Les refus ne consomment pas d’opération.
- [Régressions dédiées](../../tests/integration/seasonal_roster_date_boundaries_spec.lua) :
  **8/8 sous Lua 5.4.6, Lua 5.1.5 et Fengari** : bornes, atomicité des refus,
  prévalidation de l’assistant avant initialisation, messages FR/EN, sync
  historique authentifiée et rejeu d’un reçu créé avant cette règle.
- Sélection élargie de 21 fichiers : **239 réussis / 2 échecs sous les trois
  runtimes**, avant ajout des deux derniers cas dédiés. Les deux échecs
  se reproduisent sous Lua 5.4 avec le nouveau contrôle de chronologie neutralisé
  uniquement en mémoire : `characterEligibility.revision` absent dans une fixture
  de sync, et attente de route roster sur un état d’installation qui ouvre wizard.
  Ils ne sont pas déclarés corrigés. Compilation Lua 5.1 : **112/112**;
  documentation générée vérifiée (29 concepts, 0 erreur, 10 avertissements
  historiques), `git diff --check` réussi.
- Limite de portée : le cycle existant ferme toujours les inscriptions au début
  de saison. Ce lot valide les dates configurées et ne change pas les transitions
  ni les règles d’inscription après activation. N19 reste NON TESTÉ en jeu;
  T053 reste ouvert. Aucun commit, installation ou publication.

## Consolidation architecture/UX/sécurité — 2026-11-16

- Autorisation explicite : « ok implante la » pour la [proposition](../audits/0.8.12-PROPOSITIONS-ARCHITECTURE-UX-SECURITE-FR.md).
  Les modifications préexistantes sont conservées. Aucun nouveau rôle, critère de
  distribution ou droit de mutation; version 0.8.12 inchangée. Aucun commit, push,
  déploiement, installation ou publication.
- UI : nouveau [OfficerDashboard](../../src/ui/OfficerDashboard.lua), chargé dans
  le TOC et le loader de test avant OfficerUI. Le contrôleur fournit la projection
  autorisée; aucune dépendance inverse vers OfficerUI. Phases de profilage conservées.
  Services et prochaine action avant activité/statistiques; distinction entre saison
  disponible, récupération bloquée et vérification inconnue. RC absent est facultatif.
  Dashboard et décisions importantes localisés FR/EN; « Clore sans correction »
  décrit l’effet nul sur les soldes et conserve les gates canoniques.
- Joueur : [PlayerUI](../../src/ui/PlayerUI.lua) affiche après le solde un raccourci
  vers son propre dossier lorsqu’un Officer attend une réponse. Aucun envoi ni
  mutation comptable au clic de navigation. Portée d’ACK explicitée; [DataUI](../../src/ui/DataUI.lua)
  rappelle qu’un snapshot local partage les SavedVariables et exige une copie indépendante.
- Récupération : [Core](../../src/Core.lua) vérifie aussi les ledgers secondaires
  approuvés/archivés, avec résultats runtime liés à guilde/ledger et alias primaire
  compatible. [Disputes](../../src/modules/Disputes.lua) préserve les états des autres
  ledgers. Un conflit d’identité d’opération est détecté **avant** toute réparation
  de projection; le test vérifie l’état métier intégral inchangé au refus.
  [Ledger](../../src/modules/Ledger.lua) utilise le résultat scoped approprié,
  sans repli d’un statut primaire inconnu vers un succès en cache.
- Régressions : démarrage d’un historique secondaire non vide; réception SyncV2
  sérialisée interrompue avant la première ligne, entre les deux lignes et avant
  l’index final, puis redémarrage/reconstruction/rejeu avec oracles de soldes,
  identifiants, séquence et racine. Les gates privées sont ouvertes seulement dans
  les fixtures; les constantes de release restent fermées.
- Fixtures corrigées : rang membre explicite et vrais prérequis de navigation pour
  recherche/éligibilité; titres History localisés; cas follow-up utilisant une vraie
  transaction d’origine et autorité canonique, sans assouplir les services. Les sept
  [scénarios spoof](../../tests/unit/sa002_spoof_test_spec.lua) ont maintenant des
  assertions. Les anciens harness SA-002 roster/bypass non sélectionnés ne sont
  pas utilisés comme preuve d’acceptation de sécurité. Ancien rapport 026 qualifié
  explicitement d’historique et partiel.
- Validation ciblée finale : **334/334 sur 31 suites**, sous **Lua 5.4.6, Lua 5.1.5
  natif et Fengari**; retest final UI Fengari **97/97 sur cinq suites**. Compilation
  **112/112** sous Lua 5.1.5; graphe de livraison **121 fichiers**. Documentation
  régénérée puis Check PASS : **29 concepts, zéro erreur, dix avertissements hérités**.
  Diff-check PASS. IDE : nouveau renderer, OfficerUI, DataUI et Disputes sans erreur
  au contrôle; diagnostics de typage dynamique/@doc et un global existant dans Ledger
  restent signalés ailleurs. Ne pas présenter l’IDE global comme propre.
- **Suite globale native Lua 5.1.5 : 1 914 PASS / 221 FAIL sur 272 fichiers**.
  Ce résultat est frais, distinct de l’ancienne baseline 1 811/134. Les échecs
  comprennent des scénarios sans fondation qui attendent des pages opérationnelles,
  des actions qui attendent des corrections malgré la gate fermée et des API
  historiques absentes (BuildLegacyCorrectionReport/DescribeCorrectionOutcome).
  Pas de qualification exhaustive ni d’attribution de tous ces échecs à une cause
  préexistante. La sélection ciblée verte ne clôture pas les gates globales 026/029.
- Garde historique final : **exit 1, 209 écarts applicatifs, zéro écart protégé**;
  baseline historique inchangée. Ce n’est pas un PASS d’intégrité globale. Aucun
  contenu de bibliothèque tiers modifié. Les nouveaux écarts concernent les chemins
  de consolidation, sans recapture ou restauration automatique.
- Documents alignés : spécification/plan/tâches 011, tâches 022, plan/tâches/quickstart
  et statut 026, guides joueur/Officer FR/EN, changelog, dépendances et documentation
  générée. [Retail N16–N18](../audits/0.8.12-TESTS-RETAIL-FR.md) ajoutés **NON TESTÉS**;
  les autres observations Retail restent ouvertes. Checklists 011 : 18/18; 026 :
  23/23 (qualité de spécification seulement). Hooks SpecKit avant/après : aucun déclaré.
- **Décision bloquant uniquement la récupération externe vierge (007 T036)** :
  checksum de contenu sans authentification de l’auteur. Question présentée via
  outil asynchrone : confirmation par pair autorisé avec même chaîne canonique
  (recommandation), ou adoption exceptionnelle par GM après revue explicite.
  Aucune réponse reçue à ce checkpoint; aucune adoption ni contournement d’import.
  Documenter le choix dans les contrats avant le code dépendant.
- Suite admissible : qualifier les échecs globaux par contrat/fixture sans modifier
  les règles pour les faire passer, poursuivre les acceptations restantes 026,
  puis observer les matrices Retail dans un environnement autorisé. T049/T050
  restent ouvertes globalement; ne pas annoncer toute la proposition terminée.

## Lot joueur et readiness canonique — 2026-11-16 (validation ciblée terminée)

- Approbation explicite recueillie pour 026 : restaurer uniquement la référence
  historique `b59a3f3:docs/code-audit/BASELINE.json` puis ajouter les sept empreintes
  LibAceGUIWidgets **v0.12.0** déjà approuvées et consignées dans son registre.
  Conserver toutes les empreintes historiques; aucune recapture, aucun changement
  interne de bibliothèque et aucune acceptation automatique des autres écarts.
  L'agent doit vérifier l'intégrité avant de reprendre T046/T049. La première
  tentative n'avait changé que le relevé de blocage dans les tâches 026.
- Lot indépendant My Dibs terminé hors jeu dans [PlayerUI](../../src/ui/PlayerUI.lua) :
  Dibs restants avant allocation/utilisation, Pre-Dibs actifs avant Main/Alt.
  Contrôles Main/Alt repliés par défaut, résumé complet chargé seulement à l'ouverture,
  sélection conservée au pliage et nettoyée à la fermeture de fenêtre. Probation active
  toujours visible avec date de fin lisible; inactive masquée. Services de déclaration,
  approbation et comptabilité inchangés, sans migration. Navigation et commandes
  d'identité/feedback localisés dans [enUS](../../src/locales/enUS.lua) et
  [frFR](../../src/locales/frFR.lua), identifiants de routes conservés.
- Validation finale : **65/65 sur quatre suites sous Fengari et Lua 5.4.6 natif**,
  [RF0019](../../tests/integration/rf0019_player_eligibility_surface_spec.lua),
  [B11 Player](../../tests/integration/b11_player_ui_spec.lua),
  [seasonal completion](../../tests/integration/seasonal_roster_completion_ui_spec.lua)
  et [eligibility](../../tests/unit/character_eligibility_spec.lua). Fixture RF0019
  remise en contexte de guilde configurée pour franchir les guards; ce double UI
  ne prouve pas la readiness canonique. Nouveaux comportements en échec avant code;
  assertion d'ordre du résumé B11 corrigée sans modifier les règles pour passer.
- Guides Player FR/EN, changelog et [Retail N15](../audits/0.8.12-TESTS-RETAIL-FR.md)
  actualisés. Documentation régénérée et **Check PASS : 29 concepts, zéro erreur,
  dix avertissements hérités**; diff-check PASS. IDE : locales/tests sans erreur;
  avertissements de typage des modules dynamiques Dibs et annotations @doc toujours
  présents dans PlayerUI, sans erreur de syntaxe rapportée. Ne pas prétendre un IDE
  global propre. Lua 5.1, suite globale et Retail non exécutés; N15 reste NON TESTÉ.
- Résultat canonique reçu du même agent `e683276b-0ff2-4cfc-b322-395b13c9f7d0` :
  **026 T046 clôturée**, T049 toujours ouverte et partielle. Modifications dans
  [Core](../../src/Core.lua), [Types](../../src/Types.lua),
  [Ledger](../../src/modules/Ledger.lua), [Disputes](../../src/modules/Disputes.lua),
  deux suites existantes, tâches 026 et baseline approuvée. Core refuse une
  récupération non table et lie le résultat au guildKey/guild-primary. Readiness
  réelle : récupération et scope, autorité/coordinateur, transport, V2, retard,
  intégrité/epoch et capacités des pairs connus en ligne, sans projections UI.
  Reprise primaire et réception non-coordinateur prouvées sur historique non vide
  legacy/award/correction; identités, hashes, séquence/root et soldes préservés.
  Gate release inchangée et désactivée; aucune readiness de publication revendiquée.
- Agent : **77/77 sur six suites canoniques**, Fengari et Lua 5.4.6. Parent :
  **142/142 sur dix suites intégrées** (six canoniques + quatre Player/eligibility),
  sous les mêmes moteurs, après réception du résultat. Suites canoniques :
  ledger_operation, ledger_operation_commit, canonical_dispute_operation,
  ledger_operation_recovery, persistence_recovery et canonical_dispute_sync.
  [Quickstart 026](../../specs/026-canonical-idempotent-corrections/quickstart.md)
  et changelog alignés; documentation régénérée/vérifiée après intégration.
- Baseline historique préservée avec exactement sept empreintes protégées approuvées
  ajoutées. Guard final rapporté par l'agent : **exit 1, 206 écarts applicatifs,
  aucun protégé**, sans recapture. Ce n'est pas un PASS; ne pas masquer les écarts.
  T049 reste ouverte : startup secondaire/multi-ledger, fault cuts sur commits reçus,
  matrice complète de récupération entre clients indépendants. Lua 5.1, Retail et
  suite globale non exécutés. Dashboard et libellé de résolution restent les petits
  lots design admissibles suivants; Markdown riche/fuseaux et deux échecs Officer
  hérités inchangés. Aucun commit, push, installation, publication ou déploiement;
  version inchangée.

## Catégories unifiées et historique joueur convivial — 2026-11-16

- Approbation utilisateur : catégories d'inscription = difficultés Normal/Heroic/Mythic
  pour les nouvelles saisons et brouillons explicitement sauvegardés. Saisons
  publiées, catalogues historiques et inscriptions existantes non migrés. Un seul
  groupe de choix dans [OfficerUI](../../src/ui/OfficerUI.lua), sauvegarde obligatoire
  avant ouverture si les choix ont changé; [PlayerUI](../../src/ui/PlayerUI.lua)
  propose les catégories publiées compatibles sans changer voie demandée ni revue.
  029 FR-056–057, plan/contrat, guides et changelog alignés; T064/T065 cochées pour
  l'implémentation hors jeu. Preuves saisonnières conservées : **153/153 sur 15 suites,
  sous Fengari et Lua 5.4.6 natif**. [Retail N13](../audits/0.8.12-TESTS-RETAIL-FR.md)
  NON TESTÉ; T053 reste ouverte.
- Revue designer read-only `df7f5976-81c2-4e23-a0e0-ecd202813764` reçue : History
  au clic gauche; solde My Dibs avant les déclarations; états Dashboard avant les
  statistiques; libellé explicite de résolution sans correction; navigation localisée.
  Seul le premier petit lot a été implémenté : clic gauche et menu clic droit ouvrent
  les mêmes détails History; aide au survol et commande localisées EN/FR, signalement
  existant présélectionné. Pas de mutation comptable ni nouvelle permission.
- Validation finale History : **30/30 sur deux suites, sous Fengari et Lua 5.4.6
  natif** ([report UI](../../tests/integration/player_report_problem_ui_spec.lua) et
  [B11 Player](../../tests/integration/b11_player_ui_spec.lua)). Consultation sans
  demande créée, solde/historique conservés, clic droit maintenu. Les cas EN/FR sont
  séparés; l'échec initial concernait l'assertion d'aide : AddHeading fournit une
  infobulle, pas du texte inline. La fixture vérifie désormais sa description
  réellement transmise. L'hypothèse de cache de fenêtre n'était pas la cause.
- La suite [unified history](../../tests/integration/unified_history_search_spec.lua)
  reste **3 PASS / 2 FAIL**, cas Officer aux lignes 197 et 232. Mêmes échecs reproduits
  sous Lua natif en retirant en mémoire le nouveau clic gauche/helper History, sans
  toucher aux fichiers, puis avec le code courant. Ils préexistent à ce petit lot;
  pas de correction hors périmètre ni de succès de suite globale revendiqué.
- Guides Player, changelog et [Retail N14](../audits/0.8.12-TESTS-RETAIL-FR.md)
  mis à jour. Documentation régénérée puis **Check PASS : 29 concepts, zéro erreur,
  dix avertissements hérités**. Diff-check PASS; contrôle IDE des fichiers History,
  test et locales sans erreur au dernier appel, sans garantie globale.
- Aucun commit, push, installation, publication ou déploiement dans ces lots.
  Version 0.8.12 inchangée; changements préexistants conservés. Retail, Lua 5.1 et
  suite globale non exécutés. Markdown riche et fuseaux/DST restent différés.
  Prochain lot substantiel : **026 T046 readiness non stubée**, avant T047–T050;
  aucune tâche canonique fermée ou implémentée par ce lot. Les autres améliorations
  designer restent à faire, sans prétendre que la refonte globale est terminée.

## Refonte saisonnière implémentée et vérifiée hors jeu — 2026-11-16

- L'utilisateur a approuvé la refonte conviviale après revue designer : formulaire
  commun, essentiels visibles, facultatif repliable sans perte, saison sélectionnée
  prioritaire, création/historique/catalogue explicites. Implémentation dans
  [OfficerUI](../../src/ui/OfficerUI.lua), locales EN/FR et quatre suites UI.
  Aucun changement métier, bibliothèque, schéma ou moteur de fuseaux. Approbation
  documentée dans [029 FR-053–055](../../specs/029-seasonal-raid-roster/spec.md) et
  [021 FR-037](../../specs/021-turnkey-guided-setup/spec.md); 029 T061–T063 et
  021 T038 cochées pour l'implémentation automatisée. Guides et changelog alignés;
  [Retail N08–N12](../audits/0.8.12-TESTS-RETAIL-FR.md) restent NON TESTÉS.
- Agent `c234cf3b-7dfb-46b4-9101-d57004a743fe` : cinq nouvelles régressions UI,
  résumés et saisies conservés au pliage, erreurs dévoilées, sauvegarde périmée
  rejetée sans écrasement; rechargement explicite. Les états des sections sont
  locaux et non persistés, seuls les champs du brouillon guidé utilisent la reprise
  existante. Rapport agent **165/165 sur 12 suites Fengari**; ce n'est pas une QA
  indépendante. Parent : **186/186 sur 15 suites, sous Fengari et Lua 5.4.6 natif**,
  diff-check PASS. Inclut service/contrat/reprise/navigation, éditeurs saisonniers,
  publication/activation et rafraîchissement/silence des notifications.
- Documentation générée : premier Check a détecté quatre références périmées
  après le déplacement de lignes UI. Régénération par le script existant, puis
  **Check PASS : 29 concepts, zéro erreur, dix avertissements hérités**; références
  [générées](../generated/) à jour. Diff-check final PASS.
- Diagnostics IDE : locales sans erreur; OfficerUI conserve des diagnostics de
  namespace, annotations `@doc` et inférences. Aucun zéro diagnostic revendiqué.
  Native 5.1.5 non relancé : aucun binaire trouvé dans les chemins précédemment
  retenus (sources temporaires vidées). Rendu Retail, combat/taint, dimensions et
  deux clients non testés; suite globale non relancée. Version 0.8.12 inchangée.
- Suite de tâches après refonte : convergence du lot 021 déjà implémenté.
  [Wizard](../../src/modules/Wizard.lua) vérifié pour projection ordonnée,
  reprise locale bornée/isolation guilde et résultats réels; [PlayerUI](../../src/ui/PlayerUI.lua)
  et [options RC](../../src/integrations/RCLootCouncilOptions.lua) vérifiés pour
  rafraîchissement visible conditionnel et silence limité aux appels guidés.
  Tests correspondants verts dans le lot 186/186 : T034–T036 cochées. T037 reste
  partielle (5.1, QA indépendante et observations Retail manquantes).
- Avant refonte : fermeture de table corrigée dans
  [guided_setup_resume_spec](../../tests/integration/guided_setup_resume_spec.lua).
  Fengari **37/37 sur quatre suites** (seasonal_roster_status,
  seasonal_roster_schedule_editor, guided_setup_resume,
  guided_setup_season_draft_ui); diff-check PASS. Ne pas attribuer ces résultats à
  la nouvelle refonte. Suite globale et Retail non relancés.
- Prochain lot substantiel admissible : 026 T046, premier prérequis canonique
  avant T047–T050 et la récupération externe 007. Aucun travail canonique commencé
  par cette refonte; ne pas fermer ces tâches ni contourner leurs dépendances.
  Aucune publication/installation/déploiement effectué, changements préexistants
  préservés. Les gates Retail 021 T037/029 T053 restent ouvertes.

## État antérieur — 2026-11-15

- Suite du parcours approuvé par l'utilisateur, **021 T031–T033 terminées** : Configure propose la préparation facultative d'un vrai brouillon de saison pour les profils progression/standard, avec nom, dates saison/inscriptions, catégories et horaires/règles facultatifs. Le même clic Apply délègue à `SeasonalRoster.CreateSeason` après fondation adoptée, avec ID stable; champs invalides bloqués avant toute mutation, aperçu incomplet explicite, bouton d'ouverture du roster après succès. Les saisons existantes et modules désactivés sont préservés, Custom reste manuel; aucune publication/activation/allocation implicite, aucun contrat recovery T049 ou quota Sync changé. Texte de fondation corrigé pour distinguer bootstrap technique et préparation de saison.
- Périmètres de ce complément : `wizard_season_service` — [Wizard](../../src/modules/Wizard.lua) et [18 tests service](../../tests/integration/guided_setup_season_draft_spec.lua); parent — [OfficerUI](../../src/ui/OfficerUI.lua), locales EN/FR, spécification/plan/contrat/tâches et guides; `wizard_season_ui_tests` — [10 tests UI](../../tests/integration/guided_setup_season_draft_ui_spec.lua); `qa_wizard_season` — revue indépendante et huit scénarios supplémentaires temporaires, sans écriture source. **290/290 sur 18 suites sous Fengari, Lua 5.4.6 et Lua 5.1.5 natif; QA 80/80 sur chaque moteur** (28 nouveaux cas + 8 QA + 44 régressions). Compilation **111/111**, doc Generate/Check PASS (29 concepts, zéro erreur, dix avertissements hérités), graphe addon **120 fichiers PASS**, diff-check PASS. Diagnostics IDE de namespace/types/annotations toujours présents; suite globale non réexécutée.
- Captures Retail utilisateur : Officer limité à Guided Setup et PlayerUI en attente observés; **N01 PARTIEL**, pas de preuve de contexte membre distinct ni raccourcis directs. Profil progression sélectionné observé, application non confirmée. Nouveau **N07 NON TESTÉ** pour préparation du brouillon; rendu/calendrier/scroll réel et Sync multiclient non validés. T053 et autres gates en jeu restent ouvertes. Aucun commit/push/publication/déploiement pour ce complément. Prochaine étape : redéployer, redémarrer WoW, tester Configure → préparation de saison → Apply → ouvrir le roster, puis poursuivre N02–N07.

- Lot UI approuvé pendant les tests Retail — **021 T025–T030 et 029 T058–T060 implémentées** : première installation Officer limitée à Guided Setup; menus et routes directes/alias/ancien onglet masqués selon les prérequis réels. [Wizard](../../src/modules/Wizard.lua) fournit une projection sans flag persisté; les éditeurs restent accessibles après la fondation, les opérations Dibs demandent saison/rangs publiés/ledger prêt, sans rendre RC ou les modules facultatifs obligatoires. Le parcours personnalisé réutilise le vrai contrôle Initialize dans le Wizard. [PlayerUI](../../src/ui/PlayerUI.lua) affiche une attente publique sans commandes admin; `rosterConfigured` ouvre l'inscription avant activation comptable. Historique/migration préservés; aucun changement des contrats ledger, gouvernance, recovery T049, identifiants persistés ou quota Sync.
- [OfficerUI](../../src/ui/OfficerUI.lua) : horaires création/modification par lignes jour nommé + HH:MM, sept entrées maximum selon le service existant, durée/fuseau historiques conservés; libellés joueur fondés sur le catalogue publié, aucune règle universelle jeudi/Officer-Core. L'aide contextuelle effacée par `Clear(scroll)` au rebuild Loot Rules a été déplacée après l'effacement; les aides restent dans le viewport courant. Automatic Dibs renvoie vers le roster saisonnier avec un conseil léger, sans scan global readiness/Wizard. Les deux anciens échecs de contextual help étaient reproduits aussi avec l'OfficerUI de HEAD; ils sont maintenant corrigés.
- Preuves finales de ce lot : **262/262 tests sur 16 fichiers, chacun sous Fengari, Lua 5.4.6 et Lua 5.1.5 natif**; compilation **111/111**; doc Generate/Check PASS (zéro erreur, dix clés d'aide héritées orphelines), graphe addon **120 fichiers requis PASS**, diff-check PASS. Les anciens tests de pages UI utilisent maintenant des fixtures de guilde explicitement configurée; les nouveaux tests conservent de véritables états neuf/partiel et le vrai clic Initialize. Pas de bypass global ni d'assertions supprimées. QA indépendante **45/45 sur les trois runtimes** (30 nouveaux scénarios et 15 cas contextuels); aucun blocage confirmé. L'IDE signale encore les annotations `@doc`, champs de namespace Dibs et inférences de retours déjà incomplètes : ne pas revendiquer zéro diagnostic IDE. La suite globale entière n'a pas été réexécutée.
- Coordination : explorer read-only `open_tasks_independence`; worker `setup_navigation_service` (projection Wizard, fixtures guidées/navigation, puis aide contextuelle); worker `roster_neutral_language` (PlayerUI, langue par guilde et fixtures); parent (OfficerUI, éditeur horaires, locales, intégration/docs); QA distincte `qa_0812_test_docs`. La première QA `qa_data_stabilization` a atteint sa limite sans valider ce lot et a été remplacée. [Fiche Retail N01–N06](../audits/0.8.12-TESTS-RETAIL-FR.md) ajoutée et guides FR/EN alignés; N01 est maintenant PARTIEL sur captures utilisateur, les autres contrôles restent NON TESTÉS, T053 et autres gates en jeu restent ouvertes. Aucun commit, push, publication, déploiement ou nettoyage réel ajouté dans ce lot. Prochaine étape : déployer les sources corrigées, redémarrer WoW et exécuter N01–N06 avant de poursuivre la campagne coffre/saisons.
- Incident Retail calendrier : l'utilisateur signale trois occurrences des avertissements `embeds.xml:10/11`. Diagnostic réel : les deux Lua LibAceGUIWidgets et leurs cinq ressources/licences étaient absents du dépôt actif et donc du jeu. Le bundle exact v0.12.0 déjà approuvé dans le worktree de consolidation a été réintégré (sept SHA-256 conformes au [registre](../developer/libaceguiwidgets-vendoring.md)); aucun nouveau patch tiers. `.gitattributes` préserve ses octets. [Précontrôle](../../scripts/Test-DibsAddonFiles.ps1) branché avant toute copie dans `deploy.ps1` et avant packaging CI : références TOC/XML et ressources obligatoires. Tests PowerShell **10/10 PASS**, dont reproduction des absences, échec avant modification de l'installation et intégrité des sept fichiers; **111/111 sources compilent sous Lua 5.1.5**, les deux Lua tiers également vérifiés explicitement; graphe livré **120 fichiers requis PASS**. Aucun redéploiement réel ni retest Retail effectué par l'agent pour ce correctif; retest documenté NON TESTÉ. L'ancien ZIP temporaire `7d3294ac` était lui aussi incomplet pour le calendrier : ne plus l'utiliser; sa vérification antérieure ne couvrait pas le graphe de chargement. Redéployer depuis les sources corrigées, redémarrer WoW puis retester le chargement et le calendrier. Aucun nouveau commit/push/publication pour ce lot.
- Nettoyage local demandé : nouveau [Reset-DibsInstallation.ps1](../../scripts/Reset-DibsInstallation.ps1), aperçu par défaut et suppression uniquement avec `-Apply`, WoW fermé. Cible exacte : addon Dibs et SavedVariables `.lua`/`.lua.bak` compte/personnage de ce Retail, tous comptes; sauvegarde externe avec manifeste et SHA-256 vérifiés avant suppression, refus des jonctions/chemins hors périmètre et des fichiers modifiés pendant la copie. RCLootCouncil/autres addons/réglages partagés préservés; les données de guilde distantes ne sont pas effacées. [Tests PowerShell](../../tests/powershell/Reset-DibsInstallation.Tests.ps1) **11/11 PASS sous Windows PowerShell 5.1/Pester 3.4**, dont un processus isolé utilisant les vraies copies/suppressions sur fixtures temporaires (inventaire processus WoW simulé). Aperçu seul exécuté sur le Retail réel : **152 fichiers listés, code 0, aucune modification**. Aucun nettoyage réel exécuté; procédure ajoutée à la fiche Retail. Aucun nouveau commit pour ce lot.
- Consolidation locale autorisée par l'utilisateur : documentation et commit du candidat courant pendant ses tests. L'utilisateur confirme avoir exécuté [deploy.ps1](../../scripts/deploy.ps1) lui-même; cette déclaration de déploiement ne constitue ni une vérification indépendante des fichiers installés ni un résultat Retail. Aucun résultat en jeu n'a encore été communiqué. T053, les autres gates Retail et les tâches canoniques encore ouvertes restent inchangées; aucun push, tag ou publication autorisé. La suppression locale de `.github/skills/speckit-bug-assess/SKILL.md`, sans lien établi avec le candidat, est exclue du commit et préservée dans le dossier de travail. Les modifications des autres worktrees ne font pas partie du commit de ce dépôt.
- Contrôles de consolidation réexécutés : compilation native Lua 5.1.5 **109/109 PASS** et documentation `Check` **PASS**, zéro erreur/dix avertissements de clés d'aide héritées, fichiers générés à jour. Les preuves comportementales ci-dessous sont conservées; aucune nouvelle exécution de la suite globale ni validation Retail revendiquée par ce commit.
- Demande de procédure exécutée : [AGENTS actif](../../AGENTS.md), [AGENTS de consolidation](../../../RCLootCouncil_dibs-consolidation-v0812/AGENTS.md), [instructions UI actives](../../.github/instructions/ui.instructions.md) et la copie UI explicitement citée sous `C:/Users/yc58/OneDrive/Documents/GitHub/RCLootCouncil_dibs/.github/instructions/ui.instructions.md` relus/ajustés. Une approbation couvre les opérations ordinaires du périmètre; intégration exacte des versions approuvées, délégation globalement autorisée, packages temporaires et refactorisation ciblée complète ne nécessitent pas de nouveau consentement par lot. Ledger, permissions/isolation, préservation du travail, revues métier, véritables suppressions/publications/déploiements restent protégés. Le détail Today/Clear est renvoyé au registre existant de consolidation. Aucune configuration personnelle/modèle ni quota fournisseur modifié.
- Compression 007 **T042–T045 terminées** : nouveau [BackupTransport](../../src/modules/BackupTransport.lua), chargement du LibDeflate 1.0.2 déjà présent et intact, adaptation ImportExport/Backup/DataUI et locales. Format `DIBS-COMP-1|longueur|checksum|Base64-DEFLATE` autour du paquet original inchangé; anciens imports/exports maintenus. Limites : 250 000 caractères encodés, 32 Mio originaux, préflight RFC1951 borné avant tout décompresseur, longueur/checksum et validation de package ensuite. Ni quota Sync ni hash/schéma canonique ni chemin d'adoption T049 modifiés.
- Nouvelles grosses sauvegardes : `compressedPackageText` optionnel retient l'original attesté si l'enveloppe tient la limite. Pas de réécriture/migration des anciennes sauvegardes; anciennes copies sans original ne sont pas reconstruites. La QA a corrigé une dépendance involontaire du restore au codec : la restauration locale valide toujours payload/checksum indépendamment du transport optionnel, même absent/corrompu. L'export refuse ce transport invalide. Consentement/cache restent liés au contexte/contenu; l'export courant est aussi effacé après retrait des droits.
- Validation finale compression : **84/84 sur dix suites sous Fengari, Lua 5.4.6 et Lua 5.1.5 natif**; **QA indépendante 66/66 sur les deux natifs**, plus trois flux distance/symboles réservés refusés avant décompression. Tests vrais DEFLATE, fixtures Node/zlib stored/fixed/dynamic, borne encodée exacte 250 000, corruption et refus canonique. Premier run Fengari rouge : LibDeflate ancien suppose des doubles; le helper isole désormais les lectures byte flottantes (sémantique Lua 5.1), sans patch tiers ni modification globale de production. Fixtures réexécutées et revue QA de l'adaptation faites. Compilation source **109/109 Lua 5.1**, diagnostics des quatre modules modifiés sans erreur, doc Generate/Check zéro erreur/dix avertissements hérités et diff-check passés. Bibliothèques inchangées.
- Mesures hors WoW, données synthétiques : petit paquet local 288 octets → 281 caractères encodés; historique synthétique 2 000 lignes 288 412 octets → 30 412 caractères encodés. Aucun gain général ou timing Retail déduit. D09/D10 ajoutés à la fiche utilisateur, résultats vides; `C_EncodingUtil` réel, coexistence LibStub et comportement visuel/performance restent NON VALIDÉS en jeu. T027/T036 et les gates Retail restent ouvertes. La baseline globale précédente **1 811/134** n'a pas été relancée sur ce lot.
- Package temporaire de validation créé depuis le `src/` actif uniquement : 142 fichiers, TOC/nouveau module/LibDeflate/logo vérifiés présents; ZIP `RCLootCouncil_dibs-0.8.12-validation-7d3294ac.zip` dans le dossier temporaire de session et enregistré comme artefact. SHA-256 `98336ec7a70e2e304c41d8befa9b1e86d39ab911760a3fced516789c1262c335`. Aucun commit/push/tag, publication, installation WoW ni déploiement. Deux tentatives de workers ont atteint leur limite d'usage; implémentation poursuivie directement, QA distincte a ensuite pu s'exécuter.
- Lot historique 007 après « allons y » : **T035/T039–T041 terminées**. [Backup](../../src/modules/Backup.lua) expose `ExportSnapshot` et son contrôle lecture seule; seul le paquet original conservé et attesté est exporté, sans recapture, réencodage, changement de format ou hausse de limite (250 000 caractères, préfixe compris). Droits courants, identité connectée, propriétaire local, contexte, attestations et consentement full sont revérifiés. [DataUI](../../src/ui/DataUI.lua) propose « Exporter la sauvegarde sélectionnée », avertissement/consentement sensible et texte copiable séparé de l'export courant. Cache et consentement sont invalidés sur changement de sélection/contexte/droits/contenu, y compris remplacement valide sous le même ID; recheck du texte exact sans nouvel audit.
- Preuves du lot historique : [service](../../tests/integration/backup_historical_export_spec.lua) **19/19** et [groupe UI/backup](../../tests/integration/backup_historical_export_ui_spec.lua) **29/29** sous Fengari, Lua 5.4.6 et Lua 5.1.5 natif (12 nouveaux cas UI, 31 nouveaux cas distincts service+UI). QA indépendante **45/45 sous Lua 5.4.6 et Lua 5.1.5**, couvrant aussi l'isolation d'import et le backup canonique. Deux défauts trouvés par QA ont été corrigés et retestés : helper lecture seule normalisant des métadonnées et cache/consentement survivant à un remplacement valide. Compilation source native Lua 5.1 **108/108**. Aucun test visuel Retail exécuté; la suite globale entière n'a pas été relancée sur ce lot. **1 811/134 reste la baseline antérieure**, pas un nouveau résultat final.
- Documentation 007 : spec/plan/contrat/data-model/research/tâches/quickstart, README/changelog, guides Officer EN/FR et fiche Retail D07/D08 alignés. L'import de configuration historique passe par Preview/Apply existants, avec filtres de scope et confirmation. **T036 reste ouverte** : enregistrer directement un paquet externe comme snapshot contournerait ces filtres; la récupération canonique sur installation neuve dépend toujours de Feature 026/T049. Pas de changement à ImportExport.Apply, Backup.Restore, Sync, contrats T049, schéma ou version. T027 et toutes les gates Retail restent ouvertes; aucun commit/push/tag/publication ni bibliothèque modifiée.
- Contrôles finaux du lot historique : documentation `Generate`/`Check` PASS (29 concepts, zéro erreur, dix avertissements hérités); diff-check PASS, aucune différence de bibliothèque. Diagnostics IDE des services/UI/tests historiques sans erreur après correction d'une annotation de retour, aucune modification runtime supplémentaire. [Prochain travail 007](../../specs/007-backup-export-import-profiles/tasks.md) : T036, puis T027 avec de vraies preuves Retail; les 134 échecs de la baseline globale restent un chantier distinct, pas une certification verte de la 0.8.12.
- Stabilisation 0.8.12, demande « préparer les fix » : aperçus import/restore limités à 16 par magasin, expiration à 1 800 s, nettoyage déterministe des entrées invalides et refus avant application métier. `Backup.Create` capture une seule fois les données du snapshot et de son checksum; les copies restent détachées. Les nouveaux tests lifecycle (11) et capture (4) passent sous Fengari, Lua 5.4.6 et Lua 5.1.5; 92 régressions backup/import passent sous les deux runtimes natifs. La collecte d'un run additionnel Fengari de 78 régressions a perdu son handle; aucun résultat final n'est revendiqué pour ce run.
- Profils et UI : activation unique après autorisation/confirmation réussie, isolation locale par personnage et fallback legacy sans migration; bouton de raid indépendant réparé avec le lecteur de contrôle existant. 26/26 tests ciblés passent sous Fengari, Lua 5.4.6 et Lua 5.1.5. Suppression du constructeur PlayerUI legacy inaccessible (326 lignes), fenêtre actuelle et fallback natif conservés. DataUI explique export courant/restauration locale et classe d'import; un preview absent n'offre plus de confirmation. Régressions UI **32/32 sur les trois runtimes**. QA distincte : **93/93 sous Lua 5.4.6**, aucun défaut bloquant; contrat corrigé suite à sa revue documentaire. Diagnostics IDE encore bruyants sur les annotations `@doc` et la déclaration incomplète du namespace Dibs; aucune erreur signalée dans Backup/ImportExport/Profiles/DataUI. Compilation native Lua 5.1.5 **108/108**; documentation générée à jour, 29 concepts / zéro erreur / dix avertissements hérités; diff-check passé et bibliothèques inchangées.
- Écart sauvegardes identifié au lot précédent : ne pas présenter toute la Feature 007 comme terminée. T035 (export historique) et T036 (import d'un snapshot externe/récupération installation neuve) avaient été ouvertes; **T035 est désormais terminée par le lot ci-dessus**, T036 reste ouverte. L'import complet `LEGACY_DIAGNOSTIC_ONLY` refuse l'historique canonique inconnu; son reimport sur le même client ne prouve pas une récupération neuve. T036 dépend du chemin canonique approuvé de la Feature 026, dont T049; aucun contournement ni modification de ces contrats. T027 a été rouvert faute de preuve Retail, même si sa case historique était cochée. La fiche Retail conserve ses résultats manuels vides.
- Baseline globale avant ces correctifs : **1 785 PASS / 138 FAIL, 254 fichiers sous Lua 5.4.6**. Le triage distingue 46 échecs corrections/disputes/compatibilité 026, 39 collection/propositions RF0013, 20 réservations/handoff/snapshots, 6 intégrité/politique PreDib, 4 modules UI, 4 profils/raid indépendant, 1 baseline historique contradictoire et 18 autres UI/readiness/autorité/ledger. Plusieurs API RF0013 sont réellement absentes; les statuts d'anciens audits d'autres checkouts ne prouvent pas leur implémentation ici. Validation globale finale après fixes : **1 811 PASS / 134 FAIL, 257 fichiers Lua 5.4.6**; les quatre anciens échecs profils/bouton Officer sont résolus, aucun nom d'échec ajouté par comparaison des deux runs. La suite globale reste rouge; ne pas fermer les gates de release sur la base des suites ciblées vertes. Suite globale entière non exécutée sous Fengari ou Lua 5.1 par ce lot.
- Suite après l'export historique : définir un restore-point externe normalisé qui conserve les filtres de scope, puis son intégration au contrat de recovery canonique approuvé pour T036; traiter les écarts globaux restants par lots séparés sans changer les règles pour rendre les tests verts. T049, T027 et les gates Retail restent ouvertes. Aucun commit/push/tag/publication, bump de version ou changement de bibliothèque dans ce lot.
- Campagne utilisateur 0.8.12 préparée dans [0.8.12-TESTS-RETAIL-FR.md](../audits/0.8.12-TESTS-RETAIL-FR.md) : coffre avant claim, réception Officer, reload/rattrapage, confidentialité, UI/performance, roster et données isolées. Toutes les cases Retail restent sans résultat. GM requis pour changer les modules; coordinateur comptable autorisé pour l'activation. Version 0.8.12 inchangée, aucune installation/publication déclenchée par ce lot.
- Documentation alignée : README source corrigé 0.8.11 → 0.8.12; changelog et notes candidat distinguent le périmètre initial du 9 novembre de l'activation/réconciliation désormais implémentées; guides joueur/Officer FR/EN complétés pour capture et sync du coffre. Documentation générée régénérée par le script du projet. Deux usages concurrents de `SEASONAL_ROSTER_WITHDRAWN` séparés en statut court Officer et notice `_WITHDRAWN_NOTICE` Player, sans changement métier.
- Validation documentaire : 29 concepts, zéro erreur, dix avertissements hérités de clés d'aide sans référence; `Validate`, `Generate` et `Check` passent. Comparaison génération Windows PowerShell 5.1 / PowerShell 7 : **8/8 SHA-256 identiques**. Régressions UI ciblées **35/35 sous Fengari, Lua 5.4.6 et Lua 5.1.5**; compilation source Lua 5.1.5 **108/108**; diff-check passé. QA indépendante documentaire passée après précision du rôle GM pour S08. T051/T052 (013), T053 (029) et les gates 026 restent ouvertes.
- Feature 013 — signalement utilisateur d’un historique Grande chambre forte vide : corrections T054/T055 et QA T056 terminées. L’adaptateur reconnaît désormais l’équipement d’un bundle avec clé/objet supplémentaire, les messages personnels localisés sans GUID et les données d’infobulle tardives. Les bundles encore ambigus, autres joueurs, variantes différentes et changements de contexte restent refusés. Aucun ancien claim n’est inventé.
- PlayerUI affiche capture active/indisponible/désactivée, nombre d’options lisibles et dernier résultat localisé; les changements rafraîchissent l’onglet Vault existant et visible. Un test traverse le vrai chemin claim → réception → historique affiché, sans effet ledger. Fichiers du lot : intégration GreatVault, PlayerUI, locales EN/FR, deux specs de tests et suivi de la Feature 013; aucun contrat de persistance/récupération T049 modifié.
- Validation 013 : **93/93 sous Fengari, Lua 5.4.6 et Lua 5.1.5 natif** (14 suites). QA indépendante **27/27 sur les trois runtimes**. Compilation native Lua 5.1.5 **108/108 sources**; diff-check ciblé passé. Le compilateur a été retrouvé sous le dossier temporaire `vscode-agent-codex-sandbox-ovpxqc/dibs-lua51-validation/lua-5.1.5/src/` (`lua51.exe`/`luac51.exe`). Le résultat précédent « non disponible » décrivait seulement la recherche de l’époque; aucun test 026 supplémentaire n’a été exécuté par ce lot.
- Prochain contrôle 013 : exécuter T051 sur un vrai claim Retail (équipement + supplément), vérifier l’objet confirmé dans PlayerUI, puis T052 pour la livraison à un second client. Ces gates restent ouvertes; aucune validation Retail revendiquée, aucun commit/push/tag/publication, aucune bibliothèque tierce modifiée.
- Feature 029 : implémentation service/UI/Sync terminée pour activation cohérente, snapshots d’identité Main/Alt, réconciliation des allocations actives, historique préservé et gating du module. Aucun commit, bump de version ni publication effectué.
- Dernier lot : transport de manifeste compact `wireSchema=1` pour garder les références identité/enrollment sous le quota existant de 8 192 octets; l’expansion intervient avant validation service. Le cohort test n’utilise plus de contournement de quota.
- Validation finale : sélection ciblée **87/87** sous Fengari et Lua 5.1.5 natif; compilation des **108** fichiers source sous Lua 5.1 passe. Le round-trip compact, cohortes 30/60 avec 900 personnages hors cohorte, et quotas Sync inchangés sont couverts. `git diff --check` ne signale que les avertissements Git LF/CRLF.
- Fichiers externes `libs/` et `Libs/` préservés; aucun résultat Retail à deux clients n’est revendiqué. T053 reste le seul point Retail ouvert dans [tâches 029](../../specs/029-seasonal-raid-roster/tasks.md).
- Lots de correction : AUD-004 (import scope), AUD-005 (restore/tombstones), AUD-006 (draft selection), AUD-007 (Encounter Journal tuple). T029/030 de 007, T039/040 de 020 et T056/T057 de 029 sont maintenant fermées après tests ciblés et QA indépendante. Pour AUD-006, le cas catalogue archive-only traverse le vrai transfert SyncV2 `TRANSFER_BEGIN/CHUNK/END`.
- Validation combinée des lots : **19/19 Fengari et 19/19 Lua 5.1.5** sur import, restore, sélection draft, Encounter Journal, performance et cohorte; les cas activent 30 ou 60 personnes approuvées face à 900 membres hors cohorte et couvrent aussi une identité au-dessus du quota. La suite draft/catalogue mise à jour passe **17/17 sous chaque runtime**. La QA AUD-004 a confirmé l'invariance ledger/gouvernance; la QA AUD-005/007 confirme respectivement la persistance des tombstones et le tuple Encounter Journal; la QA AUD-006 valide aussi la réception réelle du transfert. Les validations Retail visuelles et réseau restent distinctes.
- Une QA combinée antérieure a aussi révélé B14 : `rf0041_backup_restore_hardening_spec.lua` attend `Ledger.RebuildLedgerProjections`, API exigée par FR-031/T026 mais absente du source courant. Correction de reconstruction lancée dans un lot Ledger séparé; ne pas considérer B14 comme préexistant/non pertinent sans le résoudre.
- Résultat Ledger/B14 : l’API reconstruit les projections depuis la chaîne `AWARD_COMMIT` vérifiée et les transactions legacy valides, dans des tables détachées; les commits/hash/sequence/root ne changent pas. B14 et le nouveau test dédié sont revus indépendamment; suites Ledger ciblées **23/23 Fengari et 23/23 Lua 5.1.5**. Les commits `LEDGER_OPERATION_COMMIT` sont encore refusés sans mutation.
- Vérification combinée actualisée : **53/53 sous Fengari et 53/53 sous Lua 5.1.5** sur 9 suites couvrant import, tombstones, B14, rebuild, archive/draft via SyncV2, tuple Encounter Journal, projections 20/60/500/1 000, cohortes 30/60 avec 900 personnes hors cohorte et précommit de taille. Compilation finale Lua 5.1.5 : **108/108 fichiers source**. `git diff --check` ne relève pas d’erreur d’espace (avertissements LF/CRLF uniquement); aucune différence sous `libs/` ou `Libs/`.
- Reprise Feature 026 — cohorte 029 revalidée séparément : **7/7** sous Fengari et Lua 5.1.5 sur cohortes 30/60 face à 900 membres hors cohorte, snapshot identité trop volumineux, et projections 20/60/500/1 000.
- T047 — service de correction : `canonical_dispute_operation_spec.lua` passe **23/23** sous Fengari et Lua 5.1.5. Les changements ajoutent les bornes d’injection pre-validation/pre-acceptance/balance/index, propagent les rejets ProtectedActions sans résultat succès-shaped, récupèrent les projections après commit accepté, retournent le commit complet sur replay, et relient la projection de dispute à la révision qui a autorisé l’opération. La QA indépendante confirme les gates privées et le lien de révision; elle signale un risque de lecture de projections partielles après interruption, suivi sous T049. T047 reste ouverte en attendant ses dépendances et gates générales.
- T049 — receiver Ledger vérifie désormais la récupération canonique après validation du commit reçu et avant append; la reconstruction opération/dispute reste déterministe. Core/readiness et tests indépendants de fault-cut/distributed recovery restent ouverts.
- T050 — ImportExport refuse les commits d’opération inconnus/conflictuels et les lignes opérationnelles isolées; les sauvegardes full conservent commits et hashes. Backup/restore ciblé : **11/11** sous Fengari et Lua 5.1.5; QA indépendante : **8/8** sur son sous-ensemble, `luac51` et `git diff --check` passés. La restauration avec projection manquante dépend de T049, donc T050 reste ouverte.
- T048 mise à jour : la réception refuse un ledger sans état canonique valide avant toute initialisation; le test confirme l’absence de mutation. La validation lit le dossier persisté en interne (sans vue UI filtrée), et le contenu/hash est vérifié avant l’ACK idempotent; un replay altéré est rejeté. La suite Sync passe **17/17 sous Fengari, Lua 5.1.5 et Lua 5.4.6**. La QA a corrigé le harness Lua 5.1 : `wow_api.lua` reçoit l’environnement propre au client par `setfenv`; l’autorité de production reste inchangée. Le groupe de sept suites passe maintenant **75/75 sous Fengari et Lua 5.4.6**; sa révision précédente était **74/74 sous Lua 5.1.5**, avant le dernier test de démarrage. Aucun test Retail n’est revendiqué.
- T049/T046 : `Core.Initialize` reconstruit les états canoniques après `ensureDB`, avant l’initialisation Sync; un historique à séquence manquante conserve son état exact et remonte `CANONICAL_SEQUENCE_GAP`. Si le service Disputes manque, le statut explicite est `CANONICAL_RECOVERY_UNAVAILABLE`; la suite persistence passe **17/17 sous Lua 5.4.6**. Un nouveau test vérifie la validation d’un journal canonique vide au démarrage, mais QA confirme qu’il ne couvre pas encore la reconstruction d’une projection d’opération non vide. Les tests attribution-only couvrent zéro effet comptable, replay/conflit et readiness `SYNC_BEHIND`. T049 reste partielle (reconstruction non vide au démarrage, cuts receiver et readiness générale à compléter); T046 reste ouverte sur readiness non-stubbed.
- T050 : restauration full backup avec projection d’opération manquante suivie de `ReconstructOperationStates` vérifie `VALID` sans changer `nextSeq`, `rootHash`, `commitHash` ni les soldes des deux membres. Test ciblé **9/9 sous Fengari et Lua 5.1.5**, revue QA indépendante passée; les sept suites passent maintenant **75/75 sous Fengari et Lua 5.4.6**, tandis que le dernier résultat natif Lua 5.1.5 est **74/74 avant l’ajout du test startup**. T050 reste ouverte jusqu’à la clôture de ses dépendances et de la matrice plus large.
- Convergence Feature 026 : Phase 8 ajoutée avec cinq tâches traçables T046–T050 pour le writer canonique, l’autorisation/proposition, SyncV2, recovery et backup/import. Les tâches historiques T007–T035 affirment davantage d’implémentation que le code présent; aucun de ces écarts n’est déclaré terminé par cette reprise. L’exigence de l’ancien T026 est insatisfaite malgré sa coche historique; le travail est rouvert par T049. T041 Retail, T042 version/change note et T043 activation de release restent ouverts.
- Progression T049 — Ledger : `RebuildLedgerProjections` traite maintenant les commits `LEDGER_OPERATION_COMMIT` en plus des `AWARD_COMMIT` et lignes legacy; `ClassifyCanonicalRecovery` qualifie les gaps, racines incorrectes, projections absentes et index incohérents. Le nouveau test [ledger_operation_recovery_spec.lua](../../tests/integration/ledger_operation_recovery_spec.lua) utilise le writer réel avec les seams privées de test; il passe 2/2 sous Fengari et Lua 5.1.5. Les suites ciblées rebuild/B14/opération passent 33/33 sous chaque runtime avant ce nouveau fichier, soit 35/35 en les combinant. La reconstruction de l’état des disputes et les gates de recovery dans Core/Disputes restent à faire; T049 n’est donc que partiellement réalisée.
- Note historique supersédée : les premiers essais du harness multi-client étaient rouges (7/23) avant la correction Lua 5.1 `setfenv`. La validation ultérieure passe 23/23 sur l’intégration opérationnelle et 17/17 sur Sync sous Fengari et Lua 5.1.5; T048 dispose désormais de transport de commit, mais reste ouverte aux compléments listés dans ses tâches.
- Prochaine étape : traiter les nouvelles tâches 026 dans l’ordre de dépendance; conserver le flag fermé jusqu’aux gates et revue autorisées. Maintenir T053 et les autres matrices Retail ouvertes; ne revendiquer aucune certification Retail sans session réelle.

## Reprise confirmée — 2026-11-14

- Branche : `029-seasonal-raid-roster`, HEAD `da53a49` au début de la reprise.
- Demande : corriger les problèmes de l'audit et terminer la fonctionnalité 029 avec SpecKit et plusieurs agents. Aucun commit, changement de version ou publication autorisé dans ce lot.
- Documents actifs : [tâches 029](../../specs/029-seasonal-raid-roster/tasks.md), [plan](../../specs/029-seasonal-raid-roster/plan.md), [preuves et matrice Retail](../../specs/029-seasonal-raid-roster/quickstart.md).
- Périmètres distincts : service/ledger/identités; PlayerUI/OfficerUI/locales; SyncV2; validation et documentation centralisées. Préserver les 64 changements locaux présents à la reprise et laisser toutes les bibliothèques externes en lecture seule.
- Confirmé : 4 scénarios de projection/performance passent; 22 régressions runtime/UI/EncounterJournal passent sous Fengari. Le compilateur Lua 5.1.5 est disponible dans le dossier temporaire `dibs-lua51-validation/lua-5.1.5/src/` pour le script de compilation existant.
- En cours : activation atomique, réconciliation, wrappers Main/Alt, adoption de manifeste et interfaces associées. Vérifier la limite de 60 upvalues après les derniers changements de SyncV2.
- Prochaine étape : attendre les fichiers stables des trois périmètres, valider les tests et contrats ensemble, puis mettre à jour les tâches selon les preuves. Les validations Retail à deux clients restent à exécuter; aucun résultat en jeu n'est revendiqué.

Les sections ci-dessous sont le checkpoint historique d'octobre, conservé comme contexte. Elles ne décrivent pas l'état courant et ne doivent pas guider la reprise de la fonctionnalité 029.

## Identité du projet
- **Nom** : RCLootCouncil_Dibs (WoW Retail Lua Addon)
- **Branche Git** : main (ou branche active)
- **Dernier commit** : dc388f9df313f1597e5c1a35078bb725c34c7f3e (Sun Oct 18 01:25:07 2026 -0400)
- **Message commit** : feat: guild sync repair, corroborated relay, factory reset and setup guidance (0.8.10)

## État du projet
- **Fonctionnalité active** : Gestion de la synchronisation distribuée, ledger multiple, récupération d'historique corrodoré
- **Spécifications pertinentes** : `specs/026-canonical-idempotent-corrections/` et `specs/027-feature-registry/`

## Phase actuelle
En cours de développement majeur avec très nombreux fichiers modifiés (docs/, src/, tests/)
- Focus sur l'intégration robuste avec RCLootCouncil
- Implémentation du système multi-ledger pour les données d'équipement
- Développement de la récupération historique idempotente

## Tâches confirmées comme terminées
- [x] Architecture multi-modèle établie (`src/modules/`)
- [x] Intégration EncounterJournal fonctionnelle
- [x] Système de permissions et gouvernance mis en place
- [x] Interface utilisateur Midnight configurée

## Tâches en cours
- [ ] Finalisation des corrections canoniques idempotentes (spec 026)
- [ ] Implémentation du registre de fonctionnalités (spec 027)
- [ ] Tests d'intégration pour les scénarios distribués à 4 clients globaux

## Tâches restantes
- [ ] Validation cross-version des documents générés
- [ ] Préparation du prochain release candidate
- [ ] Documentation des patterns de résilience observés

## Décisions architecturales importantes
- **Principe d'isolation** : Les ledgers sont append-only et isolés par personnage/guild
- **Autorité vérifiée** : La validation d'autorité se fait à l'acceptation, pas à l'envoi
- **RCLootCouncil optionnel** : L'accounting de Dibs ne dépend jamais du core RC
- **Contexte développeur isolé** : Les contextes test/dev restent isolés des données production

## Fichiers modifiés et pertinents (dernier commit)
Fichiers `.toc`, `Core.lua`, `Types.lua` et ~40 fichiers Lua dans `src/modules/` et `src/ui/`
- Tests d'intégration : `tests/integration/*_spec.lua`
- Helpers de test : `tests/helpers/*`

## Données de contexte persistant
- **Nombre de modules** : ~50 fichiers Lua dans `src/modules/`
- **Pattern de nommage** : Fonctions publiques PascalCase, privées lowerCamelCase
- **Localisation** : Textes utilisateurs dans `src/locales/` avec fallback EN

## Tests réellement exécutés et résultats
- Fengari tests via `tests/run.lua` (avec variable `DIBS_TEST_FILES`)
- Succès des suites d'intégration ciblés lors du dernier commit
- **ATTENTION** : Fengari success ≠ certification Retail — vérifications manuelles requises

## Problèmes connus
- Très nombreux fichiers modifiés simultanément (possible conflit de merge si branchée)
- Contexte de développement avec très grande surface de modifications actives

## Prochaine action recommandée
1. Lire CHECKPOINT.md complet pour le contexte
2. Vérifier Git status : `git status --short`
3. Consulter les spécifications actives dans `specs/026-canonical-idempotent-corrections/` et `specs/027-feature-registry/`
4. Identifier la tâche active la plus critique en cours
