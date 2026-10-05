extends RefCounted
## Routage : événement de simulation -> son -> recette(s) à jouer, avec leur hauteur et leur force.
## Portage des tables de GAMES/dungeon_666/src/audio/sfx.mjs (SOUNDS, ROUTES, SILENT_EVENTS,
## HAPTICS) et des choix par événement de recipes.mjs (quelle variante, quelle hauteur).
##
## Trois étages : un TYPE d'événement (`hit`) donne une CLÉ de son (`hit`, `burn` ou rien), qui
## porte les règles de mixage (voix, priorité, niveau) ; la clé et l'événement donnent une ou
## plusieurs RECETTES rendues (recettes.gd), chacune à sa hauteur et à son gain.
##
## Aucun état, aucun nœud : seulement les champs de l'événement reçu.

const POIDS_CRITIQUE := 25.0 # un critique passe devant un coup normal pour représenter le groupe
const INDEX_COUP_FINAL := 2.0 # 3e coup du combo : coup lourd
const DISTANCE_LOINTAINE := 900.0 # u : au-delà, le son est au plus faible
const GAIN_LOINTAIN := 0.6
const VIBRATION_MS := {"blessure": 40, "coup_lourd": 12, "gardien": 80, "esquive": 8}

## Sons : voix = voix simultanées max, par_image = sons max par image (le reste du groupe
## renforce leur gain), priorite = ordre de passage (et accès à la réserve de voix vitales),
## gain = niveau de mixage.
const SONS := {
	"swing": {"voix": 3, "par_image": 1, "priorite": 5, "gain": 0.9},
	"hit": {"voix": 4, "par_image": 2, "priorite": 6, "gain": 1.0},
	"burn": {"voix": 2, "par_image": 1, "priorite": 1, "gain": 0.15},
	"kill": {"voix": 4, "par_image": 2, "priorite": 7, "gain": 0.55},
	"chain": {"voix": 3, "par_image": 2, "priorite": 4, "gain": 0.35},
	"dash": {"voix": 2, "par_image": 1, "priorite": 7, "gain": 0.5},
	"dodge": {"voix": 2, "par_image": 1, "priorite": 9, "gain": 0.55},
	"dashNova": {"voix": 2, "par_image": 1, "priorite": 5, "gain": 0.5},
	"dashReady": {"voix": 1, "par_image": 1, "priorite": 1, "gain": 0.12},
	"deflect": {"voix": 3, "par_image": 2, "priorite": 6, "gain": 1.0},
	"skill": {"voix": 2, "par_image": 1, "priorite": 7, "gain": 0.55},
	"gadget": {"voix": 2, "par_image": 1, "priorite": 8, "gain": 0.65},
	"super": {"voix": 1, "par_image": 1, "priorite": 9, "gain": 0.7},
	"superTick": {"voix": 2, "par_image": 1, "priorite": 3, "gain": 0.45},
	"superEnd": {"voix": 1, "par_image": 1, "priorite": 3, "gain": 0.35},
	"superReady": {"voix": 1, "par_image": 1, "priorite": 8, "gain": 0.5},
	"playerHurt": {"voix": 2, "par_image": 1, "priorite": 10, "gain": 0.75},
	"playerDeath": {"voix": 1, "par_image": 1, "priorite": 10, "gain": 0.85},
	"enemyAttack": {"voix": 3, "par_image": 2, "priorite": 4, "gain": 0.3},
	"boom": {"voix": 3, "par_image": 2, "priorite": 6, "gain": 0.6},
	"hazardCancel": {"voix": 2, "par_image": 1, "priorite": 3, "gain": 0.5},
	"slam": {"voix": 3, "par_image": 2, "priorite": 6, "gain": 0.6},
	"spawnWarn": {"voix": 2, "par_image": 1, "priorite": 1, "gain": 0.05},
	"bossPhase": {"voix": 1, "par_image": 1, "priorite": 10, "gain": 0.8},
	"bossSummon": {"voix": 1, "par_image": 1, "priorite": 6, "gain": 0.5},
	"coin": {"voix": 3, "par_image": 1, "priorite": 4, "gain": 0.35},
	"heal": {"voix": 2, "par_image": 1, "priorite": 5, "gain": 0.45},
	"boonGain": {"voix": 1, "par_image": 1, "priorite": 8, "gain": 0.55},
	"equip": {"voix": 1, "par_image": 1, "priorite": 8, "gain": 0.55},
	"roomClear": {"voix": 1, "par_image": 1, "priorite": 8, "gain": 0.55},
	"doorsOpen": {"voix": 1, "par_image": 1, "priorite": 4, "gain": 0.3},
	"floorEnter": {"voix": 1, "par_image": 1, "priorite": 7, "gain": 0.5},
	"checkpoint": {"voix": 1, "par_image": 1, "priorite": 8, "gain": 0.55},
	"choiceOpen": {"voix": 1, "par_image": 1, "priorite": 3, "gain": 0.35},
	"victory": {"voix": 1, "par_image": 1, "priorite": 10, "gain": 0.7},
	"gameOver": {"voix": 1, "par_image": 1, "priorite": 9, "gain": 0.6},
	# Combat V3 (étape 5) : des sons propres aux ultimes, aux déplacements de classe, à la
	# progression et aux compétences neuves. Niveaux calés sur les sons voisins (skill 0,55 ;
	# gadget 0,65 ; super 0,7 ; boom 0,6) ; ce qui se répète (morsure, éclair, marque) est bas.
	"gadgetCharge": {"voix": 1, "par_image": 1, "priorite": 4, "gain": 0.35},
	"levelUp": {"voix": 1, "par_image": 1, "priorite": 8, "gain": 0.5},
	"land": {"voix": 1, "par_image": 1, "priorite": 6, "gain": 0.55},
	"ultFreeze": {"voix": 1, "par_image": 1, "priorite": 8, "gain": 0.35},
	"ultStrike": {"voix": 1, "par_image": 1, "priorite": 9, "gain": 0.8},
	"ultBolt": {"voix": 3, "par_image": 2, "priorite": 5, "gain": 0.4},
	"formEnd": {"voix": 1, "par_image": 1, "priorite": 5, "gain": 0.4},
	"formHowl": {"voix": 1, "par_image": 1, "priorite": 7, "gain": 0.5},
	"formBurst": {"voix": 1, "par_image": 1, "priorite": 8, "gain": 0.7},
	"packSpawn": {"voix": 2, "par_image": 1, "priorite": 6, "gain": 0.45},
	"bite": {"voix": 2, "par_image": 1, "priorite": 2, "gain": 0.22},
	"parry": {"voix": 1, "par_image": 1, "priorite": 9, "gain": 0.7},
	"block": {"voix": 2, "par_image": 1, "priorite": 7, "gain": 0.6},
	"fissure": {"voix": 2, "par_image": 1, "priorite": 6, "gain": 0.6},
	"mark": {"voix": 2, "par_image": 1, "priorite": 4, "gain": 0.3},
	"axeCatch": {"voix": 1, "par_image": 1, "priorite": 5, "gain": 0.45},
	"traitShot": {"voix": 1, "par_image": 1, "priorite": 7, "gain": 0.65},
	"stigmate": {"voix": 2, "par_image": 1, "priorite": 6, "gain": 0.6},
	"shade": {"voix": 1, "par_image": 1, "priorite": 6, "gain": 0.5},
	"swap": {"voix": 1, "par_image": 1, "priorite": 6, "gain": 0.45},
	"grace": {"voix": 1, "par_image": 1, "priorite": 7, "gain": 0.65},
	"graceKill": {"voix": 1, "par_image": 1, "priorite": 7, "gain": 0.4},
	"hailCall": {"voix": 1, "par_image": 1, "priorite": 6, "gain": 0.5},
	"hail": {"voix": 2, "par_image": 1, "priorite": 6, "gain": 0.6},
}
## Sons que la vue Son joue SANS événement de simulation (elle LIT l'état, comme le HUD) : niveau et
## priorité, et ce qui les déclenche (dit par la planche de sons). Voir son.gd, `_suivre_etat`.
const SONS_VUE := {
	"ultime_armement": {"gain": 0.4, "priorite": 8, "quand": "vue Son : attaque TENUE jauge pleine (player.superHold monte) ; coupé net si l'on relâche"},
	"franchissement": {"gain": 0.3, "priorite": 4, "quand": "vue Son : le héros passe AU-DESSUS d'une rivière ou d'un obstacle bas (déplacement de classe, Bond)"},
	"point_arbre": {"gain": 0.5, "priorite": 5, "quand": "vue Son : un point dépensé dans l'arbre au Grimoire (app.profil_change, rangs achetés en hausse)"},
}
## Sons dont le représentant d'un groupe est choisi au poids (voir `poids`).
const SONS_PESES := ["hit", "kill", "playerHurt", "enemyAttack", "boom", "slam", "spawnWarn", "coin", "ultBolt"]

