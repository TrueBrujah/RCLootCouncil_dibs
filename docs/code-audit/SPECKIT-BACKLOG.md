# Backlog potentiel Spec Kit

> Ce document transforme les constats de l'audit en propositions de travail.
> Il ne cree pas de specifications et n'autorise pas leur implementation.
> Tout nouveau travail doit commencer par confirmer les contrats et incertitudes
> listes ici avec la feature spec approuvee. Aucun changement de comportement
> n'est applique pendant l'audit.

## Contrainte permanente sur les bibliotheques

- Tout chemin contenant un repertoire nomme `libs`, sans distinction de casse,
  est une dependance tierce strictement en lecture seule. Aucun changement,
  commentaire, annotation, ajout/suppression/deplacement/renommage de fichier ou
  reformatage n'est permis, y compris par un outil automatise ou une future
  feature Spec Kit.
- Les bibliotheques sont consultables uniquement pour verifier des contrats,
  API, signatures, callbacks, evenements et compatibilite. Elles sont hors du
  decompte des modules applicatifs; aucun RF ne cible leur implementation
  interne. Un probleme possiblement externe doit etre documente separement.
- Avant de definir le perimetre ou les tests d'une feature ci-dessous, exclure
  explicitement les bibliotheques protegees et tout fichier genere; ne jamais
  proposer une migration/refactorisation qui les modifie.

## Regles de conversion

- Un RF peut alimenter un travail regroupe si les corrections sont inseparables;
  ne pas creer une feature par annotation.
- Les priorites indiquent l'ordre de triage de l'audit, pas une date de livraison.
- `KEEP` est un invariant, pas un travail de correction. `SECURITY`, `MERGE` et
  `RENAME` ne sont attribues que si une preuve correspondante existe.
- Le perimetre doit etre precise et approuve dans Spec Kit avant toute
  implementation. Les hypotheses non verifiees restent des questions ouvertes.

## P1 - Integrite comptable des corrections RF-0012

