# RF-0013 — Plan technique final (A1 et B1)

Statut : **PREPARED — NOT IMPLEMENTED**

Ce document prepare les deux decisions metier de RF-0013 pour approbation.
Il ne contient **aucune modification de production**. Les deux choix
(A1 et B1) sont *proposes* ; ils ne sont pas *decides*. Le code n'a pas
ete touche.

Les faits cites ici ont ete **verifies dans le code actuel** le
2026-10-21. Chaque affirmation porte sur une ligne precise.

---

## A1 — Collecte historique paginee

### A.1 Etat reel verifie

| Element | Valeur verifiee | Emplacement |
|---|---|---|
| Limite globale | `MAX_EVIDENCE = 500` (toutes sources ensemble) | `HistoricalBaseline.lua:14` |
| Refus de collecte | `if count(state.evidence) + newCount > MAX_EVIDENCE then return nil, "EVIDENCE_LIMIT_EXCEEDED" end` | `HistoricalBaseline.lua:256` |
| Sources multiples | `MAX_SOURCES = 50` | `HistoricalBaseline.lua:14` |
| Entree de collecte | `M.CollectEvidence(actor, source, records)` persiste a chaque appel | `HistoricalBaseline.lua:370` |
| Collecte locale | `M.CollectLocalEvidence` appelle `CollectEvidence` **deux fois** : ledger, puis Pre-Dibs | `HistoricalBaseline.lua:385-408` |
| Tri des enregistrements | `table.sort(ledgerRecords, ...)` puis `table.sort(requestRecords, ...)` par `originalId` | `HistoricalBaseline.lua:398-399` |
| Reprise du scan | `LEGACY_EVIDENCE_SCAN_INCOMPLETE:` .. `table.concat(stillMissing, ",")` | `Installation.lua:323` |
| Refus de baseliner | `if #missing > 0 then return false, "LEGACY_EVIDENCE_SCAN_INCOMPLETE:" ... end` | `Installation.lua:339` |
| Approbation d'un baseline incomplet | `options.acknowledgeIncompleteEvidence ~= true` → `INCOMPLETE_EVIDENCE_ACKNOWLEDGEMENT_REQUIRED` | `HistoricalBaseline.lua:457` |
| Source declaree complete | `complete = true` sur les deux sources de la collecte locale | `HistoricalBaseline.lua:401-405` |

### A.2 Le defaut, precise

`MAX_EVIDENCE` est **global**. La collecte locale est sequentielle :

1. `CollectEvidence(ledger)` — jusqu'a 500 preuves, **reussit** ;
2. `CollectEvidence(predibs)` — `500 + n > 500` → **`EVIDENCE_LIMIT_EXCEEDED`**,
   la source Pre-Dibs est **absente**.

Le scan est alors **incomplet** et la reprise est refusee par
`LEGACY_EVIDENCE_SCAN_INCOMPLETE:predibs`. La source ledger, elle, **est**
persistee. L'etat est coherent mais **incomplet**, et la reprise **echoue
de la meme facon** a chaque appel : la collecte est un tout-ou-rien par
source, sans progression.

C'est le point exact que A1 doit traiter : la limite est **par source**,
mais la collecte est **par source entiere**.

### A.3 Plan d'implementation propose (A1)

**Principe.** Une source peut depasser `MAX_EVIDENCE` a condition que
le **total** reste borne. La collecte se fait par lots, et la progression
est persistee pour reprendre apres un crash.

**Etape 1 — rendre la limite par source et non globale.**

| Parametre | Valeur | Justification |
|---|---|---|
| `MAX_EVIDENCE_PER_SOURCE` | 500 | Une source peut contenir 500 preuves ; le total reste borne par `MAX_SOURCES x 500`, soit au plus 25 000 preuves, ce qui reste dans la memoire SavedVariables d'un addon WoW. |
| `MAX_EVIDENCE_TOTAL` | 5000 | Garde-fou global : le total reste borne meme si une source est configuree plus large. |

Le calcul de `HistoricalBaseline.lua:256` devient :

