# RF-0013 — Decisions metier en attente

Statut : **DECIDED AND IMPLEMENTED (session 15, 2026-10-21)**

> **Historique.** Ce dossier presentait les deux sujets comme des
> decisions en attente. Les options **A1** (collecte paginee) et **B1**
> (proposition officier via `MultiLedger.ProposeLedger`) ont ete
> approuvees et implementees le 2026-10-21. RF-0013 est passe a
> `FIXED`. La specification finale qui a servi de base est
> `RF-0013-FINAL-SPECIFICATION.md` ; l'implementation et ses tests
> sont decrits dans `docs/code-audit/INDEX.md#rf-0013`.
>
> Les sections ci-dessous sont conservees telles quelles : elles
> documentent l'etat **anterieur** a la decision et les consequences
> mesurees qui l'ont fondee.

Les cinq causes techniques de RF-0013 sont corrigees et validees
(`src/modules/Installation.lua`, tests dans
`tests/integration/rf0013_partial_legacy_discovery_spec.lua`). Les deux sujets
ci-dessous ne peuvent pas etre tranches par le code seul : ils changent le
comportement attendu du produit. Ils sont documentes ici avec des options
realistes et des consequences mesurees, sans decision unilaterale.

---

## A. Limite globale de preuves `MAX_EVIDENCE = 500`

### Etat reel du code

`src/modules/HistoricalBaseline.lua:14` :

```lua
local SCHEMA, MAX_EVIDENCE, MAX_SOURCES, MAX_DECISIONS, MAX_AUDIT, MAX_DEPTH = 1, 500, 50, 500, 50, 8
```

La limite est **globale** : elle couvre toutes les sources ensemble.
`collectInto` (ligne 256) refuse la collection entiere si le total
depasserait 500 :

```lua
if count(state.evidence) + newCount > MAX_EVIDENCE then return nil, "EVIDENCE_LIMIT_EXCEEDED" end
```

`CollectLocalEvidence` appelle `CollectEvidence` deux fois, une par source
(ledger, puis Pre-Dibs). Chaque appel persiste independamment sa copie d'etat.
Consequence exacte, confirmee par la reproduction de l'assessment :

- une guilde avec **500 transactions ledger** et **au moins une demande
  Pre-Dibs** voit la premiere source passer a 500, puis la seconde echouer
  avec `EVIDENCE_LIMIT_EXCEEDED` ;
- la source ledger reste persistee, la source Pre-Dibs est absente ;
- **avant le correctif RF-0013**, ce etat etait invisible : le scan etait
  declare termine et un baseline pouvait etre approuve sans les Pre-Dibs.

### Ce qui est deja corrige

- Le scan est **repris** tant qu'une source manque
  (`LEGACY_EVIDENCE_SCAN_INCOMPLETE:<sources>`).
- `Installation.GetStatus` expose `legacy.missingScanSources` et pose le
  bloqueur `LEGACY_EVIDENCE_SCAN_REQUIRED` dans tous les etats.
- `stageBaseline` **refuse** d'approuver un baseline tant qu'une source qui
  contient des donnees n'a pas ete collectee.
- Une source **illisible** est signalee, jamais traitee comme vide.

La regle « une collecte tronquee n'est jamais une collecte complete » est donc
desormais appliquee par le code. Ce qui manque est la **politique** face a un
volume superieur a la limite.

### Options realistes

| Option | Principe | Consequences | Risque |
|---|---|---|---|
| **A1 — Pagination de la collecte** | La collecte lit par lots de N et le GM relance jusqu'a epuisement. | Necessite un etat de progression persistant (offset par source), une reprise sur crash et une UI de progression. Le baseline ne peut etre approuve qu'a epuisement. | Effort important. Modifie le contrat de `CollectEvidence`. Une pagination mal reprise peut rejouer ou perdre un lot. |
| **A2 — Limite par source** | Chaque source dispose de sa propre limite (par exemple 500 ledger + 500 Pre-Dibs), le total restant borne. | Une seule ligne a changer. Une source peut donc depasser 500, donc la memoire SavedVariables augmente. | Le total n'est plus borne, donc la memoire n'est plus garantie. Le nom `MAX_EVIDENCE` devient trompeur. |
| **A3 — Augmentation de la limite globale** | Passer `MAX_EVIDENCE` a une valeur superieure. | Une seule ligne a changer. | **Aucune garantie de memoire.** Une tres grande guilde peut faire depasser la limite de taille de SavedVariables, ce qui corrompt la sauvegarde. Ne pas faire. |
| **A4 — Approbation explicite d'un baseline partiel** | Le GM peut approuver en connaissance de cause un baseline qui declare la source omise. | Necessite une portee d'acknowledgement qui nomme la source et la raison, comme `acknowledgeIncompleteEvidence` le fait deja pour les sources incompletes. | Un baseline partiel approuve devient un historique incomplet. Acceptable seulement si l'omission est **enregistree et visible**, jamais silencieuse. |
| **A5 — Refus explicite, sans approbation** | La collecte refuse au-dela de la limite et le GM doit exporter, traiter hors ligne, puis reimporter par lot. | Aucun baseline partiel. Mais aucune voie de sortie dans l'outil. | Un guild volumineux ne peut pas etre migre du tout. |