## Événement de sim -> clé de son. Trois types dépendent de l'événement : voir `cle`.
const ROUTES := {
	"swing": "swing", "kill": "kill", "chain": "chain",
	"dash": "dash", "dodge": "dodge", "dashNova": "dashNova", "dashReady": "dashReady",
	"deflect": "deflect", "gadget": "gadget",
	"super": "super", "superTick": "superTick", "superEnd": "superEnd", "superReady": "superReady",
	"playerHurt": "playerHurt", "playerDeath": "playerDeath",
	"enemyAttack": "enemyAttack", "hazardCancel": "hazardCancel",
	"wallSlam": "slam", "chargerWall": "slam", "spawnWarn": "spawnWarn",
	"bossPhase": "bossPhase", "bossSummon": "bossSummon",
	"gold": "coin", "buy": "coin", "heal": "heal",
	"boonGain": "boonGain", "equip": "equip", "roomClear": "roomClear", "doorsOpen": "doorsOpen",
	"floorEnter": "floorEnter", "checkpoint": "checkpoint", "respawn": "checkpoint",
	"choiceOpen": "choiceOpen", "victory": "victory", "gameOver": "gameOver",
	# Charge rendue par un élite abattu : l'ancien accord « Super prêt » (la jauge PLEINE a désormais
	# son propre signal, `ultime_pret` : c'est le moment de penser à tenir le bouton).
	"gadgetCharge": "gadgetCharge",
	# Les trois ultimes de classe (étape 2), chacun ses sons depuis l'étape 5. Leur lancement est
	# l'événement `super` (ci-dessus : une recette par ultime). Sentence capitale : le temps figé,
	# le fracas, un éclair par ennemi (une exécution sonne la lame qui tombe). Forme du Damné : la
	# ruée garde le son du dash ; hurlement, embrasement et fin ont le leur. Meute des Limbes :
	# apparition et morsure ; un limier tué meurt comme un ennemi, un limier qui s'en va à la fin de
	# sa durée sonne la fin d'un Super.
	"ultFreeze": "ultFreeze", "ultStrike": "ultStrike", "ultBolt": "ultBolt",
	"formRush": "dash", "formHowl": "formHowl", "formBurst": "formBurst", "formEnd": "formEnd",
	"allyBite": "bite", "allyDeath": "kill", "allyGone": "superEnd",
	# Arbre de compétences (étape 3) : un niveau de classe passé a son arpège.
	"levelUp": "levelUp",
	# Saut du Bourreau : l'atterrissage (le décollage est l'événement `dash`, champ `move`).
	"moveLand": "land",
	# Compétences neuves (étapes 4 et 5) : une signature par compétence. Leur LANCEMENT est
	# l'événement `skill` ou `gadget` (une recette pour la Hache, la Contre-taille, le Sillage, la
	# Garde, le Leurre ; les autres gardent la recette de repli, ou sont couvertes : voir `cle`).
	"parry": "parry", "guardBlock": "block", "fissure": "fissure", "marked": "mark",
	"markJump": "chain", "axeCatch": "axeCatch", "guardEnd": "superEnd", "traitShot": "traitShot",
	"shadeSwap": "swap", "grace": "grace", "graceKill": "graceKill", "hailCall": "hailCall", "hail": "hail",
}
## Routes qui dépendent de l'événement : les clés possibles (la décision est dans `cle`).
const ROUTES_CALCULEES := {
	"hit": ["hit", "burn"], # brûlure : grésillement ; chaîne et mur : déjà portés par un autre son
	"hazardFire": ["boom"], # sauf le possédé, qui émet déjà `explode` : un seul boum
	"pickup": ["coin", "heal"],
	"skill": ["skill"], # sauf les compétences dont un autre événement porte le son (SKILLS_COUVERTES)
	"explode": ["boom", "stigmate", "shade"], # Stigmate qui explose, Ombre jumelle qui surgit : leur signature
	"allySpawn": ["packSpawn"], # les limiers ; le leurre et l'ombre sont portés par `gadget` et `explode`
}
## Compétences dont le lancement (`skill`) est TU : un événement plus précis sonne au même instant —
## traitShot (Trait de Nemrod), fissure (Faille), explode:ombre (Ombre jumelle), grace (Décollation),
## hailCall (Grêle des Limbes).
const SKILLS_COUVERTES := ["trait", "faille", "ombre", "grace", "grele"]
const COUPS_COUVERTS := ["chain", "wall"]

