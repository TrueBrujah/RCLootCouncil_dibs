# Révision de sécurité et de conception — 6 septembre 2026

Révision de l'état local du dépôt, y compris les modifications non commitées. Cette page conserve la baseline de l'audit et son historique de constats; les correctifs décrits ci-dessous sont maintenant intégrés dans les fichiers source. L'analyse cible les permissions, le transport, les identités, le ledger et l'intégration RCLootCouncil; elle ne constitue pas une certification en client WoW.

## Résultat

La structure modulaire et le point d'entrée ProtectedActions sont conservés. La baseline a relevé plusieurs défauts de permissions, de transport et d'intégrité; ils ont été corrigés puis couverts par la suite de tests.

Politique demandée pour les actions administratives Dibs :

| Rôle vérifié | Standalone | Intégration RCLootCouncil |
| --- | --- | --- |
| GM de la guilde concernée | Tous les droits Dibs | Tous les droits Dibs |
| Officier selon la politique de rangs de cette guilde | Tous les droits Dibs | Tous les droits Dibs |
| ML actuel vérifié par RCLootCouncil | Gestion du loot RCLC uniquement; consommation automatique après une réponse DIB finalisée | Gestion du loot RCLC et consommation automatique après une réponse DIB finalisée |
| Membre du conseil actuel | Aucun droit administratif Dibs par ce seul rôle | Aucun droit administratif Dibs par ce seul rôle |
| Joueur ordinaire | Consultation et opérations personnelles autorisées | Consultation et opérations personnelles autorisées |

« Tous les droits Dibs » concerne les règles et le ledger Dibs; cela ne donne pas au conseil le contrôle du butin réservé au ML dans RCLootCouncil. Le ML peut gérer la session RCLC et envoyer un rappel non comptable, mais ne peut pas accorder, retirer ou régler arbitrairement des Dibs.

## État après correction

- `AUTO`, `STANDALONE` et `RCLootCouncil` sont des modes persistants; les actions administratives exigent toujours le GM ou un officier vérifié.
- Les nominations d'anciens administrateurs restent dans l'historique sans conférer de pouvoir.
- Les callbacks RCLootCouncil ne consomment un Dib que pour une réponse `DIB` finalisée et un Master Looter vérifiable; les tests et réponses non-DIB sont ignorés.
- Les API centrales, les réglages Adventure Guide et les transitions de saison passent par l'autorisation protégée.
- Les messages de synchronisation valident guilde, propriétaire, rôle, révision, taille et transitions avant écriture.
- Les vues Officer, les journaux, les exports de snapshot/digest et le relais complet échouent sans exposer de données lorsqu'ils sont appelés par un joueur ordinaire.
- Un callback RCLootCouncil reçu sur un client qui n'est pas le Master Looter local est ignoré; le contrôle d'identité ne repose pas seulement sur un objet d'acteur fourni par l'appelant.

Les sections suivantes décrivent les constats de la baseline et les décisions qui ont conduit à ces corrections.

## Constats prioritaires de la baseline (résolus dans l'implémentation actuelle)

### 1. Élevée — permissions différentes de celles demandées

Références : `src/modules/Permissions.lua:82`, `src/integrations/RCLootCouncil.lua:1721`.

En standalone, EvaluateStandalone autorise le GM local et les administrateurs nommés dans les SavedVariables. Il ne consulte pas IsOfficer. En intégration opérationnelle, EvaluateAuthority ne compare l'acteur qu'au ML; ni le GM ni le conseil n'ont d'exception.

Reproduction : un GM local avec un autre joueur comme ML reçoit `false` pour `ledger.adjust`.

Correction : appliquer la matrice ci-dessus dans une seule politique. Identifier les rangs officiers par leurs indices configurés pour la guilde; ne pas supposer que le seul rang 1 représente tous les officiers. Revalider les droits après changement de guilde, de rang, de ML ou de conseil. Réviser les tests et le README qui imposent aujourd'hui une autre politique.

### 2. Élevée — changement implicite d'autorité quand RC est dégradé

Référence : `src/modules/Permissions.lua:94`.

