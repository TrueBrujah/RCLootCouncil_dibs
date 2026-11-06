---
name: lua-code-audit
description: Audit documentaire non destructif pour projets Lua et AddOns World of Warcraft. Inventorie fonctions/fichiers/dépendances, recherche le code mort ou dupliqué, prépare suppressions, fusions et renommages, pose des annotations @AUDIT et produit un plan de refactoring lié au code SANS changer le fonctionnement.
argument-hint: "[module, fichier ou 'projet complet']"
user-invocable: true
disable-model-invocation: true
---

# Lua Code Audit — documenter, sans refactorer

**Cette compétence est uniquement un audit préparatoire.** Ne jamais exécuter les changements proposés.

## Périmètre autorisé

- LIRE le dépôt entier, les `.lua`, `.toc`, `.xml`, les tests et la documentation pertinente.
- ÉCRIRE exclusivement dans `docs/code-audit/` (rapports et baseline) et **ajouter** des commentaires d'une seule ligne `-- @AUDIT …` dans les fichiers Lua *de première partie*.
- Pour une demande explicite de maintenance de cette compétence, ses scripts et références sous `.github/skills/lua-code-audit/` peuvent également être modifiés; cela n'autorise aucune modification de source applicative.
- Ne pas modifier le code exécutable, le formatage, les commentaires préexistants, les noms, les chemins, les `.toc` ou les `.xml`.
- Ne jamais toucher aux fichiers générés ou minifiés.
- Ne faire ni nettoyage, ni suppression, ni renommage, ni merge, ni commit. Ne pas modifier `.gitignore` ou fichiers de configuration.
- Ne jamais exécuter une commande qui réinitialise ou efface des changements (`git reset`, `git clean`, `git checkout --`, etc.).

## Règle absolue — bibliothèques externes

- Tout répertoire dont un composant du chemin se nomme `libs`, sans distinction de casse (`libs`, `Libs`, `LIBS`, ou toute autre casse), est une bibliothèque tierce en lecture seule, où qu'il se trouve dans le projet.
- Cette protection couvre **tous les fichiers** sous ce répertoire, pas uniquement Lua : aucune modification, annotation `@AUDIT`, ajout de documentation, suppression, déplacement, renommage ou reformatage n'est permis. Aucun outil automatique ni travail futur Spec Kit ne peut contourner cette règle.
- Les bibliothèques peuvent être lues uniquement pour comprendre les API, signatures, contrats, callbacks, événements et contraintes de compatibilité, et pour cartographier les dépendances applicatives. N'y créez aucun constat RF portant sur leur code interne.
- Si un problème semble provenir d'une bibliothèque, documentez-le séparément comme dépendance externe, avec l'incertitude et les preuves; ne modifiez pas la bibliothèque.
- Distinguer dans l'inventaire les sources applicatives (audit complet), les bibliothèques (lecture seule, hors décompte des modules à auditer) et les fichiers générés (hors modifications).

## Avant la moindre annotation

1. Consulter `git status --short`, consigner les changements préexistants et ne pas les toucher.
2. Lire [conventions d'identifiants et de documentation](./references/tags-and-links.md) et [points d'entrée WoW/Lua](./references/wow-lua-dependencies.md).
3. Recenser d'abord tous les fichiers, sources chargées, dépendances et références (y compris chaînes, XML, événements et appels indirects).
4. **Créer un point de comparaison** avant de toucher au premier `.lua` :

   `python .github/skills/lua-code-audit/scripts/audit_guard.py capture`

   Ceci écrit `docs/code-audit/BASELINE.json`, avec les empreintes tolérant uniquement les lignes `@AUDIT` pour le Lua hors bibliothèques et des empreintes exactes de tous les fichiers protégés sous `libs`. S'il existe déjà, le script refuse de l'écraser.
   Si une baseline schema 1 existe déjà, la migrer une seule fois par `python .github/skills/lua-code-audit/scripts/audit_guard.py capture-libraries`. Cette migration conserve les empreintes applicatives, consigne les écarts préexistants comme état initial et ne restaure aucun fichier.
5. Si Python ne peut pas s'exécuter ou si la baseline ne peut pas être créée, rester en mode **documentation uniquement** : aucun changement des fichiers Lua.

## Déroulement en lots

