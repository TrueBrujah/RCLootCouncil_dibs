# Release candidate — build manifest

Ce document identifie la version candidate construite le **2026-10-22** pour
la campagne Retail A. Il est produit **hors du depot** : le depot n'est
jamais modifie par la construction.

---

## 0. Candidate courante — registre de fonctionnalites

| Element | Valeur |
|---|---|
| Nom de l'archive | `RCLootCouncil_dibs-0.8.10-r4-feature-registry-candidate.zip` |
| Emplacement | `C:\Users\yc58\RCLootCouncil_dibs-candidate-20261022-043948\` |
| **SHA-256 de l'archive** | `4919EA05A889FD29FD86090890513A5368B223DA25994994B677228370878909` |
| Taille de l'archive | 906 380 octets |
| Fichiers dans le paquet | **139** |
| **Empreinte du contenu source** | `B7D8623FE3314AD7874976830A8585AAAC9665F4A5DCD0E86BFFDECCF6BB432E` |
| **Reference Git HEAD** | `dc388f9df313f1597e5c1a35078bb725c34c7f3e` |
| Date de construction | 2026-10-22 04:39:48 |
| Version TOC | **`0.8.10`** (inchangee) |

Cette candidate inclut le **registre de fonctionnalites centralise** :
`src/modules/FeatureRegistry.lua`, un catalogue canonique de 8 services
obligatoires et 19 fonctionnalites optionnelles, un point de controle
d'enforcement unique, la page Modules de l'interface officier etendue, et les
quatre documents de reference. Le TOC reste `0.8.10` : le nom de l'archive
porte le marqueur `r4-feature-registry` pour distinguer la candidate.

Toutes les candidates precedentes sont conservees.

| Candidate | Archive | SHA-256 |
|---|---|---|
| Session 13 (pre-RF-0013) | `RCLootCouncil_dibs-0.8.10-candidate.zip` | `57021074F5CCCF33CCAB80A1A239DCE44ADA27C5AA4A267E0488A9485308403F` |
| Session 16 (RF-0013 A1/B1) | `RCLootCouncil_dibs-0.8.10-rf0013-candidate-dc388f9….zip` | `C8AF12BCB46D1C994EA6C3BE9CF5CBC1320614C568A60D3E7466C43C90242E79` |
| **Registre de fonctionnalites** | `RCLootCouncil_dibs-0.8.10-r4-feature-registry-candidate.zip` | `4919EA05A889FD29FD86090890513A5368B223DA25994994B677228370878909` |

Le manifeste complet de la candidate courante, avec la liste des 139 fichiers
et les empreintes, est produit a cote de l'archive :
`C:\Users\yc58\RCLootCouncil_dibs-candidate-20261022-043948\MANIFEST.md`.

---

## 1. Candidate RF-0013 (pre-registre)

Ce qui suit decrit la candidate anterieure, qui reste conservee.

---

## 1. Identification

| Element | Valeur |
|---|---|
| Nom de l'archive | `RCLootCouncil_dibs-0.8.10-rf0013-candidate-dc388f9df313f1597e5c1a35078bb725c34c7f3e.zip` |
| Emplacement | `C:\Users\yc58\RCLootCouncil_dibs-candidate-20261022-014007\` |
| **SHA-256 de l'archive** | `C8AF12BCB46D1C994EA6C3BE9CF5CBC1320614C568A60D3E7466C43C90242E79` |
| Taille de l'archive | 895 636 octets |
| Fichiers dans le paquet | **138** |
| **Empreinte du contenu source** | `906F48D8FB3E7D393800FA70DCE4A297AE59DA454A613B7014FBE9D00840A776` |
| **Reference Git HEAD** | `dc388f9df313f1597e5c1a35078bb725c34c7f3e` |
| Date de construction | 2026-10-22T01:40:40-04:00 |
| Version TOC | **`0.8.10`** (inchangee) |

### Distinction des candidates

Le nom de l'archive porte le suffixe **`-rf0013-candidate-<HEAD>`** alors que
la version TOC reste `0.8.10`. Les deux candidats sont donc
distinguables sans que la version publiee ne soit incrementee :

| Candidate | Archive | SHA-256 |
|---|---|---|
| Session 13 (pre-RF-0013) | `RCLootCouncil_dibs-0.8.10-candidate.zip` | `57021074F5CCCF33CCAB80A1A239DCE44ADA27C5AA4A267E0488A9485308403F` |
| **Session 16 (RF-0013 A1/B1)** | `RCLootCouncil_dibs-0.8.10-rf0013-candidate-dc388f9….zip` | `C8AF12BCB46D1C994EA6C3BE9CF5CBC1320614C568A60D3E7466C43C90242E79` |

**Les deux archives sont conservees.** L'archive de la session 13 n'a pas
ete remplacee.

### Fichiers annexes produits avec la candidate

| Fichier | Contenu |
|---|---|
| `candidate-manifest.csv` | les 138 fichiers du paquet avec leur SHA-256 |
| `candidate-build.json` | les metadonnees de construction (memes valeurs que ci-dessus) |
| `<archive>.zip.sha256` | l'empreinte de l'archive, verifiable en une commande |

---

## 2. Resultats des 8 portes

| Porte | Verification | Resultat |
|---|---|---|
| 4.1 | Fichiers requis presents (`.toc`, `embeds.xml`, `Core.lua`, logo) | **PASS** |
| 4.2 | Ordre de chargement du TOC, dans les **deux** sens | **PASS** — 58 entrees, 57 Lua d'execution |
| 4.3 | Bibliotheques integrees intactes | **PASS** — 77/77 identiques |
| 4.4 | Compatibilite Lua 5.1 | **PASS** — 105 fichiers, `luac51.exe` (Lua 5.1.5) |
| 4.5 | Verrous RF-0012 fermes | **PASS** — `false` / `false` |
| 4.6 | Declarations SavedVariables | **PASS** — y compris `PerCharacter` |
| 4.7 | Version **inchangee** | **PASS** — `0.8.10` |
| 4.8 | `OptionalDeps: RCLootCouncil` | **PASS** |

### Controles complementaires

| Controle | Resultat |
|---|---|
| Les marqueurs RF-0013 A1/B1 sont presents dans le paquet | **12/12** (`BATCH_SIZE`, `MAX_EVIDENCE_PER_SOURCE`, `MAX_EVIDENCE_PER_CYCLE`, `collectionProgress`, `INCOMPLETE_EVIDENCE_SOURCE_IN_PROGRESS`, `PROPOSAL_PURPOSES`, `validateProposalOptions`, `DUPLICATE_LEDGER_PROPOSAL`, `PROPOSAL_VOLUME_MISMATCH`, `adoptLegacyProposal`, `ledgerProposals`, `pendingLocalScanSources`) |
| Fichiers exclus du paquet | `tests/`, `docs/`, `scripts/`, `.github/`, `.specify/`, `specs/`, `.git/` : **tous absents** |
| `Types.lua` | present dans le paquet mais **hors du runtime TOC** (declarations d'editeur uniquement) |

---

## 3. RF inclus

La candidate integre l'ensemble des **47 fiches RF**, dont :

| RF | Statut | Objet |
|---|---|---|
| RF-0012 | FIXED | Transfert de correction canonique non recupere (verrous **fermes**) |
| **RF-0013** | **FIXED** | **Collecte paginee (A1) et proposition officier validee (B1)** |
| RF-0014, RF-0017 | FIXED | Groupes de joueurs derives, jamais choisis |
| RF-0020 | FIXED | Surface de revue des declarations main/alt |
| RF-0022, RF-0028, RF-0030 | FIXED | Voies de Pre-Dibs publics |
| RF-0031, RF-0034 | FIXED | Reservations diffusees et liberees |
| RF-0033 | FIXED | Import complet et ledger local plus recent |
| RF-0035 | FIXED | Transfert de coordinateur |
| RF-0038 | FIXED | Snapshot canonique corrompu |
| RF-0041, RF-0046, RF-0047 | FIXED | Sauvegarde, restauration et attestation |

**Aucun mecanisme comptable canonique RF-0012 n'a ete modifie** : `Ledger.lua`,
`SyncV2.lua` et `ProtectedActions.lua` sont byte-identiques a la session 15
(empreintes SHA-256 comparees).

---

## 4. Resultats de validation au moment de la construction

| Validation | Resultat | Code de retour |
|---|---|---|
| Suite Lua complete | **1528 PASS / 0 FAIL** (212 fichiers) | 0 |
| Tests RF-0013 | **45 PASS / 0 FAIL** (5 + 12 A1 + 15 B1 + 13 verification) | 0 |
| Compilation Lua 5.1.5 | **PASS**, 105 fichiers | 0 |
| Pester | 26 PASS / 0 FAIL | 0 |
| Validation documentaire | **PASS**, 8/8 identiques | 0 |
| `validate_audit.py` | **0 erreur**, 47 tags / 47 fiches | 0 |
| `audit_guard.py verify` | exit 1, **0 violation de bibliotheque** | 1 (attendu) |
| `git diff --check` | aucune anomalie | 0 |
| `src/libs` | **77/77 intacts**, status clean | — |

---

## 5. Sauvegarde associee

| Element | Valeur |
|---|---|
| Emplacement | `C:\Users\yc58\RCLootCouncil_dibs-backup-20261022-013938\` |
| Fichiers | **979** (24,2 Mo) |
| Fichiers non suivis recopies explicitement | **107 / 107** |
| Bibliotheques protegees | **77/77 identiques** |
| Verification du manifeste | **0 fichier corrompu** |
| Sauvegarde de la session 13 | `RCLootCouncil_dibs-backup-20261021-175703\` — **conservee** |

La sauvegarde precede la construction : elle contient donc l'etat exact
qui a produit cette candidate.

---

## 6. Verification de l'archive par l'operateur

```powershell
# 1. L'empreinte de l'archive
Get-FileHash 'C:\Users\yc58\RCLootCouncil_dibs-candidate-20261022-014007\RCLootCouncil_dibs-0.8.10-rf0013-candidate-dc388f9df313f1597e5c1a35078bb725c34c7f3e.zip' -Algorithm SHA256
# attendu : C8AF12BCB46D1C994EA6C3BE9CF5CBC1320614C568A60D3E7466C43C90242E79

# 2. Le contenu du paquet
Get-Content '...\candidate-manifest.csv' | Select-Object -First 5

# 3. L'archive contient bien le paquet attendu
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::OpenRead('<archive>').Entries | Select-Object -First 5 FullName
```

---

## 7. Ce que la candidate n'est pas

- Elle n'est **pas publiee** et **pas deployee** dans WoW.
- Elle n'active **pas** le chemin canonique : les deux verrous sont fermes
  et le resteront pour la campagne A.
- Elle ne remplace **pas** la version TOC `0.8.10`.
- Elle ne remplace **pas** la candidate de la session 13.
