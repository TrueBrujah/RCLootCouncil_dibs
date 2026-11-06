# RF-0013 — Specification finale proposee (A1 et B1)

Statut : **PROPOSED — NOT IMPLEMENTED — EN ATTENTE D'APPROBATION DU PROPRIETAIRE**

Ce document est la **specification** des deux corrections restantes de
RF-0013. Il ne modifie **aucun** code de production. Les specifications
sont ecrites de maniere a etre implementees **telles quelles** une fois
l'approbation obtenue, sans nouvelle analyse.

Les faits sont **verifies dans le code actuel** le 2026-10-21. Chaque
affirmation porte sur une ligne precise.

---

# PARTIE A — A1 : collecte historique paginee

## A.1 Defaut, verifie

`MAX_EVIDENCE = 500` est une limite **globale** (`HistoricalBaseline.lua:14`).
`CollectLocalEvidence` (`:385-408`) collecte en deux appels **separes** et
**sequentiels** :

1. `CollectEvidence(..., ":ledger", ledgerRecords)` — la source passe a 500
   et **reussit** ;
2. `CollectEvidence(..., ":predibs", requestRecords)` — `500 + n > 500` →
   **`EVIDENCE_LIMIT_EXCEEDED`**, la source Pre-Dibs est **absente**.

La source ledger **est** persistee, la source Pre-Dibs **non**. L'etat
est coherent mais **incomplet**. Comme la collecte est un tout-ou-rien
par source et qu'aucune progression n'est memorisee, **chaque reprise
echoue de maniere identique** : le meme motif, le meme etat.

C'est precisement ce que A1 doit corriger : la limite est **globale**,
la collecte est **par source entiere**, et la reprise est **nulle**.

## A.2 Specification

### A.2.1 Limites

| Parametre | Valeur | Portee | Justification |
|---|---|---|---|
| `BATCH_SIZE` | **500** | par lot de collecte | Une unite de reprise. Un lot interrompu est rejoue en entier. |
| `MAX_EVIDENCE_PER_SOURCE` | **500** | par source, par cycle | Une source peut contenir 500 preuves par cycle de collecte. |
| `MAX_EVIDENCE_PER_CYCLE` | **5000** | par cycle de collecte | Garde-fou global : le total reste borne meme si plusieurs sources sont collectees. |
| Limite de **conservation** | **aucune** | sur la conservation | La retention n'est pas bornee : la ou la conservation est une decision metier, pas une consequence de la collecte. La borne `MAX_EVIDENCE_PER_CYCLE` regit la **collecte d'un cycle**, pas la **conservation** dans le temps. |

La distinction est essentielle : `MAX_EVIDENCE` aujourd'hui borne la
**conservation** (une base ne peut pas contenir plus de 500 preuves). A1
change la nature de la borne : elle devient une borne de **collecte par
cycle**, et la conservation n'est plus bornee par ce mecanisme.

### A.2.2 Curseur persistant

Le curseur est **externe** a la collection : il vit dans
`state.collectionProgress[sourceId]`, a cote de `state.evidence`, et
**non** dans `state.sources[sourceId].evidenceIds`.

| Champ | Type | Sens |
|---|---|---|
| `cursor` | entier | index du **dernier element confirme** de la source (base 0) |
| `sourceFingerprint` | chaine | empreinte de l'**etat de la source** au moment du curseur |
| `totalSeen` | entier | nombre d'elements vus jusqu'au curseur |
| `state` | chaine | `COMPLETE`, `INCOMPLETE` ou `ERROR` |
| `lastReason` | chaine | motif du dernier echec, si `state == "ERROR"` |
| `updatedAt` | entier | horodatage de la derniere progression |

**Ecriture :** le curseur est ecrit **apres** la confirmation du lot, et
**jamais avant**. Un crash laisse au pire un lot deja collecte, qui sera
rejoue sans effet (voir A.2.4).

