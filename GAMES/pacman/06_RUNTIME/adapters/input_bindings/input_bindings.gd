# input_bindings.gd — TABLE DE LIAISONS intention -> entrees physiques
# (lignes bindings.table, bindings.gamepad_coverage).
#
# C'est ICI, et dans AUCUN fichier de logique, que vivent les codes de touches et de
# boutons : d'ou le CONTROLE POSITIF sans lequel le comptage a 0 dans 05_SYSTEMS ne
# prouverait rien (un projet sans entree du tout passerait le test a 0).
#
# Table ENUMERABLE par intention et par peripherique — jamais une suite de conditions
# eparpillees : la question « quelles intentions n'ont aucune liaison manette ? » ne se
# pose que parce que la table est enumerable.
extends RefCounted

const Intents = preload("res://05_SYSTEMS/input_intents/input_intents.gd")

const CLAVIER := "clavier"
const MANETTE := "manette"
const TACTILE := "tactile"
# La MANETTE est le peripherique de reference (charter_v2).
const PERIPHERIQUE_REFERENCE := MANETTE
const PERIPHERIQUES: Array = [CLAVIER, MANETTE, TACTILE]

# Zones tactiles declarees, nommees : la surface reelle appartient a touch_input.
const ZONE_HAUT := "zone_haut"
const ZONE_GAUCHE := "zone_gauche"
const ZONE_BAS := "zone_bas"
const ZONE_DROITE := "zone_droite"
const ZONE_DASH := "zone_dash"
const ZONE_PAUSE := "zone_pause"

# TABLE UNIQUE. Une entree par intention du vocabulaire ferme, trois listes de liaisons.
const TABLE: Dictionary = {
	Intents.Intention.HAUT: {
		CLAVIER: [KEY_UP, KEY_W, KEY_Z],
		MANETTE: [JOY_BUTTON_DPAD_UP],
		TACTILE: [ZONE_HAUT],
	},
	Intents.Intention.GAUCHE: {
		CLAVIER: [KEY_LEFT, KEY_A, KEY_Q],
		MANETTE: [JOY_BUTTON_DPAD_LEFT],
		TACTILE: [ZONE_GAUCHE],
	},
	Intents.Intention.BAS: {
		CLAVIER: [KEY_DOWN, KEY_S],
		MANETTE: [JOY_BUTTON_DPAD_DOWN],
		TACTILE: [ZONE_BAS],
	},
	Intents.Intention.DROITE: {
		CLAVIER: [KEY_RIGHT, KEY_D],
		MANETTE: [JOY_BUTTON_DPAD_RIGHT],
		TACTILE: [ZONE_DROITE],
	},
	Intents.Intention.DASH: {
		CLAVIER: [KEY_SHIFT],
		MANETTE: [JOY_BUTTON_X],
		TACTILE: [ZONE_DASH],
	},
	Intents.Intention.PAUSE: {
		CLAVIER: [KEY_P],
		MANETTE: [JOY_BUTTON_START],
		TACTILE: [ZONE_PAUSE],
	},
	# VALIDER porte aussi la relance depuis l'ecran de fin (heritage V1 : R, entree,
	# espace) — une seule intention, plusieurs liaisons, jamais deux chemins de code.
	Intents.Intention.VALIDER: {
		CLAVIER: [KEY_ENTER, KEY_SPACE, KEY_R],
		MANETTE: [JOY_BUTTON_A],
		TACTILE: [],
	},
	# RETOUR porte la sortie de l'application depuis le titre et l'ecran de fin.
	Intents.Intention.RETOUR: {
		CLAVIER: [KEY_ESCAPE, KEY_BACKSPACE],
		MANETTE: [JOY_BUTTON_B],
		TACTILE: [],
	},
	# Liaisons DISTINCTES des directions : un pave numerique cote clavier, la croix
	# directionnelle cote manette. Sans distinction, une meme touche porterait deux
	# intentions et le comptage des liaisons cesserait d'etre interpretable.
	Intents.Intention.SELECTION_PRECEDENTE: {
		CLAVIER: [KEY_KP_8],
		MANETTE: [JOY_BUTTON_DPAD_UP],
		TACTILE: [],
	},
	Intents.Intention.SELECTION_SUIVANTE: {
		CLAVIER: [KEY_KP_2],
		MANETTE: [JOY_BUTTON_DPAD_DOWN],
		TACTILE: [],
	},
}