## Silencieux À DESSEIN : spawn (couvert par spawnWarn), attackStart / castStart (couverts par
## swing / skill), cancel, dashEnd, projectileEnd, hazard (télégraphe visuel ; enemyAttack porte
## l'audio), choiceClose, wave. Tout événement de sim est soit routé, soit listé ici (testé).
const SILENCIEUX := [
	"spawn", "attackStart", "castStart", "cancel", "dashEnd", "projectileEnd", "hazard", "choiceClose", "wave",
	"immune", # Gardien en transition de phase : retour visuel seulement
	"moveShort", # déplacement raccourci au bord de l'eau : le son du dash est déjà parti, retour visuel seulement
	"souls", # Âmes d'un élite : le son de mort de l'élite suffit
	"treePoint", # point de compétence d'un Gardien vaincu pour la première fois : le checkpoint sonne déjà
	"stash", # objet rangé au coffre : le clic du menu suffit
	"returnTown", # fin de la descente : la Ville prend le relais
	"bossShield", # chaînes du Colosse levées / brisées : retour visuel (chaînes, barre de vie)
	"hook", # crochet de la Chaîne d'Enfer qui harponne : le son d'impact (hit) le porte
	"kitPulse", # impulsion d'un Totem de givre : les coups (hit) qu'elle inflige portent le son
	"formStart", # entrée dans la Forme du Damné : le son du lancement (`super`) la porte
	"allyHurt", # limier blessé : retour visuel seulement (le son de blessure est réservé au héros)
	"parryStart", # Contre-taille : la taillade est portée par le son de la compétence (`skill`)
	"parryEnd", # la garde qui s'éteint sans avoir paré : retour visuel seulement
	"guardStart", # Garde de fer levée : le son de la compétence à charges (`gadget`) la porte
	"axeTurn", # demi-tour de la Hache du supplice : retour visuel seulement
	"sillageEnd", # fin du Sillage de braise : retour visuel seulement (une détonation émet `explode`)
	"echo", # l'Ombre jumelle répète un coup : les coups (hit) qu'elle inflige portent le son
]

