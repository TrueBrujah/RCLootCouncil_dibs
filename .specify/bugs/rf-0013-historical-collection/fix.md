# Bug Fix: collecte historique incomplete traitee comme terminee

- **Slug**: rf-0013-historical-collection
- **Fixed**: 2026-11-05T19:05:34Z
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

La collecte locale des historiques est paginee et reprenable, et ne peut pas etre approuvee tant qu'une collecte en cours ou en erreur subsiste. Une source importee manuellement et marquee incomplete reste approuvable seulement avec l'accuse de reception explicite prevu. L'assistant d'installation ne declare plus le baseline termine si des preuves n'ont pas de decision, et la proposition de ledger n'est annoncee qu'apres sa persistance verifiee.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `src/modules/HistoricalBaseline.lua` | modified | Collecte bornee par lots persistants, empreinte/cursor de reprise, erreurs de lecture explicites et resume compact; bloque la finalisation pendant une collecte incomplete. |
| `src/modules/Installation.lua` | modified | Scanne le ledger primaire; ne confond pas absence de decision et reconciliation achevee; verifie le resultat persiste de la proposition. |
| `src/modules/MultiLedger.lua` | modified | Valide et persiste les metadonnees de proposition, controle volumes/sources a l'approbation et journalise les decisions. |
| `src/ui/OfficerUI.lua` | modified | Rend visibles portee, compteurs, sources illisibles et etat de scan des propositions en attente. |
| `docs/developer/saved-variables.md` | modified | Documente l'index persistant des propositions. |
| `tests/integration/rf0013_partial_legacy_discovery_spec.lua` | updated | Couvre scan partiel, reprise, lecture illisible, et portee primaire coherente. |
| `tests/integration/rf0013_paginated_collection_spec.lua` | added/updated | Verifie pagination, reprise, idempotence, changement de source et non-suppression. |
| `tests/integration/rf0013_officer_proposal_spec.lua` | added/updated | Verifie contrat de metadonnees, approbation, permissions et traces. |
| `tests/integration/rf0013_verification_spec.lua` | added/updated | Verifie les garanties de reprise et de persistance. |
| `tests/integration/installation_wizard_spec.lua` | updated | Verifie le scope primaire, les decisions manquantes et l'accuse explicite. |

## Diff Highlights

- La finalisation refuse les etats de collecte `INCOMPLETE` ou `ERROR` meme si une source indique un append precedent.
- L'accuse explicite reste possible pour les imports manuels declares incomplets; il ne peut pas contourner l'etat persistant d'une collecte paginee interrompue.
- Le GM ne peut pas approuver une proposition dont la portee ou les volumes omettent des sources decouvertes.

## Tests Added or Updated

- `tests/integration/rf0013_paginated_collection_spec.lua` — lots limites, curseur, reprise, relecture et finalisation.
- `tests/integration/rf0013_partial_legacy_discovery_spec.lua` — scan partiel/illisible et coherence du ledger cible.
- `tests/integration/rf0013_officer_proposal_spec.lua` — metadonnees, portee, volumes, autorisation et audit.
- `tests/integration/rf0013_verification_spec.lua` — garanties de persistance apres reload.
- `tests/integration/installation_wizard_spec.lua` — non-lecture du ledger UI actif et decisions explicites.

## Local Verification

- Suite locale Lua complete — `1791 passed, 0 failed (230 files)`.
- Suite Fengari complete en 12 lots de 20 fichiers maximum — `1791 passed, 0 failed (230 files)`.
- Groupe cible RF-0013/installation/MAIN-ALT/PlayerUI/cache — `99 passed, 0 failed (9 files)` sous Fengari.
- Verification documentaire croisee PowerShell 5.1/7 — `8/8` fichiers generes identiques.
- `scripts/Generate-DibsDocs.ps1 -Generate` puis `-Check` — passe; neuf avertissements de cles d'aide historiques orphelines demeurent.
- `git diff --check` — passe.
- Validation manuelle en jeu ou en raid multiclient — non executee.

## Deviations from Assessment

- Portee etendue pour debloquer les regressions presentes dans les tests de PR25: les tests MAIN/ALT utilisent maintenant une relation approuvee realiste; le PlayerUI effectivement atteint a recu les controles MAIN/ALT et son badge RC utilise une normalisation d'etat; le cache Setup Assistant est teste sur une route qui l'evalue vraiment.
- Le controle documentaire a aussi revele une annotation/localisation manquante pour `ledger.operation`; les deux locales et la documentation generee ont ete mises a jour.
- Le check GitHub observe appartient au SHA distant `2510ea31`; ses echecs sont anterieurs aux changements locaux non commites et doivent etre revalides apres mise a jour de la branche.

## Follow-ups

- Une fois les changements revus et publies sur la branche du PR, attendre une nouvelle execution GitHub Actions; aucune donnee de guilde reelle ni verification Retail a deux clients n'est couverte par Fengari.
- Reprendre `__SPECKIT_COMMAND_BUG_TEST__ slug=rf-0013-historical-collection` si un changement ulterieur touche le contrat de collecte ou de proposition.
