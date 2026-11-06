# Gel fonctionnel — version candidate Retail A

Statut : **ACTIF**

A partir de la version candidate construite le 2026-10-22
(`RCLootCouncil_dibs-0.8.10-r4-feature-registry-candidate.zip`,
SHA-256 `4919EA05A889FD29FD86090890513A5368B223DA25994994B677228370878909`),
le code applicatif entre dans une phase de **stabilisation**.

La candidate precedente
(`RCLootCouncil_dibs-0.8.10-rf0013-candidate-dc388f9….zip`,
SHA-256 `C8AF12BCB46D1C994EA6C3BE9CF5CBC1320614C568A60D3E7466C43C90242E79`)
est **conservee** et sert de point de comparaison.

---

## 0. Derogation de perimetre autorisee

Le registre de fonctionnalites centralise
(`src/modules/FeatureRegistry.lua`) a ete construit **apres** l'etablissement
initial du gel, sur autorisation explicite du proprietaire du projet. Cette
derogation est **close** : le registre fait partie de la candidate courante
et le gel s'applique de nouveau integralement a partir d'ici.

| Element | Valeur |
|---|---|
| Perimetre derogue | Registre de fonctionnalites centralise, catalogue canonique, enforcement, interface Modules, documentation |
| Livrables | `src/modules/FeatureRegistry.lua`, `src/modules/OperationalPolicy.lua`, 12 modules d'enforcement, `src/ui/OfficerUI.lua`, 4 documents, `specs/027-feature-registry/` |
| Candidate produite | `RCLootCouncil_dibs-0.8.10-r4-feature-registry-candidate.zip` |
| Statut de la derogation | **Close** |

Aucun autre perimetre n'est derogue. Le gel est de nouveau integral.

---

## 1. Ce que le gel interdit

| Interdit | Raison |
|---|---|
| **Nouvelle fonctionnalite** | La campagne Retail doit tester un etat de code delimite. Une fonctionnalite nouvelle ne serait pas couverte par la campagne. |
| **Refactoring general** | Un refactoring sans defaut demontre ne peut pas justifier le risque qu'il introduit sur un code en cours de validation. |
| **Modification du comportement comptable** sans defaut demontre | Le ledger, ses soldes, ses projections et ses identifiants sont la garantie centrale de l'addon. |
| **Modification des mecanismes canoniques RF-0012** | Les verrous sont fermes et le chemin canonique n'est pas teste par la campagne A. |
| **Increment de la version TOC** | La version `0.8.10` reste la version publiee ; le nom de l'archive distingue les candidates. |
| **Modification des bibliotheques `libs`** | Elles sont en lecture seule et leur baseline ne doit jamais etre recapturée. |
| **Modification des SavedVariables reelles** | Elles appartiennent au operateur, pas au depot. |

## 2. Ce qui reste autorise

| Autorise | Condition |
|---|---|
| **Correction d'un defaut demontre** | Les cinq conditions de la section 3 sont remplies. |
| **Test** | Un test qui n'est pas discriminant est corrige. Aucun test n'est affaibli. |
| **Documentation** | Les documents de campagne, le journal et le manifeste de la candidate. |
| **Instrumentation de diagnostic** | Uniquement dans un environnement de test ; jamais dans le paquet candidat sans passer par les cinq conditions. |

## 3. Les cinq conditions d'une correction

Toute correction ulterieure doit satisfaire **les cinq** conditions. Une
seule ne suffit pas.

1. **Justification** — un defaut **reproduit**, avec la preuve de la
   reproduction : la sortie du test qui echoue, ou la mesure qui montre
   le comportement faux.
2. **Test de reproduction** — un test qui **echoue** avant la correction
   et **passe** apres. Un test qui passe dans les deux cas ne prouve
   rien et n'est pas recevable.
3. **Contrats preserves** — la correction ne modifie ni le schema des
   donnees, ni les identifiants serialises, ni les permissions, ni les
   invariants comptables. Toute modification d'un contrat existant exige
   une decision metier distincte.
4. **Tests passants** — la suite complete passe, et le **banc de mutation**
   confirme que la nouvelle assertion est **discriminante**.
5. **Reconstruction de la candidate** — une nouvelle archive est produite,
   avec un nouveau SHA-256, un nouveau manifeste et un nouveau nom. La
   candidate precedente **est conservee** : elle sert de point de
   comparaison.

## 4. Ce qui n'est pas un defaut demontre

Pour eviter que le gel serve d'excuse a des changements non justifies,
voici ce qui **ne constitue pas** un defaut :

- un constat de style, de lisibilite ou de nommage ;
- une preference d'architecture qui n'a aucun effet observable ;
- un cas theorique sans reproduction, sans chemin atteignable par un
  utilisateur ;
- un ecart de test que l'on ne sait pas reproduire ;
- une hypothese sur le comportement de WoW Retail qui n'a pas ete observee
  dans le client.

Ces elements peuvent etre notes dans le journal d'audit et traites
**apres** la campagne, dans une version distincte.

## 5. Controles qui doivent rester verts pendant le gel

| Controle | Attendu |
|---|---|
| Suite Lua complete | 1528+ PASS / 0 FAIL, exit 0 |
| Compilation Lua 5.1.5 | 105 fichiers, PASS |
| `validate_audit.py` | 0 erreur, 47 tags / 47 fiches |
| `audit_guard.py verify` | 0 violation de bibliotheque |
| `src/libs` | 77/77 identiques |
| Verrous RF-0012 | `false` / `false` |
| Version TOC | `0.8.10` |
| `git diff --check` | exit 0 |

## 6. Ce qui declenche la reconstruction

| Evenement | Reconstruction |
|---|---|
| Une correction qui satisfait les cinq conditions | **Obligatoire** |
| Une modification de documentation seule | Non |
| Un test ajoute sans changement de production | Non |
| Un constat de la campagne Retail qui demande un changement | **Obligatoire**, apres les cinq conditions |
| Une decision metier nouvelle (non implementable dans le gel) | Non dans cette candidate : elle ouvre une version distincte |

## 7. Periode du gel

Le gel couvre toute la **campagne Retail A** et la **campagne Retail B**,
jusqu'a ce que le proprietaire du projet leve explicitement le gel. Toute
levee est datee, motivee et consignee dans
`docs/code-audit/AUTONOMOUS-SESSION-STATUS.md`.

Le gel **n'empeche pas** la correction d'un defaut bloque la campagne
lui-meme : un defaut qui rend un scenario retail inexecutable doit etre
corrige, selon les cinq conditions, et la candidate reconstruite.