### Recommandation

**A1 (pagination)** est la seule option qui ne degrade ni l'exhaustivite ni la
garantie de memoire, et la seule qui evite d'approuver un historique
incomplet. **A2** est acceptable comme amelioration intermediaire si la
pagination est differee, a condition que le total reste borne par une somme
fixe de limites par source. **A3** est a ecarter : elle ne fait que deplacer la
limite vers un defaut plus grave. **A4** ne doit exister qu'en complement,
jamais seule, et doit enregistrer la source omise. **A5** seule ne laisse pas
de voie de sortie.

### Preuve attendue apres decision

Un test qui cree exactement `MAX_EVIDENCE` transactions ledger **et** au moins
une demande Pre-Dibs, puis exige soit une collecte complete et paginee, soit
un refus nomme et repris, avec un baseline approuve contenant **toutes** les
sources, ou un refus explicite d'approbation.

---

## B. Proposition de correction par un officier

### Etat reel du code

`Installation.Initialize` (branche officier non GM) :

- appelle `stageLegacyDiscovery(actor)` ;
- si le ledger primaire manque, appelle `MultiLedger.ProposeLedger(actor, "Guild Primary")` ;
- renvoyait `ok = true, reasonCode = "PROPOSAL_CREATED"` **sans lire aucun
  des deux resultats**.

**Corrige** : les deux resultats sont lus. Un echec de decouverte est
propage (`LEGACY_EVIDENCE_SCAN_INCOMPLETE:...`), et l'absence de proposition
verifiable est propagee (`LEDGER_PROPOSAL_NOT_CREATED`). Le code ne pretend
plus avoir cree une proposition inexistante.

### Ce qui reste a decider

La forme exacte de l'objet de proposition. Les options ci-dessous sont
conformes a l'architecture existante ; aucune n'introduit un second registre
comptable ni un second proprietaire des intentions.

| Option | Forme de la proposition | Consequences |
|---|---|---|
| **B1 — Proposition `MultiLedger` existante** | L'officier cree une proposition de ledger via `MultiLedger.ProposeLedger`, avec un statut `PROPOSED`, que le GM approuve ensuite. | Reutilise le contrat existant, la validation de nom et la permission `ledger.propose` deja presents. **Aucun index de propositions n'existe** : une proposition est un `db.ledgers[ledgerId]` au statut `PROPOSED`, et rien n'empeche deux propositions de meme nom de coexister (verifie en session 14 : deux propositions « Guild Primary » sont acceptees, sans contexte, et restent indistinguables). B1 doit donc **creer** l'index de propositions et la garde anti-duplicat, en plus de porter le perimetre, le volume, le motif et les sources illisibles. Specification complete : `RF-0013-FINAL-SPECIFICATION.md`. |
| **B2 — Proposition Governance de canal** | L'officier cree une proposition Governance de type "configuration de guilde", que le GM approuve. | Aligne l'officier sur le meme mecanisme que les corrections. Mais Governance ne gere pas aujourd'hui ce type de proposition, et l'ajouter releve d'un nouveau contrat. |
| **B3 — Aucune proposition par l'officier** | L'officier ne fait que verifier l'etat et le GM effectue toute la configuration. | Le plus simple et le plus sur. Mais retire une capacite de l'officier et contredit les guides qui annoncent une proposition. |

### Recommandation

**B1** est la seule option qui ne demande aucun nouveau contrat : la
proposition de ledger existe deja, elle est persistante, elle est verifiable,
et elle porte un statut explicite. **B2** introduirait un type de proposition
Governance absent et donc un second chemin d'intention. **B3** est la plus
sure mais retire une capacite documentee.

Dans tous les cas, le code ne doit **jamais** renvoyer `PROPOSAL_CREATED` sans
objet de proposition reellement persiste. Cette regle est deja appliquee par
le correctif et doit etre preservee.

### Preuve attendue apres decision

Un test qui verifie qu'apres une initialisation par un officier, l'objet de
proposition existe dans le magasin attendu, porte le statut attendu, et que
`Installation.GetStatus` et l'interface reflètent cet etat. Un test qui
verifie qu'un echec de proposition est propage et non presente comme un
succes.