# NOMS LISIBLES des entrees physiques (V3, cause racine P1).
#
# Un code de touche est un ENTIER : `str(KEY_UP)` rend « 4194320 », qui n'est pas un
# libelle mais un detail d'implementation du moteur affiche par accident. La traduction
# code -> nom humain vit ICI, dans le fichier qui DECLARE les codes, et nulle part
# ailleurs : l'ecran de controles ne peut pas recopier un nom de touche (il est mesure
# sans « KEY_ » ni « JOY_ »), donc s'il devait nommer les touches lui-meme il inventerait
# une seconde source qui pourrait deriver de la table.
#
# AUCUN NOM NE PORTE DE CHIFFRE : c'est ce qui rend le defaut P1 falsifiable — un code
# brut reapparaissant a l'ecran s'y verrait immediatement (voir liaisons_sans_nom et
# nom_porte_un_code_brut).
const NOMS_CLAVIER: Dictionary = {
	KEY_UP: "Fleche haut",
	KEY_DOWN: "Fleche bas",
	KEY_LEFT: "Fleche gauche",
	KEY_RIGHT: "Fleche droite",
	KEY_W: "W",
	KEY_A: "A",
	KEY_S: "S",
	KEY_D: "D",
	KEY_Q: "Q",
	KEY_Z: "Z",
	KEY_R: "R",
	KEY_P: "P",
	KEY_SHIFT: "Maj",
	KEY_ENTER: "Entree",
	KEY_SPACE: "Espace",
	KEY_ESCAPE: "Echap",
	KEY_BACKSPACE: "Retour arriere",
	KEY_KP_8: "Pave numerique haut",
	KEY_KP_2: "Pave numerique bas",
}

const NOMS_MANETTE: Dictionary = {
	JOY_BUTTON_DPAD_UP: "Croix haut",
	JOY_BUTTON_DPAD_DOWN: "Croix bas",
	JOY_BUTTON_DPAD_LEFT: "Croix gauche",
	JOY_BUTTON_DPAD_RIGHT: "Croix droite",
	JOY_BUTTON_A: "Bouton A",
	JOY_BUTTON_B: "Bouton B",
	JOY_BUTTON_X: "Bouton X",
	JOY_BUTTON_START: "Start",
}

const NOMS_TACTILE: Dictionary = {
	ZONE_HAUT: "Zone haut",
	ZONE_BAS: "Zone bas",
	ZONE_GAUCHE: "Zone gauche",
	ZONE_DROITE: "Zone droite",
	ZONE_DASH: "Zone dash",
	ZONE_PAUSE: "Zone pause",
}

# Valeur RENDUE pour une liaison sans nom declare. Chaine vide NOMMEE : le refus est une
# valeur de retour, jamais une exception ni un code brut de repli.
const NOM_INCONNU := ""

# Les intentions DE JEU : celles qui agissent sur la partie, hors navigation de menu.
const INTENTIONS_DE_JEU: Array = [
	Intents.Intention.HAUT, Intents.Intention.GAUCHE, Intents.Intention.BAS,
	Intents.Intention.DROITE, Intents.Intention.DASH, Intents.Intention.PAUSE,
]

# Les QUATRE GESTES dont F113 mesure la decouvrabilite (constat humain, pas oracle).
const GESTES_DECOUVRABLES: Array = [
	Intents.Intention.HAUT, Intents.Intention.DASH,
	Intents.Intention.PAUSE, Intents.Intention.RETOUR,
]

const CODE_ABSENT: int = -1


static func intentions_liees() -> Array:
	var sortie: Array = []
	for i in Intents.TOUTES:
		if TABLE.has(i):
			sortie.append(i)
	return sortie