Tout état RC autre que `operational` finit dans EvaluateStandalone, y compris `degraded` ou une erreur de détection. Cela peut rendre des droits aux administrateurs standalone alors que l'installation utilise RC. Le README promet l'inverse.

Correction : stocker un choix explicite `standalone` ou `rclootcouncil`. Dans le second mode, conserver l'accès du GM vérifié conformément à la demande, mais refuser les droits ML/conseil invérifiables. Ne pas transformer une panne de RC en changement de politique.

### 3. Élevée — sérialisation incompatible avec la bibliothèque embarquée

Références : `src/integrations/Ace3.lua:43`, `src/libs/AceSerializer-3.0/AceSerializer-3.0.lua:122`, `tests/helpers/load_addon.lua`.

Serialize attend `true, payload` de la bibliothèque, alors que la vraie bibliothèque retourne directement la chaîne. L'adaptateur retourne donc nil. Sync.Send se replie sur un message texte contenant essentiellement le type et un identifiant : les données des demandes et des manifestes sont perdues.

Reproduction avec la bibliothèque du dépôt : résultat natif `string`, résultat de l'adaptateur `nil`. Le simulateur retourne précisément le faux contrat attendu, ce qui masque le défaut.

Correction : lire `ok, payload = pcall(...)`, puis valider le type string. Ajouter un test aller-retour utilisant la vraie bibliothèque embarquée et vérifier le contenu reçu, pas uniquement le résultat d'envoi.

### 4. Élevée — consommation de Dibs pour des attributions qui ne sont pas des DIB

Références : `src/integrations/RCLootCouncil.lua:1806`, `src/modules/ProtectedActions.lua:222`.

OnAwardSuccess force `finalized = true` et ne vérifie pas la réponse choisie. Un candidat simplement éligible peut perdre un Dib pour un loot normal. Le statut `test_mode` passe également.

Reproduction : OnAwardSuccess avec `test_mode` diminue le vrai solde local de 1.