# ---------------------------------------------------------------- clé de son -> recettes

## Sons à recette unique.
const RECETTE_SIMPLE := {
	"burn": "brulure", "dodge": "esquive", "dashReady": "dash_pret",
	"deflect": "parade", "superEnd": "super_fin", "superReady": "ultime_pret", "gadgetCharge": "super_pret",
	"levelUp": "niveau", "land": "saut_atterrissage",
	"ultFreeze": "sentence_gel", "ultStrike": "sentence_fracas",
	"formEnd": "forme_fin", "formHowl": "forme_hurlement", "formBurst": "forme_embrasement",
	"packSpawn": "meute_apparition", "bite": "meute_morsure",
	"parry": "parade_contre_taille", "block": "garde_blocage", "fissure": "faille_fissure", "mark": "marque",
	"axeCatch": "hache_retour", "traitShot": "trait_tir", "stigmate": "stigmate_explosion",
	"shade": "ombre_surgit", "swap": "ombre_echange", "grace": "decollation", "graceKill": "decollation_encore",
	"hailCall": "grele_tir", "hail": "grele_chute",
	"playerHurt": "blessure", "playerDeath": "mort_heros", "hazardCancel": "annulation",
	"slam": "choc", "spawnWarn": "apparition", "bossPhase": "rugissement", "bossSummon": "invocation",
	"heal": "soin", "doorsOpen": "portes", "checkpoint": "checkpoint", "choiceOpen": "choix",
	"victory": "victoire", "gameOver": "fin_de_partie", "dashNova": "gadget",
}
## Sons dont un champ de l'événement choisit le timbre : [champ, préfixe, valeurs, recette de repli].
const RECETTE_PAR_CHAMP := {
	"skill": ["skill", "competence_", ["chain", "bond", "brasier", "volee", "hachette", "riposte"], "competence"],
	"gadget": ["gadget", "gadget_", ["bombe", "piege", "cri", "totem", "sillage", "garde", "leurre"], "gadget"],
	"super": ["super", "super_", ["sentence", "nuee", "forme", "magie", "meute"], "super"],
	"dash": ["move", "deplacement_", ["saut", "roulade"], "dash"], # le déplacement de la classe ; repli : le dash (et la ruée de forme)
	"superTick": ["super", "super_coup_", ["sentence", "nuee"], "super_coup"],
	"boonGain": ["rarity", "benediction_", ["commun", "rare", "epique"], "benediction_commun"],
	"enemyAttack": ["enemy", "cri_", ["imp", "archer", "brute", "charger", "pyromancer", "necromancer", "summon", "pavois", "stalker", "boss", "bossRing", "cerbere", "minos", "colosse"], "cri_defaut"],
}
## Sons dont la recette (ou la superposition) se décide par plusieurs champs : voir `parties`.
const RECETTES_COMPOSEES := {
	"swing": ["coup_0", "coup_1", "coup_2", "coup_frappe", "tir_arc", "tir_lourd"],
	"hit": ["impact", "impact_lourd", "critique"],
	"kill": ["mort", "mort_elite", "mort_gardien"],
	"chain": ["eclair_0", "eclair_1", "eclair_2"],
	"boom": ["explosion", "explosion_feu"],
	"coin": ["piece", "piece_achat"],
	"equip": ["equipement_0", "equipement_1", "equipement_2", "equipement_3"],
	"roomClear": ["salle_nettoyee", "salle_gardien"],
	"floorEnter": ["etage", "etage_gardien"],
	"ultBolt": ["sentence_eclair", "sentence_execution"],
}
## Recettes jouées HORS événement de simulation : par les écrans (`son.jouer("clic")`), ou par la
## vue Son elle-même quand elle lit l'état (SONS_VUE).
const RECETTES_ECRANS := ["clic", "ultime_armement", "franchissement", "point_arbre"]

