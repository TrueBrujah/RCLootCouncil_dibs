# RCLootCouncil_dibs — Project-Specific Agent Constraints

## 0. Authorized scope and continuity

Une approbation couvre toutes les opérations ordinaires nécessaires au périmètre
autorisé. Avancer sur les tâches indépendantes et ne redemander une décision que
pour une extension de périmètre, un choix métier non tranché ou une opération
destructive ou externe non autorisée. Une étape, un lot ou une refactorisation
technique justifiée ne constituent pas à eux seuls une nouvelle demande d'accord.

## 1. External Libraries — Integrity and Approved Integration

Les répertoires `libs/` et `Libs/` contiennent des bibliothèques externes.

**Le contenu interne des bibliothèques tierces reste protégé.**

Les agents ne doivent jamais :
- Modifier le contenu interne d'un fichier tiers; supprimer ou renommer des éléments hors d'une intégration exactement approuvée.
- Ajouter des annotations ou du code local dans une bibliothèque tierce.
- Reformater le code.
- Ajouter des commentaires `@AUDIT`.
- Patcher silencieusement une dépendance ou changer une version non approuvée.

La consultation en lecture seule est autorisée pour comprendre les dépendances.

L'intégration exacte d'une dépendance et d'une version déjà approuvées dans le plan
applicable est autorisée sans nouvelle demande : conserver provenance, licence,
empreintes et métadonnées de livraison, sans modifier son code interne. Adapter le
chargement ou les adaptateurs du projet fait partie de cette intégration. Un patch
interne, une dépendance ou une version hors périmètre exige une décision explicite.
Consigner les particularités de chaque dépendance dans son registre, plutôt que
multiplier les exceptions dans les présentes instructions.

## 2. Lua Architecture and WoW Compatibility

- Respecter l'architecture et les conventions existantes.
- Préserver les API publiques et les contrats entre modules.
- Éviter les dépendances circulaires et les changements structurels non demandés.
- Respecter les restrictions de l'API World of Warcraft.
- Ne pas contourner les mécanismes de protection de Blizzard.
- Ne pas supposer qu'une API WoW est disponible sans vérification.
- Préserver la compatibilité avec les versions du jeu officiellement ciblées par le projet.
- Distinguer les erreurs du code addon des limitations de l'environnement WoW.

## 3. DIBS Governance and Data Integrity

- Préserver les règles de gouvernance DIBS approuvées.
- Ne pas modifier silencieusement les critères d'attribution.
- Respecter les contrats des opérations du ledger.
- Préserver l'identité, la provenance et la traçabilité des opérations.
- Ne jamais supprimer ou réinterpréter silencieusement une opération historique.
- Préserver les mécanismes de migration et de compatibilité des données.
- Vérifier les conséquences sur les données existantes avant toute modification de schéma.
- Ne pas changer une règle métier pour faire réussir un test.

Une évolution réelle des règles métier d'attribution, de validation, de contestation
ou de gouvernance nécessite une révision des spécifications et une approbation
explicite. Une correction interne qui rétablit les règles et contrats déjà approuvés
reste autorisée dans le périmètre de la mission, avec ses tests de régression.

## 4. Spec-Driven Development

Utiliser les trois modes suivants :

**DISCUSS**
- Questions, analyses, investigations et explications.
- Lecture seule par défaut.
- Aucune modification sans demande explicite.

**CHANGE**
- Corrections techniques conformes aux spécifications approuvées.
- La plus petite solution complète et cohérente, avec refactorisation ciblée si elle est justifiée par le problème et protégée par des tests.
- Tests de régression appropriés.
- Préservation des contrats existants.

**SDD**
- Nouvelles fonctionnalités.
- Modification des règles métier.
- Évolution des contrats publics.
- Changement architectural significatif.

Pour le mode SDD :
- Examiner les spécifications et décisions existantes.
- Réviser les documents concernés avant l'implémentation.
- Respecter les dépendances et les critères d'acceptation.
- Réutiliser les décisions et autorisations acquises; la mise à jour documentaire ou un changement de contrat interne conforme à la mission ne demandent pas un nouvel accord à chaque étape.
- Ne pas créer une nouvelle fonctionnalité lorsque l'évolution appartient clairement à une fonctionnalité existante.
- Ne pas modifier les exigences uniquement pour rendre le code conforme.

## 5. Deferred Approvals — Non-Blocking Execution

Lorsqu'une décision nécessite une approbation humaine :

1. Enregistrer la question et son contexte.
2. Identifier les options possibles.
3. Présenter une recommandation justifiée.
4. Identifier les tâches dépendantes.
5. Bloquer uniquement les tâches qui nécessitent cette décision.
6. Continuer les tâches indépendantes déjà autorisées.
7. Regrouper les décisions en attente dans le rapport final.

Une absence de réponse ne constitue jamais une approbation.

Les décisions approuvées doivent être documentées avant la reprise des tâches dépendantes.

Les situations présentant un risque critique pour l'intégrité des données, la sécurité ou le dépôt nécessitent un arrêt contrôlé.

## 6. Testing and Regression Protection

- Utiliser les tests et outils de validation existants.
- Ajouter des tests de régression pour les corrections de bogues.
- Tester les migrations avec des données représentatives.
- Vérifier les cas limites et les états invalides.
- Préserver la déterminisme des tests lorsque possible.
- Distinguer les validations automatisées des tests nécessitant le client WoW.
- Ne jamais déclarer une fonctionnalité compatible avec WoW uniquement parce que les tests Lua réussissent.
- Signaler explicitement les validations non exécutées.

## 7. Repository and Change Management

- Vérifier l'état Git avant toute modification.
- Préserver les changements existants.
- Limiter les modifications aux fichiers nécessaires.
- Éviter les refactorisations et changements de formatage sans lien avec la demande; autoriser la refactorisation ciblée nécessaire à une solution complète et cohérente.
- Ne pas modifier les fichiers générés sans comprendre leur processus de génération.
- Respecter les conventions de branches et de versions existantes.
- Ne pas publier de version Main, Dev ou Beta sans autorisation explicite.
- Ne jamais déclencher une publication CurseForge ou GitHub Release sans autorisation.
- Les packages locaux de validation dans un dossier temporaire sont autorisés dans le périmètre des tests; ils ne valent ni installation WoW, ni publication, ni validation runtime.
- Commit, push, suppression destructive, installation réelle et déploiement externe restent soumis à l'autorisation correspondant à l'opération et à sa portée.

## 8. Delegation and shared design

- Lorsque la mission autorise globalement les agents, déléguer les tâches suffisamment indépendantes sans redemander un accord par lot.
- Définir des responsabilités et fichiers distincts; éviter les écritures concurrentes et préserver les modifications des autres agents.
- Centraliser les décisions, l'intégration et la validation finale; signaler l'indisponibilité ou la limite réelle d'un agent sans inventer sa revue.
- Préserver la cohérence du design partagé. Une évolution commune approuvée peut modifier les composants et règles de référence; éviter les exceptions visuelles isolées par page.

## 9. Execution and Reporting

À la fin de chaque lot de travail :

- Résumer les tâches terminées.
- Identifier les fichiers modifiés.
- Indiquer les tests exécutés et leurs résultats.
- Présenter les problèmes non résolus.
- Regrouper les décisions nécessitant une approbation.
- Identifier les tâches bloquées.
- Proposer les prochaines tâches indépendantes admissibles.

Ne jamais présenter une tâche partiellement implémentée comme terminée.

Ne pas créer de nouveaux systèmes de checkpoints ou de rapports si le projet dispose déjà de mécanismes équivalents.