1. **Inventaire global en lecture seule**, avant toute conclusion de suppression : ordre de chargement `.toc`, tables globales, prototypes/instances, registres, hooks, événements, slash commands, callbacks et XML. Écrire `INVENTORY.md` et premières dépendances observables.
2. **Analyser un module à la fois** : noms trop longs/ambigus, fichiers aux responsabilités proches, duplication fonctionnelle, code historique possiblement mort, fort couplage. Noter les preuves (chemin + symbole + type d'appel). Ne pas confondre l'absence de référence statique avec la certitude d'inutilité.
3. **Étiqueter avec parcimonie** les points d'entrée essentiels et les candidats de refactoring. Identifiants `RF-0001`, `RF-0002`… uniques et stables. Ajouter seulement des lignes autonomes `-- @AUDIT …` immédiatement avant le symbole ou dans l'en-tête sûr du fichier. Ne pas placer d'annotation à l'intérieur d'une chaîne longue, d'un commentaire long ou d'un bloc lexical ambigu.
4. **Mettre à jour dans le même lot** `INDEX.md`, `DEPENDENCIES.md`, `REFACTOR-PLAN.md` et `PROGRESS.md`; chaque annotation doit avoir son entrée INDEX. Utiliser les modèles dans [assets](./assets/).
5. **Valider après chaque lot** :

   Sous PowerShell Windows, définir `$env:PYTHONIOENCODING = 'utf-8'` avant les commandes Python afin de conserver les diagnostics lisibles.

   `python .github/skills/lua-code-audit/scripts/validate_audit.py`

   `python .github/skills/lua-code-audit/scripts/audit_guard.py verify`

   `git diff --check`

   `git diff -- '*.lua'` (aucun changement dans les bibliothèques; le garde vérifie tous leurs fichiers et repère les ajouts, suppressions, déplacements et modifications).

   Si le contrôle échoue, ne pas prétendre que le code est intact; identifier la différence sans écraser un changement utilisateur.
6. **Faire une passe transverse** après les modules : corriger les hypothèses contredites par des références retrouvées, consolider le plan, exécuter les contrôles une dernière fois.

## Classification et exigences de preuve

- `KEEP` : élément important à conserver, par exemple point d'entrée confirmé; ne pas annoter toutes les fonctions triviales.
- `TO_REMOVE` : **candidat seulement**. Exiger recherche étendue des références et noter ce qui reste incertain.
- `NEED_UPDATE` : amélioration à envisager, sans patch.
- `COULD_MERGE target=RF-XXXX` : comparer le comportement et lister les différences, pas seulement les noms; `target` doit désigner une entrée RF existante.
- `RENAME_CANDIDATE` : proposer un nom plus clair; **ne pas simplement raccourcir** un nom au détriment de sa compréhension.
- `FIXED` : le défaut de la fiche a été démontré **et corrigé**; le code annoté porte désormais le correctif.
- `PARTIALLY_FIXED` : une partie du défaut a été corrigée, une décision métier reste en attente. Le corps de la fiche doit nommer précisément ce qui reste ouvert.
- `OPEN` : le défaut est constaté et documenté, mais n'est pas encore corrigé.
- Les références à une bibliothèque protégée sont des dépendances externes, jamais des candidats `TO_REMOVE`, des annotations ou des RF sur son implémentation interne.

Chaque entrée de l'index doit donner `Status`, `Confidence` (`HIGH|MEDIUM|LOW`), `Risk` (`HIGH|MEDIUM|LOW`), `Source` (lien Markdown relatif fonctionnel vers le Lua), `Evidence`, `Rationale`, `References/Dependencies` et `Proposed action`. Noter `UNKNOWN` quand l'information manque. Prioriser risque et impact : jamais de certitude de code mort fondée uniquement sur `rg`.

## Continuité pour petit modèle local

- Analyser des lots raisonnables (par module, 3–8 fichiers si possible) et compresser l'information dans `PROGRESS.md` après **chaque** lot : terminé, à faire, prochaine plage d'IDs, risques et décisions non vérifiées.
- **Relire** `PROGRESS.md` et `INDEX.md` au démarrage; ne jamais renuméroter un RF existant, ni repartir de `RF-0001` s'il existe déjà.
- Ne pas générer des milliers de tags `KEEP`; résumer les fonctions ordinaires dans `INVENTORY.md`.
- Continuer aussi loin que le contexte le permet, sans inventer les résultats des modules non inspectés.

## Livrables obligatoires

Dans `docs/code-audit/` :

- `INDEX.md` — identifiants / liens / preuves / niveaux de confiance.
- `INVENTORY.md` — responsabilités et inventaire par fichier, périmètre étudié.
- `DEPENDENCIES.md` — carte des liens directs et dynamiques, incertitudes.
- `REFACTOR-PLAN.md` — propositions futures, ordre de travail et tests.
- `PROGRESS.md` — état de travail reprenable, limites de l'audit.
- `BASELINE.json` — empreintes Lua hors bibliothèques (seules lignes `@AUDIT` ignorées) et empreintes strictes de tous les fichiers sous les répertoires protégés (créé/migré par `audit_guard.py`).

**Critère final :** fonctionnement non modifié, aucun refactoring appliqué, liens valides, contrôle d'intégrité réussi (ou échec explicitement rapporté), recommandations vérifiables et incertitudes conservées.

Les règles de lecture seule des bibliothèques s'appliquent aussi à toute feature ou opération de refactoring Spec Kit ultérieure; elles ne sont pas levées par le périmètre d'une feature.