const HAUTEUR_GARDIEN := 0.7
## Timbre de la cible : les grosses bêtes sonnent plus grave (champ `enemy` de hit / kill).
const HAUTEUR_ENNEMI := {
	"imp": 1.1, "archer": 1.05, "exploder": 1.15, "charger": 0.92, "brute": 0.8,
	"gardien": HAUTEUR_GARDIEN, "boss": HAUTEUR_GARDIEN, "pyromancer": 1.08, "necromancer": 1.0,
	"pavois": 0.86, "stalker": 1.12, "banner": 0.95, # lourd et cuirassé ; mince et vif ; porteur moyen
}
const CRIS_DE_GARDIEN := ["boss", "bossRing", "cerbere", "minos", "colosse"]
const ARMES_LOURDES := ["arbalete"]
const COUP_LEGER := 8.0 # dégâts d'un coup « léger » (aigu, discret)
const COUP_ENORME := 40.0 # dégâts d'un coup « énorme » (grave, fort)
const HAUTEUR_COUP := [1.15, 0.72] # léger -> énorme
const GAIN_COUP := [0.6, 1.25]
const BLESSURE_REFERENCE := 30.0 # dégâts d'un coup qui fait vraiment mal
const GAIN_BLESSURE := [0.8, 1.2]
const RAYON_REFERENCE := 100.0 # u : rayon d'une explosion « standard »
const TAILLE_EXPLOSION := [0.6, 1.6]
const ETINCELLES_PAR_RARETE := {"commun": 0, "magique": 1, "rare": 2, "legendaire": 3}
const VARIANTES_ECLAIR := 3
## Style par type de zone (hazard.kind) : hauteur, gain, couche de feu.
const STYLE_ZONE := {
	"brute": [0.9, 0.9, false], "bossSlam": [0.75, 1.15, false], "fireBlast": [1.0, 1.0, true],
	"sinBlast": [1.3, 0.6, true], "exploder": [1.0, 1.0, true],
	"cerbereLand": [0.85, 1.0, false], "cerbereShock": [0.95, 0.8, false],
	"cerbereFlame": [1.15, 0.7, true], "cerbereFire": [1.2, 0.6, true],
	"minosSentence": [1.3, 0.55, false], "minosTile": [1.4, 0.5, false], "minosSeal": [0.9, 0.9, false],
	"colosseFist": [0.7, 1.2, false], "colosseQuake": [0.65, 0.9, false],
	"colosseRock": [0.8, 0.8, false], "colosseEmber": [1.3, 0.35, true],
	# Zones du héros (explode{hero, kind}) : sans crépitement de feu (le feu = les ennemis).
	"bombe": [0.85, 1.1, false], "piege": [1.4, 0.6, false], "bond": [0.7, 1.1, false],
	"brasier": [1.2, 0.55, false],
	"pyre": [1.2, 0.55, true], # cercle de la Pyromancienne qui s'embrase
	"stalker": [1.25, 0.8, false], # frappe de lames du Traqueur : plus sèche et plus aiguë qu'une masse
	# Souffles des compétences neuves qui gardent le boum commun (sans crépitement de feu) : braises
	# du Sillage qui détonent (petites, aiguës), contrecoup de la Garde de fer, leurre piégé.
	"sillage": [1.5, 0.35, false], "garde": [0.8, 1.0, false], "leurre": [1.1, 0.8, false],
}
## Variantes rejouées autrement : [hauteur, gain] quand le champ nommé est vrai.
const VARIANTE_FORTE := {
	"slam": ["boss", 0.8, 1.2], "spawnWarn": ["elite", 0.8, 1.4],
}
const NOVA_DE_DASH := [1.2, 0.55] # la nova de dash (bénédiction) : petite sœur du gadget
const MARQUE_DE_PROIE := 1.25 # hauteur de la marque de la Chasseresse (celle du Stigmate : 1)
const TRAIT_LACHE_TOT := [1.15, 0.6] # Trait de Nemrod lâché avant la pleine charge : plus aigu, moins fort
const GAIN_REAPPARITION := 0.7

