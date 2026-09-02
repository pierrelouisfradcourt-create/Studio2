# ghost_targeting.gd — mesure de distance UNIQUE et cinq formules de case-cible
# (lignes targeting.distance, targeting.chase_targets, targeting.scatter_corners,
# targeting.corners_from_state_map).
#
# V2 : les COINS DE DISPERSION viennent de la CARTE RECUE et non d'une constante
# globale — une carte de dimensions differentes a ses propres coins sans qu'aucune
# formule de ciblage ne change.
#
# Les quatre fantomes ne different QUE par leur cible : c'est ce qui rend la variance
# des trajectoires attribuable au ciblage, et non a quatre algorithmes de deplacement.
extends RefCounted

const Maze = preload("res://05_SYSTEMS/maze/maze.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

# Index nominatifs des quatre fantomes (ordre fixe, jamais un Dictionary).
const ROUGE: int = 0
const ROSE: int = 1
const CYAN: int = 2
const ORANGE: int = 3
const NOMBRE_FANTOMES: int = 4

# Avance du ciblage rose (cases devant Pac-Man) et du point pivot cyan.
const AVANCE_ROSE: int = P.AVANCE_ROSE
const AVANCE_CYAN: int = P.AVANCE_CYAN
# Seuil de bascule du fantome orange : au-dela il vise Pac-Man, en deca son coin.
const SEUIL_ORANGE: int = P.SEUIL_ORANGE


# Mesure de distance de grille UNIQUE (ligne targeting.distance) : les quatre ciblages
# et les assertions de seuil du fantome orange passent par CETTE fonction.
static func distance(a: Vector2i, b: Vector2i) -> int:
	return Maze.distance(a, b)


# Case-cible de DISPERSION, nominative : quatre coins deux a deux differents, LUS SUR
# LA CARTE portee par l'etat.
static func cible_dispersion(carte, index: int) -> Vector2i:
	return carte.COINS[index]


# Case-cible de POURSUITE (lignes F15..F18).
static func cible_poursuite(carte, index: int, pac: Vector2i, pac_dir: Vector2i, fantomes: Array) -> Vector2i:
	if index == ROUGE:
		return pac
	if index == ROSE:
		return pac + pac_dir * AVANCE_ROSE
	if index == CYAN:
		var pivot: Vector2i = pac + pac_dir * AVANCE_CYAN
		return pivot * 2 - fantomes[ROUGE]
	# ORANGE : bascule au seuil de distance, assertee exactement a 9, 8 et 7.
	if distance(fantomes[ORANGE], pac) > SEUIL_ORANGE:
		return pac
	return cible_dispersion(carte, ORANGE)
