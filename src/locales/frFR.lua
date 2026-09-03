local Dibs = _G.Dibs
Dibs.L = Dibs.L or {}

local L = Dibs.L

L.AUTHORITY_INVALID_ACTION = "Action protegee inconnue."
L.AUTHORITY_INVALID_ACTOR = "Impossible d'identifier l'acteur."
L.AUTHORITY_RC_UNVERIFIABLE = "L'autorite RCLootCouncil n'a pas pu etre verifiee."
L.AUTHORITY_RC_STATE_CHANGED = "L'autorite RCLootCouncil a change pendant l'evaluation."
L.AUTHORITY_RC_AUTHORIZED = "Autorise par RCLootCouncil."
L.AUTHORITY_RC_NOT_MASTER_LOOTER = "Seul le Master Looter actuel de RCLootCouncil peut effectuer cette action."
L.AUTHORITY_STANDALONE_GUILD_MASTER = "Autorise en tant que maitre de guilde."
L.AUTHORITY_STANDALONE_APPOINTED_ADMIN = "Autorise en tant qu'administrateur Dibs."
L.AUTHORITY_STANDALONE_NOT_AUTHORIZED = "Vous n'etes pas autorise a effectuer cette action Dibs."
L.STANDALONE_ADMIN_GM_ONLY = "Seul le maitre de guilde peut gerer les administrateurs Dibs."
L.PROTECTED_ACTION_DENIED = "Action refusee."
L.PROTECTED_ACTION_UNAVAILABLE = "Module requis indisponible."
L.SEASON_CREATE_FAILED = "Echec de creation de la saison."
L.SEASON_NOT_FOUND = "Saison introuvable."
L.AWARD_NOT_FINAL = "Le loot n'est pas finalise; aucun Dib n'est consomme."
L.AWARD_INVALID = "Le payload du loot n'a pas les champs requis."
L.AWARD_CONSUME_FAILED = "Impossible de consommer un Dib pour ce loot."
L.UI_DEFERRED_COMBAT = "L'interface officier s'ouvrira apres le combat."
L.RC_STATUS_UNAVAILABLE = "Le statut RCLootCouncil est indisponible."
L.RC_COMPATIBILITY_FALLBACK = "L'integration candidats RCLootCouncil est indisponible; affichage local Dibs utilise."