```lua
-- avant
if count(state.evidence) + newCount > MAX_EVIDENCE then return nil, "EVIDENCE_LIMIT_EXCEEDED" end

-- apres
local sourceCount = count(existingSource and existingSource.evidenceIds or {})
if sourceCount + newCount > MAX_EVIDENCE_PER_SOURCE then return nil, "EVIDENCE_SOURCE_LIMIT_EXCEEDED" end
if count(state.evidence) + newCount > MAX_EVIDENCE_TOTAL then return nil, "EVIDENCE_LIMIT_EXCEEDED" end
```

**Etape 2 — collecter par lots, avec progression persistee.**

`CollectLocalEvidence` devient iteratif :

```lua
-- proposition
local function CollectLocalEvidence(actor, sourceIdPrefix)
  local progress = readCollectionProgress(sourceIdPrefix)   -- { ledgerOffset, predibsOffset }
  repeat
    local batch, nextOffset, exhausted = nextBatch("ledger", progress.ledgerOffset, BATCH_SIZE)
    if #batch > 0 then
      local added, reason = M.CollectEvidence(actor, ledgerDescriptor(), batch)
      if not added then return nil, reason end
      progress.ledgerOffset = nextOffset
      writeCollectionProgress(sourceIdPrefix, progress)
    end
    if exhausted then break end
  until true
  -- ... puis la source Pre-Dibs, de la meme maniere
end
```

Regles de la progression :

- l'offset est **externe** a la collection elle-meme : il est stocke
  dans `state.collectionProgress[sourceId]`, hors de `state.evidence` ;
- l'offset est **monotone** et **borne** par le nombre d'enregistrements
  de la source ; un offset superieur a la taille courante signale que la
  source a **change** et invalide la progression (la source est
  re-collectee depuis le debut) ;
- un lot **partiellement** collecte est repris depuis son **debut**, pas
  depuis son milieu : le lot est l' unite de reprise ;
- la source est declaree `complete = true` **seulement** quand son offset
  a atteint la fin.

**Etape 3 — rendre la reprise reelle.**

`missingLocalScanSources` doit distinguer trois etats au lieu de deux :

| Etat | Signification | Effet |
|---|---|---|
| `missing` | la source n'a pas ete collectee du tout | reprise |
| `partial` | la source a ete collectee en partie | reprise, au lot suivant |
| `complete` | l'offset a atteint la fin | rien |

Le motif de refus devient
`LEGACY_EVIDENCE_SCAN_INCOMPLETE:<sources>` pour une source absente et
`LEGACY_EVIDENCE_SCAN_PARTIAL:<source>@<offset>` pour une source
partielle. Le second motif est **actionnable** par l'interface : il dit
ou reprendre.

**Etape 4 — interdire l'approbation d'une source partielle.**

`FinalizeBaseline` (`:457`) refuse deja un baseline incomplet. La regle
doit devenir explicite : une source **partielle** n'est jamais
「acknowledgeable」. `acknowledgeIncompleteEvidence` ne peut porter que
sur une source **illisible** ou **volontairement omise** — pas sur une
source dont la collecte n'est pas terminee. C'est la difference entre
« on a decide de ne pas l'inclure » et « on n'a pas fini de la
collecter ».

### A.4 Risques et mitigations

| Risque | Gravite | Mitigation |
|---|---|---|
| Un lot rejoue duplique des preuves | Haute | `collectInto` est deja idempotent sur `evidenceId` : un enregistrement deja present est ignore, et un `sourceRecordHash` different produit `EVIDENCE_ID_CONFLICT`. Le rejeu est donc **sans effet**. |
| Une reprise apres crash perd un lot | Haute | L'offset est ecrit **apres** le lot, jamais avant. Un crash laisse au pire un lot deja collecte, re-collecte sans effet. |
| Une source change entre deux collectes | Moyenne | L'offset borne par la taille de la source est invalide si la source a change ; la source est re-collectee depuis le debut. Le `sourceHash` deja existant (`SOURCE_PROVENANCE_CONFLICT`) detecte un changement de provenance. |
| La memoire SavedVariables grossit | Moyenne | `MAX_EVIDENCE_TOTAL = 5000` borne le total. Le rapport de taille de sauvegarde (`ImportExport.GetSizeDiagnostics`) permet de verifier avant la bascule. |
| La pagination change le contrat de `CollectEvidence` | Moyenne | `CollectEvidence` reste l'API de base ; c'est `CollectLocalEvidence` qui boucle. Le contrat public est preserve. |
| Le changement de `MAX_EVIDENCE` affecte une base existante | Faible | Le nom `MAX_EVIDENCE` est utilise en un seul point (`:256`). Le renommer en `MAX_EVIDENCE_TOTAL` est un changement interne ; la valeur est lue a chaque appel, pas stockee. |

