# Bug Verification: collecte historique incomplete traitee comme terminee

- **Slug**: rf-0013-historical-collection
- **Tested**: 2026-11-05T19:05:34Z
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: partial

## Summary

Les scenarios de regression et les suites completes passent sous Lua et Fengari. La correction est donc verifiee par les tests locaux; la validation reste partielle pour PR25, car le check distant porte encore sur l'ancien SHA et aucune verification en jeu/raid multiclient n'a ete faite.

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Tests RF-0013, installation, MAIN/ALT, PlayerUI et cache | Lua et Fengari sur 9 fichiers cibles | pass | 99 tests, 0 echec sous chaque moteur. |
| Suite complete Lua | `DIBS_TEST_FILES=<230 specs>; lua tests/run.lua` | pass | 1 791 tests, 0 echec, 230 fichiers. |
| Suite complete CI Fengari | `npx.cmd --yes --package=fengari-node-cli fengari tests/run.lua`, lots de 20 specs | pass | 1 791 tests, 0 echec, 230 fichiers, 12 lots. |
| Validation documentation | `scripts/Generate-DibsDocs.ps1 -Generate` puis `-Check` | pass | 0 erreur; 9 avertissements historiques de help keys orphelines. |
| Documentation multi-version | `scripts/Test-DibsDocsCrossVersion.ps1` | pass | 8/8 artefacts identiques entre PowerShell 5.1 et 7. |
| Hygiene du diff | `git diff --check` | pass | Aucun espace blanc invalide. |
| CI GitHub PR25 actuel | `gh pr view 25` / run `42048287447` | skipped (ancien SHA) | Test job rouge au SHA distant `2510ea31`; build du paquet reussi. Les echecs RF-0013 montrent des API absentes du commit distant, alors qu'elles existent dans l'arbre local teste. |
| Verification Retail / donnees reelles | Non executee | not-run | Necessite WoW Retail et un scenario de guilde/raid multiclient. |

## Output Excerpts

```text
99 passed, 0 failed (9 files)
1791 passed, 0 failed (230 files)
Cross-version SHA-256: 8/8 MATCH
Documentation Validation: Errors 0; RESULT: PASS
```

Le run distant observe sur PR25 contenait les erreurs `ListProposals` et `GetCollectionProgress` nil sous RF-0013; il s'agit du commit distant anterieur aux modifications locales presentes dans ce workspace.

## Residual Risks

- Les tests utilisent des doubles WoW/Ace3 et ne certifient pas le comportement Retail, la persistance d'un compte reel, ni l'ordre/latence de synchronisation de plusieurs clients.
- La mise a jour de la branche PR n'a pas ete publiee; le statut GitHub et le paquet correspondant au nouvel arbre ne sont donc pas encore valides par CI.
- Neuf avertissements documentaires concernent des cles d'aide de synchronisation historiques non referencees; aucun ne bloque la validation.

## Recommendation

Garder le PR non fusionne tant que les changements locaux n'ont pas ete revus puis transmis a la branche distante et que le nouveau run GitHub Actions n'est pas vert. Le correctif RF-0013 passe les tests locaux complets; confirmer ensuite le statut distant, puis effectuer les essais Retail prevus pour la release.
