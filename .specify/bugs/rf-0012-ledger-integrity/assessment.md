# Bug Assessment: Integrite des corrections de litige (RF-0012)

- **Slug**: `rf-0012-ledger-integrity` (fourni par l'utilisateur)
- **Created**: 2026-10-18
- **Source**: texte fourni dans la demande; aucun URL externe
- **Verdict**: valid
- **Severity**: critical
- **Priorite demandee**: P0 — DATA_INTEGRITY
- **Base analysee**: branche `dev`, HEAD `dc388f9`; arbre de travail courant

## Rapport

L'analyse demandee porte sur les corrections de litige qui peuvent produire
plusieurs ecritures, echouer partiellement, etre rejouees ou viser un autre
ledger, ainsi que sur leur replication en V2. Le rapport demande une architecture
qui preserve les ecritures historiques, l'autorite GM/Officer, la convergence
V2 et une reprise explicite sans supposer que SavedVariables fournit des
transactions atomiques ou une persistance immediate.

## Symptome

Une correction de cible peut enregistrer l'inversion du joueur initial sans
crediter le joueur cible. Le code tente alors une compensation sans verifier son
resultat et laisse le dossier reessayable; le rejeu peut ajouter d'autres
ecritures. En mode V2, les ajustements/refund `dispute-center` peuvent aussi
modifier uniquement le ledger local, sans commit canonique correspondant.

Une correction peut en outre etre evaluee par rapport au ledger actif plutot
qu'au ledger de la transaction d'origine. Le comportement precis en cas
d'evidence absente reste une decision produit a confirmer.

## Reproduction

Les deux premiers scenarios sont reproductibles dans un test avec injection de
pannes. Le rejet reel de la deuxieme ecriture ou de la compensation n'a pas ete
reproduit en client Retail.

1. Creer une ecriture originale liee a une demande, puis executer
   `Disputes.Resolve(requestId, "correct_target", ...)` avec changement de joueur.
   Injecter un rejet dans le deuxieme appel `ProtectedActions.Execute` :
   `applyTargetCorrection` a deja demande l'inversion du joueur initial, appelle
   ensuite le rollback, mais ne verifie pas son resultat. La demande n'est pas
   enregistree dans `state.corrections` sur cette branche.
2. Faire echouer aussi le rollback, puis rejouer la meme correction. Le premier
   appel a pu conserver une ecriture; le nouvel appel produit des IDs de
   transaction frais et repete l'inversion. Comparer soldes, transactions,
   resolution du dossier et diagnostics; ne pas verifier uniquement le retour
   Lua.
3. Avec V2 impose, executer une correction `dispute-center` qui passe par
   `ledger.adjust` ou `ledger.refund`. Comparer le ledger local au ledger d'un
   autre membre et verifier si `nextSeq`/`rootHash` du ledger canonique avance.
   Le code actuel predit une mutation locale sans nouveau `AWARD_COMMIT`; le
   scenario a deux clients reste a executer.
4. Creer une evidence dans un ledger, changer le ledger actif, puis resoudre la
   demande. `findTransaction` et les mutations n'ont pas de `ledgerId` explicite.
   Si la recherche ne retrouve pas la ligne originale, la correction de cible
   peut encore modifier l'attribution et resoudre le dossier sans transfert de
   solde.

**[NEEDS CLARIFICATION]** Quel rejet concret de la deuxieme ecriture ou de la
compensation est attendu dans Retail? Les tests doivent injecter ces erreurs,
mais l'analyse n'a pas etabli de cause deterministe de rejet dans le client
normal. **[NEEDS CLARIFICATION]** Pour une demande sans transaction originale
retrouvable, faut-il permettre une correction d'attribution seule ou refuser
la resolution comptable?

Le test existant `tests/integration/dispute_center_spec.lua` verifie le
transfert nominal, les soldes attendus et le refus d'une seconde resolution
apres succes. Il ne couvre pas les echecs de la deuxieme ecriture, du rollback,
le rejeu apres echec partiel, ni la convergence V2.

## Chemins de code suspectes

- `src/modules/Disputes.lua:216` — `findTransaction` recherche award et
  transaction dans le ledger actif faute de `ledgerId` passe.
- `src/modules/Disputes.lua:806` — `targetCorrectionDetails` derive la ligne
  originale et le montant a transferer a partir de cette recherche.
- `src/modules/Disputes.lua:843` — `applyTargetCorrection` calcule la cle,
  execute jusqu'a trois mutations independantes et ne stocke l'etat de
  correction qu'apres le transfert complet.
- `src/modules/Disputes.lua:968` — `applyCorrection` utilise egalement la cle
  persistante et les ProtectedActions, mais ses actions restent des mutations
  unitaires locales pour les chemins `dispute-center`.
- `src/modules/Disputes.lua:1036` — `Resolve` protege les transitions de dossier
  et rejette une demande deja resolue; cela ne forme pas une transaction avec
  les mutations du ledger.
- `src/modules/Disputes.lua:1139` — `Reopen` remet le dossier en etat ouvert
  lorsque la transition est permise; la cle de correction persistante est
  distincte de cet etat de demande.
- `src/modules/ProtectedActions.lua:253` et `:261` — les wrappers `use` et
  `refund` ne propagent pas les codes de rejet renvoyes par Ledger.
- `src/modules/ProtectedActions.lua:279` — `executeLedgerAdjust` ne restitue
  specialement le code Ledger que pour `source="MANUAL_ADMIN"`, pas pour
  `source="dispute-center"`.
- `src/modules/ProtectedActions.lua:741` — chaque action protegee re-evalue
  l'autorisation. Cela constitue un controle existant a conserver, pas une
  garantie d'atomicite ou de replication.
- `src/modules/Ledger.lua:403` — un ID de transaction est genere si l'appelant
  n'en fournit pas; les appels de correction et rollback ne fournissent pas
  d'identifiant stable.
- `src/modules/Ledger.lua:443` et `:458` — `appendValidated` met a jour plusieurs
  tables derivees; `CommitLocalTransaction` deduplique par `transactionId` et
  contenu canonique, pas par `correctionKey`.
- `src/modules/Ledger.lua:576` — `ApplyAwardCommit` verifie l'autorite,
  l'epoch, la sequence et le hash, puis applique un seul transaction de commit.
- `src/modules/Ledger.lua:637` — la mutation V2 canonique de `DIB_USED` passe par
  le coordinateur; le chemin local bloque `DIB_USED` sous V2 et peut produire
  une proposition.
- `src/modules/Ledger.lua:731` et `:790` — seul `source="MANUAL_ADMIN"` passe
  par `commitCanonicalAdminAdjustment` en V2. `dispute-center` continue par la
  compatibilite locale; `DIB_REFUNDED` suit aussi la mutation locale.
- `src/modules/Ledger.lua:945`, `:949` et `:974` — recherches de transactions
  acceptant un ledger optionnel; l'index `evidenceTransactions` ne conserve
  qu'un identifiant par evidence.
- `src/modules/MultiLedger.lua:128`, `:208` et `:216` — distinguent le ledger
  actif (contexte de mutation) du ledger de vue (consultation seule).
- `src/modules/SyncV2.lua:1421`, `:1777`, `:1900`, `:2589` et `:2787` — digest
  fonde sur l'etat canonique; les details, demandes et applications sont
  explicitement routees par type, notamment `AWARD_COMMIT`.
- `tests/integration/dispute_center_spec.lua:124` — test nominal de correction
  cible, sans panne injectee.
- `tests/integration/request_followup_spec.lua:93` — conservation du lien de
  correction apres fermeture/archive; pas de test de reprise apres echec partiel.

## Analyse des causes et garanties reelles

### 1. Ecritures en plusieurs etapes et compensation

`applyTargetCorrection` execute d'abord un `ledger.adjust` negatif sur le
joueur initial, puis un second `ledger.adjust` sur le joueur cible. Ce sont deux
appels separes a `ProtectedActions.Execute`, chacun pouvant append une
transaction. Si le second est refuse, le code tente un troisieme `ledger.adjust`
pour restaurer l'ancien solde, ignore completement le resultat de cet appel et
retourne seulement le rejet du deuxieme appel.

- Si la compensation reussit, l'effet net du transfert est annule, mais les
  transactions deja append-only restent dans l'historique.
- Si elle echoue, le premier effet peut rester en place sans transaction cible.
  Le dossier reste reessayable et ne porte pas de statut de reprise.
- Un rejeu utilise de nouveaux IDs; il peut reappliquer l'inversion avant de
  crediter la cible. Le solde final peut donc differer d'un transfert unique.
- Une erreur ou interruption entre les mutations et l'ecriture de l'etat du
  dossier n'a pas de journal de reprise connu. La possibilite d'une interruption
  Retail au milieu de l'appel synchrone n'a pas ete demontree.

La compensation actuelle n'est pas un rollback transactionnel: elle est une
nouvelle ecriture comptable append-only et son echec n'est ni conserve ni
rapporte.

### 2. Portee exacte de `correctionKey`

La cle a une utilite de correlation: elle est placee dans les metadonnees des
transactions. `Disputes` l'utilise aussi comme cle de `db.disputes.corrections`:
pour une correction cible, cette entree n'est enregistree qu'apres les deux
ecritures reussies; pour une correction simple, elle l'est apres la mutation
unitaire reussie.

Cette protection ne garantit donc pas l'idempotence de l'operation:

- La branche d'echec partiel n'enregistre pas l'entree cible. Le rejeu ne trouve
  donc pas d'etat persistant de correction a dedupliquer.
- `Ledger.CommitLocalTransaction` compare `transactionId` et le hash du contenu;
  il ne recherche jamais `correctionKey`. Une cle identique avec un nouvel ID
  represente une nouvelle transaction.
- `Dibs.NewId("tx")` genere un ID base sur l'heure et une partie aleatoire; le
  code de correction ne reemploie pas l'ID ni le contenu immuable d'une
  tentative.
- L'entree persistante de `Disputes` n'est pas appendue avec les transactions
  dans un journal commun et n'est pas une preuve que toutes les jambes existent
  dans le ledger cible.
- La cle est construite par concatenation de champs, mais n'inclut pas le
  `ledgerId` ni un hash complet du payload immutable. Elle n'est donc pas un
  identifiant canonique de mutation multi-ledger.

En consequence, la cle peut reconnaitre certains succes deja enregistres au
niveau `Disputes`, si ce chemin est atteint, mais elle ne fournit ni
exactly-once, ni detection de compensation incomplete, ni deduplication
cross-ledger ou V2.

### 3. Ledger, MultiLedger et historique

`findTransaction` appelle `GetTransactionForAward`/`GetAllTransactions` sans
`ledgerId`. `attachedContext` et les payloads de correction conservent la saison
et les references d'evidence, mais pas le ledger d'origine. Les appels de
mutation retombent eux aussi sur le ledger actif. `SetViewLedger` n'est pas une
solution de scope: c'est une selection de consultation separee.

Si la ligne d'origine n'est pas dans le ledger actif, `targetCorrectionDetails`
peut ne pas disposer de son montant. La correction d'attribution peut alors
continuer sans les deux jambes comptables et resoudre la demande. En cas de
changement de ledger, une cle persistante ne prouve pas que les transactions
retournees appartiennent au ledger original.

`appendValidated` met a jour l'index `evidenceTransactions[evidenceId]` avec un
seul `transactionId`. Les deux jambes d'une correction cible partagent
l'evidenceId; la seconde remplace donc la premiere dans cet index. Les deux IDs
sont conserves dans le dossier apres succes, mais pas dans cet index et pas dans
le dossier en cas d'echec partiel.

Les corrections actuelles ajoutent des transactions et ne modifient pas la
ligne originale; l'invariant append-only est preserve par ce chemin. Il n'existe
toutefois pas de recovery qui permette de conclure automatiquement si une ligne
isol ee est un transfert partiel, une compensation, ou une autre mutation.

### 4. ProtectedActions, autorite et erreurs

L'autorisation GM/Officer n'est pas absente: `Disputes.Resolve` passe par son
controle d'officier et `ProtectedActions.Execute` appelle `Permissions.Evaluate`
au moment de chaque mutation. Le ledger canonique V2 valide aussi le coordinateur,
l'epoch et l'identite de l'expediteur. Ces controles doivent etre conserves.

Le probleme V2 est que `source="dispute-center"` n'emprunte pas le chemin
canonique qui impose le coordinateur. Une mutation locale peut ainsi etre
acceptee par un officier autorise sans devenir un commit canonique; ce n'est pas
une absence de GM/Officer, mais une difference de chemin d'autorite et de
replication.

Les wrappers `ledger.use`/`ledger.refund` ne conservent que le premier retour du
Ledger. `ledger.adjust` capture un code de rejet, mais le transmet specialement
seulement pour `MANUAL_ADMIN`; un rejet `dispute-center` peut remonter le code
de decision de permission ou un diagnostic generique au lieu de la cause Ledger.
Le resultat de compensation est encore moins visible, puisqu'il est ignore.

### 5. Persistance et synchronisation V2

En V2, `AdminAdjust` ne route vers `commitCanonicalAdminAdjustment` que lorsque
la source vaut `MANUAL_ADMIN`. Les corrections `dispute-center` de type
`DIB_ADMIN_ADJUSTMENT` et `DIB_REFUNDED` peuvent passer par
`CommitLocalTransaction`; le garde V2 de cette fonction bloque `DIB_USED`, mais
pas ces deux types. Le chemin canonique construit un `AWARD_COMMIT`, fait
avancer la sequence/racine et l'annonce. Le chemin local ne le fait pas.

`SyncV2.BuildLedgerDigest` expose la sequence et la racine canoniques; les
transferts de detail V2 autorisent `AWARD_COMMIT`, et le receveur applique ce
commit dans `Ledger.ApplyAwardCommit`. Aucun transport generique des seules
transactions locales de correction n'a ete identifie dans le chemin audite.
Une correction locale peut donc changer le solde affiche sur le poste qui l'a
faite sans changer le digest canonique ni fournir aux autres membres les memes
ecritures. Une correction `ledger.use` est un cas different: elle est refusee
sous V2 par le garde local, et sa proposition eventuelle n'est pas preservee
uniformement par les wrappers.

Les doubles de test partagent des tables SavedVariables; ils ne prouvent pas une
atomicite disque ou une persistance immediate. Aucune garantie de commit durable
avant la sauvegarde WoW ne peut etre deduite de ces fichiers.

## Cause fondamentale

**Hypothese de cause racine — confiance elevee sur la structure du code,
moyenne sur la frequence en Retail.** Une correction composee est modelisee
comme plusieurs mutations unitaires locales, avec un etat de correction ecrit
apres les effets, au lieu d'etre une seule operation ledger-scoped, identifiable
et reappliquable. La compensation est une tentative best-effort non journalisee.
En V2, le routage par `source` laisse en plus certaines corrections hors du
journal canonique observe par SyncV2. Les IDs de transaction frais et l'absence
de ledgerId explicite empechent le dedup/recovery existant d'etablir une
operation unique.

La cause est donc confirmee par les chemins de code, mais aucun echec reel de
compensation n'a ete observe en Retail; le niveau d'occurrence reste inconnu.

## Evaluation des risques

| Risque | Niveau | Preuve / limite |
|---|---|---|
| Solde partiellement transfere ou applique plusieurs fois apres echec/retry | Critique | Deux mutations, rollback ignore, etat de correction absent sur l'echec; rejet runtime non reproduit |
| Divergence persistante entre membres V2 | Critique | Mutations locales hors de la sequence/hash canoniques; test multi-client non execute |
| Mutation du mauvais ledger ou correction d'attribution sans mutation attendue | Eleve | Recherche et mutation basees sur le ledger actif, sans ledgerId attache a l'evidence |
| Diagnostic d'echec insuffisant pour detecter/reparer | Eleve | Erreurs Ledger perdues dans les wrappers; erreur du rollback ignoree |
| Alteration silencieuse des transactions historiques | Faible dans le chemin audite | Les corrections ajoutent des transactions; aucun edit de transaction originale observe |
| Bypass de GM/Officer | Non etabli | Les protections d'autorisation sont presentes; le defaut concerne surtout le chemin canonique/coordonateur |

## Remediation proposee

**Recommandation: une operation de correction canonique, multi-jambes,
ledger-scoped et rejouable, plutot qu'une succession de transactions compensees.**

1. Construire un payload immuable valide avant tout effet: guild, `ledgerId`,
   saison, demande/revision, evidence, transaction originale, acteur verifie,
   raison, montant et jambes signees. Si la transaction originale existe, son
   `ledgerId` determine le scope; si aucune ligne n'est liee, ne pas retomber
   silencieusement sur le ledger actif. Le comportement pour une correction
   d'attribution seule doit etre explicite.
2. Attribuer a l'operation un `operationId` persistant et stable, lie au
   `ledgerId` et au hash du payload canonique. Indexer l'ID au niveau du ledger:
   meme ID/meme hash = replay sans nouvel effet; meme ID/hash different =
   conflit rejete. Attribuer aussi des IDs stables aux jambes. Conserver
   `correctionKey` comme metadonnee de compatibilite si necessaire, mais ne pas
   la traiter comme une cle de dedup sans cet index et cette validation.
3. Faire de la correction un seul enregistrement canonique versionne contenant
   toutes ses jambes, par exemple `LEDGER_OPERATION_COMMIT` avec un tableau
   valide de transactions. Valider l'autorite, l'original, le ledger approuve,
   les identites, les montants et l'absence de conflit pour toutes les jambes
   avant d'ajouter l'operation. Une seule sequence/hash represente alors la
   correction complete; ne pas emettre deux commits independants qui
   exposeraient un transfert intermediaire.
4. Dans V2, accepter l'operation seulement sous l'autorite actuelle prevue par
   le protocole. Un officier non-coordinateur doit passer par une proposition
   de correction relayee au coordinateur, avec le meme `operationId`; il ne
   faut jamais retomber sur `CommitLocalTransaction` si V2 exige un commit
   distribue. A la reception, verifier l'expediteur reel, la guilde, le
   coordinateur, l'epoch, la sequence, le hash precedent, le `ledgerId`, le
   hash du payload et les doublons.
5. Faire des transactions, soldes et statut de demande des projections
   reconstruisibles depuis le journal canonique. L'enregistrement complet de
   l'operation doit preceder la mise a jour des projections; au chargement,
   rejouer ou verifier les operations deja acceptees et signaler explicitement
   tout etat incomplet. Une erreur ne doit pas retourner un succes ni cacher
   une compensation ratee. Propager le code de rejet Ledger et, en cas d'etat
   a reparer, un diagnostic/recovery explicite.
6. Une compensation ne devrait pas etre la voie normale pour un transfert a
   deux jambes: rejeter l'ensemble avant commit si une jambe est invalide. Si
   un evenement compose est accepte mais qu'une projection s'interrompt, la
   reprise doit rejouer la meme operation idempotente, pas emettre une
   compensation aveugle. Toute reparation d'anciennes ecritures partielles doit
   etre une nouvelle operation auditee apres reconciliation.

Le modele de journal unique rend les rejouements detectables et les projections
reconstructibles, mais **ne transforme pas SavedVariables en stockage atomique
ou en flush immediat**. Le contrat de livraison doit distinguer l'operation
acceptee en memoire de sa sauvegarde par WoW. Sans mecanisme de persistance ou
d'accuse durable specifique, ne pas promettre une survie a une fermeture
brutale survenue avant sauvegarde. Les membres qui se reconnectent doivent
pouvoir recuperer le commit canonique conserve par la source autoritaire; un
client hors ligne ne peut converger avant de retrouver une source valide.

### Solutions evaluees

- **Deux commits canoniques separes avec compensation**: rejete comme solution
  principale. Cela replique chaque jambe, mais laisse un etat intermediaire
  visible et demande encore une saga persistante, une compensation fiable et un
  recovery complexe.
- **Conserver les deux appels locaux et reutiliser seulement `correctionKey`**:
  insuffisant. La cle n'est pas verifiee par Ledger et n'est ecrite qu'apres
  succes; elle ne protege pas les reprises partielles.
- **Journal d'operation + identifiant stable + commit compose**: recommande.
  Il regroupe idempotence, scope ledger, replay des messages et application
  multi-jambes dans la sequence canonique existante.
- **Transaction distribuee 2PC ou quorum de tous les clients**: non recommande
  a ce stade. Le chemin audite est un journal ordonne par coordinateur avec
  rattrapage; aucun protocole 2PC ne justifie sa complexite. Le niveau
  d'accuse requis pour declarer la convergence devra etre decide dans le
  contrat V2, sans supposer que tous les membres sont en ligne.

## Compatibilite avec les donnees existantes

- Ne jamais modifier ni supprimer les transactions historiques; les nouvelles
  corrections restent des enregistrements append-only lies a l'original.
- Ne pas reinterpreter automatiquement les anciennes `correctionKey` comme des
  IDs idempotents et ne pas regenerer leurs hashes.
- Les corrections completes deja listees dans `db.disputes.corrections`
  peuvent aider a retrouver des IDs, mais ne prouvent pas la presence des
  transactions dans chaque ledger ou sur chaque membre.
- Pour les corrections partielles historiques, grouper les candidats par
  `reviewRequestId`, `evidenceId`, `originalTransactionId`, joueur, signe et
  `correctionKey` (y compris le suffixe `:rollback`), puis produire un rapport
  de reconciliation. Ne pas compenser ou synchroniser automatiquement une
  ligne isolee: son intention et son ledger d'origine peuvent etre ambigus.
- Ajouter un schema/version de commit sans invalider les anciens
  `AWARD_COMMIT`; garder les anciennes transactions consultables et importer/
  restaurer les nouveaux enregistrements via les chemins Backup/ImportExport.
- Les receveurs V2 actuels n'acceptent pas un type de transfert generique pour
  cette operation. Negocier/capabiliser le nouveau format et refuser
  l'operation si un chemin de replication compatible n'est pas disponible; ne
  pas utiliser le chemin local comme fallback silencieux.
- Les appels existants `Disputes.Resolve`, les IDs serialises et les controles
  ProtectedActions doivent rester compatibles ou etre migres explicitement.

## Fichiers applicatifs potentiellement concernes

- `src/modules/Disputes.lua` — preparation, scope et statut recuperable de
  l'operation; aucune mutation comptable multi-appels.
- `src/modules/ProtectedActions.lua` et, si un nouveau type de commande le
  necessite, `src/modules/Permissions.lua` — delegation protegee unique et
  propagation des rejets.
- `src/modules/Ledger.lua` — enveloppe multi-jambes, identifiant/index de
  deduplication, verification complete, append et reconstruction des
  projections.
- `src/modules/MultiLedger.lua` — resolution explicite du ledger d'origine et
  interdiction de repli implicite sur le ledger actif.
- `src/modules/Governance.lua` — autorite coordinateur, reception et proposition
  de correction si l'acteur local n'est pas le coordinateur.
- `src/modules/SyncV2.lua` — schema, allowlist, detail, validation, annonce,
  rejeu, gap-recovery et gating de compatibilite pour le commit compose.
- `src/modules/Backup.lua` et `src/modules/ImportExport.lua` — seulement si le
  schema du journal canonique ou son index requiert une adaptation de
  sauvegarde/restauration.
- Suites candidates: `tests/integration/dispute_center_spec.lua`,
  `tests/integration/request_followup_spec.lua`,
  `tests/integration/b06_distributed_ledger_spec.lua`,
  `tests/integration/multi_ledger_sync_spec.lua` et
  `tests/unit/b03_local_ledger_spec.lua`.
- Documentation a mettre a jour lors d'une implementation approuvee:
  contrat de synchronisation et SavedVariables, ainsi que la specification du
  Dispute Center. Aucun de ces fichiers n'est modifie par cette evaluation.

## Plan de migration

1. Lire les anciens enregistrements et produire un inventaire de corrections
   completes, partielles, ambiguës et locales-only; comparer les ledgers
   concernes sans muter les donnees.
2. Introduire le nouveau schema en lecture additive; les anciens journaux
   gardent leur representation et leurs IDs.
3. Activer l'ecriture composee seulement apres validation du protocole V2 et de
   la compatibilite des clients concernes; sinon refuser avec un diagnostic.
4. Ne pas convertir automatiquement les anciennes jambes en commits V2:
   l'ordre, les balances de depart et l'origine d'une eventuelle compensation
   manquante peuvent etre inconnus. Toute reconciliation choisie est
   un nouveau commit audite et explicitement autorise.
5. Verifier backup, restauration, redemarrage, reprise des gaps et conservation
   des anciennes transactions avant activation generalisee.

## Tests de non-regression necessaires

Les assertions portent sur les balances, le contenu append-only, le journal,
les IDs, la sequence/hash canonique, l'etat de demande et la convergence.

1. **Correction normale** — transfert de `n` entre deux membres: les deux
   jambes portent le meme `operationId`, le ledger lie, l'original et la raison;
   la balance source augmente de `n`, celle de la cible diminue de `n`, une seule
   operation canonique est ajoutee et l'original est inchange.
2. **Echec de la premiere jambe / validation** — aucune transaction, projection,
   sequence, racine ou resolution de demande ne change.
3. **Echec de la deuxieme jambe** — rejet du bundle complet avant commit; ni
   demi-transfert, ni statut Resolved, ni transaction orpheline.
4. **Echec d'une compensation** — le flux normal ne depend pas d'une
   compensation best-effort. Pour un chemin de recovery legacy, l'echec doit
   rester durablement visible, avec erreur primaire et erreur de recovery
   distinctes; aucun succes ne doit etre rapporte.
5. **Retry apres echec partiel** — reprendre avec le meme `operationId` et le
   meme hash produit un seul effet total; le meme ID avec un autre payload
   retourne un conflit sans mutation.
6. **Meme correctionKey repetee** — les appels repetes, avec ou sans reload,
   ne changent pas une seconde fois les balances et ne creent pas une seconde
   paire de transactions.
7. **Rechargement** — reinitialiser les modules depuis le meme snapshot
   SavedVariables; retrouver le commit, ses jambes et l'index idempotent.
   Distinguer ce test de la garantie de flush disque, qui n'est pas offerte par
   les doubles.
8. **Changement de ledger actif ou de vue** — la correction touche uniquement
   le `ledgerId` explicite de l'operation; changer le ledger de vue ne change
   jamais sa cible. Ledger inconnu/non approuve: echec ferme sans mutation.
9. **Synchronisation multi-membres V2** — coordinateur et followers ont les
   memes transaction IDs, balances, epoch, sequence et root hash apres commit.
   Un client en retard converge par rattrapage avant d'annoncer l'etat comme a
   jour.
10. **Messages dupliques ou differes** — commit identique rejoue = no-op
    idempotent; sequence en avance = SYNC_BEHIND; hash/position contradictoire
    = rejet, sans effet partiel.
11. **Interruption entre journal et projections** — injecter une panne apres
    l'enregistrement canonique puis entre les mises a jour de projections;
    au redemarrage, reconstruire les deux jambes une seule fois depuis le
    journal.
12. **Conservation de l'historique** — l'original et toute correction
    precedente restent identiques octet/logiquement; toutes les nouvelles
    jambes referencent la demande et l'original; les balances restent
    derivables de l'historique.
13. **Autorisation et coordinatorat** — un non-officier est refuse; un officier
    verifie sans autorite de commit passe par la proposition prevue; un sender
    usurpe ou un ancien coordinateur est refuse par le receveur.
14. **Evidence sans transaction** — le resultat explicite choisi pour
    l'attribution seule ou le refus est applique; jamais de resolution laissant
    croire qu'un solde a ete corrige alors qu'aucune operation ne l'a fait.

## Criteres d'acceptation verifiables

- Une correction est liee a un unique `guildKey`, `ledgerId`, `requestId`,
  `evidenceId`, transaction originale si presente, operation ID et hash de
  payload.
- La meme operation ne peut modifier le solde qu'une fois, y compris apres
  retry, rechargement et livraison dupliquee; une reutilisation de son ID pour
  un contenu different est refusee.
- Une correction de deux membres est acceptee/rejetee comme un bundle: aucune
  jambe n'est visible dans les projections avant acceptation complete.
- Un membre V2 ne voit pas une correction acceptee comme canonique tant qu'il
  ne possede pas le meme commit ou qu'un etat explicite `SYNC_BEHIND` ne le
  signale; aucun chemin local silencieux ne contourne le protocole.
- Tous les rejets du Ledger et les echecs de recovery sont restitues au caller
  avec des diagnostics distincts; aucune compensation non verifiee n'est
  consideree comme reussie.
- Les permissions GM/Officer, l'autorite coordinateur V2 et la validation du
  sender sont toujours verifiees au point d'acceptation.
- Les transactions historiques ne sont ni modifiees ni supprimees; tout
  repair d'un ancien cas partiel est une nouvelle action append-only, auditee
  et explicitement approuvee.
- La documentation ne promet aucune persistance atomique ou immediate au-dela
  de ce que SavedVariables et la replication testee garantissent.

## Conditions necessaires avant implementation

1. Decider le scope d'une correction quand aucune transaction originale n'est
   retrouvee: ledger explicitement choisi, correction d'attribution seule avec
   resultat distinct, ou refus.
2. Definir le contrat de compatibilite V2 et la politique fail-closed pour les
   clients qui ne reconnaissent pas le commit compose.
3. Definir ce qui constitue un commit accepte et quelle garantie peut etre
   annoncee avant la sauvegarde WoW; ne pas presenter une ecriture SavedVariables
   en memoire comme une persistance disque confirmee.
4. Faire une analyse/reconciliation sans mutation des anciennes corrections
   locales ou potentiellement partielles, puis choisir explicitement les cas
   necessitant une nouvelle ecriture.
5. Approuver le schema d'operation, son index idempotent, le modele de
   proposition au coordinateur et les transitions de recovery dans une feature
   Spec Kit; ne pas etendre le perimetre aux autres mutations ledger sans
   preuve.
6. Ajouter les tests de panne, d'integration V2, de backup/restore et
   d'autorite ci-dessus avant l'activation; tests Fengari seuls ne valent pas
   certification Retail ni verification multiclient.

## Risques et considerations

- Un nouveau type de commit modifie un contrat serialise et la liste de types
  acceptes par SyncV2; compatibilite et versionnement sont bloquants.
- Un journal compose doit etre reconstruit sans s'appuyer sur des projections
  de balance qui peuvent etre partielles. Le code actuel stocke commits,
  transactions, indexes et projections separement dans les SavedVariables.
- Le statut de demande est un autre enregistrement persistant; il doit pouvoir
  etre reconcilie avec un commit accepte apres rechargement.
- Le maintien d'une voie de compatibilite locale en V2 annulerait la garantie
  de convergence; tout fallback doit echouer ferme.
- Les historiques preexistants peuvent contenir des cas partiels ambigus; les
  reparer automatiquement risquerait de produire un deuxieme effet comptable.
- L'evaluation ne trouve pas de preuve que l'autorisation GM/Officer elle-meme
  est contournee, ni que les transactions originales sont editees.

## Questions ouvertes

- **[NEEDS CLARIFICATION]** Pour une correction liee a une transaction, le
  ledger original doit-il toujours prevaloir sur le ledger actif? Recommandation:
  oui; si l'original est absent, refuser le transfert plutot que changer de
  ledger implicitement.
- **[NEEDS CLARIFICATION]** Une correction sans transaction comptable liee
  peut-elle fermer le dossier comme changement d'attribution seulement?
- **[NEEDS CLARIFICATION]** Quelle est la politique pour les membres V2
  temporairement hors ligne ou executant une version ne supportant pas le
  nouveau format? Recommandation: pas de commit local fallback; appliquer le
  rattrapage lorsque le client compatible revient.
- **[NEEDS CLARIFICATION]** Quel niveau de durabilite est requis avant de
  confirmer le succes a l'Officer, compte tenu du modele SavedVariables de WoW?
- **[NEEDS CLARIFICATION]** Les echecs de deuxieme ecriture et de compensation
  devront etre provoques par injection de faute en tests; aucune cause Retail
  deterministe n'a ete identifiee par cette analyse.