### A.5 Tests requis avant de Considerer A1 implemente

1. Une source unique de **exactement 500** enregistrements est collectee
   integralement, sans erreur.
2. Une source de **500** enregistrements **plus** une source de **1**
   enregistrement : la premiere reussit, la seconde est refusee avec un
   motif nomme, et la reprise **aboutit** apres pagination.
3. Un lot interrompu au milieu (simulation d'un echec injecte) est
   repris **sans doublon** : le nombre final de preuves est exact et
   chaque `evidenceId` n'apparait qu'une fois.
4. Un lot rejoue deux fois ne change rien (idempotence).
5. Une source qui **change** entre deux collectes invalide la progression
   et la source est re-collectee depuis le debut.
6. `FinalizeBaseline` **refuse** un baseline dont une source est
   partielle, meme avec `acknowledgeIncompleteEvidence = true`.
7. `FinalizeBaseline` **accepte** un baseline dont toutes les sources
   sont completes, et le hash du baseline est stable.
8. Le motif de reprise nomme la source **et l'offset**, de sorte que
   l'interface puisse afficher « 250 / 1200 ».

### A.6 Cout

| Fichier | Modification |
|---|---|
| `src/modules/HistoricalBaseline.lua` | 2 constantes ; le calcul de limite ; la lecture/ecriture de la progression ; `CollectLocalEvidence` en boucle ; `missingLocalScanSources` distingue 3 etats. |
| `src/modules/Installation.lua` | propagation du motif `PARTIAL` ; regle d'approbation stricte. |
| `src/ui/` | affichage de la progression (une source de progression deja presente pour les scans). |
| `tests/` | 8 tests ci-dessus, plus une reprise non-regression de `rf0013_partial_legacy_discovery_spec`. |

Estimation : **moderee**. Le risque est dans la reprise apres crash, pas
dans la pagination elle-meme.

---

## B1 — Proposition officier via `MultiLedger.ProposeLedger`

### B.1 Etat reel verifie

| Element | Valeur verifiee | Emplacement |
|---|---|---|
| Permission | `Dibs.Permissions.Evaluate("ledger.propose", actor)` | `MultiLedger.lua:511` |
| Nom | `trim(name)`, refuse au-dela de 50 caracteres | `MultiLedger.lua:518` |
| Identifiant | `"LDR-" .. tostring(now) .. "-" .. randSuffix` | `MultiLedger.lua:523` |
| Objet persiste | `db.ledgers[ledgerId] = { id, name, status = "PROPOSED", createdAt, createdBy, isDefault = false, options = options or {}, transactions = {}, playerStates = {}, ... }` | `MultiLedger.lua:527-540` |
| Resultat | `return { ok = true, ledgerId = ledgerId }` | `MultiLedger.lua:541` |
| Approbation | `MultiLedger.ApproveLedger` refuse un ledger qui n'est pas `PROPOSED`, exige `ledger.approve`, appelle `Dibs.Governance.RecordLedgerApproval(actor, ledgerId, ledger.name)`, puis passe a `APPROVED` | `MultiLedger.lua:543+` |
| Listage | `MultiLedger.GetLedgers` expose `id`, `name`, `status`, `createdAt`, `createdBy` | `MultiLedger.lua:448-470` |
| Refus propage | `return { ok = false, stage = "ledger", reasonCode = "LEDGER_PROPOSAL_NOT_CREATED", ... }` | `Installation.lua:419` |
| Restitution | `return { ok = true, reasonCode = "PROPOSAL_CREATED", status = Installation.GetStatus(actor) }` | `Installation.lua:421` |

### B.2 Le chemin existe deja

Le chemin B1 est **integralement en place** : une proposition persistante,
un statut explicite `PROPOSED`, une permission dediee, une approbation
par le GM avec trace d'audit, et un refus propage quand la proposition
n'a pas ete creee. La precondition de B1 est **verifiee**, pas supposee.

### B.3 Ecarts de contrat identifies

B1 n'est toutefois **pas** suffisante telle quelle. Quatre informations
manquent a l'objet de proposition pour que le GM puisse **decider** :

| # | Ecart | Ce que le GM doit savoir | Ce que l'objet porte aujourd'hui |
|---|---|---|---|
| **B1-E1** | **Perimetre couvert** | quelles sources ont ete decouvertes, et si le scan est complet | `options` est libre ; rien n'est impose |
| **B1-E2** | **Volume decouvert** | combien de transactions et de demandes ont ete trouves | absent |
| **B1-E3** | **Motif de la demande** | pourquoi l'officier demande une proposition (configuration initiale, ledger manquant, reprise) | absent |
| **B1-E4** | **Anomalies de lecture** | une source illisible a ete rencontree (le GM doit le savoir avant d'approuver) | absent |

**B1-E1 et B1-E2 sont les plus importants.** Sans eux, le GM approuve un
ledger dont il ne sait pas ce qu'il contient : la proposition existe et
est verifiable, mais elle ne **porte pas l'information** qui justifie la
proposition. La proposition serait donc formellement valide et
substantiellement vide.

**B1-E4 est un cas de securite.** `stageLegacyDiscovery` distingue deja
une source **illisible** (`LEGACY_EVIDENCE_SOURCE_UNREADABLE`) d'une
source absente. L'officier qui a rencontre une source illisible doit le
signaler dans la proposition, sinon le GM approuve en croyant que le
scan etait complet.

### B.4 Plan d'implementation propose (B1)

**Principe.** Reutiliser `MultiLedger.ProposeLedger` **sans modifier son
contrat**, et porter l'information manquante dans le champ `options`,
qui existe deja et n'est pas contraignant.

```lua
-- proposition
local proposed = Dibs.MultiLedger.ProposeLedger(actor, "Guild Primary", {
  purpose          = "GUILD_PRIMARY_MISSING",   -- B1-E3
  discoveredSources = { "ledger", "predibs" },   -- B1-E1
  discoveredCounts = { ledger = 1234, predibs = 56 }, -- B1-E2
  unreadableSources = { },                        -- B1-E4
  scanComplete     = true,
})
```

Regles :

1. `purpose` est un **ensemble ferme** de valeurs : la liste est declaree
   dans `MultiLedger` et refusee a l'ecriture si elle n'y figure pas.
   Aucune valeur libre ne peut etre stockee.
2. `discoveredSources` et `unreadableSources` sont des **listes de
   sources connues** (`ledger`, `predibs`), refusees si elles contiennent
   une source inconnue.
3. `discoveredCounts` est un **entier non negatif** par source.
4. `scanComplete` ne peut valoir `true` que si `unreadableSources` est
   **vide**.
5. `MultiLedger.GetLedgers` expose ces quatre champs a l'interface
   officier, de sorte que le GM **voit** le perimetre avant d'approuver.
6. `MultiLedger.ApproveLedger` **refuse** d'approuver une proposition
   dont `scanComplete` est `false` **et** dont `unreadableSources` est non
   vide : une source illisible doit etre consciously levee par le GM, pas
   fermee par defaut.

### B.5 Ce qui ne change pas

- `MultiLedger.ProposeLedger` garde son contrat public : meme signature
  de retour, meme permission, meme forme de l'objet. Seul le contenu de
  `options` s'enrichit.
- La proposition reste **un ledger** : aucun second registre, aucun
  second proprietaire des intentions.
- `Governance.RecordLedgerApproval` reste la seule trace d'approbation.
- Le garde-fou « ne jamais renvoyer `PROPOSAL_CREATED` sans objet
  persiste » est **preserve tel quel** : c'est la partie de la decision
  B qui ne depend d'aucun arbitrage.

### B.6 Risques et mitigations

| Risque | Gravite | Mitigation |
|---|---|---|
| `options` devient un sac fourre-tout | Moyenne | Les quatre champs sont **valides a l'ecriture** (liste fermee, types contraints) et `options` n'est lu que par l'interface et l'approbation. |
| Le GM approuve sans lire le perimetre | Haute | `GetLedgers` expose les quatre champs ; l'approbation refuse une proposition dont une source est illisible. |
| Un second registre d'intentions apparait | Haute | Aucune : la proposition reste un `db.ledgers[ledgerId]`. |
| Le contrat de `ProposeLedger` casse un appelant | Faible | La signature ne change pas ; `options` est deja un parametre optionnel. |
| Le GM ne peut plus approuver une source illisible | Moyenne | C'est un **choix** : soit il corrige la source et re-propose, soit il leve explicitement la proposition. Ce comportement doit etre confirme par la decision metier. |

### B.7 Tests requis avant de Considerer B1 implemente

1. Un officier sans la permission `ledger.propose` ne cree **aucune**
   proposition, et le refus est nomme.
2. La proposition creee est **persistee**, porte le statut `PROPOSED`, et
   `GetLedgers` la expose avec ses quatre champs.
3. Le resultat `PROPOSAL_CREATED` n'est returned que si l'objet existe
   reellement dans le magasin.
4. Une proposition dont `unreadableSources` est non vide et
   `scanComplete = false` est **refusee** a l'approbation.
5. Une proposition complete (`scanComplete = true`, aucune source
   illisible) est **approuvee** par le GM, passe a `APPROVED`, et laisse
   une trace d'audit via `Governance.RecordLedgerApproval`.
6. Un `purpose` hors de la liste fermee est refuse a l'ecriture.
7. Une source inconnue dans `discoveredSources` est refusee a l'ecriture.
8. Un `discoveredCounts` negatif ou non entier est refuse a l'ecriture.
9. Le chemin **officier** de `Installation.Initialize` propage un echec de
   proposition au lieu de presenter un succes.
10. Le chemin **officier** ne modifie **aucune** donnee de production :
    le ledger propose est vide et le ledger vivant est intact.

### B.8 Cout

| Fichier | Modification |
|---|---|
| `src/modules/MultiLedger.lua` | validation des quatre champs a l'ecriture ; exposition dans `GetLedgers` ; garde d'approbation. |
| `src/modules/Installation.lua` | construction de `options` a partir du resultat de `stageLegacyDiscovery`. |
| `src/ui/OfficerUI.lua` | affichage du perimetre propose devant le GM (**ne pas toucher a la ligne 3632**). |
| `tests/` | 10 tests ci-dessus. |

Estimation : **faible a moderee**. Le point sensible est la garde
d'approbation, qui est une **decision metier** (B-6 ci-dessus).

---

## C. Les deux decisions restent ouvertes

| Decision | Option proposee | Etat | Ce qu'il faut pour la trancher |
|---|---|---|---|
| A | A1 (pagination) | **PREPARE, NOT IMPLEMENTED** | Valider `MAX_EVIDENCE_PER_SOURCE = 500` et `MAX_EVIDENCE_TOTAL = 5000`, et le refus d'approuver une source partielle. |
| B | B1 (`ProposeLedger` enrichi) | **PREPARE, NOT IMPLEMENTED** | Valider les quatre champs de `options`, et le refus d'approuver une proposition dont une source est illisible. |

Aucune de ces deux decisions n'a ete prise en session 13. Le code de
production est **inchange** pour RF-0013. RF-0013 reste
`PARTIALLY_FIXED` et T041 reste `PENDING_MANUAL_VALIDATION`.

La garde-fou deja en place — ne jamais renvoyer `PROPOSAL_CREATED` sans
objet persiste — ne depend d'aucune de ces decisions et doit etre
preservee quelle que soit l'option retenue.
