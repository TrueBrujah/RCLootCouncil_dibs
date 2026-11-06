# Installation locale du Skill GitHub Copilot « lua-code-audit »

## Où installer ?

Copier le dossier `.github/skills/lua-code-audit/` dans la **racine du dépôt Lua** (même niveau que son `.git` et le `.toc`).

Si ton dépôt a déjà un `.github/`, fusionner les dossiers sans effacer le contenu existant.

N'installe pas les modèles de documentation `assets/*.template.md` directement dans `docs/` : l'agent les utilisera pour créer de vrais rapports vérifiés.

## Dans VS Code

1. Ouvrir le dossier du projet, pas uniquement un fichier Lua.
2. Ouvrir Chat Copilot en mode Agent; vérifier que les Agent Skills sont activés (configuration `chat.useAgentSkills`, normalement active).
3. Saisir `/lua-code-audit projet complet` (ou `/lua-code-audit Modules/Loot.lua`).
4. Vérifier dans l'activité de l'agent qu'il a chargé `SKILL.md` et exécuté les contrôles.
5. Le Skill est **manuel** : il ne s'exécute pas tout seul, pour éviter d'annoter le code pendant d'autres tâches.

## Commandes de sécurité

Depuis la racine du projet (PowerShell Windows, Python 3 requis) :

```powershell
python .github/skills/lua-code-audit/scripts/audit_guard.py capture
python .github/skills/lua-code-audit/scripts/audit_guard.py verify
python .github/skills/lua-code-audit/scripts/validate_audit.py
git diff --check
git diff -- '*.lua'
```

**Attention** : `capture` doit être exécuté une seule fois **avant** la première annotation. L'agent le fait normalement. Si `BASELINE.json` existe, ne pas l'écraser sans décider explicitement de recommencer une nouvelle période d'audit. `verify` ne garantit pas qu'un commentaire @AUDIT a été placé dans un contexte syntaxique sûr; il faut relire les changements.

## Qwen/Ollama

Ce dossier suit le format standard Agent Skills, reconnu par GitHub Copilot dans VS Code. Une extension tierce utilisant Qwen/Ollama ne l'utilisera que si elle prend en charge ce mécanisme ou si tu lui fournis explicitement le contenu du Skill. Le nom du modèle ne suffit pas à garantir cette prise en charge.

## Documentation générée

L'agent crée les fichiers `docs/code-audit/INDEX.md`, `INVENTORY.md`, `DEPENDENCIES.md`, `REFACTOR-PLAN.md`, `PROGRESS.md` et `BASELINE.json` après examen du **vrai code**. Le ZIP n'inclut pas de résultats fictifs pour ton AddOn.
