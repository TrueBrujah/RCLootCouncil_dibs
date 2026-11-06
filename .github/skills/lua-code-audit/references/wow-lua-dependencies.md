# Pièges de l'analyse statique Lua / WoW

## Classification des sources et dépendances protégées

- Sources applicatives : auditer leurs références statiques et dynamiques; les annoter uniquement dans le respect du skill.
- Bibliothèques externes : tout répertoire nommé `libs` sans distinction de casse, à n'importe quelle profondeur, et tout son contenu. Elles sont en lecture seule, ne comptent pas parmi les modules applicatifs restant à auditer, et ne peuvent recevoir ni annotations ni constats RF sur leur code interne.
- Fichiers générés : les identifier séparément et ne pas les modifier dans le cadre de l'audit. Une dépendance externe n'est consultable que pour confirmer ses API, signatures, contrats, événements, callbacks et contraintes de compatibilité.
- La protection est contrôlée par `audit_guard.py verify` sur tous les types de fichiers et leurs octets exacts; les lignes `@AUDIT` ne sont jamais retirées des empreintes protégées. L'outil signale les ajouts, suppressions, déplacements identifiables et modifications; il ne restaure rien.
- Cette limite reste applicable aux changements futurs proposés par Spec Kit; aucune feature de refactoring ne peut l'assouplir.

Ne pas classifier `TO_REMOVE` sur un `rg functionName` négatif sans examiner :

- Fichiers `.toc` : ordre de chargement, `LoadOnDemand`, fichiers embarqués, interfaces multiples, `.toc` de sous-dossiers et éventuels `.xml` inclus.
- Fichiers XML : scripts/handlers appelés par nom, templates hérités, frames nommées et callbacks.
- Événements : `RegisterEvent`, `RegisterUnitEvent`, `SetScript("OnEvent", ...)`, `ADDON_LOADED`, `PLAYER_LOGIN`, `PLAYER_ENTERING_WORLD`.
- Hooks : `hooksecurefunc`, `SecureHook`, `RawHook`, méthodes remplacées/encapsulées et callbacks indirects.
- Registrations : `SlashCmdList`, `SLASH_...`, `C_Timer.After`, `C_Timer.NewTicker`, événements AceEvent, AceHook, AceComm, LibStub/CallbackHandler.
- Calls dynamiques : `someTable[name]`, `_G[name]`, `loadstring`, table dispatch, métatables (`__index`, `__call`), références stockées dans tables ou closures.
- UI : `CreateFrame`, `SetScript`, handlers `OnShow`, `OnUpdate`, `OnClick`, `OnEnter`, XML, frames globales nommées.
- Interfaces externes : globals et méthodes publiques appelables par d'autres AddOns (absence d'usage dans ce dépôt ≠ dead code).
- Réseau/versions : APIs Retail/Classic, compatibilité interface WoW, conditions de version, paramètres de combat protégés.
- Fonctions au contenu identique mais aux responsabilités ou contrats distincts : ne pas les fusionner automatiquement.

## Preuve minimale pour proposer suppression

1. Trouver la définition et vérifier le mode d'exposition (local, export, global, table).
2. Recherche directe (nom exact, alias, référence stockée) dans `.lua`, `.xml` et `.toc`.
3. Recherche dynamique/registrations liées.
4. Vérifier les dépendances publiques et les variantes (Retail/Classic) si détectées.
5. Marquer `TO_REMOVE` avec degré de confiance et liste des vérifications encore nécessaires. Sinon `NEED_UPDATE` et `UNKNOWN`.

## Noms

Privilégier des noms explicites et cohérents (`RefreshLootDisplay` plutôt que `DoUI2` ou `RefreshRaidLootDisplayWindowAndUpdate...`). Les propositions de noms doivent être justifiées par responsabilités et conventions observées du projet.