# ---------------------------------------------------------------- lecture d'un événement

## Nombre fini, sinon valeur de repli (un événement mal formé ne casse jamais le son).
static func nombre(v, repli: float) -> float:
	if (v is float or v is int) and is_finite(v):
		return float(v)
	return repli

static func types_routes() -> Array:
	return ROUTES.keys() + ROUTES_CALCULEES.keys()

## Le type est-il connu du son (routé ou silencieux à dessein) ?
static func connu(type: String) -> bool:
	return ROUTES.has(type) or ROUTES_CALCULEES.has(type) or SILENCIEUX.has(type)

## Clé de son d'un événement ; "" : silencieux.
static func cle(ev: Dictionary) -> String:
	var type = ev.get("type")
	var kind = ev.get("kind")
	match type:
		"hit":
			if kind is String and kind == "burn":
				return "burn"
			return "" if COUPS_COUVERTS.has(kind) else "hit"
		"hazardFire":
			return "" if (kind is String and kind == "exploder") else "boom"
		"pickup":
			return "heal" if (kind is String and kind == "heal") else "coin"
		"skill":
			return "" if SKILLS_COUVERTES.has(ev.get("skill")) else "skill"
		"explode":
			if D6Js.truthy(ev.get("hero")) and kind is String and kind == "stigmate":
				return "stigmate"
			return "shade" if (D6Js.truthy(ev.get("hero")) and kind is String and kind == "ombre") else "boom"
		"allySpawn":
			return "" if kind is String else "packSpawn" # un allié qui a un genre (leurre, ombre) a déjà son son
	return ROUTES.get(type, "")

## Coup lourd : frappe de dash, ou 3e coup du combo.
static func coup_lourd(ev: Dictionary, dernier_coup: float) -> bool:
	var kind = ev.get("kind")
	if not (kind is String):
		return false
	return kind == "strike" or (kind == "melee" and dernier_coup == INDEX_COUP_FINAL)

## Poids d'un événement dans son groupe : le plus lourd représente le groupe.
static func poids(cle_son: String, ev: Dictionary) -> float:
	match cle_son:
		"hit":
			return nombre(ev.get("amount"), 0.0) + (POIDS_CRITIQUE if D6Js.truthy(ev.get("crit")) else 0.0)
		"kill":
			return (2.0 if D6Js.truthy(ev.get("boss")) else 0.0) + (1.0 if D6Js.truthy(ev.get("elite")) else 0.0)
		"playerHurt":
			return nombre(ev.get("amount"), 0.0)
		"enemyAttack":
			return 1.0 if CRIS_DE_GARDIEN.has(ev.get("enemy")) else 0.0
		"boom":
			return nombre(ev.get("r"), 0.0)
		"slam":
			return 1.0 if D6Js.truthy(ev.get("boss")) else 0.0
		"spawnWarn":
			return 1.0 if D6Js.truthy(ev.get("elite")) else 0.0
		"coin":
			return 1.0 if ev.get("type") == "buy" else 0.0
		"ultBolt":
			return 1.0 if D6Js.truthy(ev.get("executed")) else 0.0
	return 0.0

