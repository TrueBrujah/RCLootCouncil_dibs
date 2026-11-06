# Reprise de l'audit

## Checkpoint de priorité — audit runtime du 28 octobre 2026

- Charge 50–60 connectés examinée : nouveaux tests de réception de 49/59 index
  courants de 20 demandes => 980/1180 GetHistory, zéro détail demandé. Tranche
  1 PASS/2 FAIL : heartbeat 60 s rediffuse le même index. Prolonge RA-01, sans
  confondre 60 membres en ligne et 60 clients Dibs. BULK régule le transport,
  pas le calcul. Roster Identity déjà caché, coalescence 1 s/5 s déjà présente.
- Nouveau RA-16 : Initialize crée la fenêtre officier cachée mais rend overview;
  le dashboard demande GetLootCatalog(3500). Test journal vide : 1 appel catalogue,
  2 lectures d'instances, fenêtre cachée; 0 PASS/1 FAIL sur budget zéro scan avant
  ouverture. Proposer report du rendu initial au premier OnShow et correction
  du flag skip-refresh. Cache Journal local, pas catalogue diffusé en réseau.
  Ordre proposé : RA-16/15, indexation RA-01, puis budgets/dispersion/cache des
  annonces, en préservant la réparation périodique et la cadence de spec 017.
  Aucune production/bibliothèque modifiée; mesures natives encore nécessaires.

- Nouvelles alertes fournies : CMC dépasse son budget (14), BugGrabber (10),
  sans pile Dibs ni nom d'événement. Recherche locale sans lien textuel direct
  Dibs↔CMC; CMC dispose de plusieurs callbacks EventRegistry, impossible de
  désigner celui de la pile tronquée. L'utilisateur confirme avoir réactivé les
  autres addons avant ces alertes : session complète, distincte du test Dibs+RC;
  ne pas confondre une erreur historique avec l'état chargé actuel. Les anciens
  A/B et mesures Dibs sont conservés, aucun problème tiers déclaré confirmé.

- Premiers CPU natifs rapportés vers 20 h : Dibs 18,93984 puis 18,93994 ms
  RecentAverageTime, RC ~0,00777 ms; à 20:01 Dibs 0,000215 et RC 0,001422.
  Moyennes sur 60 ticks, pas ms/image; épisodes distincts non garantis. Message
  « trop d'erreurs UI » intercalé; fenêtres/évolution du lag à CPU bas demandées.
  General.log s'arrête pour ces erreurs à 19:39; SV BugGrabber à 19:59:53 vides.
  Aucune première erreur actuelle récupérée. Ancienne compilation >60 upvalues
  dans RC persisté, pas confirmée actuelle; luac local 5.4.6, pas validation 5.1.
  Sources non modifiées, pas de nouvelle exécution de tests sur source inchangé.

- Dernier A/B utilisateur : RC+Dibs actifs, lag dès reload, 70–100 FPS contre
  120–130 sans Dibs; nouvelles captures 301–319 Mo via un autre compteur.
  Avertissements AceHook/AccWideUILayoutSelection et BugGrabber, sans preuve
  de responsabilité de ces addons. RC 3.24.1 présent sur disque; le correctif
  whispers ne prouve pas la résolution du timeout. Nouveau RA-15 : lecture
  d'une règle actuelle copie tout le catalogue via GetCatalogState. Fixture
  50 révisions : 1 copie par décision; 200 copies / 40 ticks du watcher, qui
  s'arrête bien et ne notifie aucun changement. Deux régressions FAIL ciblées;
  proposer GetCatalogRevision existant, conserver la validation du record.
  Aucun code de production changé. Test Dibs+RC seuls : toujours 70–100 FPS
  selon l'utilisateur, sans mesure horodatée ni temps CPU par fonction.

- Nouveau retour utilisateur : Dibs seul fluide au repos, lenteurs sur Rank
  Rules / Loot Rules / System Settings, variables selon pages et contenu.
  Sonde du contrat AceGUI AddChild→DoLayout : 40 contrôles, 42 layouts,
  822 visites d'enfants. Routes avec 100 membres / Officier en dernier :
  2300–3200 lectures roster; zéro GetSizeDiagnostics sur ces trois pages.
  1 PASS/1 FAIL dans ui_layout_work_audit_spec. RA-13/14 proposent batching
  des layouts et projection de lecture par rendu; contrôles d'autorisation
  des mutations à conserver. Aucun correctif de production appliqué.

- Retour en jeu ultérieur : Dibs affiché à 135 Mo; avertissements de temps
  d'exécution RC répétés. Platynator a été retiré. Test A/B utilisateur :
  Dibs désactivé + RC actif + /reload → lag et nouveaux avertissements cessent.
  Intégration RC ciblée : 34 PASS/0 FAIL sous doubles. Comparaison Dibs seul
  reçue ensuite et détaillée ci-dessus; aucune boucle native précise ni cause
  des 135 Mo démontrée.

- Complément installation : chemin Retail fourni par l'utilisateur, Dibs 0.8.10
  et RC 3.24.0. Vérification finale 139/139 fichiers installés identiques à src.
  Derniers SV Dibs : 0,345 Mio, 6 scopes, 23 transactions dans les cartes de
  ledgers, zéro backup/aperçu/snapshot de migration; sandbox presque vide.
  La rétention reproduite en test ne caractérise donc pas ces données disque.
  Priorité aux allocations, événements et interactions RC pendant la session.
  Voir les deux artefacts INSTALLED-* et la mise à jour en tête du rapport.

- Build audité : HEAD cb3f12a, source 0.8.10; 58 sources applicatives chargées.
- Symptôme utilisateur : environ 250 Mo et lag avant toute ouverture de page.
  Aucune mesure WoW réelle disponible dans l'environnement.
- Preuves nouvelles : 21 copies de ledger pour un digest de 20 demandes;
  paquets annulés et snapshots prunés encore référencés; listeners d'événements
  remplacés; snapshots altérés restaurés; cache de digests rejetés non borné.
- Le fallback compact précédemment incriminé est retiré : le runtime V2
  redéfinit ces fonctions et retourne SYNC_UNAVAILABLE sans fallback.
- Tranche baseline 87 PASS/7 FAIL; backup 28/14; disputes 28/2;
  nouveaux contrôles + atomicité renforcée 3/15. Tranches partiellement communes.
  Les fixtures historiques incompatibles sont distinguées des défauts réels.
- Sources et bibliothèques conservées; tests ciblés ajoutés/renforcés, aucun
  correctif, nettoyage de données, commit ou déploiement.
- Prochaine étape : baseline du client installé, puis lots minimaux décrits dans
  [le rapport runtime](PERFORMANCE-ARCHITECTURE-SECURITY-20261028.md).
  Ce checkpoint prévaut sur les déclarations historiques de correction ci-dessous.

- Statut global : **REVUE SEMANTIQUE TERMINEE**; inventaire global termine,
  les 58 sources applicatives de `src/` hors bibliotheques ont ete auditees.
- **Session 4** : 35 modules supplementaires audites sans defaut confirme.
  Couverture portee a **58 COMPLET / 0 PARTIEL / 0 INVENTORIE**. Voir
  [AUTONOMOUS-SESSION-STATUS.md](AUTONOMOUS-SESSION-STATUS.md).
