# Release readiness assessment — RCLootCouncil_dibs

Statut global : **READY_FOR_RETAIL_TESTING**

Ce document evalue la readiness de la version de travail en cours pour une
**campagne de validation manuelle dans WoW Retail**. Il ne declares pas
`READY_FOR_RELEASE` : la publication reste subordonnee aux validations
manuelles listees en section 14, dont aucune n'a encore ete executee dans
le client.

Date d'evaluation : 2026-10-21
Perimetre : code de production de `src/` (hors bibliotheques), suite de
tests Lua, compilateur Lua 5.1, documentation generee, garde de
bibliotheques.

---

## 1. Etat des RF critiques

47 fiches RF sont enregistrees dans `docs/code-audit/INDEX.md` :
**29 `FIXED`**, 10 `KEEP`, 6 `NEED_UPDATE`, 1 `PARTIALLY_FIXED`,
1 `TO_REMOVE`.

| RF | Statut | Risque | Objet |
|---|---|---|---|
| RF-0012 | FIXED | HIGH | Transfert de correction canonique non recupere |
| RF-0013 | **FIXED** | HIGH | Decouverte legacy partielle ; collecte paginee (A1) et proposition officier validee (B1) implementees le 2026-10-21 |
| RF-0014 | FIXED | HIGH | Un changement de main fusionnait deux joueurs sans lien |
| RF-0017 | FIXED | HIGH | Identifiant de groupe fourni par le declarant |
| RF-0020 | FIXED | MEDIUM | Surface de revue des declarations main/alt |
| RF-0022 | FIXED | HIGH | Repli contournant l'interdiction de Pre-Dibs publics |
| RF-0026 | FIXED | HIGH | La reconstruction des projections divergait du chemin incremental |
| RF-0027 | FIXED | HIGH | Le hachage canonique supposait un instantane d'identite present |
| RF-0031 | FIXED | HIGH | Une proposition terminale conservait sa reservation de Dib |
| RF-0033 | FIXED | HIGH | Un import complet annulait un ledger local plus recent |
| RF-0034 | FIXED | HIGH | Une reservation diffusee n'etait jamais liberee chez les pairs |
| RF-0035 | FIXED | HIGH | Le transfert de coordinateur ne convergeait pas |
| RF-0038 | FIXED | HIGH | Un snapshot canonique corrompu etait accepte |
| RF-0041 | FIXED | HIGH | Une restauration ne validait pas l'instantane |
| RF-0042 | FIXED | HIGH | Un paquet de recovery contradictoire etait applique |
| RF-0045 | FIXED | HIGH | Une demande de Pre-Dibs etait copiee dans un second ledger |
| RF-0046 | FIXED | HIGH | Une sauvegarde valide ne pouvait plus etre restauree |
| RF-0047 | FIXED | HIGH | La validation d'instantane n'etait pas exercee par la restauration |

**Aucun RF P0 ouvert.** Le dernier RF non entierement corrige, RF-0013, a
ete tranche et implemente le 2026-10-21 (section 11).

## 2. Etat des tests

| Mesure | Valeur |
|---|---|
| Suites Lua | **209** fichiers |
| Cas de test | **1 501** |
| Assertions | **8 800+** |
| Densite moyenne | **5,8 assertions par cas** |
| Suites a zero assertion | **0** |
| Resultat | **1501 PASS / 0 FAIL** |
| Code de sortie | **0** |

## 3. Qualite des tests

La qualite n'est pas mesuree par le nombre de tests, mais par la capacite
d'un test a **detecter** une regression. Cette capacite a ete verifiee
experimentalement en session 12 par **mutation controlee** : chaque defaut
historique a ete reinjecte dans la source de production, dans un
environnement isole, et la suite supposed le couvrir a ete reexecutee.