## Atténuation douce des sons lointains, relative au héros ; 1 si l'événement n'a pas de position.
static func attenuation(ev: Dictionary, game) -> float:
	if not (game is Dictionary) or not (game.get("player") is Dictionary):
		return 1.0
	var p: Dictionary = game.player
	var x := nombre(ev.get("x"), nombre(ev.get("x0"), NAN))
	var px := nombre(p.get("x"), NAN)
	if is_nan(x) or is_nan(px):
		return 1.0
	var py := nombre(p.get("y"), 0.0)
	var dy := nombre(ev.get("y"), nombre(ev.get("y0"), py)) - py
	var loin := clampf(Vector2(x - px, dy).length() / DISTANCE_LOINTAINE, 0.0, 1.0)
	return lerpf(1.0, GAIN_LOINTAIN, loin)

## Vibration (ms) demandée par un événement ; 0 = aucune.
static func vibration(ev: Dictionary, lourd: bool) -> int:
	match ev.get("type"):
		"playerHurt":
			return VIBRATION_MS.blessure
		"hit":
			return VIBRATION_MS.coup_lourd if lourd else 0
		"kill":
			return VIBRATION_MS.gardien if D6Js.truthy(ev.get("boss")) else 0
		"bossPhase":
			return VIBRATION_MS.gardien
		"dodge":
			return VIBRATION_MS.esquive
	return 0

# ---------------------------------------------------------------- recettes d'un son

## Toutes les recettes qu'une clé de son peut demander (outillage : test, planche de sons).
static func recettes_de(cle_son: String) -> Array:
	if RECETTE_SIMPLE.has(cle_son):
		return [RECETTE_SIMPLE[cle_son]]
	if RECETTES_COMPOSEES.has(cle_son):
		return RECETTES_COMPOSEES[cle_son]
	if not RECETTE_PAR_CHAMP.has(cle_son):
		return []
	var regle: Array = RECETTE_PAR_CHAMP[cle_son]
	var out: Array = [regle[3]]
	for valeur in regle[2]:
		if not out.has(regle[1] + valeur):
			out.append(regle[1] + valeur)
	return out

## Types d'événements qui peuvent mener à cette clé de son.
static func evenements_de(cle_son: String) -> Array:
	var out: Array = []
	for type in ROUTES:
		if ROUTES[type] == cle_son:
			out.append(type)
	for type in ROUTES_CALCULEES:
		if ROUTES_CALCULEES[type].has(cle_son):
			out.append(type)
	return out

## Les parties à jouer ensemble pour un son : [[recette, hauteur, gain], …].
## `hauteur` : la variation aléatoire déjà tirée ; `lourd` : coup lourd (voir `coup_lourd`).
static func parties(cle_son: String, ev: Dictionary, lourd: bool, hauteur: float) -> Array:
	match cle_son:
		"swing":
			return [[_coup(ev), hauteur, 1.0]]
		"hit":
			return _impact(ev, lourd, hauteur)
		"kill":
			return _mort(ev, hauteur)
		"boom":
			return _explosion(ev, hauteur)
		"chain":
			return [["eclair_%d" % (randi() % VARIANTES_ECLAIR), hauteur, 1.0]]
		"coin":
			return [["piece_achat" if ev.get("type") == "buy" else "piece", hauteur, 1.0]]
		"equip":
			return [["equipement_%d" % ETINCELLES_PAR_RARETE.get(ev.get("rarity"), 0), hauteur, 1.0]]
		"roomClear":
			return [["salle_gardien" if D6Js.truthy(ev.get("boss")) else "salle_nettoyee", hauteur, 1.0]]
		"floorEnter":
			return [["etage_gardien" if D6Js.truthy(ev.get("isBoss")) else "etage", hauteur, 1.0]]
		"ultBolt":
			return [["sentence_execution" if D6Js.truthy(ev.get("executed")) else "sentence_eclair", hauteur, 1.0]]
	if RECETTE_PAR_CHAMP.has(cle_son):
		var regle: Array = RECETTE_PAR_CHAMP[cle_son]
		var valeur = ev.get(regle[0])
		return [[regle[1] + valeur if regle[2].has(valeur) else regle[3], hauteur, 1.0]]
	return _simple(cle_son, ev, hauteur)

