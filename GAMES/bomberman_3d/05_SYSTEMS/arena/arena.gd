# arena.gd — la GRILLE COURANTE, mutable. Detient les types de case et rien d'autre.
#
# Difference avec map_schema : le schema lit un descripteur FIGE, l'arene porte l'etat
# qui CHANGE en cours de partie (une case destructible devient du sol quand elle explose).
# C'est cette mutabilite qui distingue Bomberman des jeux de grille deja produits ici :
# la carte n'est pas un decor, c'est une variable.
#
# NE DECIDE JAMAIS d'une mort ni d'une explosion — il repond a des questions sur l'espace.
# Logique PURE : RefCounted.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const Schema = preload("res://05_SYSTEMS/map_schema/map_schema.gd")

var largeur: int = 0
var hauteur: int = 0
var cases: PackedByteArray = PackedByteArray()


static func depuis_descripteur(desc: Dictionary) -> Object:
	var a = load("res://05_SYSTEMS/arena/arena.gd").new()
	var plan: Array = desc["plan"]
	a.largeur = Schema.largeur(plan)
	a.hauteur = Schema.hauteur(plan)
	a.cases = Schema.table_des_types(plan)
	return a


func clone() -> Object:
	var a = load("res://05_SYSTEMS/arena/arena.gd").new()
	a.largeur = largeur
	a.hauteur = hauteur
	a.cases = cases.duplicate()
	return a


func dans_bornes(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < largeur and c.y < hauteur


# Type d'une case. Hors bornes vaut SOLIDE : le monde est ferme, et une lecture hors carte
# ne leve jamais — elle repond « mur », ce qui est la reponse sure pour un deplacement
# comme pour une flamme.
func type_case(c: Vector2i) -> int:
	if not dans_bornes(c):
		return P.SOLIDE
	return cases[c.y * largeur + c.x]


func est_solide(c: Vector2i) -> bool:
	return type_case(c) == P.SOLIDE


func est_destructible(c: Vector2i) -> bool:
	return type_case(c) == P.DESTRUCTIBLE


# Une case franchissable par un acteur, du seul point de vue du TERRAIN. Les bombes et les
# acteurs ne sont pas du terrain : leur blocage appartient a movement_rules.
func est_libre(c: Vector2i) -> bool:
	return type_case(c) == P.SOL


# Detruit une case destructible. Rend true si quelque chose a REELLEMENT ete detruit —
# la valeur de retour est le fait, pas un effet de bord silencieux.
func detruire(c: Vector2i) -> bool:
	if not dans_bornes(c):
		return false
	if cases[c.y * largeur + c.x] != P.DESTRUCTIBLE:
		return false
	cases[c.y * largeur + c.x] = P.SOL
	return true


# Rend une case SOLIDE (mort subite). Symetrique de `detruire` : rend true si la case a
# REELLEMENT change. Une case deja solide n'est pas un echec, c'est un non-evenement.
func solidifier(c: Vector2i) -> bool:
	if not dans_bornes(c):
		return false
	if cases[c.y * largeur + c.x] == P.SOLIDE:
		return false
	cases[c.y * largeur + c.x] = P.SOLIDE
	return true


func nb_destructibles() -> int:
	var n: int = 0
	for i in range(cases.size()):
		if cases[i] == P.DESTRUCTIBLE:
			n += 1
	return n