**Reprise :** la reprise relit `state.collectionProgress[sourceId]`,
valide le `sourceFingerprint`, et continue a partir de `cursor + 1`.

**Invalidation :** si `sourceFingerprint` ne correspond plus a l'etat
courant de la source, la source a **change** : le curseur est remis a 0
et la source est re-collectee depuis le debut. Le motif est
`EVIDENCE_SOURCE_CHANGED`.

### A.2.3 Etats

| Etat | Signification | Effet |
|---|---|---|
| `COMPLETE` | le curseur a atteint la fin de la source ; la source est **complete** | la source compte comme collectee |
| `INCOMPLETE` | la collecte est **en cours** ; le curseur est valide et la source a encore des elements | la source compte comme **manquante** ; la reprise est possible et **actionnable** |
| `ERROR` | la collecte a **echoue** ; le motif est enregistre dans `lastReason` | la source compte comme **manquante** ; la reprise est possible si le motif est recuperable |

La source est `complete` **seulement** si son etat de collecte est
`COMPLETE` **et** que `state.sources[sourceId]` existe. Une source
`INCOMPLETE` ou `ERROR` n'est **jamais** comptee comme collectee par
`collectedLocalScanSources` (`Installation.lua:81-93`).

### A.2.4 Deduplication

La deduplication est **deja** correcte et ne doit pas etre reimplementee :
`collectInto` (`HistoricalBaseline.lua:250-274`) ignore un
`evidenceId` deja present et refuse un `sourceRecordHash` different pour
le meme identifiant (`EVIDENCE_ID_CONFLICT`).

Consequence : le rejeu d'un lot est **sans effet**. A1 n'a donc pas
besoin d'une deduplication supplementaire ; elle doit simplement
**s'appuyer** sur celle existante et ne jamais l'affaiblir.

La specification impose que le lot soit **rejouable** : un lot
re-execute doit produire **exactement** le meme ensemble d'`evidenceId`,
et l'etat final doit etre identique a celui d'une collecte sans
reprise.

### A.2.5 Interdiction d'approuver une source incomplete

`FinalizeBaseline` (`HistoricalBaseline.lua:457`) refuse deja un baseline
incomplet via `INCOMPLETE_EVIDENCE_ACKNOWLEDGEMENT_REQUIRED`, mais
l'acknowledgement est **global** : il ne distingue pas une source
volontairement omise d'une source dont la collecte n'est pas terminee.

**Specification :** l'acknowledgement ne peut porter que sur une source
**illisible** ou **volontairement omise**. Une source dont l'etat de
collecte est `INCOMPLETE` **interdit** l'approbation, meme avec
`acknowledgeIncompleteEvidence = true`. Le motif devient explicite :
`INCOMPLETE_EVIDENCE_SOURCE_IN_PROGRESS`.

Cette distinction est la substance de la decision : « on a decide de ne
pas l'inclure » et « on n'a pas fini de la collecter » ne doivent pas
produire le meme resultat.

### A.2.6 Reprise apres interruption

Trois interruptions doivent etre couvertes :

| Interruption | Comportement attendu |
|---|---|
| Crash **entre** deux lots | La reprise repart du curseur confirme ; aucun element perdu, aucun doublon. |
| Crash **au milieu** d'un lot | Le lot n'est pas confirme ; le curseur n'a pas avance ; le lot est rejoue en entier. |
| Crash **apres** le curseur, **avant** la persistance de l'etat | Le lot est rejoue ; la deduplication le rend sans effet ; le curseur est reecrit a la meme valeur. |

## A.3 Modifications attendues