Le [code amont RCLootCouncil](https://github.com/evil-morfar/RCLootCouncil2/blob/develop/ml_core.lua) émet RCMLAwardSuccess avec notamment les statuts `test_mode`, `normal`, `manually_added` et `indirect`, ainsi qu'un argument responseText. La présence de l'événement ne suffit donc pas à prouver une dépense DIB réelle.

Correction : vérifier la réponse DIB et le mode réel de l'attribution avant d'écrire. Exclure les tests du ledger réel. Définir aussi le traitement d'une réattribution : compensation de l'ancien débit et nouveau débit si nécessaire.

### 5. Élevée — identifiant d'attribution non unique entre sessions

Référence : `src/integrations/RCLootCouncil.lua:1812`.

La référence est construite avec l'index de session, le gagnant et l'itemID. Elle ne contient ni identifiant unique de séance de loot, ni saison. Deux objets identiques attribués au même joueur au même index lors de séances différentes sont confondus.

Reproduction : deux appels avec les mêmes paramètres ne débitent qu'une fois, même si le second doit représenter une nouvelle attribution. C'est souhaitable pour une retransmission, mais incorrect pour une nouvelle séance.

Correction : distinguer l'identifiant persistant de la séance et celui de l'objet attribué; inclure le périmètre de guilde/saison. Tester retransmission et nouvelle attribution séparément.

### 6. Élevée — synchronisation sans validation suffisante de l'émetteur et du contenu

Références : `src/modules/Sync.lua:48`, `src/modules/PreDibs.lua:564`, `src/modules/PreDibs.lua:593`.

La réception vérifie principalement que playerName correspond à l'émetteur. Elle ne vérifie ni l'appartenance à la guilde, ni la politique de réservation, ni le rôle autorisé pour un accusé de réception. UpsertFromSync accepte directement une nouvelle demande confirmée et ne réapplique pas les règles de transition aux mises à jour. Un statut final local peut donc être remplacé par un statut actif avec une révision supérieure. Les champs reçus sont copiés largement.

Reproductions : demande d'un joueur extérieur au roster acceptée; accusé de réception provenant d'un autre joueur quelconque accepté.

Correction : utiliser exclusivement l'émetteur fourni par le transport, vérifier guilde et canal, valider une liste fermée de champs et réappliquer les invariants de création/transition. Vérifier l'autorité des ACK et leur révision exacte. Limiter demandes, révisions, taille, profondeur et fréquence par émetteur. Les SavedVariables ou un champ actorId déclaré ne sont pas une preuve d'autorité distante.

### 7. Élevée — protocole de récupération incomplet et messages pouvant déclencher des erreurs

Référence : `src/modules/Sync.lua:48`.

MANIFEST construit un FETCH mais le gestionnaire réseau ne l'envoie pas. FETCH retourne simplement true et ne transmet aucune donnée. TRANSFER_END applique message.request sans assembler ni vérifier tous les fragments. Les fragments ne sont pas liés à l'émetteur initial et le nombre global de transferts n'est pas plafonné. Le manifeste ne couvre que les demandes actives du joueur local, ce qui omet les annulations nécessaires à la récupération.

Reproduction : TRANSFER_BEGIN avec transferId mais sans chunkCount provoque `attempt to compare nil with number`. Un ACK sans révision peut également atteindre une comparaison numérique invalide si la demande existe.

Correction : implémenter et tester le cycle complet entre deux clients, y compris annulations, pertes et retransmissions; valider chaque message avant tout accès ou comparaison. Ajouter plafonds globaux, budget total d'octets, indices entiers, assemblage complet et liaison transfert/émetteur.

Les saisons, règles de rang et transactions ne disposent pas ici d'un échange réseau opérationnel. SyncSnapshot/ApplySnapshot ne suffisent pas à fournir cette convergence.

### 8. Élevée — deux calculs contradictoires du solde et règles zéro écrasées

Références : `src/modules/Ledger.lua:74`, `src/modules/Ledger.lua:326`, `src/Core.lua:361`.

GetBalance utilise l'allocation enregistrée dans l'état du ledger. GetPlayerSeasonState utilise la règle du rang actuel. La colonne RC et les contrôles d'éligibilité peuvent donc travailler avec des montants différents. ApplyDefaultRules remplace aussi une allocation configurée à zéro par 1 au démarrage.

Reproductions : après définition d'une allocation à 5, GetBalance donne 1 et GetPlayerSeasonState donne 5; une règle mise à zéro redevient 1 après ApplyDefaultRules.

Correction : choisir un calcul unique pour toutes les interfaces et validations. Si le ledger est la source de vérité, enregistrer les allocations et ajustements comme événements plutôt que recalculer implicitement selon le rang actuel. Distinguer une règle absente d'une règle égale à zéro.

### 9. Élevée — écritures comptables insuffisamment validées

Références : `src/modules/Ledger.lua:95`, `src/modules/Ledger.lua:219`, `src/modules/ProtectedActions.lua`, `src/modules/Sync.lua:220`.

Les mutations normales passent par AddTransaction, qui ne fait pas appel à ValidateTransaction. Use accepte un nombre négatif et inverse son signe; aucun contrôle de solde suffisant n'est imposé à cet endroit. ApplySnapshot injecte également des transactions via AddTransaction sans contexte de provenance.

Reproduction : Use(joueur, -2) augmente le solde de 2.

Correction : un seul chemin d'écriture avec validation des types, montants finis et entiers, signe selon l'action, existence de la saison et motif. Empêcher une dépense supérieure au solde si les Dibs ne permettent pas de dette. Réserver les valeurs signées aux ajustements administratifs explicites. Ne pas exposer ApplySnapshot au réseau sans validation de provenance.

Nuance : les fonctions globales Lua ne constituent pas une frontière de sécurité contre le propriétaire du client. Le risque interjoueurs dépend de ce que les autres clients acceptent; je n'ai pas trouvé de branche réseau appelant directement ApplySnapshot dans cet état du code.

### 10. Élevée — boucle de rafraîchissement possible dans la fenêtre de vote

Références : `src/integrations/RCLootCouncil.lua:1437`, `src/integrations/RCLootCouncil.lua:1593`.

Le hook Update programme apply. apply retire le drapeau pending avant d'appeler les installateurs et refreshVotingColumns, lequel appelle de nouveau Update. Une fois le hook installé, le rafraîchissement déclenche ainsi son propre prochain timer. Déduit du chemin d'appel; non reproduit dans un vrai client WoW.

Correction : garder un garde de réentrance pendant toute l'opération et ne pas appeler Update depuis son propre hook. Ne réinstaller les colonnes qu'après changement de structure. Tester la file de timers jusqu'à stabilisation.

### 11. Moyenne — résolution des identités ambiguë entre royaumes

Références : `src/Core.lua:282`, `src/modules/Permissions.lua:50`, `src/modules/Ledger.lua:21`.

GetPlayerName ne retient que le premier résultat de UnitName. IsOfficer compare ensuite cette valeur sans normalisation au nom du roster. Le ledger accepte aussi le premier nom court correspondant, même si le nom demandé contenait un autre royaume. Deux personnages homonymes peuvent être confondus. Le simulateur fournit déjà un nom complet via UnitName, masquant une partie du problème.

Correction : centraliser l'identité GUID et Nom-Royaume; privilégier la correspondance complète et refuser une résolution courte ambiguë. Ne jamais ajouter un royaume à une chaîne qui est déjà un GUID. Tester deux personnages homonymes et un roster encore indisponible.

### 12. Moyenne — modification automatique de l'historique appartenant à RC

Référence : `src/integrations/RCLootCouncil.lua:1151`.

sanitizeRCLootCouncilHistory parcourt toutes les entrées de l'historique RC et remplace les identifiants qui ne correspondent pas à son format attendu, dès l'initialisation. Il ne limite pas ce traitement aux entrées créées par Dibs.

Correction : conserver l'audit Dibs séparément. Si une migration de ses propres entrées RC est nécessaire, la limiter à un marqueur de provenance, la versionner et préserver les identifiants précédents.

## Proposition de conception et ordre de travail

1. **Permissions et installation.** Conserver un paquet unique avec RC en dépendance optionnelle, ce que le TOC prévoit déjà. Ajouter un choix explicite des deux modes. Centraliser la matrice demandée et retirer les administrateurs standalone nommés du modèle par défaut, puisqu'ils ajoutent un troisième mécanisme non demandé. Identifier les rangs officiers dans la configuration de guilde.
2. **Comptabilité.** Un service de mutation validé, un calcul de solde unique, des événements d'allocation et de compensation explicites. Corriger les attributions DIB, les tests RC et les identifiants d'attribution avant le déploiement.
3. **Échanges.** Corriger AceSerializer, puis réaliser un vrai scénario à deux clients : configuration de saison commune, demande, acceptation, accusé, annulation, déconnexion et récupération. Chaque client vérifie lui-même l'émetteur et les droits avant d'adopter une mutation.
4. **Concurrence.** ML/conseil/officiers peuvent avoir les mêmes droits, mais deux postes ne doivent pas valider simultanément la dernière unité du même joueur. Prévoir un séquenceur de mutations par périmètre partagé ou une autre règle de concurrence explicite, particulièrement entre raids. Une simple fusion d'identifiants ne garantit pas un solde cohérent.
5. **Intégration.** Supprimer le cycle Update, isoler les adaptations RC dans l'adaptateur, préserver son historique et tester la version effectivement installée chez Yan.

## Validation effectuée et limites

- Suite existante exécutée dans Lua 5.1 via un moteur temporaire : **102 tests réussis, 0 échec, 33 fichiers**.
- Sondes indépendantes exécutées avec le chargeur de test du dépôt : incompatibilité du vrai AceSerializer, erreur TRANSFER_BEGIN, différences de soldes, écrasement du zéro, quantité négative, GM refusé sous RC, repli en état dégradé, débit en test_mode, collision de référence, demande et ACK sans autorité suffisante.
- Le simulateur utilise notamment un faux contrat Serialize et un UnitName déjà qualifié. Ces tests ne remplacent pas un chargement réel des bibliothèques et un échange entre clients.
- La boucle UI, les effets des homonymes en client et les changements d'historique RC ont été examinés statiquement. Aucun test en jeu ni validation de la version WoW réellement installée n'a été effectué.
- L'analyse de la sécurité vise l'intégrité des Dibs entre clients; elle ne démontre pas une compromission du compte Battle.net ou de l'ordinateur.
