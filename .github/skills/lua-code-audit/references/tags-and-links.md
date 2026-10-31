# Système de tags, liens, preuves

## Format Lua exact

Une ligne autonome, immédiatement avant un symbole Lua :

```lua
-- @AUDIT RF-0001 status=KEEP doc=docs/code-audit/INDEX.md#rf-0001
local function InitializeAddon()
    -- code existant, intact
end

-- @AUDIT RF-0002 status=COULD_MERGE target=RF-0003 doc=docs/code-audit/INDEX.md#rf-0002
local function RefreshLootUI()
    -- code existant, intact
end
```

Règles :
- Un ID RF ne correspond qu'à **un** emplacement Lua, jamais deux. Si un même problème affecte plusieurs fonctions, créer plusieurs RF et les relier dans la documentation.
- Ne pas utiliser le même RF pour le fichier entier et une fonction.
- L'ID reste stable, même si son statut évolue dans une analyse future.
- Les seules lignes **nouvelles** autorisées dans un Lua applicatif sont `-- @AUDIT ...` ; aucune autre modification, même purement esthétique.
- `doc=` est un chemin **depuis la racine du dépôt**, identique partout, pratique pour la recherche textuelle. Il ne garantit pas un Ctrl+clic natif dans un commentaire Lua.
- `target` obligatoire pour `COULD_MERGE` et interdit pour les autres statuts.
- Interdiction absolue d'annotation ou de modification dans tout répertoire dont un composant du chemin s'appelle `libs`, sans distinction de casse (`libs`, `Libs`, `LIBS`, etc.). Cette règle couvre tous les types de fichiers, pas uniquement Lua, et s'applique aussi aux générations automatiques et aux futures features Spec Kit.
- Ne créer aucun RF portant sur le code interne d'une bibliothèque. Une dépendance externe peut être décrite séparément si son contrat ou son comportement est incertain, avec les preuves et limites observées.

## Lien inverse depuis Markdown

Dans `docs/code-audit/INDEX.md` :

```markdown
<a id="rf-0001"></a>
## RF-0001 — InitializeAddon

- Status: KEEP
- Confidence: HIGH
- Risk: LOW
- Source: [Core/Main.lua](../../Core/Main.lua) — `InitializeAddon`
- Evidence: Chargement depuis `Addon.toc`, invocation par `ADDON_LOADED`.
- Rationale: Point d'entrée confirmé.
- References/Dependencies: `ADDON_LOADED`, [RF-0005](#rf-0005).
- Proposed action: Conserver.
```

`../../Core/Main.lua` est un exemple; **calculer le chemin réel**, relatif au répertoire `docs/code-audit/`. Les fichiers peuvent avoir un chemin plus profond. Dans les liens Markdown, encoder les caractères spéciaux au besoin.

La navigation est **bidirectionnelle par l'identifiant** : clic sur le lien Markdown vers le fichier source; recherche globale `RF-0001` depuis le code pour retrouver l'entrée documentaire. Ne pas promettre un clic direct dans Lua sans extension de navigation dédiée.

## Références et evidence

- Pour des références directes, indiquer le symbole appelant et l'emplacement prouvé dans le dépôt.
- Pour l'absence supposée d'usage, consigner l'étendue des recherches et les **limites** (appels indirects, XML, AddOns externes).
- Une fonction accessible globalement n'est pas morte du seul fait que le dépôt ne l'appelle pas.
- Éviter la fusion d'APIs publiques ou de handlers déclenchés de façon distincte sans démonstration d'équivalence.
- `Confidence=HIGH` signifie que l'observation est solidement documentée, **pas** que la modification future est sans risque.
- Pour `COULD_MERGE` : cible RF annotée, comparaison des entrées/sorties, effets secondaires, fréquence d'appel, ordre d'exécution, contraintes de WoW.