| Constat | Detail |
|---|---|
| Suites auditees par mutation | 24 mutations (18 defauts historiques + 3 de la fixture + 3 de confirmation) |
| Defauts detectes | **22 / 24** |
| Faux positifs demonstres | **1** (RF-0041), corrige par la suite RF-0047 |
| Echec attendu non corrige | 1 (mutation ciblee vers la mauvaise suite, detectee des qu'elle vise la bonne) |
| Fichier restaure | hash SHA-256 identique apres chaque reinjection |
| Isolation de la mutation | ligne de base pristine capturee avant toute mutation ; restauration depuis cette ligne de base ; reverification que le texte mute a disparu |

Un **faux positif** a ete decouvert et corrige : la suite RF-0041 affirmait
que la restauration refusait un instantane damage, mais n'exercait que le
refus de l'**apercu** ; la restauration etait ensuite appelee avec
l'identifiant litteral `"none"` et renvoyait `PREVIEW_NOT_FOUND`, donc
l'assertion passait pour la mauvaise raison. La meme mutation qui laissait
la suite verte echoue aujourd'hui **4 tests** de la suite RF-0047.

La suite de tests elle-meme est desormais couverte par la suite
`tests/integration/distributed_fixture_isolation_spec.lua`, qui verifie que
la fixture multi-clients isole bien reellement ses clients (environnement
Lua, SavedVariables, namespace, serialisation, perte de message,
reconnexion, idempotence, surface de permission, expéditeur forge).

## 4. Couverture des contrats

Les contrats suivants sont couverts par des tests **discriminants**,
c'est-a-dire qui echouent lorsque le contrat est viole :

| Contrat | Preuve |
|---|---|
| Ledger append-only | `rf0026`, `rf0033`, `rf0038`, `rf0039` |
| Integrite des corrections canoniques | `canonical_dispute_operation`, `canonical_dispute_sync` |
| Isolation des permissions | `rf0014`, `rf0017`, `rf0020`, `permissions_spec` |
| Portee de ledger | `rf0032`, `rf0033`, `rf0037`, `rf0045` |
| Non-double comptabilisation | `rf0031`, `rf0034`, `rf0036`, `rf0043` |
| Convergence distribuee | `rf0035`, `rf0036`, `rf0037`, `rf0043`, `distributed_fixture_isolation` |
| Reprise apres incident | `rf0039`, `rf0043` |
| Restauration et sauvegarde | `rf0041`, `rf0046`, `rf0047`, `backup_import_profiles`, `backup_sync_restore` |
| Confidentialite des donnees | `sync_privacy`, `great_vault_privacy`, `dispute_authority_privacy`, `audit_export_contract` |
| Compatibilite de schema | `migration_spec`, `rf0027`, `persistence_recovery` |

## 5. Problemes bloquants

**Aucun bloqueur pour la campagne Retail.**

Aucun element n'est en attente de decision. RF-0013 a ete tranche et
implemente le 2026-10-21 (section 11) : la collecte est paginee avec un
curseur persistant, et la proposition officier porte le perimetre, le
volume, le motif et les sources illisibles que le Maitre de guilde
verifie avant d'approuver. Ces deux decisions n'affectaient aucun
parcours utilisateur existant.

## 6. Regressions restantes

Aucune regression introduite par les sessions d'audit. Le seul constat
ouvert de la session 12 est le faux positif de test RF-0041, **corrige**.

Les 6 fiches `NEED_UPDATE` (RF-0001, RF-0002, RF-0004, RF-0006, RF-0009,
RF-0010) sont des constats de qualite de code sans risque P0/P1 confirme :
ils portent sur une detection de fonction au lieu d'un succes, un fallback
de preference, une documentation de types, un apercu de restauration
presentant moins d'effets, et une sonde de synchronisation. Aucun n'a de
comportement metier incorrect demontre ; tous demandent un arbitrage de
contrat pour etre corriges.

## 7. Etat des verrous

| Verrou | Valeur | Verifie |
|---|---|---|
| `Dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED` | `false` | oui |
| `DISPUTE_OPERATION_WRITES_ENABLED` | `false` | oui |
| T041 (validation Retail RF-0012) | `PENDING_MANUAL_VALIDATION` | oui |
| Version TOC | `## Version: 0.8.10` (inchangee) | oui |
| `OfficerUI.lua:3632` | exclu, correctif preserve, non rouvert | oui |

Aucune activation en production, aucune incrementation de version, aucun
deploiement dans WoW.

## 8. Compatibilite Lua 5.1

Compilation effective avec **Lua 5.1.5** (`luac51.exe`, construit depuis
la distribution amont `lua-5.1.5.tar.gz`) :

- **105 fichiers** de source applicative compiles ;
- **0 erreur** ;
- limite d'upvalues verifiee (maximum 56 pour une limite de 60) ;
- la compilation 5.4 ne remplace pas cette preuve : elle est complementaire.

## 9. Compatibilite SavedVariables

- La disposition `db.<section>` est inchangee ; aucun renommage n'a ete
  fait sans migration.
- La cle d'isolation par guilde (`realm:<guild>`) est preservee.
- Les donnees historiques sont conservees a l'identique : les correctifs
  d'audit n'ont **jamais** reecrit une transaction.
- La reprise apres echec de persistance, la quarantaine et la
  sauvegarde de demarrage sont couvertes par `persistence_recovery_spec`.
- La migration depuis les schemas anterieurs est couverte par
  `migration_spec`, `rf0027`, `predibs_migration`, `great_vault_migration`.

## 10. Compatibilite Backup

| Garantie | Etat |
|---|---|
| Une sauvegarde ecrite par l'addon est restaurable | **VERIFIED** (RF-0046, C01/C07/C09/C10) |
| Une sauvegarde de plus de 250 Ko est restaurable | **VERIFIED** (C01) |
| Une sauvegarde portant du texte joueur est restaurable | **VERIFIED** (C15) |
| Une sauvegarde anterieure a RF-0041 est restaurable | **VERIFIED** (C02) |
| Un payload altere est refuse avant mutation | **VERIFIED** (C14, D01, D04) |
| Un checksum incorrect est refuse | **VERIFIED** (C03, C06, D02) |
| Une sauvegarde d'une autre guilde est refusee | **VERIFIED** (C04, D03) |
| Une sauvegarde incomplete est refusee | **VERIFIED** (C05) |
| La restauration revalide l'instantane | **VERIFIED** (RF-0047, D01 a D04) |
| Une restauration repetee ne change pas l'etat | **VERIFIED** (C13) |
| L'historique existant est preserve | **VERIFIED** (toutes les suites backup) |
| Une sauvegarde sans attestation reste restaurable | **VERIFIED** (C11, C12) — voir section 12 |

## 11. Compatibilite SyncV2

- Protocole V2 impose par la gouvernance, avec epoque, sequence, hash
  precedent et hash de contenu.
- Reprise de gap, transfert de coordinateur, rejection d'une epoque
  perimee, et non-application d'un record incompatible : couverts par
  `rf0035`, `rf0036`, `rf0037`, `rf0038`, `rf0043`.
- La fixture multi-clients est verifiee **elle-meme** par
  `distributed_fixture_isolation_spec` : chaque client possede son
  environnement Lua et ses SavedVariables, les messages sont reellement
  serialises, un client hors ligne perd reellement le message et le
  recupere a la reconnexion, une redelivery est idempotente, une
  declaration d'expediteur forgee est refusee.
- Aucun chemin local de repli ne contourne SyncV2.

## 12. Etat des permissions

| Surface | Regle | Test |
|---|---|---|
| Lecture du ledger par un tiers | refusee | `combat_safety`, `rf0014_security_matrix` |
| Resolution d'un litige par un membre | refusee (`GUILD_ADMIN_REQUIRED`) | `dispute_integrity_hardening` B05/B16/B29 |
| Approbation main/alt par un non-officier | refusee | `rf0020` (2 suites) |
| Pre-Dibs publics desactive | refus sans ecriture | `rf0022`, `rf0028`, `rf0030` |
| Export d'audit anonyme par un membre | refuse | `audit_export_contract` |
| Lecture d'une demande par un joueur distant | refusee | `dispute_integrity_hardening` B13/B15 |
| Soumission de litige au nom d'un autre | refusee | `dispute_integrity_hardening` B26 |

Les permissions GM et Officier restent distinctes. Le code ne pretend
jamais avoir enregistre une mutation qu'il n'a pas effectuee.

**Frontiere explicite.** Un instantane ecrit avant l'introduction de
l'attestation ne porte **aucune** attestation d'integrite : son payload
est alors applique tel quel. C'est un choix de compatibilite assume — un
instantane sans attestation resterait irrestaurable, ce qui supprimerait le
chemin de recuperation des guildes qui en possedent deja. Un checksum
detecte une **corruption**, il n'est **jamais** une preuve d'authenticite.

## 13. Etat de la documentation

| Element | Etat |
|---|---|
| `validate_audit.py` | **0 erreur** — 47 tags Lua / 47 fiches, 0 avertissement |
| Documentation generee | **PASS** — 8/8 fichiers identiques, `Test-DibsDocsCrossVersion.ps1` |
| Pester (generation de documentation) | **26 PASS / 0 FAIL** |
| Journal d'audit | `docs/code-audit/AUTONOMOUS-SESSION-STATUS.md` a jour |
| Journal de progression | `docs/code-audit/PROGRESS.md` reconcilie (58 FULL / 0 PARTIAL / 0 INVENTORIED) |
| Fiches RF | 47 fiches, toutes ancrees et annotees dans la source |
| `CHANGELOG.md` | entrees des sessions 8 a 12 |

## 14. Tests Retail necessaires

La publication reste **soumise** a la campagne Retail. La matrice
complete (89 scenarios), avec un statut par scenario, est dans
[`RETAIL-TEST-MATRIX.md`](RETAIL-TEST-MATRIX.md).

Aucun scenario ne peut etre marque `MANUAL_PASS` sans execution reelle
dans le client. T041 (validation Retail RF-0012) reste
`PENDING_MANUAL_VALIDATION`.

## 15. Verdict

| Element | Statut |
|---|---|
| Qualite du code audit | `NOT_VALIDATED` — 47 fiches, toutes tranchees |
| Qualite de la suite de tests | `NOT_VALIDATED` — discriminant verifie par mutation, campagne Retail requise |
| Integrite des donnees | `NOT_VALIDATED` — invariants verifies en simulation, validation Retail requise |
| Preparation de la campagne Retail | **`READY_FOR_RETAIL_TESTING`** |

Le code est **pret pour une campagne de validation manuelle dans WoW
Retail**. Il n'est **pas** declare pret pour la publication : la
publication exige la campagne Retail, dont la totalite des scenarios
`MANUAL_PENDING` doit d'abord etre executee et documentee.