| Fichier | Modification |
|---|---|
| `src/modules/HistoricalBaseline.lua` | `BATCH_SIZE`, `MAX_EVIDENCE_PER_SOURCE`, `MAX_EVIDENCE_PER_CYCLE` ; le calcul de limite de `collectInto` ; lecture/ecriture de `state.collectionProgress` ; `CollectLocalEvidence` en boucle par lot ; `M.GetCollectionProgress` pour l'interface. |
| `src/modules/Installation.lua` | `collectedLocalScanSources` distingue `COMPLETE` / `INCOMPLETE` / `ERROR` ; motif de reprise nomme avec la source et le curseur ; `stageBaseline` refuse une source en cours. |
| `src/ui/` | affichage de la progression (« 250 / 1200 ») et de l'etat par source. |
| `docs/developer/saved-variables.md` | documenter `state.collectionProgress` comme surface de persistance. |

## A.4 Specification des tests (a implementer apres approbation)

Fichier : `tests/integration/rf0013_paginated_collection_spec.lua`

| # | Cas | Assertion discriminante |
|---|---|---|
| A01 | Une source de exactement 500 elements | collecte **reussie**, 500 preuves, etat `COMPLETE` |
| A02 | Une source de 500 elements **plus** une source de 1 element | la 2e source echoue avec un motif nomme **n'exposant pas** la limite globale, et la reprise **aboutit** |
| A03 | Reprise apres interruption **entre** deux lots | le nombre final de preuves est exact, chaque `evidenceId` apparait **une seule fois** |
| A04 | Reprise apres interruption **au milieu** d'un lot | le lot est rejoue **en entier** ; l'etat final est identique a une collecte sans reprise |
| A05 | Rejeu d'un lot deja confirme | **aucun** changement d'etat, **aucun** doublon |
| A06 | Une source qui **change** entre deux collectes | le curseur est invalide, la source est re-collectee depuis le debut, motif `EVIDENCE_SOURCE_CHANGED` |
| A07 | `FinalizeBaseline` avec une source `INCOMPLETE` | **refus** meme avec `acknowledgeIncompleteEvidence = true`, motif `INCOMPLETE_EVIDENCE_SOURCE_IN_PROGRESS` |
| A08 | `FinalizeBaseline` avec une source `ERROR` | **refus** avec un motif nommant `lastReason` |
| A09 | `FinalizeBaseline` avec toutes les sources `COMPLETE` | **accepte** ; le hash du baseline est **stable** entre deux executions |
| A10 | Une source `INCOMPLETE` apres un cycle | le motif de reprise nomme la source **et** le curseur, de sorte que l'interface puisse afficher la progression |
| A11 | Collecte de 0 element | etat `COMPLETE`, 0 preuve, aucune erreur (une source vide n'est pas un blocage) |
| A12 | Deux collectes successives de la meme source | la 2e est un **no-op** : 0 nouvelle preuve, curseur inchange |

**Non-regression obligatoire :** `rf0013_partial_legacy_discovery_spec`
(5 cas) doit rester vert, ainsi que `canonical_dispute_backup_spec` et
`historical_baseline_recovery_spec`.

---

# PARTIE B — B1 : proposition officier

## B.1 Verification du contrat `MultiLedger.ProposeLedger`

### B.1.1 Ce que le contrat offre aujourd'hui

| Element | Verifie | Emplacement |
|---|---|---|
| Permission | `Dibs.Permissions.Evaluate("ledger.propose", actor)` ; `ledger.propose` est dans `ADMIN_ACTIONS` (donc accessible a un officier), et `ledger.approve` est dans `GM_ONLY_ACTIONS` (donc reserve au GM) | `MultiLedger.lua:511`, `Permissions.lua:84-85, 91-102` |
| Validite du nom | `trim(name)`, refuse au-dela de 50 caracteres, motif `INVALID_LEDGER_NAME` | `MultiLedger.lua:518-520` |
| Persistance | `db.ledgers[ledgerId] = { ... status = "PROPOSED", ... }` | `MultiLedger.lua:527-540` |
| Identite | `"LDR-" .. tostring(now) .. "-" .. randSuffix` | `MultiLedger.lua:523` |
| Approbation GM | `MultiLedger.ApproveLedger` verifie `ledger.status ~= "PROPOSED"`, exige `ledger.approve`, appelle `Dibs.Governance.RecordLedgerApproval(actor, ledgerId, ledger.name)`, puis passe a `APPROVED` | `MultiLedger.lua:545+` |
| Audit | l'approbation passe par `Governance.RecordLedgerApproval` | `MultiLedger.lua:566+` |
| Enumeration | `MultiLedger.GetLedgers` expose `id`, `name`, `status`, `createdAt`, `createdBy` | `MultiLedger.lua:448-481` |
| Refus propage | `LEDGER_PROPOSAL_NOT_CREATED` | `Installation.lua:419` |
| Garde-fou | `PROPOSAL_CREATED` n'est retourne que si l'objet existe reellement | `Installation.lua:409-421` |

**Le chemin B1 existe donc integralement.** Les exigences « proposition
reellement persistee », « approbation GM », « permissions » et « audit »
sont **deja satisfaites**.

### B.1.2 Ce que le contrat ne fournit pas — cinq ecarts

Le dossier `RF-0013-BUSINESS-DECISIONS.md` (ligne 111) presente B1 comme
reutilisant « l'index de propositions deja presents ». **Cette affirmation
est inexacte** et doit etre corrigee.

**Verification par lecture de la source :** `MultiLedger.lua` ne contient
**aucune** structure d'index de propositions. Le seul mot « proposal »
qui y apparait est dans le commentaire d'en-tete (ligne 5). Une
proposition est un simple `db.ledgers[ledgerId]` dont le `status` vaut
`PROPOSED`.

**Verification par mesure (session 14) :**

| Mesure | Resultat |
|---|---|
| Deux propositions nommees « Guild Primary » creees par le **meme** officier | **les deux sont acceptees** (`ok = true`), identifiants distincts `LDR-1700000183-9faa` et `LDR-1700000184-a234` |
| Nombre de ledgers nommes « Guild Primary » | **2** |
| Nombre de propositions en attente | **2** |
| `options` de chaque proposition | **vide** (`OPTIONS_KEYS` = chaine vide) |
| Garde de `Installation.Initialize` | `hasLedger = true` — la proposition **PROPOSED** satisfait la garde **par son nom** |
| apres approbation d'une proposition | l'autre reste **PROPOSED**, et les deux sont **indistinguables** |

Il n'existe **ni index de propositions, ni garde anti-duplicat, ni
contexte porte par la proposition**.

| # | Ecart | Exigence RF-0013 non satisfaite | Etat |
|---|---|---|---|
| **B1-E1** | Perimetre couvert | Le GM ne sait pas quelles sources ont ete decouvertes | absent |
| **B1-E2** | Volume decouvert | Le GM ne sait pas combien d'elements ont ete trouves | absent |
| **B1-E3** | Motif de la demande | Le GM ne sait pas pourquoi la proposition est faite | absent |
| **B1-E4** | Sources illisibles signalees | Le GM ne sait pas si une source n'a pas pu etre lue | absent |
| **B1-E5** | Unicite de la proposition | Deux propositions de meme nom coexistent, sans index ni garde | absent |

**B1-E5 est un constat de securite** : deux propositions indistinguables
laissent le GM approuver l'une pendant que l'autre reste en attente
et pourroit etre approuvee ulterieurement, creant un second ledger
« Guild Primary » concurrent.

**Conclusion de la verification :** B1 **ne correspond pas** en l'etat
au contrat metier de RF-0013. Elle correspond a la *forme* (un objet
propose, approuve par le GM, trace), mais pas au *contenu* (le GM ne peut
pas decider).

## B.2 Specification

### B.2.1 Validation du perimetre (B1-E1)

Champ `options.discoveredSources` : liste de sources **connues**, extraite
d'une **liste fermee** `{ "ledger", "predibs" }`. Toute source inconnue
est refusee a l'ecriture, motif `INVALID_PROPOSAL_SCOPE`.

Une source **obligatoire** absente du perimetre alors que la source
contient des donnees rend la proposition **inapprovable** (voir B.2.7).

### B.2.2 Validation du volume (B1-E2)

Champ `options.discoveredCounts` : table `source -> entier`. Chaque valeur
doit etre un **entier positif ou nul**. Une valeur negative, non
entiere, ou une cle inconnue est refusee, motif
`INVALID_PROPOSAL_VOLUME`.

Le volume est **declare par l'officier** et **recoupe** par le
coordinateur au moment de l'approbation : si le volume reellement
constate differe du volume declare, l'approbation est refusee, motif
`PROPOSAL_VOLUME_MISMATCH`. Sans cette recoupement, B1-E2 ne serait
qu'une declaration non verifiee.

### B.2.3 Validation du motif (B1-E3)

Champ `options.purpose`, tire d'une **liste fermee** :

| Valeur | Signification |
|---|---|
| `GUILD_PRIMARY_MISSING` | le ledger primaire n'existe pas |
| `GUILD_PRIMARY_UNAPPROVED` | le ledger primaire existe mais n'est pas approuve |
| `LEGACY_SCAN_INCOMPLETE` | la decouverte legacy n'est pas terminee |
| `RECOVERY_AFTER_FAILURE` | reprise apres un echec d'initialisation |

Toute autre valeur est refusee a l'ecriture, motif
`INVALID_PROPOSAL_PURPOSE`. Le motif permet a l'interface d'afficher une
phrase adaptee au lieu d'un texte generique.

### B.2.4 Identification des sources illisibles (B1-E4)

Champ `options.unreadableSources` : liste de sources de la liste fermee.
Une source listee ici est **explicitement** declaree non lisible par
l'officier.

Regle : `options.scanComplete` ne peut valoir `true` que si
`unreadableSources` est **vide**. Le couple est valide a l'ecriture :
`scanComplete = true` avec une source illisible est refuse, motif
`INVALID_PROPOSAL_COMPLETENESS`.

Ce qui distingue ce champ du `acknowledgeIncompleteEvidence` existant :
`acknowledgeIncompleteEvidence` est un **aveu** de l'omission, alors
qu'`unreadableSources` est un **constat de technique de lecture**. Une
source illisible doit etre **signalee**, pas silencieusement omise.

### B.2.5 Unicite de la proposition (B1-E5)

`MultiLedger.ProposeLedger` refuse une **deuxieme** proposition active
de meme `purpose` et meme perimetre, motif `DUPLICATE_LEDGER_PROPOSAL`.

La « proposition active » est une proposition dont le `status` est
`PROPOSED`. Une proposition approuvee ou archivee ne bloque plus une
nouvelle proposition : le refus porte sur la **coexistence**, pas sur
l'historique.

Ce point necessite la creation d'un **index de propositions** — celui
que le dossier d'origine supposea deja exister. L'index est une table
dediee, par exemple `db.ledgerProposals[proposalId]`, qui **ne
constitue pas** un second registre comptable : il ne contient que des
metadonnees de proposition, jamais de transactions.

### B.2.6 Proposition reellement persistee

La proposition doit etre **verifiable** par le GM. Specification :

- `MultiLedger.ProposeLedger` retourne `{ ok = true, ledgerId, proposalId }` ;
- `proposalId` est un identifiant **stable et distinct** du `ledgerId` ;
- `MultiLedger.GetProposal(proposalId)` retourne la proposition ;
- `MultiLedger.ListProposals()` retourne la liste des propositions
  **actives** ;
- la proposition est **persistee avant** le retour de succes.

### B.2.7 Approbation GM et refus sur sources obligatoires incompletes

`MultiLedger.ApproveLedger` refuse, en plus des controles existants :

| Condition | Motif |
|---|---|
| `options` absents ou invalides | `INVALID_PROPOSAL_METADATA` |
| une source **obligatoire** declaree presente dans `discoveredSources` mais dont la collecte est `INCOMPLETE` ou `ERROR` | `PROPOSAL_SOURCE_INCOMPLETE` |
| `unreadableSources` non vide et `scanComplete = false` | `PROPOSAL_UNREADABLE_SOURCES` |
| `discoveredCounts` different du volume reellement constate | `PROPOSAL_VOLUME_MISMATCH` |

La **reprise** doit rester possible : une proposition refusee pour une
source incomplete n'est pas perdue ; l'officier peut la **mettre a
jour** (recollecter, puis mettre a jour `options`) et la soumettre a
nouveau. `MultiLedger.UpdateProposal(proposalId, options, actor)` est
specifie pour cela, avec la meme permission `ledger.propose` et un audit.

### B.2.8 Audit

Chaque mutation de proposition est tracee dans l'`auditLog` de la
guilde :

| Action | Declencheur |
|---|---|
| `LEDGER_PROPOSAL_CREATED` | creation |
| `LEDGER_PROPOSAL_UPDATED` | mise a jour des metadonnees |
| `LEDGER_PROPOSAL_REJECTED` | refus d'approbation, avec le motif |
| `LEDGER_PROPOSAL_APPROVED` | approbation GM |

L'approbation conserve deja sa trace via
`Governance.RecordLedgerApproval` : la trace de proposition et la trace
d'approbation sont **complementaires**, pas concurrentes.

## B.3 Modifications attendues

| Fichier | Modification |
|---|---|
| `src/modules/MultiLedger.lua` | `PROPOSAL_PURPOSES`, `PROPOSAL_SOURCES`, validation de `options` ; index de propositions ; `ProposeLedger` refuse le doublon ; `GetProposal`, `ListProposals`, `UpdateProposal` ; `ApproveLedger` applique les quatre refus ; exposition des champs dans `GetLedgers`. |
| `src/modules/Installation.lua` | construction de `options` a partir du resultat de `stageLegacyDiscovery` ; lecture de l'etat de collecte par source. |
| `src/ui/OfficerUI.lua` | affichage du perimetre, du volume, du motif et des sources illisibles devant le GM. **Ne pas toucher a la ligne 3632.** |
| `docs/developer/saved-variables.md` | documenter `db.ledgerProposals`. |

## B.4 Specification des tests (a implementer apres approbation)

Fichier : `tests/integration/rf0013_officer_proposal_spec.lua`

| # | Cas | Assertion discriminante |
|---|---|---|
| B01 | Un membre ordinaire tente de proposer | **refus** nomme ; **aucune** proposition creee ; `db.ledgerProposals` vide |
| B02 | Un officier propose avec des metadonnees valides | la proposition est **persistee**, `status = "PROPOSED"`, `options` conserve les quatre champs, et l'objet est relisible par `GetProposal` |
| B03 | Deux propositions de meme `purpose` et meme perimetre | la 2e est **refusee** (`DUPLICATE_LEDGER_PROPOSAL`) ; une seule proposition active |
| B04 | `purpose` hors liste fermee | **refus** a l'ecriture (`INVALID_PROPOSAL_PURPOSE`) ; rien n'est persiste |
| B05 | source inconnue dans `discoveredSources` | **refus** (`INVALID_PROPOSAL_SCOPE`) |
| B06 | `discoveredCounts` negatif ou non entier | **refus** (`INVALID_PROPOSAL_VOLUME`) |
| B07 | `scanComplete = true` avec une source illisible | **refus** (`INVALID_PROPOSAL_COMPLETENESS`) |
| B08 | Une source obligatoire en `INCOMPLETE` | l'approbation est **refusee** (`PROPOSAL_SOURCE_INCOMPLETE`) ; le ledger reste `PROPOSED` |
| B09 | `unreadableSources` non vide | l'approbation est **refusee** (`PROPOSAL_UNREADABLE_SOURCES`) |
| B10 | Le volume reel differe du volume declare | l'approbation est **refusee** (`PROPOSAL_VOLUME_MISMATCH`) |
| B11 | Un GM approuve une proposition valide | le ledger passe a `APPROVED`, `Governance.RecordLedgerApproval` est appele, et l'`auditLog` contient `LEDGER_PROPOSAL_APPROVED` |
| B12 | Un officier tente d'approuver | **refus** (`GUILD_MASTER_REQUIRED`) ; le ledger reste `PROPOSED` |
| B13 | `UpdateProposal` avec des metadonnees corrigees | la proposition est mise a jour, l'audit contient `LEDGER_PROPOSAL_UPDATED`, et l'approbation devient possible |
| B14 | Le chemin officier de `Installation.Initialize` | un echec de proposition est **propage** (`LEDGER_PROPOSAL_NOT_CREATED`), jamais presente comme un succes |
| B15 | Le chemin officier ne modifie aucune donnee de production | le ledger vivant est intact et le ledger propose est vide |

**Non-regression obligatoire :**
`rf0013_partial_legacy_discovery_spec` (5 cas),
`rf0020_officer_relationship_review_spec` (6 cas),
`rf0020_officer_relationship_review_integration_spec` (5 cas),
`multi_ledger_spec`, `protected_actions_ledger_op_spec`.

## B.5 Ce qui ne change pas

- `MultiLedger.ProposeLedger` garde sa **signature publique** :
  `(actor, name, options)` et `{ ok = true, ledgerId }`. Seuls des
  champs **additionnels** sont ajoutes au resultat.
- Une proposition reste **un ledger** : aucun second registre, aucun
  second proprietaire des intentions. L'index de propositions ne
  contient que des metadonnees.
- `Governance.RecordLedgerApproval` reste la seule trace d'approbation
  d'un ledger.
- Le garde-fou « ne jamais renvoyer `PROPOSAL_CREATED` sans objet
  persiste » est preserve tel quel.

---

# PARTIE C — Correction de la fiche RF-0013

Le dossier `RF-0013-BUSINESS-DECISIONS.md` doit etre corrige sur un
point, parce que l'affirmation est **inexacte** et pourrait conduire a
une implementation qui suppose un mecanisme inexistant.

| Emplacement | Texte actuel | Texte correct |
|---|---|---|
| `RF-0013-BUSINESS-DECISIONS.md:111` | « ... et l'index de propositions deja presents. Aucun nouvel objet. » | « ... et la permission `ledger.propose` deja presente. **Aucun index de propositions n'existe** : une proposition est un `db.ledgers[ledgerId]` au statut `PROPOSED`, et rien n'empeche deux propositions de meme nom de coexister. B1 doit donc **creer** l'index et la garde anti-duplicat. » |

---

# PARTIE D — Etat et decision

| Decision | Specification | Etat |
|---|---|---|
| A | A1 : collecte paginee, limite 500/source/cycle et 5000/cycle, curseur persistant, reprise, dedup, etats `COMPLETE`/`INCOMPLETE`/`ERROR`, interdiction d'approuver une source incomplete | **PREPAREE, NON IMPLEMENTEE** |
| B | B1 : `ProposeLedger` valide et porte le perimetre, le volume, le motif et les sources illisibles ; unicite garantie ; approbation GM refusee si une source obligatoire est incomplete ; audit complet | **PREPAREE, NON IMPLEMENTEE** |

**Aucune modification de production n'a ete faite.** RF-0013 reste
`PARTIALLY_FIXED` et T041 reste `PENDING_MANUAL_VALIDATION` jusqu'a
l'approbation explicite du proprietaire du projet **et** la mise en
oeuvre des tests decrits ci-dessus.
