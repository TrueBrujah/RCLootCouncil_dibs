# Specification Quality Checklist: Roster saisonnier et inscriptions aux raids

**Purpose**: Valider la complétude et la qualité de la spécification avant la planification
**Created**: 2026-11-03 — révision de planification 2026-11-07
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] La spécification se concentre sur les besoins des joueurs et des GM/officiers.
- [x] Les scénarios et exigences sont formulés pour les utilisateurs et sont indépendants du langage ou du framework.
- [x] Tous les titres obligatoires du modèle sont remplis.
- [x] Les exemples observés dans le classeur sont distingués des règles produit demandées.

## Requirement Completeness

- [x] Aucun marqueur `[NEEDS CLARIFICATION]` ne reste; les champs « Dibs Used » et « Raid Token » restent sans comportement associé tant que leur sens n’est pas confirmé.
- [x] Les exigences définissent les acteurs, les autorisations, les états ouverts/fermés et les refus attendus.
- [x] Les critères de réussite sont mesurables et formulés du point de vue utilisateur.
- [x] Les scénarios couvrent inscription, lecture seule, gestion, Main/Alt, probation et désactivation.
- [x] Les scénarios couvrent le choix, la révision et la conservation historique des statuts saisonniers de participation.
- [x] La voie Core demandée est distincte du statut Core accordé; la première version ne simule pas un suivi d’assiduité ou de performance.
- [x] Les règles, critères de promotion, allocations et roster référencent une seule identité canonique de saison avec manifeste de cohérence.
- [x] L’activation est explicite et prévisualisée; l’allocation et la réconciliation sont limitées au roster saisonnier approuvé.
- [x] Les rapprochements de soldes historiques, allocations initiales et dérives de rang en saison sont des opérations séparées.
- [x] Les cas limites incluent personnages hors guilde, doublons, changements d’autorité, données partielles et saisons historiques.
- [x] Le périmètre exclut professions et équipes Mythic+.
- [x] Les dépendances et hypothèses de synchronisation, d’identité et d’autorité sont explicites.

## Feature Readiness

- [x] Chaque exigence fonctionnelle peut être reliée à un critère ou scénario de validation.
- [x] Les parcours prioritaires sont testables séparément.
- [x] Les statistiques ont des règles vérifiables de comptage et de cohérence avec les listes.
- [x] Les contraintes de confidentialité, d’intégrité du ledger et d’intégration RCLootCouncil sont explicites.
- [x] Les validations en jeu et sur roster volumineux sont demandées.

## Notes

- Les clarifications du 2026-11-03 sont intégrées : « Dibs Used » et « Raid Token » sont omis, le solde suit la personne/Main, et le GM ou l'officier rapproche les soldes avant leur regroupement.
- La décision du 2026-11-06 est intégrée : AotC correspond à Raider; les statuts saisonniers et leurs explications sont modifiables et versionnés; ils sont réévalués à chaque saison sans modifier automatiquement les rangs WoW.
- La révision du 2026-11-07 unifie l’identité logique de saison, sépare voie Core demandée et promotion accordée, et exige une activation explicite protégée par un manifeste.
- Cette checklist valide la planification seulement. Les tâches d’implémentation sont à faire; aucun comportement de production n’est déclaré implémenté ou testé par cette révision.
