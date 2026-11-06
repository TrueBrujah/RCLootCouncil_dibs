# Bug Assessment: Collecte historique incomplete traitee comme terminee (RF-0013)

- **Slug**: `rf-0013-historical-collection` (fourni par l'utilisateur)
- **Created**: 2026-10-18T15:12:50-04:00
- **Source**: texte fourni dans la demande; aucun URL externe
- **Verdict**: valid
- **Severity**: high
- **Priorite demandee**: P0 — DATA_INTEGRITY
- **Base analysee**: branche `dev`, HEAD `dc388f9`; arbre de travail courant

## Rapport

La demande concerne l'import des anciennes transactions Ledger et demandes
Pre-Dibs dans les preuves de reconciliation historique. Elle signale que les
sources sont collectees et sauvegardees separement, que le retry peut confondre
un premier append avec une collecte terminee, que la detection et la collecte
peuvent viser des ledgers differents, et que certaines erreurs ou actions
officier ne sont pas rapportees fidelement.

L'objectif est de rendre la collecte complete, verifiable et reprenable, sans
modifier les donnees historiques ni declarer une source vide lorsqu'elle n'a
pas ete lue avec succes.

## Symptome

Si la source Ledger est ajoutee, puis que l'ajout de la source Pre-Dibs echoue,
la premiere source reste dans `legacyBaseline`. Au retry, Installation saute
la collecte des qu'une evidence existe; la source absente n'est pas reconnue
comme incomplete et un GM peut ensuite approuver un baseline qui ne la contient
pas. Des retours d'echec du parcours officier peuvent egalement etre presentes
comme un succes.

La collecte ne modifie pas directement les transactions Ledger ni les demandes
Pre-Dibs d'origine: le risque est de figer un baseline d'evidence incomplet,
pas de supprimer ces enregistrements sources.

## Reproduction

1. Dans une fixture neuve, placer exactement 500 transactions valides dans
   `guild-primary`, au moins une demande Pre-Dibs dans ce meme ledger et aucune
   evidence historique preexistante. Appeler `Installation.Initialize` comme
   GM. `CollectEvidence` accepte la source Ledger, puis la source Pre-Dibs
   echoue avec `EVIDENCE_LIMIT_EXCEEDED`, car la limite est globale et vaut
   500. L'initialisation GM retourne alors un echec de stage `legacy`.
2. Verifier qu'il reste 500 evidences et une source `installation-wizard:ledger`,
   mais aucune source `installation-wizard:predibs`. Resoudre les decisions
   necessaires pour les evidences deja presentes, puis relancer l'initialisation.
   `stageLegacyDiscovery` retourne `NO_ACTION_REQUIRED` parce que
   `evidenceCount > 0`; la liste des sources attendues n'est pas comparee.
   `FinalizeBaseline` ne voit aucune source manquante ou marquee
   `complete=false` et peut produire un baseline ne contenant que le Ledger.
3. Refaire le test avec un autre ledger approuve actif contenant les anciennes
   transactions, tandis que `guild-primary` est vide. La detection sans
   `ledgerId` observe le ledger actif; la collecte lit explicitement
   `guild-primary`. Comparer l'etat de detection, les sources du baseline et le
   hash final. Le test existant de collecte indique que la collecte historique
   cible `guild-primary`, meme quand un autre ledger est actif; la portee de
   detection doit donc etre alignee sur cette intention ou un nouveau contrat
   explicite.
4. Dans un test officier, forcer `CollectLocalEvidence` a retourner
   `nil, reason`, puis forcer `MultiLedger.ProposeLedger` a retourner
   `{ ok = false, reasonCode = ... }`. `Installation.Initialize` ignore ces
   resultats et retourne tout de meme `ok=true, reasonCode="PROPOSAL_CREATED"`.
   Le test actuel verifie surtout ce code de retour, pas l'existence d'une
   proposition persistante.

**[NEEDS CLARIFICATION]** Si le volume depasse 500 evidences, la collecte doit-
elle etre paginee/etendue ou l'Officer peut-il demander au GM d'approuver
explicitement un baseline incomplet? Le contrat ne doit pas changer
silencieusement la limite ni omettre des donnees.

## Diagnostic

### Garanties existantes et cause de la collecte partielle

`HistoricalBaseline.CollectEvidence` copie l'etat courant, normalise et valide
une source complete dans cette copie, puis remplace `db.legacyBaseline` si
l'appel reussit. Ainsi, une source individuelle n'est pas ajoutee record par
record en cas d'erreur de validation. Cette garantie ne s'etend pas aux deux
sources de `CollectLocalEvidence`: celle-ci appelle `CollectEvidence` une fois
pour Ledger, puis une seconde fois pour Pre-Dibs. Le premier remplacement est
deja visible si le deuxieme appel echoue.

`MAX_EVIDENCE` vaut 500 au total, et `collectInto` rejette l'ajout qui depasse
ce compte. Le scenario 500 transactions Ledger plus une demande Pre-Dibs
reproduit donc un echec deterministe de la seconde source. Le collecteur ne
marque pas la premiere source comme provisoire et ne cree pas de manifeste
annoncant que la deuxieme est encore attendue.

### Detection incomplete et reprise incorrecte

`Installation.GetStatus` calcule `hasUncollectedEvidence` a partir de
`hasRealLegacyData and evidenceCount == 0`; il ne compare pas les sources
attendues. `stageLegacyDiscovery` s'arrete lorsque `evidenceCount > 0`, meme si
cette evidence vient d'une seule source ou d'un import/recovery different.
`stageBaseline` verifie les findings ouverts, pas que Ledger et Pre-Dibs ont
tous deux ete lus.

`HistoricalBaseline.FinalizeBaseline` sait bloquer une source qui existe avec
`complete=false`, sauf acknowledgement explicite, mais ne peut pas detecter
une source absente de `state.sources`. La projection finale enumere seulement
les sources effectivement enregistrees. Un baseline sans aucune evidence peut
aussi etre construit pour un vrai guild propre; actuellement, le code ne
distingue pas toujours ce cas d'une lecture impossible qui a produit une liste
vide.

Le controle d'incomplete source est donc partiellement utile: la suite de tests
verifie qu'un descripteur present avec `complete=false` bloque normalement la
finalisation et qu'un GM peut explicitement l'accepter. Elle ne couvre pas
l'absence totale du descripteur attendu apres echec de la seconde source. Un
simple boolean d'acknowledgement ne documente par ailleurs ni la source omise
ni la raison de l'exception.

### Erreurs de lecture et sources vides

`Installation.detectRealLegacyData` enveloppe `Ledger.GetAllTransactions()`
dans `pcall`, mais ignore le resultat d'erreur et convertit un retour invalide
en zero transaction. Si aucune evidence Pre-Dibs n'est comptee, une erreur de
lecture peut donc etre traitee comme une installation propre. L'appel
`PreDibs.GetHistory()` dans ce detecteur n'est pas sous `pcall`; une exception
de cette API peut au contraire se propager hors de la projection de statut.

Dans `HistoricalBaseline.CollectLocalEvidence`, les getters sont exprimes avec
des fallbacks `or {}` / `or preDibs.requests or {}`. Une methode absente ou un
retour `nil` peut etre transforme en liste vide; le descripteur de source est
ensuite cree avec `complete=true`. Une exception de `GetAllTransactions`
pendant la collecte n'est pas convertie en resultat structure; un retour
`nil, reason` de `GetHistory` perd son second retour au profit du fallback.
Dans ces cas, le systeme ne distingue pas clairement une lecture reussie vide
d'une source non disponible.

Les validations de `normalizeRecord` protegent les formes non-hashables, les
identifiants absents, les montants/horodatages non finis et certaines
incoherences. Le chemin de collecte locale n'active pas le mode `strict` utilise
pour un recovery package: des champs semantiquement ambigus peuvent etre
conserves comme preuves avec findings plutot que rejetes. Cette distinction
est utile pour l'audit, mais la completude de l'enumeration doit rester separee
de la qualite semantique de chaque record.

### Portee du ledger

`detectRealLegacyData` appelle `Ledger.GetAllTransactions()` et
`PreDibs.GetHistory()` sans identifiant; ces getters utilisent le ledger actif.
`HistoricalBaseline.CollectLocalEvidence`, au contraire, demande explicitement
`guild-primary` pour les deux sources. `MultiLedger.GetActiveLedgerId` peut
retourner le choix actif local ou le ledger impose par la politique de guilde.
La selection de vue de `MultiLedger` est en lecture seule et ne doit pas etre
confondue avec la portee de collecte.

Un test existant change le ledger actif vers un ledger alternatif, puis appelle
`CollectLocalEvidence` et verifie que l'historique Pre-Dibs principal est le
seul qui reste historique dans ce baseline. Cela appuie une portee de collecte
legacy primaire, pas un scan implicite du ledger actif. La detection non
parametree contredit cette portee. Les donnees d'autres ledgers ne doivent pas
etre fusionnees dans le primary sans contrat distinct; si le produit veut les
inclure, chaque ledger doit etre une source explicitement scopee.

### Autorisations et faux succes officier

`Installation.Initialize` verifie que l'acteur est GM ou Officer avant
d'appeler le parcours. `HistoricalBaseline.FinalizeBaseline` exige une
identite GM valide et fraiche; les decisions de reconciliation exigent un
assistant autorise. `MultiLedger.ProposeLedger` verifie `ledger.propose`.
`CollectLocalEvidence` ne modifie pas Ledger/Pre-Dibs et n'accorde pas
d'autorite canonique; son helper `CollectEvidence` verifie l'identite locale,
mais ne demande pas lui-meme `requireAssistant`. Le parcours normal reste
garde par `Installation.Initialize`; le contrat de son API publique directe
doit etre decide si elle est appelee hors de ce parcours.

La branche Officer de `Installation.Initialize` ne verifie toutefois ni le
resultat de `stageLegacyDiscovery` ni celui de `MultiLedger.ProposeLedger` et
retourne `PROPOSAL_CREATED` dans tous les cas. `MultiLedger.GetLedgers` appelle
`ensureLedgers`, qui cree le ledger primaire par defaut; dans l'etat normal,
la condition qui appelle `ProposeLedger("Guild Primary")` est donc deja
satisfaite et aucune proposition n'est creee. Si la proposition est tentee et
refusee, son erreur est ignoree. `OfficerUI.runInstallationAction` presente
ensuite tout resultat avec `ok=true` comme une configuration mise a jour.

Le guide GM/Officer affirme qu'une initialisation par un Officer cree une
proposition de configuration. La specification `021-turnkey-guided-setup` est
encore `Draft`, mais ses scenarios disent qu'un Officer ne doit pas pretendre
qu'une approbation GM a reussi et qu'une action partiellement executee doit
signaler ses echecs. Ces documents soutiennent le besoin de retour fidele; ils
ne resolvent pas quel objet de proposition doit etre persiste.

### Persistance, reprise et donnees sources

La collecte ajoute des copies d'evidence dans `db.legacyBaseline`; elle
n'ajoute, ne supprime et ne reecrit pas de transaction Ledger ni de demande
Pre-Dibs. Les demandes `pending`/`confirmed` sont conservees comme preuves
historiques a reconfirmer, pas relancees comme requetes actives. Ce comportement
doit rester inchange.

Les affectations `Dibs.GetDB().legacyBaseline = staged` sont des mises a jour
de SavedVariables en memoire, pas des transactions DB ou une preuve de flush
durable. Le code ne fournit pas d'atomicite de stockage disque ou de
persistance immediate. `StageRecoveryPackage`/`CommitRecoveryPackage` fournit
neanmoins un prior art utile: validation d'un etat detache complet, controle
de hash, backup de securite, deduplication par hash de package et remplacement
unique de l'etat. Il valide le package entier avant de muter les evidences.

## Chemins de code suspectes

- `src/modules/Installation.lua:65` — `detectRealLegacyData` masque l'echec
  de lecture Ledger dans `pcall` et lit les sources sans portee explicite.
- `src/modules/Installation.lua:96` — `GetStatus` deduit la collecte de
  `evidenceCount == 0`; la presence d'une seule source fait disparaitre
  `hasUncollectedEvidence`.
- `src/modules/Installation.lua:232` — `stageLegacyDiscovery` ne relance pas
  la collecte des qu'une evidence est presente.
- `src/modules/Installation.lua:242` — `stageBaseline` ne verifie pas les
  sources attendues avant finalisation.
- `src/modules/Installation.lua:290` — `Initialize` orchestre le chemin GM;
  sa branche Officer ignore les resultats de collecte et de proposition puis
  retourne `PROPOSAL_CREATED`.
- `src/modules/HistoricalBaseline.lua:14` et `:241` — limite globale de 500
  evidences et validation individuelle de source.
- `src/modules/HistoricalBaseline.lua:370` — copie l'etat courant, applique
  une source, puis remplace les SavedVariables seulement si cette source passe.
- `src/modules/HistoricalBaseline.lua:385` — collecte deux sources en appels
  separes, force `guild-primary` et marque chacune `complete=true`.
- `src/modules/HistoricalBaseline.lua:451` — bloque uniquement les sources
  presentes marquees incompletes; aucune verification de manifeste attendu.
- `src/modules/HistoricalBaseline.lua:494` et `:508` — prior art de recovery
  entierement valide avant remplacement, avec backup et protection de rejeu.
- `src/modules/PreDibs.lua:1420` — `GetHistory(ledgerId)` accepte un ledger
  explicite, mais utilise le ledger actif quand aucun n'est passe.
- `src/modules/MultiLedger.lua:27`, `:128` et `:230` — cree/retourne le ledger
  primaire par defaut, distingue ledger actif et selection de vue.
- `src/modules/MultiLedger.lua:288` — `ProposeLedger` a un resultat
  `ok/reasonCode` sous controle de permission que l'appelant doit verifier.
- `src/ui/OfficerUI.lua:2860` — transforme `result.ok` en message de succes ou
  d'echec visible dans le parcours UI.
- `tests/integration/historical_baseline_recovery_spec.lua:120` — couvre une
  source explicitement incomplete, pas l'absence d'une source attendue.
- `tests/integration/historical_baseline_recovery_spec.lua:140` — couvre
  l'isolation primary/ledger actif pour l'historique Pre-Dibs.
- `tests/integration/installation_wizard_spec.lua:120` — tests du blocage
  `complete=false` et de son acknowledgement explicite.
- `tests/integration/guided_setup_wizard_spec.lua:557` — attend
  `PROPOSAL_CREATED` sans verifier une proposition persistante.
- `docs/code-audit/INDEX.md:447` — fiche RF-0013 et limites connues.
- `docs/code-audit/DEPENDENCIES.md:28` — dependances Installation,
  HistoricalBaseline, MultiLedger et retours UI.
- `docs/code-audit/SPECKIT-BACKLOG.md:232` — perimetre futur propose et tests.

## Cause fondamentale

**Confiance elevee** sur les chemins et les conditions de faux achevement.
**Confiance moyenne** sur le perimetre produit exact au-dela de `guild-primary`
et sur la frequence des exceptions de lecture en client Retail.

Le processus n'a pas de manifeste de collecte exprimant les sources attendues
et l'etat de chacune. La persistance par source est localement prudente, mais
l'orchestrateur suppose a tort que toute evidence implique que la collecte
complete est terminee. Une source absente n'est pas representee par
`complete=false`; le retry s'arrete sur le nombre global d'evidences et le
baseline n'a aucun moyen de detecter l'omission. Le detecteur de donnees
utilise en plus un autre scope et peut convertir une erreur de lecture en
"aucune donnee".

Dans le chemin Officer, la propagation des resultats est une cause independante
de faux succes: une preparation partiellement echouee n'empeche pas le code de
retourner `ok=true`.

## Proposition de remediation

**Approche recommandee: un manifeste de collecte dans `HistoricalBaseline`,
avec source-scope explicite, validation detached et complétion verifiable.**

1. Definir un run de collecte versionne et guild-scoped dans l'etat deja
   possede par `HistoricalBaseline`, pas un second registre autoritatif dans
   Installation. Pour le scan legacy actuel, le manifeste doit nommer
   explicitement `LEDGER_TRANSACTION` et `PREDIB_REQUEST` sur `guild-primary`;
   cette portee correspond au collecteur et au test existants.
2. Pour chaque source, enregistrer un etat tel que `PENDING`, `COMPLETE`,
   `FAILED` ou `OUT_OF_SCOPE`, son `ledgerId`, type, sourceClient/version,
   compte de records, hash deterministe du snapshot, et code d'erreur. Une
   source vide n'est `COMPLETE` que si son getter a reussi et que le snapshot
   valide contient zero record. L'absence d'un descripteur n'equivaut jamais a
   une source vide.
3. Lire toutes les sources attendues avec retour d'erreur explicite et valider
   le type de chaque resultat. Ne pas remplacer un getter absent, un `nil` ou
   une exception par `{}`. Si `pcall` est necessaire autour d'une API, convertir
   son echec en `READ_FAILED` conserve et visible; ne pas supprimer la cause.
   Valider les identifiants et hashes source par source; conserver les records
   semantiquement ambigus comme findings reviewables lorsque possible, sans les
   declarer absents.
4. Construire le nouveau lot dans un etat detache, puis valider ensemble les
   sources requises, les limites et l'absence de conflits avant de le publier.
   Reutiliser le pattern `StageRecoveryPackage`/`CommitRecoveryPackage` pour
   preparer l'etat complet et faire un remplacement unique des SavedVariables
   en memoire. Ce n'est pas une garantie de flush disque atomique; le statut
   doit rester revalidable apres reload.
5. Conserver un identifiant stable de run et des identites deterministes
   d'evidence. Au retry, comparer compte/hash de chaque source, completer les
   sources manquantes sans dupliquer les evidences identiques, et marquer un
   conflit si une source deja achevee a change. Ne pas reinterpretrer un ancien
   evidence count comme un marqueur de complétion.
6. Faire dependre `GetStatus`, `stageLegacyDiscovery`, `stageBaseline` et
   `FinalizeBaseline` du manifeste: la collecte est complete uniquement quand
   chaque source requise a un snapshot valide et que compte/hash concordent.
   Une erreur de lecture ou source absente doit etre un blocage, pas une
   installation `CLEAN` ni une simple indication de succes.
7. Enregistrer aussi un scan reussi de sources vides. Un baseline genesis vide
   reste possible pour une guilde propre, mais seulement apres avoir confirme
   la lecture reussie de chaque source de son scope.
8. Garder une exception de baseline incomplet uniquement si le produit la
   confirme: acknowledgement GM explicite, sources omises listees, raison
   conservee dans l'audit, et avertissement visible. Le boolean actuel ne
   suffit pas a expliquer pourquoi l'omission est acceptee.
9. Aligner detection et collecte sur le meme scope. Pour le scan actuel,
   l'implementation et le test existants pointent vers `guild-primary`;
   detector et collecteur doivent donc lire ce ledger. Tout besoin d'inclure
   les autres ledgers approuves doit etre un scan separe ou un manifeste
   multi-ledger dont chaque entree porte son `ledgerId`; ne pas fusionner des
   historiques par defaut.
10. Dans le parcours Officer, propager tout echec de `stageLegacyDiscovery` et
    toute erreur de proposition. Ne retourner `PROPOSAL_CREATED` que si
    l'objet attendu existe reellement; sinon afficher la preparation achevee
    et l'approbation GM encore necessaire. La proposition de setup ne doit pas
    inventer un nouvel etat persistant concurrent a Governance/MultiLedger.
11. Garder les controles existants: GM/Officer verifie pour l'initialisation,
    GM verifie pour finaliser le baseline, assistant verifie pour decider les
    evidences et permission `ledger.propose` pour une proposition. Clarifier si
    l'API publique `CollectLocalEvidence` doit elle-meme exiger un Officer,
    sachant qu'elle ne change que les evidences locales et que le parcours
    `Installation.Initialize` est deja protege.

Pour les donnees au-dela de `MAX_EVIDENCE=500`, le systeme doit renvoyer un
blocage explicite avec compte attendu/limite et ne rien declarer complet. Une
pagination/collecte bornee peut etre une solution future; une hausse de limite
exige validation memoire/performance. Ne pas contourner le garde en tronquant
ou en oubliant une source.

### Alternatives

- **Faire seulement passer `evidenceCount > 0` a une comparaison de
  `complete=false`**: insuffisant. La source manquante n'existe pas dans
  `state.sources`, et un compteur ne specifie pas le lot attendu.
- **Relancer systematiquement `CollectLocalEvidence` si une source manque**:
  meilleur retry, mais ne suffit pas sans identifiant de run, hash de source,
  erreur explicite et controle de la limite. Une source modifiee pourrait
  sinon s'ajouter silencieusement au meme scan.
- **Persister chaque source progressivement avec curseur**: utile si la
  volumetrie depasse 500, mais exige idempotence par lot, journal de progression
  et recovery apres reload. Ne pas mettre en place avant d'avoir defini
  l'exigence de snapshot et la limite supportee.
- **Un seul lot detached suivi d'un remplacement SavedVariables**: prefere
  pour la version initiale tant que le lot complet tient dans la capacite. Il
  evite l'etat partiel en memoire mais ne garantit pas une sauvegarde disque
  durable contre une interruption arbitraire.

## Compatibilite et impact sur les donnees historiques

- La collecte courante est additive: elle copie les transactions et requetes
  d'origine dans les evidences. Garder cette propriete; ne jamais modifier,
  supprimer, migrer ou re-activer les objets Ledger/Pre-Dibs sources pendant
  l'assessment ou une future collecte.
- Les requetes Pre-Dibs `pending`/`confirmed` restent des evidences
  historiques a reconfirmer et ne sont pas reinstallees comme requetes actives.
- Ne pas supprimer un baseline approuve, changer son `legacyBaselineHash` ou
  changer une reference de Governance automatiquement. Les nouvelles donnees
  source doivent passer par une version/schema additive et les migrations
  doivent conserver tous les champs et l'historique d'audit.
- Pour un etat connu du nouveau schema sans manifestation complete, reprendre
  les sources manquantes en dedupliquant par evidence ID et hash de record.
  Si la source primaire deja enregistree differe de la source relue, produire
  un finding/conflit et exiger une decision plutot que remplacer l'ancienne
  preuve.
- Pour les anciens etats sans manifeste: une paire telle que
  `installation-wizard:ledger` et `installation-wizard:predibs` permet de
  reconnaitre certains runs. Une seule source de cette paire est une forte
  indication de collecte partielle; une evidence issue d'un import ou d'un
  recovery different ne prouve pas que le scan local est termine.
- Un baseline deja approuve sans manifeste ne permet pas de savoir si la
  source etait vide ou jamais lue. Le classer `coverage_unknown` pour
  diagnostic, sans annuler la gouvernance ni reconstruire automatiquement le
  hash. Une nouvelle reconciliation complete doit etre une action explicite
  et auditee.
- Les sources de ledgers autres que `guild-primary` ne doivent pas etre
  melangees a ce baseline sans decision explicite. Le guide multi-ledger et le
  test de collecte indiquent que les historiques sont scopes et ne doivent
  pas etre fusionnes implicitement.

## Plan de reprise et migration

1. Lire l'etat existant sans mutation et classifier:
   - les deux sources attendues presentes et completes;
   - source Ledger presente, source Pre-Dibs absente;
   - source Pre-Dibs presente, source Ledger absente;
   - run hors schema/ambigu;
   - baseline deja approuve sans preuve de couverture.
2. Migrer de facon additive vers un manifeste de run. Pour les anciennes paires
   de sources identifiables, conserver les evidences et ajouter une indication
   de couverture deduite avec niveau de confiance; ne jamais inventer un hash
   ou des records pour une source absente.
3. Rescanner uniquement les sources manquantes dans le meme scope explicite.
   Pour les identifiants deja observes, comparer le contenu et dedupliquer les
   records identiques; divergence de contenu = finding, pas remplacement.
4. Si le scan complet depasse la limite, rester en etat incomplet et proposer
   l'action de reconciliation approuvee pour ce volume. Ne pas approuver par
   defaut un sous-ensemble.
5. Pour un baseline approuve ancien dont la couverture est inconnue, presenter
   les preuves et demander une decision GM sur le maintien ou une reconciliation
   gouvernee. Conserver l'ancien baseline et son hash tant que cette decision
   n'a pas ete prise.
6. Auditer la transition: run ID, scopes/ledgers, sources, comptes, hashes,
   erreurs, acteur, decisions et eventuel acknowledgement d'incompletude.
   Verifier qu'une restauration de backup garde ce manifeste et les anciennes
   preuves.

## Fichiers applicatifs potentiellement concernes

- `src/modules/HistoricalBaseline.lua` — manifeste, lecture/validation des
  sources, staging detached, reprise, completion et finalisation.
- `src/modules/Installation.lua` — detection en erreur explicite, statut
  base sur le manifeste, retry des sources manquantes et propagation des
  resultats GM/Officer.
- `src/modules/Ledger.lua` — uniquement pour garantir les retours et scopes de
  lecture utilises par le scan; aucune modification des transactions.
- `src/modules/PreDibs.lua` — retour source/ledger explicite et distinction
  entre historique vide et lecture indisponible.
- `src/modules/MultiLedger.lua` — resolution documentee du ledger source;
  ne pas fusionner des historiques distincts.
- `src/modules/Permissions.lua` et `src/modules/ProtectedActions.lua` —
  seulement si le futur flux ajoute une commande protegee; les controles
  directs existants d'Installation et `ledger.propose` doivent etre conserves.
- `src/ui/OfficerUI.lua` et `src/ui/SetupAssistant.lua` — exposer les sources
  manquantes, limites et echecs; ne pas afficher un succes global faux.
- `src/locales/` et documentation de setup/officier/SavedVariables —
  expliquer les statuts, l'exception explicite d'incompletude et le scope.
- Tests candidats: `tests/integration/historical_baseline_recovery_spec.lua`,
  `tests/integration/installation_wizard_spec.lua`,
  `tests/integration/guided_setup_wizard_spec.lua`,
  `tests/unit/multi_ledger_spec.lua` et un test de lecture/collecte Pre-Dibs.

## Tests requis

Chaque assertion doit verifier les sources, leur provenance, comptes/hashes,
les SavedVariables avant/apres, le statut d'installation et l'eventuel
baseline; une assertion `not error` seule ne suffit pas.

1. **Collecte complete** — deux sources attendues completees, comptes et hashes
   exacts, snapshot present dans le baseline apres decisions.
2. **Collecte Ledger en echec** — erreur/retour invalide rend le run `FAILED`
   ou `UNKNOWN`; aucune source vide artificielle, aucun baseline approuvable.
3. **Ledger reussi, Pre-Dibs echoue** — conserver ou rejeter le lot entier selon
   le contrat choisi, mais toujours marquer le run incomplet; aucun faux
   `complete=true` pour Pre-Dibs.
4. **Retry apres echec partiel** — reprend seulement les sources manquantes,
   conserve les donnees precedentes, ne cree aucun doublon et ne finalise
   jamais avant completion.
5. **Sources historiques absentes** — differencier getter reussi avec liste
   vide (source complete, compte 0) de getter absent, retour `nil`, erreur ou
   API indisponible (source incomplete/erreur).
6. **Sources corrompues** — tester record non-table, ID absent/duplique,
   structure trop profonde, hash impossible, montant/horodatage invalide et
   identite ambigue; aucune evidence partielle perdue, finding ou erreur
   explicite selon la politique.
7. **Echec d'action officier** — retour d'echec de collecte et refus/erreur de
   `ProposeLedger` sont visibles; le caller n'obtient pas un faux
   `PROPOSAL_CREATED`. Verifier le cas normal ou le ledger primaire existe
   deja.
8. **Ledger actif different de guild-primary** — detection et collecte ont un
   scope identique et documente; tester primary non vide/active vide, active
   non vide/primary vide, et deux ledgers non vides. Aucun melange implicite.
9. **Rechargement** — serialiser/recharger les SavedVariables apres chaque
   frontiere de collecte; conserver le manifeste incomplet et reprendre sans
   doublon. Distinguer ce test de la garantie de flush disque immediate.
10. **Reexecution d'une collecte complete** — meme run/snapshots = replay
    idempotent, meme hash et memes IDs; source changee = conflit ou nouveau
    run audite, jamais ajout silencieux au baseline approuve.
11. **Preservation des donnees** — comparer Ledger et Pre-Dibs avant/apres:
    contenu et IDs originaux identiques, demandes historiques non reactivees,
    preuves ajoutees non destructives.
12. **Limite de 500** — 500 transactions Ledger puis au moins une demande
    Pre-Dibs donnent un statut explicite de limite et jamais `COMPLETE`.
    Verifier la decision choisie pour pagination, hausse borne ou acknowledgement
    GM documente.
13. **Finalisation** — sources manquantes/inconnues bloquent baseline; seules
    des sources prouvees vides permettent un baseline genesis vide. Si
    incomplete acknowledgement est garde, raison et sources omises doivent
    etre consignees.
14. **Autorite** — non-officier refuse l'initialisation; Officer peut preparer
    uniquement ce qui lui est autorise; la finalisation exige GM frais;
    reception/apply de baseline ne fait pas confiance a un role declare dans
    une payload.

## Criteres d'acceptation verifiables

- Le manifeste declare toutes les sources requises pour son scope, ledger et
  type inclus; source absente et source lue vide sont deux etats differents.
- Un run n'est complete que si chaque source requise a ete lue, validee,
  comptee et hashée avec succes. Un echec de lecture n'est jamais un compte 0.
- Echec de la source 1 ou 2, erreur de deserialisation, limite ou retry ne peut
  produire un baseline declare complet sans acknowledgement explicite et
  auditee.
- `Installation.GetStatus` et les boutons d'initialisation signalent
  `INCOMPLETE`, `READ_FAILED`, `SCOPE_MISMATCH` ou la limite plutot que `CLEAN`
  ou succes.
- Relancer une source identique ne change ni le nombre d'evidences ni le hash;
  changement d'un snapshot deja termine est rejete comme conflit ou cree un
  run explicitement distinct.
- Detection et collecte utilisent le meme scope. Avec le contrat actuel,
  `guild-primary` est collecte; tout autre ledger est hors scope signale ou
  une source explicite, jamais un remplacement tacite.
- Les operations GM/Officer verifient leurs autorisations au point d'execution
  et les erreurs/reponses de proposition sont transmises sans success-shaped
  fallback.
- Les donnees Ledger et Pre-Dibs d'origine restent strictement identiques et
  les demandes historiques ne sont pas reactives.
- La documentation et les tests ne promettent pas une atomicite de stockage ou
  persistance immediate que SavedVariables ne fournissent pas.

## Risques et considerations

- La limite globale `MAX_EVIDENCE=500` peut rendre impossible une collecte
  complete si les deux sources depassent ensemble la limite; changer cette
  limite a des couts memoire/performance et necessite une mesure.
- Un descripteur de source marque `complete=true` sans manifeste ni contenu
  verifie peut donner un faux sentiment de couverture; conserver compte/hash
  et statut comme valeurs distinctes.
- Une migration d'un baseline deja approuve peut modifier son hash ou
  l'attachement de l'autorite; aucune reecriture automatique n'est sure.
- Scope primary-only est fortement indique par l'implementation et le test
  existant, mais les ledgers supplementaires doivent etre explicitement
  signales si le produit veut une reconciliation guild-wide.
- La lecture locale de demandes Pre-Dibs et de transactions est soumise aux
  changements de donnees entre retries; un run doit identifier le snapshot et
  signaler les differences.
- L'API `CollectLocalEvidence` ne requiert pas elle-meme un role assistant dans
  son `localSnapshot`; son usage interne est actuellement sous le gate de
  `Installation.Initialize`. Clarifier avant d'elargir ses callers, sans
  presenter cette collecte locale comme une mutation comptable.
- L'evaluation confirme les chemins de code, mais ne reproduit pas une panne
  Retail de getter; utiliser des doubles/fault injection puis des scenarios
  multiclients distincts.
- Aucune bibliotheque tierce n'est une cible de modification. Tous les
  repertoires `libs` restent strictement en lecture seule pour toute
  implementation future.

## Conditions necessaires avant implementation

1. Approuver la portee source/ledger: primary legacy seulement ou tous les
   ledgers approuves, et traitement explicite des autres histories.
2. Fixer la politique de capacite au-dela de 500 et determiner si un GM peut
   approuver une incompletude; si oui, exiger raison, sources omises et audit.
3. Definir le manifeste et la migration des etats partiels/anciens baselines
   sans supprimer ou rehash les preuves ni l'autorite existante.
4. Fixer le contrat de `PROPOSAL_CREATED`: quel objet existe, quelle permission
   l'accepte et quel resultat est presente lorsqu'aucune proposition n'a ete
   creee.
5. Reproduire via fault injection les erreurs de getter, second source,
   capacity et operation officier; valider la reprise apres rechargement.
6. Implementer seulement apres approbation d'une feature Spec Kit et de ses
   criteres. Cette assessment ne lance ni `speckit-bug-fix` ni un refactoring.

## Questions ouvertes

- **[NEEDS CLARIFICATION]** Le baseline initial doit-il porter uniquement sur
  `guild-primary`, comme l'implementation et le test actuel l'indiquent, ou sur
  chaque ledger approuve? Recommandation: garder primary comme source de
  migration legacy et enumerer separement tout ledger supplementaire.
- **[NEEDS CLARIFICATION]** Comment traiter un inventaire de plus de 500
  evidences: collecte paginee, limite augmentee et mesuree, ou acknowledgement
  GM explicite d'un baseline incomplet?
- **[NEEDS CLARIFICATION]** Une source historique structurellement corrompue
  doit-elle toujours bloquer, ou un GM peut-il l'exclure apres un finding et
  une raison auditables?
- **[NEEDS CLARIFICATION]** Quel est l'objet reel attendu par le message
  `PROPOSAL_CREATED` et ou sa persistance est-elle autoritative? Le test actuel
  verifie le code retour, pas l'objet.
- **[NEEDS CLARIFICATION]** Les anciennes guildes avec baseline approuve mais
  sans manifeste doivent-elles rester operationnelles avec un avertissement
  `coverage_unknown`, ou exiger une reconciliation GM avant toute prochaine
  activation?
- **[NEEDS CLARIFICATION]** La methode publique `CollectLocalEvidence` doit-elle
  imposer explicitement l'autorite Officer/GM, ou rester une collecte locale
  non autoritative appelable apres validation d'identite?