- **Session 8** : audit des reservations de Dib, de MultiLedger et de
  Backup/ImportExport. 3 defauts P0 confirmes et corriges (RF-0031,
  RF-0033, RF-0034), 1 hypothese refutee et verrouillee par test
  (RF-0032).
  Couverture maintenue a **58 COMPLET / 0 PARTIEL / 0 INVENTORIE**.
- **Session 9** : audit de la coherence distribuee sur des clients
  distincts (rattrapage de gap, transfert de coordinateur, snapshots
  canoniques, liberation distribuee des reservations, rattrapage d'un
  Secondary Ledger, reconstruction apres interruption). 2 defauts P0
  confirmes et corriges (RF-0035, 3 causes ; RF-0038, 2 ecarts avec le
  chemin d'ecriture), 3 scenarios verifies sans defaut (RF-0036,
  RF-0037, RF-0039).
  Couverture maintenue a **58 COMPLET / 0 PARTIEL / 0 INVENTORIE**.
- **Session 10** : audit des sauvegardes, des importations et de la
  recuperation historique (65 scenarios de brief couverts : 25
  d'importation, 20 de sauvegarde/restauration, 20 de recovery). 2 defauts
  P0 confirmes et corriges (RF-0041 : une restauration ne validait pas
  l'instantane ; RF-0042 : un paquet de recovery contradictoire etait
  applique) et deux chemins verrouilles sans correction de production
  (RF-0040 : importation ; RF-0043 : scenario global a quatre clients,
  qui a aussi conduit a une correction de la **fixture** de transport
  multi-clients).
  Couverture maintenue a **58 COMPLET / 0 PARTIEL / 0 INVENTORIE**.
- Derniere validation : suite complete **1419 PASS / 0 FAIL sur 204 fichiers** ;
  compilation Lua 5.1.5 **0 echec / 105** ; suites distribuee/sync/transport/
  gouvernance **190 PASS / 0 FAIL** ; suites import/backup **60 PASS / 0 FAIL** ;
  validateur docs 0 erreur ; `git diff --check` OK ;
  `audit_guard.py verify` exit 1 avec **0 PROTÉGÉ** et **0 libs** ;
  `src/libs` **77 entrees protegees, 0 delta**.
- Revision de base auditee : `dc388f9df313f1597e5c1a35078bb725c34c7f3e`, branche `dev`.
- Prochain identifiant RF libre : RF-0045.
- Baseline existante migree sans reinitialisation : 235 fichiers Lua hors `libs` et 77 fichiers/entrees sous `src/libs/` proteges par empreinte stricte.
- Validation tags/liens : 34 tags / 34 fiches, 0 avertissement, 0 erreur; liens
  Lua <-> INDEX coherents.
- Validation d'integrite : OK, 235 fichiers Lua hors bibliotheques et 77
  empreintes strictes sous `libs`; aucun fichier lib modifie.
- `git diff --check` : OK. Aucun commit, push, merge, publication ou deploiement.

## Avancement 2026-10-22 (session 16)

### Session 16 — Version candidate et preflight Retail

- **Phase 1 — verification RF-0013** : 13 cas ajoutes
  (`rf0013_verification_spec.lua`). Pagination complete sans perte a la
  frontiere de lot, reprise apres interruption, deduplication, source
  changeante **sans boucle infinie**, racine SavedVariables anterieure,
  collecte partielle jamais approuvable, proposition anterieure au
  contrat de metadonnees **non abandonnee**, metadonnees absentes
  refusees, doublon refuse, reverification a l'approbation,
  permissions, persistance au rechargement, audit des decisions.
- **Un defaut reel corrige** : une proposition ecrite avant le contrat de
  metadonnees ne pouvait etre **ni approuvee ni reparee** — elle etait
  abandonnee. Elle est desormais **adoptee** dans l'index lorsqu'elle est
  lue, avec les metadonnees que l'officier fournit. Discrimination
  verifiee par reinjection ; `MultiLedger.lua` restaure identique.
- **Phase 3 — sauvegarde** : nouvelle sauvegarde externe
  (`RCLootCouncil_dibs-backup-20261022-013938`), 979 fichiers, 0
  corrompu, 107/107 non suivis recopies, 77/77 bibliotheques
  identiques. L'ancienne est **conservee**.
- **Phase 4 — candidate** : nouvelle archive
  `RCLootCouncil_dibs-0.8.10-rf0013-candidate-dc388f9….zip`,
  SHA-256 `C8AF12BCB46D1C994EA6C3BE9CF5CBC1320614C568A60D3E7466C43C90242E79`,
  138 fichiers, **8 portes / 8 PASS**, manifeste et empreinte source
  ecrits. L'ancienne candidate est **conservee**. TOC `0.8.10`
  **inchange**.
- **Phase 5 — gel fonctionnel** : `docs/developer/FUNCTIONAL-FREEZE.md`,
  **ACTIF**. Cinq conditions pour toute correction ulterieure, et
  reconstruction de la candidate obligatoire.
- **Phase 6 — checklist Retail A** :
  `docs/developer/RETAIL-A-CHECKLIST.md`, quatre blocs, inventaire des
  ressources, commandes de diagnostic WoW, fiche de resultat. Aucun
  scenario `MANUAL_PASS` sans observation ecrite.
- **Validations** : suite **1541 PASS / 0 FAIL** (212 fichiers) · RF-0013
  45/0 · MultiLedger+Governance+distribues 86/0 · RF-0012+Backup 142/0 ·
  Lua 5.1.5 105 fichiers PASS · Pester 26/0 · docs 8/8 · `validate_audit`
  0 erreur · `audit_guard` 0 violation libs · libs 77/77 clean ·
  `git diff --check` exit 0 · verrous RF-0012 fermes · **aucun commit ni
  push**.

## Avancement 2026-10-21 (session 15)

### Session 15 — Implementation finale de RF-0013 (A1 et B1)

- **A1 — collecte historique paginee** (`HistoricalBaseline.lua`,
  `Installation.lua`) : `BATCH_SIZE = 500`,
  `MAX_EVIDENCE_PER_SOURCE = 500` (par lot),
  `MAX_EVIDENCE_PER_CYCLE = 5000`, **aucune limite de retention** et
  **aucune suppression** de preuve historique. Curseur persistant
  (`cursor`, `sourceFingerprint`, `totalSeen`, `state`, `lastReason`)
  qui **n'avance qu'apres** l'acceptation du lot ; empreinte de source
  qui invalide un curseur devenu faux ; etats `COMPLETE` / `INCOMPLETE` /
  `ERROR` ; **deduplication non reimplementee** (celle de `collectInto`
  fait foi) ; source illisible avec diagnostic explicite ; collecte
  partielle signalee avec la source et le curseur ; et une collecte
  **incomplete jamais approuvable**, meme avec
  `acknowledgeIncompleteEvidence = true`.
- **B1 — proposition officier** (`MultiLedger.lua`) : `ProposeLedger`
  **etendu** (signature et contrat publics inchanges). Perimetre, volume,
  motif et sources illisibles valides a la creation et **reverifies a
  l'approbation** ; unicite des propositions actives ; refus
  d'approbation si une source est en cours, illisible, ou si le volume
  contredit les preuves ; proposition persistee avant tout succes,
  lisible et corrigeable ; audit des creations, corrections, approbations
  et refus ; permissions Officier/GM preservees ; `PROPOSAL_CREATED`
  jamais annonce sans objet persiste. `Installation.Initialize` verifie
  le **statut** du ledger primaire, plus le nom.
- **Trois defauts rencontres et corriges pendant l'implementation** :
  `CollectEvidence` effacait le `collectionProgress` en remplacant
  l'etat ; le resultat de la collecte ne rapportait que les
  enregistrements ajoutes et non toute la source ; et `stageBaseline`
  utilisait les findings comme signal de reconciliation alors qu'une
  collecte propre n'en produit aucun — le baseline refusait plus tard
  avec un motif generique.
- **27 tests ajoutes** (12 A1, 15 B1) ; 32 tests RF-0013 au total, tous
  verts. Les 84 cas des suites d'installation et de RF-0013 passent.
- **Aucun mecanisme comptable canonique RF-0012 n'a ete touche** ; les
  verrous restent fermes ; aucune bibliotheque `libs` n'a ete modifiee ;
  aucun commit ni push.

## Avancement 2026-10-21 (session 14)

### Session 14 — Specification finale RF-0013 et preflight Retail

- **Phase A — specification finale** :
  `docs/code-audit/RF-0013-FINAL-SPECIFICATION.md`.
  **A1** : `BATCH_SIZE = 500`, `MAX_EVIDENCE_PER_SOURCE = 500`,
  `MAX_EVIDENCE_PER_CYCLE = 5000`, **aucune limite de conservation** ;
  curseur persistant ecrit **apres** la confirmation du lot ; etats
  `COMPLETE` / `INCOMPLETE` / `ERROR` ; deduplication **deja correcte**,
  non reimplementee ; **interdiction d'approuver une source incomplete**,
  meme avec `acknowledgeIncompleteEvidence = true`. 12 tests specifies.
  **B1** : le contrat de `ProposeLedger` a ete **verifie par mesure** —
  il ne correspond **pas** au contrat metier de RF-0013. Cinq ecarts :
  perimetre, volume, motif, sources illisibles, unicite. **L'affirmation
  du dossier d'origine sur un « index de propositions deja present » est
  inexacte** : il n'en existe pas, et deux propositions de meme nom
  coexistent aujourd'hui, sans contexte et indistinguables. Le dossier
  a ete corrige. 15 tests specifies.
- **Phase B — campagne A** :
  `docs/developer/RETAIL-CAMPAIGN-A-PROCEDURE.md`. Sauvegarde prealable
  des SavedVariables en trois fichiers, installation isolee avec
  deploiement de l'ancien dossier, creation des donnees par le parcours
  de l'interface, sections main/alt, Pre-Dibs, attribution et
  reservation, sauvegarde/restauration, synchronisation quatre clients,
  compatibilite RC, mode independant, interface, retour a l'etat initial.
  Aucune ligne ne peut porter `MANUAL_PASS` avant observation ecrite.
- **Phase C — prevalidation RF-0012** :
  `docs/developer/RF-0012-PREVALIDATION-PLAN.md` — **plan seulement**.
  Aucun contournement par SavedVariables, interface ou commande slash :
  le seul mecanisme admis est une revision source examinee compilee dans
  un build separe. 6 autorisations distinctes demandees, **aucune
  accordee**.
- **Aucune source de production modifiee.** RF-0013 reste
  `PARTIALLY_FIXED`, les verrous RF-0012 restent fermes, T041 reste
  `PENDING_MANUAL_VALIDATION`.

## Avancement 2026-10-21 (session 13)

### Session 13 — Preparation de la validation Retail et securite de la version candidate

- **Phase 1 — reconciliation par mesure reelle** : **209 suites**,
  **1501 tests executes** (0 echec, exit 0), **8 529 assertions**, densite
  **5,67** par cas, **0** suite a zero assertion. L'ecart entre les 1503
  tests declares et les 1501 executes est **explique** : les 2 tests
  manquants appartiennent au banc de performance **opt-in**
  (`DIBS_PERF_BENCH=1`), jamais execute par la suite normale ni par
  l'integration continue.
- **Defaut de test trouve et corrige** : l'execution du banc opt-in a
  revele que son second test **echouait** depuis l'introduction de
  l'evaluation par bouton de reponse et de l'index
  `confirmedPreDibsByItem`. La fixture ne creait aucun bouton, donc le
  chemin mesure n'etait **jamais** atteint, et les attentes par
  candidat dataient d'une optimisation anterieure. Fixture et attentes
  corrigees : le banc passe **2/2** et reste auto-exclu sans la variable
  d'environnement. **Aucune modification de production.**
- **Phase 2 — RF-0013** : plan technique A1 et B1 redige
  (`docs/code-audit/RF-0013-TECHNICAL-PLAN.md`), **non implemente**. La
  cause de A1 est verifiee (limite globale de 500, collecte par source en
  tout-ou-rien, reprise qui echoue a l'identique). B1 existe
  integralement, mais **quatre ecarts de contrat** sont identifies :
  `options` est stocke sans validation et lu nulle part, donc la
  proposition est formellement valide et substantiellement vide. Les deux
  decisions restent **ouvertes**.
- **Phase 3 — worktree** : 121 entrees (58 modifiees, 63 non suivies, 0
  supprimee, 0 indexee). Procedure de sauvegarde ecrite **et executee** :
  962 fichiers, 0 corrompu, 77/77 bibliotheques identiques.
- **Phase 4 — version candidate** : procedure ecrite **et executee**,
  **8 portes sur 8 PASS** (fichiers requis, ordre du TOC dans les deux
  sens, bibliotheques, Lua 5.1, verrous RF-0012, SavedVariables,
  version inchangee, `OptionalDeps`). Artefact produit, rien de publie,
  rien de deploye, version `0.8.10` inchangee.
- **Phase 5 — matrice Retail reconciliee** : la correspondance
  S1–S14 → 20 observations est verifiee **mecaniquement** (20/20
  couvertes, 0 manquante). Les 89 scenarios produit ne sont **pas** tous
  couverts par T041 : 13 constituent une **campagne A** distincte.
  **33 enregistrements** a remplir, pas 13.
- **Phase 6 — scenario quatre clients** : A coordinateur, B officier,
  C joueur, D deconnecte ; 11 etapes, 8 criteres PASS/FAIL, liste de
  collecte complete. Regle absolue : les SavedVariables reelles ne sont
  jamais utilisees pour fabriquer un scenario.
- **Aucune decision metier prise** : RF-0013 reste `PARTIALLY_FIXED`, le
  verrou RF-0012 reste ferme, T041 reste `PENDING_MANUAL_VALIDATION`.

## Avancement 2026-10-21 (session 12)

### Session 12 — Qualite de la suite de tests et preparation de la publication

- **Phase A — inventaire** : 207 suites, 1 483 cas, 8 472 assertions,
  densite moyenne **5,71 assertions par cas**, **0 suite a zero
  assertion**. Les 7 suites a moins de 2 assertions par cas ont ete
  examinees : aucune n'est defectueuse. Les 43 appels de mutation dont le
  resultat est abandonne ont ete verifies : tous sont des mises en place
  dont l'effet est verifie par une assertion portee sur l'etat.
- **Phase B — mutation controlee des RF P0** : un banc d'audit par
  mutation a ete construit. **24 mutations** ont ete reinjectees dans la
  source de production, chaque suite RF supposee couverte a ete
  reexecutee, et la source a ete restauree et reverifiee par empreinte.
  **22 mutations sur 24 sont detectees.** Les 2 echecs sont attendus : le
  faux positif RF-0041 (corrige) et une mutation ciblee vers la mauvaise
  suite (detectee des qu'elle vise la bonne suite).
- **Phase C — isolation de la fixture distribuee** : la fixture
  multi-clients est desormais verifiee **elle-meme** par 11 cas. Trois
  mutations de la fixture ont ete reinjectees : **les trois sont
  detectees**.
- **Phase D — garanties de sauvegarde** : 11 des 12 garanties enumerees
  par le brief etaient couvertes ; **une manquait** (absence de
  `ImportExport.Checksum`). Trois cas ont ete ajoutes.
- **Phase E — faux positifs** : **un faux positif reel** a ete decouvert et
  corrige (RF-0047). La production n'a pas ete modifiee : la validation
  etait deja correcte, c'est la **preuve** qui manquait. Un defaut de
  procedure du banc d'audit a egalement ete corrige (ligne de base
  pristine, reverification de l'absence de mutation residuelle).
- **Phase F — RF-0013** : le dossier a ete re-verifie contre le code
  actuel et complete. Les deux decisions restent **ouvertes** ; aucune
  n'a ete prise. Les premises de B1 sont **verifiees** (proposition
  persistante `PROPOSED`, permission `ledger.propose`, approbation GM
  avec trace d'audit).
- **Phases G et H — publication** : `RELEASE-READINESS-ASSESSMENT.md`
  (statut **`READY_FOR_RETAIL_TESTING`**) et `RETAIL-TEST-MATRIX.md`
  (89 scenarios ; 76 `AUTOMATED_PASS`, 13 `MANUAL_PENDING`, 0
  `MANUAL_PASS`). **`READY_FOR_RELEASE` n'est pas declare.**
- **Aucune decision metier prise** : RF-0013 reste `PARTIALLY_FIXED`, le
  verrou RF-0012 reste ferme, T041 reste `PENDING_MANUAL_VALIDATION`.

## Avancement 2026-10-21 (session 11)

### Session 11 — Securite applicative (PreDibs, litiges, livraison, export)

- **Phase A — PreDibs (20 scenarios, RF-0045)** : **defaut P1 confirme et
  corrige**. `PreDibs.UpsertFromSync` cherchait la demande **uniquement
  dans le ledger nomme par l'enregistrement recu**. Une mise a jour
  nommant un autre ledger n'etait donc pas trouvee, tombait dans la
  branche de creation, et **copiait la demande dans un second ledger**.
  Correction : recherche inter-ledgers, refus `LEDGER_SCOPE_MISMATCH`, et
  `ledgerId` exclu du jeu de champs modifiables.
- **Phase B — litiges (30 scenarios)** : **aucun defaut confirme**. Le
  centre de litiges est un **contexte local** : toute lecture et toute
  ecriture sont refusees pour un acteur distant. Le chemin de correction
  passe par `ProtectedActions.Execute` avec une cle de correction
  idempotente et une resolution de ledger d'origine qui refuse un
  original ambigu. L'historique n'est jamais reecrit, la revision reste
  monotone, la vue sure n'expose ni l'identite, ni l'autorite de
  livraison, ni la chronologie brute.
- **Phase C — sauvegarde / restauration (12 scenarios, RF-0046)** :
  **defaut P0 d'integrite des donnees confirme et corrige**. La
  validation d'instantane de RF-0041 verifiait le **package encode** au
  travers de `ImportExport.Decode`, qui est un **garde d'importation** et
  non un lecteur de sauvegarde. Quatre consequences reproduites :
  1. une sauvegarde legitime de plus de 250 Ko etait refusee
     (`INVALID_PACKAGE_SIZE`) alors qu'une sauvegarde peut atteindre
     32 MiB — **toute guilde au-dela de la limite portable perdait son
     chemin de recuperation** ;
  2. une sauvegarde portant du texte joueur etait refusee
     (`UNSAFE_CONTENT`) ;
  3. toute sauvegarde anterieure a RF-0041 etait refusee
     (`SNAPSHOT_PACKAGE_MISSING`) ;
  4. **le payload applique n'etait pas atteste** : un montant modifie
     de `1` a `9999` a ete **applique sans verification**.
  Correction : `payloadChecksum` sur le payload applique et
  `packageChecksum` sur le package conserve ; le garde d'importation
  n'est plus employe pour lire une sauvegarde.
- **Phase D — livraison et export d'audit** : revus, **aucune mutation**.
  La livraison ne modifie jamais de donnee comptable, refuse un message
  dont l'autorite ne correspond pas au coordinateur courant, et
  reprojecte le corps recu au lieu de lui faire confiance. L'export
  d'audit anonyme ne porte ni identite ni transaction executable.
- **Aucune decision metier prise** : RF-0013 reste `PARTIALLY_FIXED`, le
  verrou RF-0012 reste ferme, T041 reste `PENDING_MANUAL_VALIDATION`.

## Avancement 2026-10-21 (session 10)

### Session 10 — Sauvegardes, importations, recuperation historique

- **Phase A — importation (25 scenarios, RF-0040)** : l'invariant est
  respecte — une importation invalide ne modifie aucune donnee
  comptable. Deux hypotheses refutees : « une importation complete echoue
  toujours » (faux) et « la garde peut distinguer une ligne bootstrap
  d'une operation canonique » (hors contrat, modification abandonnee car
  elle cassait RF-0033). **Aucune correction de production.**
- **Phase B — sauvegarde / restauration (20 scenarios, RF-0041)** :
  **defaut P0 confirme et corrige**. `Backup.Restore` ne validait pas
  l'instantane : un instantane incomplet **effacait** l'historique
  local, un instantane corrompu etait applique, un instantane d'une
  autre guilde etait melange. Le snapshot ne conservait pas le package
  encode, donc son checksum etait **inverifiable**. Correction :
  `validateSnapshot` avant toute mutation, dans `Restore` **et**
  `PreviewRestore` ; le snapshot conserve `packageText`.
- **Phase C — recuperation historique (20 scenarios, RF-0042)** :
  **defaut P0 confirme et corrige**. Un paquet portant le meme
  identifiant legacy qu'une preuve stockee mais avec un contenu
  different etait **commite** : l'`evidenceId` inclut le hash de
  l'enregistrement source, donc la contradiction produisait un second
  identifiant. Le constat `LEGACY_ID_CONTENT_CONFLICT` existait deja
  mais n'etait pas consulte par le commit. Correction : comparaison du
  `legacyIdHash` avant toute mutation.
- **Aucune decision metier prise** : RF-0013 reste `PARTIALLY_FIXED`, le
  verrou RF-0012 reste ferme, T041 reste `PENDING_MANUAL_VALIDATION`.

## Avancement 2026-10-21 (session 9)

### Session 9 — Coherence distribuee (gap recovery, handoff, snapshots)

- **Fixture multi-clients etendue** : `SetOnline`, `IsOnline`, `Deliver`,
  `DeliverOnce`, `Reconnect` dans
  `tests/helpers/canonical_operation_clients.lua`. Un client hors ligne ne
  recoit rien, et les messages restent en file : une deconnexion reelle
  est simulee sans partager la moindre table entre clients.
- **Rattrapage de gap canonique** (`tests/integration/rf0035_canonical_gap_recovery_spec.lua`,
  8 cas) : commit unique rattrape, plusieurs commits rattrapes, aucune
  double comptabilisation, rejeu idempotent, commit altere refuse
  (`COMMIT_HASH_MISMATCH`), commit hors ordre refuse (`STALE_SEQUENCE`),
  commit qui ne s'enchaîne pas refuse (`SYNC_BEHIND`), diagnostic explicite
  du gap. **Chemin sain, aucun defaut.**
- **Transfert de coordinateur** (`tests/integration/rf0035_coordinator_handoff_spec.lua`,
  12 cas) : **RF-0035** confirme et corrige. Trois causes distinctes :
  la requete de detail de gouvernance ne nommait pas la revision posee
  (les registres deja connus etaient renvoyes puis refuses, et le registre
  manquant n'etait jamais atteint) ; `BeginHandoff` n'annoncait rien (le
  resultat dependait du timing) ; et `authorityContent` refusait
  l'adoption d'une autorite tant que le client etait « behind », alors
  que le client applique le registre precisement parce qu'il est en
  retard (verrou mortel). Corrections dans `SyncV2.lua` et
  `Governance.lua` ; aucune regle metier modifiee.
- **Snapshots canoniques** : chemins d'application, de validation, de
  reconstruction et d'import verifies (`HistoricalBaseline`,
  `ImportExport`, `Ledger.RebuildLedgerProjections`). **Aucun defaut
  confirme.**
- **Liberation distribuee des reservations**
  (`tests/integration/rf0036_reservation_reconnection_spec.lua`, 4 cas) :
  le scenario critique de la session 8 est verifie. **Aucun defaut**
  (RF-0036) : le tombeau empeche la ressuscitation, la nouvelle reservation
  est conservee, les soldes convergent, un pair ne rediffuse pas.
- **Snapshots canoniques** (`tests/integration/rf0038_canonical_snapshot_spec.lua`,
  10 cas) : **RF-0038** confirme et corrige. Deux ecarts entre le chemin
  d'ecriture (`verifyCanonicalCursor`) et le chemin de reconstruction
  (`ClassifyCanonicalRecovery`) : la racine d'une chaine vide n'etait
  **jamais** verifiee contre le baseline d'autorite (donc un snapshot
  corrompu etait accepte comme valide et reconstruit), et une position
  hors sequence ou une epoch future n'etait pas refusee par la
  classification. Corrections dans `Ledger.ClassifyCanonicalRecovery` ;
  aucune regle metier modifiee.
- **Rattrapage d'un Secondary Ledger**
  (`tests/integration/rf0037_secondary_ledger_catchup_spec.lua`, 5 cas) :
  replication de l'approbation, rattrapage apres reconnexion, separation
  des soldes, refus de scope, refus d'une ledger non approuvee.
  **Aucun defaut** (RF-0037).
- **Reconstruction apres interruption**
  (`tests/integration/rf0039_projection_rebuild_interruption_spec.lua`,
  4 cas) : reconstruction identique a l'historique, reconstruction
  repetee identique, ligne d'attribution interrompue restauree, ligne
  historique locale conservee. **Aucun defaut** (RF-0039).
- **Aucune decision metier prise** : RF-0013 reste `PARTIALLY_FIXED`, le
  verrou RF-0012 reste ferme, T041 reste `PENDING_MANUAL_VALIDATION`.

## Avancement 2026-10-21 (session 8)

### Session 8 — Reservations, Secondary Ledgers, Backup/ImportExport

- **Audit du cycle de reservation de Dib** (`Ledger.GetPendingDibReservations`,
  `Governance.ResolveAwardProposal`, `SyncV2.BuildAwardReservationDigest`,
  `SyncV2.GetSynchronizationStatus`) : **RF-0031** confirme et corrige.
  Une proposition terminale (`STALE`, `REJECTED`) etait encore comptee
  comme reservation, ce qui reduisait definitivement le solde disponible
  sans mouvement comptable. La correction libere la reservation sur le
  chemin terminal et cesse de diffuser une proposition terminale comme
  `PENDING` aux pairs. Aucune regle metier modifiee.
- **Audit du chemin pair de la reservation** (`SyncV2.ClearAwardReservation`,
  `SyncV2.AnnounceAwardReservationRelease`, reception du digest
  `AWARD_RESERVATION_DIGEST`) : **RF-0034** confirme et corrige. Le digest
  est une liste de remplacement, pas un delta : un pair ne pouvait pas
  deduire qu'une reservation terminale avait disparu, et aucun tombeau
  `RELEASED` n'etait diffuse. Une reservation diffusee restait donc
  fantome sur tous les clients non-coordinateur. La liberation est desormais
  annoncee explicitement, avec controle d'autorite de l'expediteur et
  resolution du joueur contre le roster local.
- **Audit de `MultiLedger.lua`** (33 fonctions) : l'hypothese « le verrou
  `v2Enforced` est par ledger » est **refutee** — `IsV2Enforced()` est un
  etat de guilde, et un Secondary Ledger suit le meme chemin canonique que
  le Primary Ledger. Verrouille par **RF-0032** (8 cas) : ledger non
  approuvee, ledger archivee, emetteur non coordinateur, commit destine a
  une autre ledger, separation des soldes, ledger de consultation, membre
  sans autorite. Aucune correction de code.
- **Audit de `Backup.lua` et `ImportExport.lua`** : **RF-0033** confirme et
  corrige. L'import de portee `full` remplacait `db.ledgers` wholesale
  alors que la table vivante `db.ledger` venait d'etre modifiee ; le solde
  etait recalcule a partir de la mauvaise table et une allocation
  posterieure a l'export etait annulee en silence. La fusion est desormais
  par ledger, conservant les transactions et `playerStates` locaux, et
  `db.ledger` est re-pointe sur `db.ledgers[active]`.
- **Tests ajoutes** : 24 cas sur 4 suites
  (`rf0031_dib_reservation_release_spec`, 7 ;
  `rf0032_secondary_ledger_protection_spec`, 8 ;
  `rf0033_full_import_ledger_rollback_spec`, 4 ;
  `rf0034_peer_reservation_release_spec`, 5). Chaque cause est verifiee
  comme discriminate par reinjection.
- **Aucune decision metier prise** : RF-0013 reste `PARTIALLY_FIXED`, le
  verrou RF-0012 reste ferme, T041 reste `PENDING_MANUAL_VALIDATION`.

## Avancement 2026-10-19 (session autonome)

### Session 4 — PlayerUI et modules restants

- **Audit reel de `src/ui/PlayerUI.lua`** : identification des joueurs,
  associations main/alt, groupes d'eligibilite, historique des acquisitions,
  creation de Pre-Dib, validation des demandes, permissions, etats UI,
  synchronisation, callbacks, gestion des erreurs, persistance/reload et
  divulgation entre joueurs. Verifie : `GetSummary` ->
  `GetCanonicalPlayerDibsState` / `GetPlayerState` / `GetHistory` ;
  `BuildRequestView` -> `Disputes.ListForPlayer` (requetes propres
  seulement, `PLAYER_SCOPE_REQUIRED`) ; `getPlayerTransactions` filtre sur la
  cle du joueur ; `submitPublicPreDib` porte le proprietaire sur le joueur
  local ; `getGuildCharacterChoices` montre l'effectif de guilde moins le
  joueur local ; aucun etat persistant propre. **Aucun defaut confirme.**
- **35 modules supplementaires audites**, aucun defaut confirme :
  `LootRules`, `LootPipeline`, `GreatVault`, `RaidPrompts`, `Notifications`,
  `RankRules`, `DryRun`, `Midnight`, `EnvironmentAdapters`, `HistoryFilters`,
  `LogsUI`, `DebugLogsUI`, `WindowState`, `DeveloperMode`,
  `DeveloperSandbox`, `DeveloperSandboxStore`, `DeveloperSandboxScenarios`,
  `DeveloperUI`, `DataUI`, `HealthUI`, `MinimapButton`, `SetupAssistant`,
  `EncounterJournal`, `RCLootCouncilOptions`, `RaidRelay`,
  `IndependentRaid`, `Governance`, `ProtectedActions`, `Ledger`,
  `RCLootCouncil`, `Core`, `SyncV2`, `OfficerUI`, `AceGUI`, `Types`.
- **Points de securite verifies en profondeur** : `Ledger.ApplyAwardCommit`
  valide integralement avant toute mutation ; `Governance.ReceiveRelayedProposal`
  resout l'expediteur dans le roster et exige GM/officier ;
  `CoreAPI.getTransactions` renvoie `PLAYER_SCOPE_REQUIRED` hors officier ;
  `SyncV2.applyRequest` applique une projection expurgee quand un officier
  relaie vers un non-officier ; `RCLootCouncil.HandleAwardCallback` persiste
  un recu normalise *avant* le chemin protege ; `Disputes.ListForPlayer`
  impose `isLocalActor` et filtre par `isLocalIdentity` au niveau service,
  pas seulement dans l'interface.
- **RF-0006 reconfirme** : `DibsSyncMessageType` decrit le registre V1
  (`Sync.lua`, `MESSAGE_TYPES`) et non le registre V2 (`SyncV2.lua`, `TYPES`).
  Corriger l'alias exige de decider laquelle des deux unions exposer, ou de
  les declarer separement. Aucune correction appliquee : risque LOW, fiche
  deja ouverte, aucun effet sur le comportement.
- **Couverture des locales verifiee** : `enUS` et `frFR` exposent 978 cles
  chacun, 0 ecart par `Compare-Object`, et les 25 cles appelees statiquement
  dans le code sont toutes definies.
- **Balayage des ecritures d'etat de guilde sans garde d'autorite** : 4
  candidats, 3 confirmes sans risque, 1 consigne sans correctif
  (`SelectButtonTemplate`, etat d'editeur local sans effet de bord
  metier). Voir la section « Ecart constate » du journal.
- **Aucun nouveau RF** dans cette session. Aucun correctif applicatif. Le
  worktree n'a recu que des mises a jour de documentation d'audit.

- Session autonome en cours : voir
  [AUTONOMOUS-SESSION-STATUS.md](AUTONOMOUS-SESSION-STATUS.md) pour l'etat
  vivant, les preuves et la procedure de reprise exacte.
- **Suite complete relansee** : 1201 PASS / 0 FAIL sur 175 fichiers avant
  l'application de RF-0013, puis 176 fichiers avec la suite de reproduction
  RF-0013.
- **Compilation Lua 5.1.5 retablie** : un vrai compilateur 5.1.5 (source
  officielle, compile avec MSVC) est utilise comme reference. Deux fichiers ne
  compilaient pas sous la limite de 60 upvalues de Lua 5.1 :
  `src/modules/SyncV2.lua` (`Sync.Receive`, introduit par RF-0012) et
  `src/ui/OfficerUI.lua` (`renderRoute`, pre-existant). Les deux ont ete
  corriges par extraction, sans changement de comportement. La garde
  permanente est `tests/powershell/Test-DibsLua51Compilation.ps1`.
- **RF-0013 analyse, reproduit et partiellement corrige** : cinq causes
  confirmees dans `src/modules/Installation.lua` (reprise d'un scan partiel,
  signalement par source, refus d'approuver un baseline incomplet, chemin
  officier fidele, portee de detection et erreurs de lecture). Tests :
  `tests/integration/rf0013_partial_legacy_discovery_spec.lua` (5 cas, chacun
  verifie comme discriminant par reinjection de la cause). Restent ouverts :
  la limite globale `MAX_EVIDENCE = 500` et l'objet de proposition de
  l'Officer, qui demandent une decision metier.
- **Erreur runtime OfficerUI corrigee** : `Dibs.AceGUI.GetText` n'existait pas
  (l'adaptateur ne definit que `SetText`) ; le bouton "Start Independent
  Session" echouait donc a chaque clic. Corrige via le helper existant
  `getControlText`. Test de reproduction :
  `tests/integration/officer_ui_independent_raid_button_spec.lua`.
- **Verrou RF-0012 durci** : le drapeau de release est desormais la
  constante compilee `Dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED` et non une
  valeur SavedVariables. Aucun reglage, controle UI ou commande `/dibs` ne
  peut ouvrir le chemin canonique.
- **RF-0014 confirme et corrige** : `Eligibility.RequestMainChange` derivait le
  groupe de joueur de l'ancien main sans verifier le nouveau. Apres
  approbation, un personnage d'un joueur sans lien entrait dans le groupe du
  demandeur, heritait de son groupe d'eligibilite et pouvait lire son
  historique d'acquisitions. Correction dans
  `src/modules/CharacterEligibility.lua` (garde a la demande et a
  l'approbation) ; le flux legitime « changement de role » vers un personnage
  encore non rattache reste possible. Tests :
  `tests/integration/rf0014_main_change_group_escape_spec.lua` (5 cas, chacun
  verifie comme discriminant).

## Protection permanente des bibliotheques externes

- Tout composant de chemin dont le nom est `libs`, sans distinction de casse,
  est strictement en lecture seule; la regle couvre tous les types de fichiers
  et s'applique aussi aux futurs travaux Spec Kit.
- Inventaire courant : `src/libs/`, 77 fichiers/entrees dont 47 Lua. Aucun
  changement Git preexistant ni ecart de contenu Lua avec l'ancienne baseline
  n'a ete signale a la migration; aucun fichier n'a ete restaure ou modifie.
- `audit_guard.py capture-libraries` a ajoute une empreinte brute par entree
  protegee et a conserve les hashes Lua hors `libs`; `validate_audit.py`
  exclut ces fichiers du compte des modules et rejette tout tag `@AUDIT` dedans.
- Regression synthétique du garde : 13 assertions reussies couvrant modification,
  ajout, suppression, deplacement, annotation interdite, casses mixtes,
  `node_modules` et migration schema 1.
- Bibliotheques consultables uniquement pour contrats/API/callbacks/evenements
  et compatibilite. Aucun constat RF ne porte sur leur implementation interne.
- `MACHINE-INVENTORY.json` et `BASELINE.json` sont des sorties d'outils; les
  fichiers generes, archives, journaux et donnees personnelles restent hors
  perimetre de modification (sauf mise a jour explicite de la baseline par son garde).

## Lots termines

| Lot / module | Fichiers analyses | RF attribues | Verifications |
|---|---|---|---|
| 0 - Inventaire | 58 sources premiere partie, TOC, XML, chemins tests/docs/outils | Aucun | 164 suites, definitions et registrations recensees; pas de preuve d'inutilite |
| 1 - Controles personnels | MinimapButton complet; AceGUI AddRange/AddCheckBox; PlayerUI Preferences; test minimap complet; Slider tiers callbacks | RF-0001 a RF-0003 | Deux incoherences UI statiquement confirmees; aucun correctif applique |
| 2 - Bootstrap/transport | Ace3 complet; Core namespace/local settings/Initialize/events; Sync complet; SyncV2 registre et receive/transport/lifecycle cibles; Types aliases cibles | RF-0004 a RF-0006 | Wrapper sans AceEvent; services V1 encore utilises; types documentaires incomplets |
| 3 - Donnees | Backup, Profiles, ImportExport, AuditExport complets; DataUI preview/restore cibles; tests backup/import/profiles et sync-safe cibles; spec 007 sections pertinentes | RF-0007 a RF-0009 | Helper local candidat; plusieurs actifs reproduits; preview sync-safe incomplete |
| 4 - Projections setup | SetupAssistant et Capabilities complets; Readiness helpers/Evaluate initial/Run/fraicheur/gate; Wizard GetTurnkeyStatus et etapes legacy; Core closures capabilities cibles | RF-0010 a RF-0011 | Getter sync absent/en erreur affiche ready; delegation protegee preservee |
| 5 - Identite, autorite et litiges | Identity/Permissions complets; Governance/ProtectedActions par plages; Disputes complet; trace cible Ledger/MultiLedger/SyncV2/ProtectedActions et contrats sauvegarde/sync | RF-0012 approfondi | Compensation non verifiee; ajustements de litige hors chaine canonique V2; idempotence et scope ledger insuffisants; revue complete de ces modules a poursuivre |
| 6 - Installation / reconciliation historique | Installation complet; chemins `HistoricalBaseline.CollectLocalEvidence` cibles; tests installation/guided setup et documentation de l'architecture/guides | RF-0013 | Collecte ledger puis Pre-Dibs en deux writes; retry apres une seule source peut la traiter comme complete; detecteur active vs collecteur `guild-primary`; code officier ignore erreurs |
| 7 - Reprise ciblee RF-0012/RF-0013 | `ProtectedActions.Execute` -> `Ledger.AdminAdjust`/wrappers -> `CommitLocalTransaction` ou voie canonique; `MultiLedger` actif/vue; detecteur Installation et retour UI officier | RF-0012, RF-0013 | Confirme la cle de correction comme metadonnee, le filtrage du commit canonique, le scope actif et la perte de diagnostics Ledger; ajoute le cas `pcall` silencieux et les retours officier ignores. Aucune modification de comportement. |
| Transverse | Liens des rapports, TOC/XML, callbacks sliders, namespace Sync partage, scopes de donnees, distinction Readiness/Setup/Wizard et AuditExport/ImportExport; backlog Spec Kit | Aucun autre ID | Backlog groupe les travaux; aucun patch fonctionnel, suppression, fusion ou renommage applique |
| 8 - Reprise autonome RF-0013/RF-0014 | Installation complet; CharacterEligibility complet; Wizard complet; Readiness complet; Profiles complet; OperationalPolicy, RequestDelivery, Seasons, Backup, ImportExport, AuditExport, HealthUI, RaidRelay, IndependentRaid, PreDibs, MultiLedger, HistoricalBaseline, Sync V1 | RF-0013 a RF-0018 | RF-0013 partiellement corrige (deux decisions metier en attente, documentees dans `RF-0013-BUSINESS-DECISIONS.md`) ; RF-0014 a RF-0018 confirmes et corriges avec test discriminant ; `stepDibsRules` classe NOT A DEFECT, comportement non modifie |

## Couverture exacte a la pause

- 58/58 sources applicatives recensees structurellement; les 77 fichiers de
  `src/libs/` sont exclus de ce compte et proteges separement.
- 10 modules lus integralement dans les lots : Ace3, MinimapButton, Sync, Backup,
  Profiles, ImportExport, AuditExport, SetupAssistant, Capabilities, Installation.
- Disputes, Identity et Permissions sont aussi lus integralement; 13 fichiers
  complets au total selon les lots documentes.
- 13 autres revus par plages : Core, Types, AceGUI, PlayerUI, DataUI, SyncV2,
  Wizard, Readiness, Governance, ProtectedActions, Ledger, MultiLedger,
  HistoricalBaseline.
- Reprise autonome 2026-07-20 : 18 modules supplementaires lus integralement
  (Installation, HistoricalBaseline, MultiLedger, PreDibs, CharacterEligibility,
  OperationalPolicy, RequestDelivery, Seasons, Backup, ImportExport,
  AuditExport, HealthUI, RaidRelay, IndependentRaid, Wizard, Readiness,
  Profiles, Sync V1). Total : **25 fichiers applicatifs lus integralement**
  sur 58 sources.
- 12 revus par plages : Core, Types, AceGUI, PlayerUI, DataUI, SyncV2,
  Governance, ProtectedActions, Ledger, RCLootCouncil, RCLootCouncilOptions,
  EncounterJournal.
- Restent seulement inventories : **0 fichier applicatif** sur 58 sources.
  La liste de 21 << seulement inventories >> ci-dessus correspondait a un etat
  de pause anterieur : ces 21 fichiers ont ete relus depuis (sessions 4, 5
  et 6) et portent chacun une ligne de resultat dans
  [AUTONOMOUS-SESSION-STATUS](AUTONOMOUS-SESSION-STATUS.md).
- **Decompte reconcilie (session 8, confirme en session 11)** : 58 FULL / 0
  PARTIAL / 0 INVENTORIED sur les 58 sources applicatives de `src/` hors
  bibliotheques. La methode et les preuves sont dans
  [AUTONOMOUS-SESSION-STATUS](AUTONOMOUS-SESSION-STATUS.md#reconciliation-full--partial--inventoried-session-6).
  Verification mecanique : 58/58 fichiers cites dans au moins un document
  d'audit, 22/58 portant un tag `@AUDIT` rattache a une fiche.
- 47 fiches : RF-0001 a RF-0044, RF-0045, RF-0046 et RF-0047. 29 `FIXED`, 1 `PARTIALLY_FIXED`
  (RF-0013), 6 `NEED_UPDATE`, 10 `KEEP`, 1 `TO_REMOVE`. Aucune fiche
  `OPEN` : RF-0020, RF-0021, RF-0023, RF-0026 a RF-0031, RF-0033, RF-0035,
  RF-0038, RF-0041 et RF-0042 ont ete corrigees ; RF-0032, RF-0036,
  RF-0037, RF-0039, RF-0040, RF-0043 et RF-0044 sont des hypotheses
  refutees verrouillees par test.
- Aucun COULD_MERGE ou RENAME_CANDIDATE faute de preuve suffisante.
- RF-0012 : le chemin de mutation et ses facades sont maintenant traces
  jusqu'aux gardes Permissions/Governance/MultiLedger et au digest/rattrapage
  `AWARD_COMMIT`; les echecs de compensation, le rejeu stable et la convergence
  ne sont pas couverts par des tests existants.
- RF-0013 : confirme le retry qui saute les sources manquantes, le `pcall`
  silencieux du detecteur et les deux resultats officier non verifies. Le
  scope voulu (ledger actif, primary ou plusieurs ledgers) et la frequence
  d'une exception de lecture restent UNKNOWN.
- Les specs 007 et 021 consultees portent le statut Draft : elles eclairent
  l'intention documentaire, elles ne sont pas une approbation de nouvelles regles.
- [SPECKIT-BACKLOG.md](SPECKIT-BACKLOG.md) priorise les travaux potentiels RF-0001
  a RF-0013; aucune feature Spec Kit n'a ete creee.

## Prochain lot

1. Poursuivre l'audit ligne par ligne de `Ledger.lua` et
   `SyncV2.lua` au-dela des chemins deja traces, en portant une
   attention particuliere a l'idempotence et a la reprise apres
   interruption.
2. Completer `Core.lua` (facade `Dibs.CoreAPI`, closures de
   capabilities) et `EncounterJournal.lua` au-dela des plages
   examinees.
3. Reprendre `RCLootCouncilOptions.lua` : la coherence de
   garde entre `SelectButtonTemplate` et ses six pairies reste
   un ecart de coherence signale, sans consequence metier.
4. Verifier la persistance et le reload de la surface de revue Officier
   ajoutee en session 6 (RF-0020).

## Hypotheses non verifiees

- Revue ligne par ligne des 49 233 lignes premiere partie : NON terminee.
- Aucun code mort ni fusion equivalente demontres.
- Contrats dynamiques externes et versions Retail : UNKNOWN.
- Une exception reelle de `Ledger.GetAllTransactions` et un rejet de la
  compensation de correction n'ont pas ete reproduits.
- Ne pas reprendre l'ancien resultat de tests 1097/1097 comme une execution de cet audit.
- Les 73 tests verts de cette reprise n'invalident pas RF-0012 ni RF-0013 : les
  tests actuels couvrent le transfert reussi et l'issue nominale du setup, pas
  les echecs de compensation, la convergence des ajustements de litige sous V2,
  ni l'echec de collecte/proposition officier.
- Le cas AceEvent absent est confirme dans les doubles; aucune panne de la
  bibliotheque embarquee n'est affirmee dans le package Retail normal.

## Validation reproductible

Depuis la racine, sans modifier les fichiers de tests :

```powershell
$env:PYTHONIOENCODING = 'utf-8'
python .github\skills\lua-code-audit\scripts\validate_audit.py
python .github\skills\lua-code-audit\scripts\audit_guard.py verify
git diff --check
git --no-pager diff -- '*.lua'
```

Selection Fengari executee, en preservant/restaurant DIBS_TEST_FILES :

- `tests\integration\dispute_center_spec.lua`
- `tests\integration\b06_distributed_ledger_spec.lua`
- `tests\integration\installation_wizard_spec.lua`
- `tests\integration\guided_setup_wizard_spec.lua`
- `tests\unit\b03_local_ledger_spec.lua`
- `tests\unit\multi_ledger_spec.lua`
- `tests\integration\multi_ledger_sync_spec.lua`
- `tests\integration\historical_baseline_recovery_spec.lua`

Commande : `npx.cmd --yes --package=fengari-node-cli fengari tests\run.lua`.
Verification visuelle Retail et scenarios multiclients : NON FAITS.

Validation additionnelle du lot 5, commande Fengari identique :
43 tests passes, 0 echec, 7 suites (Disputes, autorite/confidentialite,
permissions, bootstrap/identite, autorite B05b, ProtectedActions et identite Core).
Les tests existants couvrent le transfert de cible reussi, mais pas le rejet
de la seconde ecriture ni l'echec de compensation documentes en RF-0012.

Selection de verification apres la reprise RF-0012/RF-0013 :
113 tests passes, 0 echec, 8 fichiers.
`validate_audit.py` : 13 tags/fiches coherents, 0 avertissement, 0 erreur.
`audit_guard.py verify` : avant la nouvelle protection, 282 fichiers Lua
conformes a la baseline historique hors annotations `@AUDIT`; la migration
courante scinde maintenant le controle en 235 Lua hors `libs` et 77 empreintes
strictes. `git diff --check` : OK. Ces tests ne simulent pas un rejet
de la compensation, une correction dispute V2 sur coordinateur/follower, ni un
echec de la seconde source du scan legacy a la limite de capacite.

Le recensement machine est un instantane pre-annotations; ses numeros de lignes
doivent etre resolves par symbole dans le code actuel. Ne pas regenerer la baseline
pour masquer une difference. Relire ce fichier et INDEX avant d'attribuer RF-0012.

## Etat Git preexistant / limites constatees

Avant toute ecriture :

```text
?? .github/skills/lua-code-audit/
?? INSTALLATION.md
?? docs/code-audit/
```

Le repertoire d'audit contenait uniquement `.gitkeep` (vide). Ces elements
preexistants ne doivent pas etre modifies, supprimes, stages ou commites.
La competence n'est pas enregistree dans le chargeur de skills; son fichier local
et ses references ont ete lus directement.

Au debut de la presente reprise, l'etat Git contenait aussi des modifications
preexistantes dans `src/Core.lua`, `src/Types.lua`, plusieurs modules et fichiers
UI, ainsi que des elements non suivis `.specify/` et d'autres skills. Ils ont
ete conserves. Le statut/diff cible `src/libs/` etait vide; la garde confirme
apres migration que les bibliotheques n'ont pas change.

Le premier validateur a affiche 0 erreur puis echoue en sortie console cp1252
sur le caractere de fleche. Relance avec `PYTHONIOENCODING=utf-8` : OK.
Aucun script modifie. Le recensement XML initial par regex incluait un commentaire;
il a ete recalcule avec ElementTree : 107 entrees actives, aucun chemin manquant.

Probes en memoire, donnees synthetiques seulement :

```text
RF-0001: OnValueChanged absent
RF-0002: stored=false; checkbox=true
RF-0008: active profiles after A -> B: 2
RF-0004: AceEvent wrapper returns false, Core setup returns true
AUDIT_PROBES_OK
```

Execution via Fengari stdin et `tests/helpers/load_addon.lua`, avec package.path,
unpack et register_reset initialises comme le harness. Deux tentatives initiales
non concluantes (quoting `-e` Windows, puis registre reset absent) ont ete
remplacees par une execution complete affichant le marqueur final ci-dessus.
Ces probes ne prouvent ni rendu Retail ni absence d'autres problemes.

Probe du lot 4, meme harness et marker final `SETUP_AUDIT_PROBE_OK` :
`IsSyncBehind` missing -> ready; exception -> ready; false -> ready; true -> degraded.
Ces etats concernent le check sync_state, pas le verdict global ni une acceptation reseau.

Seules nouvelles ecritures autorisees : rapports/baseline dans ce repertoire et
annotations Lua `-- @AUDIT` autonomes. Pas de CHANGELOG/version bump : la consigne
specifique de l'audit interdit toute ecriture hors de ce perimetre.