---

## Ce qui n'est pas bloque

Ces deux decisions ne bloquent aucun travail independant :

- la reprise d'un scan partiel est implementee et testee ;
- le signalement par source est implemente et teste ;
- le refus d'approuver un baseline incomplet est implemente et teste ;
- le chemin officier est fidele et teste ;
- la portee de detection et les erreurs de lecture sont corrigees et testees.

RF-0013 reste `PARTIALLY_FIXED` tant que A et B ne sont pas tranches, mais
aucune autre cause racine n'est ouverte.

---

## Verification des premises (session 12, 2026-10-21)

Les faits decrits ci-dessus ont ete **re-verifies contre le code actuel**,
et non repris du dossier d'origine. Chaque affirmation porte sur une ligne
de code precise.

### A — la limite est toujours globale

| Element | Valeur verifiee | Emplacement |
|---|---|---|
| Declaration | `local SCHEMA, MAX_EVIDENCE, MAX_SOURCES, MAX_DECISIONS, MAX_AUDIT, MAX_DEPTH = 1, 500, 50, 500, 50, 8` | `src/modules/HistoricalBaseline.lua:14` |
| Refus de collecte | `if count(state.evidence) + newCount > MAX_EVIDENCE then return nil, "EVIDENCE_LIMIT_EXCEEDED" end` | `src/modules/HistoricalBaseline.lua:256` |
| Reprise du scan | `LEGACY_EVIDENCE_SCAN_INCOMPLETE:` .. `table.concat(stillMissing, ",")` | `src/modules/Installation.lua:323` |
| Refus de baseliner | `if #missing > 0 then return false, "LEGACY_EVIDENCE_SCAN_INCOMPLETE:" .. table.concat(missing, ",") end` | `src/modules/Installation.lua:339` |

**La decision A reste entiere et non tranchee.** La limite est bien globale
et le refus de collecte est bien present ; seule la **politique** face a un
volume superieur manque.

### B — le chemin de proposition existe et est verifiable

| Element | Valeur verifiee | Emplacement |
|---|---|---|
| Permission | `Dibs.Permissions.Evaluate("ledger.propose", actor)` | `src/modules/MultiLedger.lua:511` |
| Creation | `db.ledgers[ledgerId] = { ... status = "PROPOSED", ... }` puis `return { ok = true, ledgerId = ledgerId }` | `src/modules/MultiLedger.lua:507-540` |
| Approbation | `MultiLedger.ApproveLedger` refuse un ledger qui n'est pas `PROPOSED`, appelle `Dibs.Governance.RecordLedgerApproval(actor, ledgerId, ledger.name)`, puis passe le ledger a `APPROVED` | `src/modules/MultiLedger.lua:542+` |
| Lecture des resultats | `local proposed = Dibs.MultiLedger.ProposeLedger(actor, "Guild Primary")` | `src/modules/Installation.lua:409` |
| Refus propage | `return { ok = false, stage = "ledger", reasonCode = "LEDGER_PROPOSAL_NOT_CREATED", ... }` | `src/modules/Installation.lua:419` |
| Restitution | `return { ok = true, reasonCode = "PROPOSAL_CREATED", status = Installation.GetStatus(actor) }` — atteint **uniquement** si la proposition a ete reellement creee | `src/modules/Installation.lua:421` |

**Le chemin B1 existe donc integralement** : une proposition persistante,
un statut explicite `PROPOSED`, une permission dediee `ledger.propose`,
une approbation par le GM (`ledger.approve`) et une trace d'audit via
`Governance.RecordLedgerApproval`. La precondition de l'option B1 est
**verifiee**, pas supposee.

Le garde-fou « ne jamais renvoyer `PROPOSAL_CREATED` sans objet persiste »
est en place et doit etre preserve : c'est la seule partie de la decision
B qui ne depend pas d'un arbitrage metier.

### Preuve attendue apres decision

- **A** : un test qui cree exactement `MAX_EVIDENCE` transactions ledger
  **et** au moins une demande Pre-Dibs, puis exige soit une collecte
  complete et paginee, soit un refus nomme et repris, avec un baseline
  approuve contenant **toutes** les sources, ou un refus explicite
  d'approbation.
- **B** : un test qui verifie qu'apres une initialisation par un officier,
  l'objet de proposition existe dans le magasin attendu, porte le statut
  `PROPOSED`, que l'approbation GM le fait passer a `APPROVED` avec une
  trace d'audit, et qu'un echec de proposition est propage et non presente
  comme un succes.