- **Identifiant RF:** RF-0012
- **Categorie:** DATA_INTEGRITY, BUG
- **Statut:** **LIVRE par la spec
  [026](../../specs/026-canonical-idempotent-corrections/spec.md) (T015 / T024 /
  T027).** Fiche reclassifiee `FIXED` en session 4 (2026-10-20) ; voir
  [INDEX](INDEX.md#rf-0012) pour la resolution appliquee et sa preuve.
  Le bloc ci-dessous est conserve comme trace de l'etat observe avant la
  correction.
- **Titre:** Rendre les corrections de litige ledger-scoped, repliquees et recuperables
- **Probleme:** Les corrections de cible effectuent une inversion puis un credit
  dans deux appels ProtectedActions independants. L'echec de la seconde ecriture
  declenche une compensation dont le resultat est ignore; les IDs sont aleatoires
  et aucune cle stable ne deduplique l'operation. En outre, le chemin
  `source="dispute-center"` passe par l'ajustement local meme sous V2, tandis que
  digests et rattrapage V2 portent sur les commits canoniques. Le ledger actif
  n'est pas explicitement lie a la preuve originale.
- **Comportement attendu:** Une correction acceptee a une portee ledger explicite,
  une autorite validee et un resultat durable qui converge chez les membres V2.
  Rejouer la meme operation ne doit pas appliquer une seconde fois son effet.
  Un echec partiel doit etre signale et recuperable, sans pretendre qu'une
  compensation a reussi lorsque son resultat n'a pas ete verifie. La resolution
  d'attribution sans mutation de solde doit rester distincte et explicite.
- **Modules concernes:** `Disputes`, `ProtectedActions`, `Permissions`, `Ledger`,
  `MultiLedger`, `Governance`, `SyncV2`, `Backup`, `ImportExport`,
  `RequestDelivery`.
- **Dependances:** Reconfirmer le contrat de la [spec 009](../../specs/009-officer-audit-dispute-center/spec.md),
  le commit canonique B06 et l'autorite requise pour l'ajustement; determiner si
  la correction cible le ledger courant ou celui de la transaction originale;
  definir ce que signifie une correction sans ligne comptable liee.
- **Risque:** HIGH. Une correction locale non canonique peut diverger entre
  membres; un transfert partiel ou rejoue peut modifier plusieurs fois le solde.
- **Priorite:** P1 - traiter avant d'etendre les mecanismes de correction ou de
  reparation des ledgers V2.
- **Niveau de confiance:** HIGH sur les chemins locaux, la compensation ignoree,
  la cle non deduplicatrice et le transport V2 canonique; MEDIUM sur la
  probabilite d'une compensation rejetee en fonctionnement Retail et sur
  l'intention du scope MultiLedger.
- **Tests necessaires:** Echec de la seconde jambe avec compensation reussie et
  rejetee; etat des soldes et de toutes les lignes append-only; reprise apres
  echec; rejeu avec identite stable; correction apres changement de ledger actif;
  execution V2 sur coordinateur et membre follower, avec comparaison des
  transactions, balances, sequence et hash; sauvegarde/restauration d'un ledger
  ayant des ecritures locales non canoniques; tests d'autorite en cas de
  changement de role/coordonateur; reouverture puis rejeu d'une correction
  simple lorsque l'ID memorise n'est pas present dans le ledger actif; verifier
  que les causes de rejet Ledger et toute proposition V2 sont visibles au
  caller, sans etre remplacees par le seul resultat d'autorisation.
- **Prerequis:** Tracer les chemins de correction simple et target; verifier les
  tests de transfert, de commits admin et de restauration; decider explicitement
  si le design garantit atomicite, compensation persistante ou etat recuperable.
- **Proposition de perimetre pour Spec Kit:** Une feature unique couvrant le
  modele d'operation de correction, son identifiant idempotent, le lien a un
  `ledgerId`, l'application sous autorite V2, la diffusion/reprise, les etats
  d'echec et les projections UI/diagnostics. Ne pas inclure d'autres operations
  comptables sans preuve qu'elles partagent le meme defaut.

## P1 - Robustesse du bootstrap evenements RF-0004

- **Identifiant RF:** RF-0004
- **Categorie:** BUG, MAINTENANCE
- **Titre:** Fonder l'initialisation runtime sur les enregistrements reussis
- **Probleme:** Core peut marquer les evenements comme enregistres si le wrapper
  AceEvent existe alors que son implementation sous-jacente retourne false.
- **Comportement attendu:** Un echec d'enregistrement est visible et le fallback
  natif ou une nouvelle tentative est utilise sans doublonner les evenements.
- **Modules concernes:** `Core`, `Ace3`.
- **Dependances:** Disponibilite reelle des bibliotheques embarquees et contrat
  de `RegisterEvent`/`RegisterComm`.
- **Risque:** MEDIUM; scenario degrade confirme dans les doubles, panne en
  installation Retail normale non etablie.
- **Priorite:** P1.
- **Niveau de confiance:** HIGH sur le chemin conditionnel observe.
- **Tests necessaires:** Wrapper present avec lib absente, lib renvoyant false,
  exception d'enregistrement, fallback reussi, retry et absence de double
  livraison.
- **Prerequis:** Reprendre le contrat Ace3 sans modifier la bibliotheque tierce.
- **Proposition de perimetre pour Spec Kit:** Corriger le seul cycle
  d'enregistrement runtime et ses diagnostics; ne pas refondre les integrations.

## P1 - Etat des profils RF-0008

- **Identifiant RF:** RF-0008
- **Categorie:** BUG, DATA_INTEGRITY
- **Titre:** Maintenir un seul profil actif par bucket et portee
- **Probleme:** La transition observee de A vers B conserve deux profils
  marques actifs dans le meme bucket.
- **Comportement attendu:** L'activation, l'echec d'application et la restauration
  laissent un statut actif deterministe par scope; les autres scopes/personnages
  restent isoles.
- **Modules concernes:** `Profiles`, `Core`, `DataUI`, `Backup`.
- **Dependances:** Contrats des scopes guild/personnage, snapshot rate et
  politique de profil adoptee.
- **Risque:** MEDIUM; l'etat stocke peut ne pas refleter le profil applique.
- **Priorite:** P1.
- **Niveau de confiance:** HIGH pour le probe A -> B; semantics de toutes les
  portees a confirmer.
- **Tests necessaires:** A -> B, echec a chaque etape d'activation, changement
  guild/personnage, restauration et migration de donnees existantes.
- **Prerequis:** Lire l'ensemble des transitions et migrations Profiles avant
  de choisir l'invariant de stockage.
- **Proposition de perimetre pour Spec Kit:** Un lot de coherence de statut actif
  et de tests de scope, sans fusion de Profiles avec Backup/ImportExport.

## P1 - Sonde sync inconnue RF-0010

- **Identifiant RF:** RF-0010
- **Categorie:** BUG, MAINTENANCE
- **Titre:** Distinguer etat de synchronisation inconnu d'un etat pret
- **Probleme:** Une sonde `IsSyncBehind` absente ou en erreur peut etre interpretee
  comme `ready` dans le check sync de SetupAssistant.
- **Comportement attendu:** Les etats succes, retard, API indisponible et erreur
  sont presentes distinctement avec diagnostic/remediation adaptes, sans
  inventer une nouvelle garde metier.
- **Modules concernes:** `SetupAssistant`, `Readiness`, `SyncV2`, locales UI.
- **Dependances:** Contrat de Readiness/SetupAssistant et signification du code
  `SYNC_BEHIND`.
- **Risque:** MEDIUM; affichage pret potentiellement trompeur, sans preuve que
  cette projection seule accepte une mutation.
- **Priorite:** P1.
- **Niveau de confiance:** HIGH sur les quatre resultats du probe.
- **Tests necessaires:** Getter absent, exception, false, true; codes localises;
  aucune mutation/annonce reseau provenant du rendu.
- **Prerequis:** Separarer le diagnostic de readiness de l'execution des actions.
- **Proposition de perimetre pour Spec Kit:** Corriger le modele de resultat et
  son rendu pour cette sonde, avec les quatre cas ci-dessus.

## P1 - Controles Preferences RF-0001 et RF-0002

- **Identifiant RF:** RF-0001, RF-0002
- **Categorie:** BUG
- **Titre:** Aligner les valeurs Preferences avec les callbacks et l'etat masque
- **Probleme:** Le slider de taille minimap ne persiste/applique pas les
  changements transmis par molette; une preference booleenne `false` est
  affichee comme `true` au rerendu.
- **Comportement attendu:** Les changements utilisateur pris en charge par le
  slider sont appliques et persistes; le checkbox reproduit exactement `true`,
  `false` et la valeur absente par defaut.
- **Modules concernes:** `AceGUI`, `PlayerUI`, `MinimapButton`, widget Slider
  embarque (lecture seulement sauf besoin prouve).
- **Dependances:** Contrat des callbacks AceGUI et setters generiques
  `RenderOptionsGroup`.
- **Risque:** LOW local; un changement generique de callback pourrait avoir un
  risque plus large.
- **Priorite:** P1.
- **Niveau de confiance:** HIGH sur les deux defauts reproduits par probes.
- **Tests necessaires:** Molette, drag, clavier, bornes, reset/persistance;
  hide -> Preferences -> checkbox decoché -> reopen; controle des autres
  consommateurs generiques d'AddRange.
- **Prerequis:** Garder l'effet de bord du slider borne au controle personnel,
  sauf preuve que le contrat generique peut etre change sans regression.
- **Proposition de perimetre pour Spec Kit:** Une petite feature UI peut regrouper
  ces deux regressions Preferences car elles sont toutes deux verifiees dans
  `PlayerUI`; conserver des assertions/tests independants par comportement.

## P1 - Preview de restauration RF-0009

- **Identifiant RF:** RF-0009
- **Categorie:** MAINTENANCE, BUG
- **Titre:** Montrer dans l'apercu les sous-arbres locaux conserves
- **Probleme:** La preview generique de restore ne montre pas entierement les
  donnees locales gardees par la logique sync-safe.
- **Comportement attendu:** Avant confirmation, l'utilisateur voit les parties
  importees, preservees localement, ignorees et les conflits selon le plan de
  restauration effectivement calcule.
- **Modules concernes:** `Backup`, `DataUI`, `ImportExport`.
- **Dependances:** Plan de merge/restore non mutant, changement possible de l'etat
  partage entre preview et confirmation.
- **Risque:** MEDIUM; choix de restauration moins informe.
- **Priorite:** P1.
- **Niveau de confiance:** HIGH pour l'incompletude observee; les surfaces de
  preview restantes sont a revoir.
- **Tests necessaires:** Preview non mutante, `keptLocal`, conflit de revisions,
  etat modifie depuis preview, restore Guild vs Full et preservation de sync.
- **Prerequis:** Etablir si confirmation reutilise ou recalcule le plan.
- **Proposition de perimetre pour Spec Kit:** Etendre la projection de preview
  uniquement aux decisions deja prises par Backup; ne pas changer la politique
  de fusion.

## P2 - Types de messages RF-0006

- **Identifiant RF:** RF-0006
- **Categorie:** MAINTENANCE
- **Titre:** Aligner les types documentaires avec les registres de messages
- **Probleme:** L'union des messages Sync documentee dans `Types.lua` ne suit pas
  les registres V1/V2 observes.
- **Comportement attendu:** Les types statiques refletent les messages et
  payloads effectivement pris en charge, ou sont explicitement identifies comme
  historiques.
- **Modules concernes:** `Types`, `Sync`, `SyncV2`, documentation du protocole.
- **Dependances:** Inventaire complet des registres, messages dynamiques et
  alias historiques.
- **Risque:** LOW; impact surtout sur l'aide au developpement et la confiance
  dans les types.
- **Priorite:** P2.
- **Niveau de confiance:** HIGH sur la divergence de l'union ciblee; couverture
  totale des payloads a completer.
- **Tests necessaires:** Comparaison mecanique des registres, compilation/
  validation LuaLS si disponible, tests de compatibilite des messages gardes.
- **Prerequis:** Finir l'inventaire des chemins V1/V2 avant suppression d'un type.
- **Proposition de perimetre pour Spec Kit:** Mise a jour documentaire/type
  uniquement; aucune modification du protocole ou des messages serialises.

## P1 - Completude du scan historique RF-0013

- **Identifiant RF:** RF-0013
- **Categorie:** DATA_INTEGRITY, BUG, MAINTENANCE
- **Titre:** Rendre la collecte legacy complete et reprenable par source
- **Probleme:** `HistoricalBaseline.CollectLocalEvidence` persiste les lignes du
  ledger puis celles de Pre-Dibs par deux appels separes. Si le second echoue,
  le premier reste sauvegarde. `Installation` traite pourtant toute evidence
  existante comme la preuve que la collecte a deja eu lieu. Avec 500 lignes
  ledger et une ligne Pre-Dibs, la seconde source peut echouer a la limite de
  500 alors que le premier appel est accepte. L'etat de readiness ne compare pas
  la liste attendue de sources. En outre, le detecteur utilise le ledger actif
  alors que le collecteur lit `guild-primary`.
- **Comportement attendu:** La collecte ne peut etre consideree terminee que si
  toutes les sources requises pour son scope sont presentes et complete. Un
  echec partiel est explicite et un retry reprend les sources manquantes sans
  duplication. Le scope observe par le detecteur est le meme que celui du
  collecteur. L'issue officier `PROPOSAL_CREATED` ne masque pas un echec et ne
  promet pas une proposition persistante absente.
- **Modules concernes:** `Installation`, `HistoricalBaseline`, `Ledger`,
  `MultiLedger`, `OfficerUI`, guides officier FR/EN et documentation
  d'architecture.
- **Dependances:** Capacite `MAX_EVIDENCE=500`; types et identifiants des sources
  legacy; choix explicite entre ledger actif, primary ou plusieurs ledgers;
  architecture qui interdit un second etat d'installation autoritatif.
- **Risque:** HIGH; un baseline historique peut etre finalise apres une
  collecte partielle et omettre une source de demandes Pre-Dibs.
- **Priorite:** P1.
- **Niveau de confiance:** HIGH sur le sequenceur non atomique et le garde
  `evidenceCount`; le scope multi-ledger attendu et la consequence produit des
  anciennes demandes manquantes restent a confirmer.
- **Avancement 2026-10-19:** Partiellement corrige. Causes confirmees et
  corrigees dans `src/modules/Installation.lua` : manifeste de sources
  attendues, reprise d'un scan partiel, refus d'approuver un baseline
  incomplet, portee de detection alignee sur `guild-primary`, erreur de
  lecture non convertie en source vide, chemin officier fidele. Tests de
  reproduction : `tests/integration/rf0013_partial_legacy_discovery_spec.lua`
  (5 cas, chacun verifie comme discriminant). Restent ouverts et dependent
  d'une decision metier : la limite globale `MAX_EVIDENCE = 500` partagee par
  toutes les sources, et l'objet de proposition que l'Officer doit creer.
- **Tests necessaires:** Exactement 500 transactions valides puis au moins une
  requete Pre-Dibs; echec source 2; retry et presence des deux sources; tests
  d'identifiants/provenance conflictuels; ledger actif different de
  `guild-primary`; tentative d'approbation apres collecte partielle; echec de
  collecte et de proposition dans le chemin officier; erreur de lecture du
  ledger dans `detectRealLegacyData`; reload.
- **Prerequis:** Confirmer quelles sources et quels ledgers appartiennent au
  baseline d'installation, puis decider comment representer une collecte
  complete sans ajouter une copie persistante de l'etat d'autorite.
- **Proposition de perimetre pour Spec Kit:** Une feature centree sur
  completion/reprise du scan historique, sa portee explicite et les diagnostics
  officier/GM. N'inclure aucune modification des transactions ou des regles
  d'approbation du baseline sans besoin etabli.

## P3 - Helper sizeOf RF-0007

- **Identifiant RF:** RF-0007
- **Categorie:** CLEANUP
- **Titre:** Confirmer puis retirer le helper local sans reference
- **Probleme:** `sizeOf` dans Backup est un candidat local non reference dans le
  fichier examine; son inaccessibilite dynamique doit etre confirmee.
- **Comportement attendu:** Aucun helper supprime tant que callbacks, closures,
  hooks ou references indirectes ne sont pas exclus.
- **Modules concernes:** `Backup`, appels indirects et tests backup/import.
- **Dependances:** Recherche complete de references, appels locaux et usages
  captures/dynamiques.
- **Risque:** LOW si l'absence de reference est confirmee; l'audit ne declare pas
  de code mort sur une recherche textuelle seule.
- **Priorite:** P3.
- **Niveau de confiance:** HIGH pour l'absence de reference statique dans la
  surface deja inspectee; conclusion d'inutilite a confirmer.
- **Tests necessaires:** Suite Backup/ImportExport/Profiles et validation de
  l'integrite des exports/restores apres une future suppression approuvee.
- **Prerequis:** Revue complete des appels de Backup et des references indirectes.
- **Proposition de perimetre pour Spec Kit:** Une tache de nettoyage faible
  impact, seulement si cette analyse supplementaire confirme l'inutilite.

## Invariants sans travaux ouverts

- **RF-0003 - MinimapButton.Create:** conserver l'entree indirecte, ses callbacks
  et son bootstrap; aucune suppression proposee.
- **RF-0005 - Sync.lua:** conserver les services encore utilises par SyncV2;
  aucune refonte/suppression de module ne decoule du constat.
- **RF-0011 - SetupAssistant.ExecuteAction:** conserver la delegation a
  ProtectedActions; aucune mutation comptable directe dans l'UI.
- **SECURITY:** aucun nouveau constat de securite n'est retenu par cette revue
  preparatoire. Cela ne vaut pas audit de securite.
- **REFACTOR / MERGE / RENAME:** aucun travail n'est propose a ce stade; les
  equivalences, fusions ou renommages ne sont pas suffisamment demontres.

## Ordre de triage propose

1. ~~RF-0012 - cadrer l'integrite comptable et la convergence V2 avant toute
   reparation automatisee ou autre mutation de correction.~~ **LIVRE** (spec
   026). Il ne reste que la validation Retail du chemin canonique (T041), qui
   est conditionnee par l'ouverture — non faite — du verrou de release.
2. RF-0004 et RF-0010 - fiabilite et visibilite des diagnostics.
3. RF-0008 - coherence du statut actif des profils. **LIVRE** (RF-0018).
4. RF-0001/RF-0002 et RF-0009 - feedback Preferences et restauration.
5. RF-0006 - contrats de types/documentation.
6. RF-0007 - nettoyage conditionnel de faible impact.

Cet ordre est provisoire et ne remplace pas l'approbation d'une feature spec.