static func _simple(cle_son: String, ev: Dictionary, hauteur: float) -> Array:
	if not RECETTE_SIMPLE.has(cle_son):
		return []
	var h := hauteur
	var g := 1.0
	if VARIANTE_FORTE.has(cle_son) and D6Js.truthy(ev.get(VARIANTE_FORTE[cle_son][0])):
		h *= VARIANTE_FORTE[cle_son][1]
		g = VARIANTE_FORTE[cle_son][2]
	match cle_son:
		"dashNova":
			h *= NOVA_DE_DASH[0]
			g = NOVA_DE_DASH[1]
		"playerHurt":
			g = lerpf(GAIN_BLESSURE[0], GAIN_BLESSURE[1], clampf(nombre(ev.get("amount"), 0.0) / BLESSURE_REFERENCE, 0.0, 1.0))
		"checkpoint":
			g = GAIN_REAPPARITION if ev.get("type") == "respawn" else 1.0
		"mark":
			h *= MARQUE_DE_PROIE if ev.get("mark") == "proie" else 1.0
		"traitShot":
			if not D6Js.truthy(ev.get("full")):
				h *= TRAIT_LACHE_TOT[0]
				g = TRAIT_LACHE_TOT[1]
	return [[RECETTE_SIMPLE[cle_son], h, g]]

## Coup du héros : tir (arc ou trait lourd), frappe de dash, ou coup du combo.
static func _coup(ev: Dictionary) -> String:
	var frappe := D6Js.truthy(ev.get("strike"))
	if D6Js.truthy(ev.get("ranged")):
		return "tir_lourd" if (frappe or ARMES_LOURDES.has(ev.get("weapon"))) else "tir_arc"
	if frappe:
		return "coup_frappe"
	return "coup_%d" % int(clampf(D6Js.jround(nombre(ev.get("index"), 0.0)), 0.0, INDEX_COUP_FINAL))

## Impact : plus le coup est fort, plus il est grave et fort ; la cible donne le timbre ;
## l'éclat du critique garde sa hauteur.
static func _impact(ev: Dictionary, lourd: bool, hauteur: float) -> Array:
	var degats := nombre(ev.get("amount"), COUP_LEGER)
	var force := clampf((degats - COUP_LEGER) / (COUP_ENORME - COUP_LEGER), 0.0, 1.0)
	var corps: float = hauteur * lerpf(HAUTEUR_COUP[0], HAUTEUR_COUP[1], force) * HAUTEUR_ENNEMI.get(ev.get("enemy"), 1.0)
	var out: Array = [["impact_lourd" if lourd else "impact", corps, lerpf(GAIN_COUP[0], GAIN_COUP[1], force)]]
	if D6Js.truthy(ev.get("crit")):
		out.append(["critique", hauteur, 1.0])
	return out

static func _mort(ev: Dictionary, hauteur: float) -> Array:
	var out: Array = [["mort", hauteur * HAUTEUR_ENNEMI.get(ev.get("enemy"), 1.0), 1.0]]
	if D6Js.truthy(ev.get("elite")):
		out.append(["mort_elite", hauteur, 1.0])
	if D6Js.truthy(ev.get("boss")):
		out.append(["mort_gardien", hauteur, 1.0])
	return out

## Explosion (explode) ou zone qui frappe (hazardFire) : la taille règle hauteur et force.
static func _explosion(ev: Dictionary, hauteur: float) -> Array:
	var style: Array = STYLE_ZONE.get(ev.get("kind"), STYLE_ZONE.exploder)
	var taille := clampf(nombre(ev.get("r"), RAYON_REFERENCE) / RAYON_REFERENCE, TAILLE_EXPLOSION[0], TAILLE_EXPLOSION[1])
	var gain: float = style[1] * sqrt(taille)
	var out: Array = [["explosion", hauteur * style[0] / sqrt(taille), gain]]
	if style[2]:
		out.append(["explosion_feu", hauteur, gain])
	return out
