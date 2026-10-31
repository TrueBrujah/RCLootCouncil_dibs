# RCLootCouncil_Dibs — Persistent Project Checkpoint

## Identité du projet
- **Nom** : RCLootCouncil_Dibs (WoW Retail Lua Addon)
- **Branche Git** : main (ou branche active)
- **Dernier commit** : dc388f9df313f1597e5c1a35078bb725c34c7f3e (Sun Oct 18 01:25:07 2026 -0400)
- **Message commit** : feat: guild sync repair, corroborated relay, factory reset and setup guidance (0.8.10)

## État du projet
- **Fonctionnalité active** : Gestion de la synchronisation distribuée, ledger multiple, récupération d'historique corrodoré
- **Spécifications pertinentes** : `specs/026-canonical-idempotent-corrections/` et `specs/027-feature-registry/`

## Phase actuelle
En cours de développement majeur avec très nombreux fichiers modifiés (docs/, src/, tests/)
- Focus sur l'intégration robuste avec RCLootCouncil
- Implémentation du système multi-ledger pour les données d'équipement
- Développement de la récupération historique idempotente

## Tâches confirmées comme terminées
- [x] Architecture multi-modèle établie (`src/modules/`)
- [x] Intégration EncounterJournal fonctionnelle
- [x] Système de permissions et gouvernance mis en place
- [x] Interface utilisateur Midnight configurée

## Tâches en cours
- [ ] Finalisation des corrections canoniques idempotentes (spec 026)
- [ ] Implémentation du registre de fonctionnalités (spec 027)
- [ ] Tests d'intégration pour les scénarios distribués à 4 clients globaux

## Tâches restantes
- [ ] Validation cross-version des documents générés
- [ ] Préparation du prochain release candidate
- [ ] Documentation des patterns de résilience observés

## Décisions architecturales importantes
- **Principe d'isolation** : Les ledgers sont append-only et isolés par personnage/guild
- **Autorité vérifiée** : La validation d'autorité se fait à l'acceptation, pas à l'envoi
- **RCLootCouncil optionnel** : L'accounting de Dibs ne dépend jamais du core RC
- **Contexte développeur isolé** : Les contextes test/dev restent isolés des données production

## Fichiers modifiés et pertinents (dernier commit)
Fichiers `.toc`, `Core.lua`, `Types.lua` et ~40 fichiers Lua dans `src/modules/` et `src/ui/`
- Tests d'intégration : `tests/integration/*_spec.lua`
- Helpers de test : `tests/helpers/*`

## Données de contexte persistant
- **Nombre de modules** : ~50 fichiers Lua dans `src/modules/`
- **Pattern de nommage** : Fonctions publiques PascalCase, privées lowerCamelCase
- **Localisation** : Textes utilisateurs dans `src/locales/` avec fallback EN

## Tests réellement exécutés et résultats
- Fengari tests via `tests/run.lua` (avec variable `DIBS_TEST_FILES`)
- Succès des suites d'intégration ciblés lors du dernier commit
- **ATTENTION** : Fengari success ≠ certification Retail — vérifications manuelles requises

## Problèmes connus
- Très nombreux fichiers modifiés simultanément (possible conflit de merge si branchée)
- Contexte de développement avec très grande surface de modifications actives

## Prochaine action recommandée
1. Lire CHECKPOINT.md complet pour le contexte
2. Vérifier Git status : `git status --short`
3. Consulter les spécifications actives dans `specs/026-canonical-idempotent-corrections/` et `specs/027-feature-registry/`
4. Identifier la tâche active la plus critique en cours
