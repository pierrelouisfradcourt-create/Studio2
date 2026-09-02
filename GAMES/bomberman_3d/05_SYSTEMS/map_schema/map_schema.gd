# map_schema.gd — CONVENTION de lecture d'une carte.
#
# La convention vit dans la LOGIQUE, les instances vivent dans la DONNEE : ce module
# connait la legende fermee des symboles et les champs obligatoires d'un descripteur, et
# il ne connait AUCUNE carte. Il ne va chercher aucun fichier — le descripteur lui est
# REMIS EN ARGUMENT.
#
# Logique PURE : RefCounted, aucune scene, aucun noeud, aucune horloge, aucun alea, aucune
# I/O. Depend de params uniquement (types de case).
#
# reused_from = CONCEPT (games/pacman/05_SYSTEMS/map_schema/map_schema.gd) : on reutilise
# la FORME prouvee — legende fermee + champs obligatoires + table plate derivee — jamais
# les symboles, qui sont ceux de Pac-Man (maison, tunnel, pastilles) et n'ont aucun sens ici.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")

# LEGENDE FERMEE. Un symbole absent de cette table est un symbole INCONNU : il se
# CONSTATE (symboles_inconnus) au lieu de se deviner.
#   '#' -> SOLIDE        indestructible, arrete la flamme
#   '+' -> DESTRUCTIBLE  detruit par la flamme, peut reveler un power-up
#   '.' -> SOL           franchissable
#   'S' -> SOL portant un point d'apparition
const LEGENDE: Dictionary = {
	"#": P.SOLIDE,
	"+": P.DESTRUCTIBLE,
	".": P.SOL,
	"S": P.SOL,
}

const SYMBOLE_SOLIDE := "#"
const SYMBOLE_DESTRUCTIBLE := "+"
const SYMBOLE_SOL := "."
const SYMBOLE_SPAWN := "S"

# Champs qu'un descripteur DOIT porter. Aucun defaut n'est invente a leur place.
const CHAMPS_OBLIGATOIRES: Array = [
	"id", "nom", "plan", "powerup_rules", "victory_rule",
]


static func symbole_connu(c: String) -> bool:
	return LEGENDE.has(c)


# Type d'un symbole. Un symbole hors legende vaut SOLIDE : la lecture ne leve jamais, elle
# refuse. Le REFUS explicite est le travail de map_validator, pas de la convention.
static func type_du_symbole(c: String) -> int:
	if not LEGENDE.has(c):
		return P.SOLIDE
	return LEGENDE[c]


# Champs obligatoires ABSENTS du descripteur, dans l'ordre declare (jamais l'ordre d'un
# Dictionary).
static func champs_manquants(desc: Dictionary) -> Array:
	var sortie: Array = []
	for champ in CHAMPS_OBLIGATOIRES:
		if not desc.has(champ):
			sortie.append(champ)
	return sortie


# Symboles du plan absents de la legende, sans doublon, dans l'ordre de lecture.
static func symboles_inconnus(plan: Array) -> Array:
	var sortie: Array = []
	for y in range(plan.size()):
		var ligne: String = String(plan[y])
		for x in range(ligne.length()):
			var c: String = ligne.substr(x, 1)
			if not symbole_connu(c) and not sortie.has(c):
				sortie.append(c)
	return sortie


static func plan_rectangulaire(plan: Array) -> bool:
	if plan.is_empty():
		return false
	var l: int = String(plan[0]).length()
	if l <= 0:
		return false
	for ligne in plan:
		if String(ligne).length() != l:
			return false
	return true


static func largeur(plan: Array) -> int:
	if plan.is_empty():
		return 0
	return String(plan[0]).length()


static func hauteur(plan: Array) -> int:
	return plan.size()


# Points d'apparition, DERIVES du plan dans l'ordre de lecture (haut->bas, gauche->droite).
# Ils ne sont jamais declares deux fois : le plan est la source unique.
static func spawn_points(plan: Array) -> Array:
	var sortie: Array = []
	for y in range(plan.size()):
		var ligne: String = String(plan[y])
		for x in range(ligne.length()):
			if ligne.substr(x, 1) == SYMBOLE_SPAWN:
				sortie.append(Vector2i(x, y))
	return sortie


# Table PLATE des types, indexee y * largeur + x. C'est la carte UTILISABLE construite a
# partir du descripteur recu : une donnee, pas un comportement.
static func table_des_types(plan: Array) -> PackedByteArray:
	var l: int = largeur(plan)
	var h: int = hauteur(plan)
	var t := PackedByteArray()
	t.resize(l * h)
	for y in range(h):
		var ligne: String = String(plan[y])
		for x in range(l):
			t[y * l + x] = type_du_symbole(ligne.substr(x, 1))
	return t


# Le bord du plan est-il ENTIEREMENT solide ? Invariant de genre : une arene Bomberman est
# fermee, sinon la flamme et les acteurs sortent du monde.
static func bord_solide(plan: Array) -> bool:
	var l: int = largeur(plan)
	var h: int = hauteur(plan)
	if l < 3 or h < 3:
		return false
	for x in range(l):
		if type_du_symbole(String(plan[0]).substr(x, 1)) != P.SOLIDE:
			return false
		if type_du_symbole(String(plan[h - 1]).substr(x, 1)) != P.SOLIDE:
			return false
	for y in range(h):
		if type_du_symbole(String(plan[y]).substr(0, 1)) != P.SOLIDE:
			return false
		if type_du_symbole(String(plan[y]).substr(l - 1, 1)) != P.SOLIDE:
			return false
	return true