static func liaisons(intention: int, peripherique: String) -> Array:
	if not TABLE.has(intention):
		return []
	var e: Dictionary = TABLE[intention]
	if not e.has(peripherique):
		return []
	return e[peripherique]


# Intention portee par un code de touche ; AUCUNE si la touche n'est liee a rien.
# L'ORDRE d'examen suit Intents.TOUTES : jamais l'ordre d'un Dictionary.
static func intention_de_touche(keycode: int) -> int:
	for i in Intents.TOUTES:
		if liaisons(i, CLAVIER).has(keycode):
			return i
	return Intents.Intention.AUCUNE


static func intention_de_bouton(bouton: int) -> int:
	for i in Intents.TOUTES:
		if liaisons(i, MANETTE).has(bouton):
			return i
	return Intents.Intention.AUCUNE


static func intention_de_zone(zone: String) -> int:
	for i in Intents.TOUTES:
		if liaisons(i, TACTILE).has(zone):
			return i
	return Intents.Intention.AUCUNE


# COUVERTURE MANETTE : intentions atteignables au clavier SANS aucune liaison manette.
# Le nombre attendu vaut exactement 0.
static func intentions_sans_manette() -> Array:
	var sortie: Array = []
	for i in intentions_liees():
		if not liaisons(i, CLAVIER).is_empty() and liaisons(i, MANETTE).is_empty():
			sortie.append(i)
	return sortie


# Intentions injouables a la manette parmi les intentions DE JEU.
static func intentions_de_jeu_sans_manette() -> Array:
	var sortie: Array = []
	for i in INTENTIONS_DE_JEU:
		if liaisons(i, MANETTE).is_empty():
			sortie.append(i)
	return sortie


# Nombre de liaisons declarees pour un peripherique — sert au controle positif.
static func nombre_de_liaisons(peripherique: String) -> int:
	var n: int = 0
	for i in intentions_liees():
		n += liaisons(i, peripherique).size()
	return n


# --- NOMS LISIBLES (cause racine P1) ---------------------------------------------
# Table de noms du peripherique demande ; un peripherique inconnu rend une table VIDE,
# jamais la table d'un autre.
static func noms_du_peripherique(peripherique: String) -> Dictionary:
	if peripherique == CLAVIER:
		return NOMS_CLAVIER
	if peripherique == MANETTE:
		return NOMS_MANETTE
	if peripherique == TACTILE:
		return NOMS_TACTILE
	return {}


# NOM HUMAIN d'une liaison. C'est la fonction que P1 rendait absente : sans elle,
# l'affichage retombait sur `str(liaison)`, c'est-a-dire le keycode brut.
static func nom_liaison(liaison, peripherique: String) -> String:
	var noms: Dictionary = noms_du_peripherique(peripherique)
	if not noms.has(liaison):
		return NOM_INCONNU
	return String(noms[liaison])


# Le nom contient-il un CHIFFRE ? Un nom qui en porte est le symptome exact de P1 : un
# code de touche recrache tel quel. Aucun nom declare n'en contient.
static func nom_porte_un_code_brut(nom: String) -> bool:
	for i in range(nom.length()):
		var c: String = nom[i]
		if c >= "0" and c <= "9":
			return true
	return false


# Liaisons DECLAREES sans nom lisible, rendues nommement (intention, peripherique,
# liaison) pour qu'un echec designe la liaison fautive au lieu d'un nombre nu.
# La valeur attendue vaut exactement 0.
static func liaisons_sans_nom() -> Array:
	var sortie: Array = []
	for i in intentions_liees():
		for p in PERIPHERIQUES:
			for l in liaisons(i, p):
				if nom_liaison(l, p) == NOM_INCONNU:
					sortie.append([i, p, l])
	return sortie


# Liaisons dont le nom declare porte un chiffre. Attendu : exactement 0.
static func noms_portant_un_code_brut() -> Array:
	var sortie: Array = []
	for i in intentions_liees():
		for p in PERIPHERIQUES:
			for l in liaisons(i, p):
				if nom_porte_un_code_brut(nom_liaison(l, p)):
					sortie.append([i, p, l])
	return sortie
