# params.gd — ligne params.bloc_unique. BLOC UNIQUE de constantes nommees de gameplay.
# C'est ICI, et NULLE PART AILLEURS, que vit un litteral numerique de gameplay (garde-fou (d),
# ratifie Pierre 2026-07-28). Feuille du graphe : ne depend de rien. RefCounted (logique pure,
# aucune API moteur, aucune horloge, aucun alea).
#
# reused_from = CONCEPT (games/breakout_v2/05_SYSTEMS/params/params.gd) : on reutilise la FORME
# prouvee (un script de constantes nommees et rien d'autre), jamais les valeurs — la physique
# continue de Breakout n'a aucun sens sur une grille discrete.
extends RefCounted

# ============================================================================
# GEOMETRIE DU PUITS (grille discrete). Tetris marathon standard = 10 x 20.
# ============================================================================
const COLS: int = 10
const ROWS: int = 20

# Origine (coin haut-gauche de la boite englobante 4x4) ou une piece entrante apparait.
# x=3 centre les tetrominos larges (I occupe alors les colonnes 3..6).
const SPAWN: Vector2i = Vector2i(3, 0)

# ============================================================================
# CADENCE (difficulte ressentie). Une piece descend d'une case toutes les
# GRAVITY_PERIOD ticks en l'absence d'input — genre.tetris.discrete_gravity.
# ============================================================================
const GRAVITY_PERIOD: int = 30

# ============================================================================
# NOMBRE DE PIECES : exactement les 7 tetrominos (genre.tetris.seven_tetrominoes).
# Ordre canonique des identifiants -> l'entier de type indexe cette liste.
# ============================================================================
const PIECE_COUNT: int = 7
const PIECE_IDS: Array = ["I", "O", "T", "S", "Z", "J", "L"]

# ============================================================================
# BAREME SUPERLINEAIRE (genre.tetris.superlinear_multi_clear_reward). Nettoyer N
# lignes d'un coup rapporte STRICTEMENT plus PAR LIGNE que N nettoyages separes :
# 800/4 = 200 par ligne pour un quadruple, contre 100 pour un simple.
# ============================================================================
const SCORE_SIMPLE: int = 100
const SCORE_DOUBLE: int = 300
const SCORE_TRIPLE: int = 500
const SCORE_QUAD: int = 800

# ============================================================================
# GEOMETRIE DES TETROMINOS — DONNEE CONSTANTE (offsets de cellules par orientation),
# pas un litteral de gameplay reglable : c'est la forme meme des pieces du genre.
# 4 orientations par piece, 4 cellules par orientation, offsets (x, y) dans une
# boite englobante 4x4, y vers le bas. Materialisee une fois en static var (evite
# les limites d'expression const sur des Array[Vector2i] imbriques).
# ============================================================================
static var _shapes: Array = _build_shapes()

# Cellules (offsets) d'une piece de type `type` en orientation `rot` (0..3).
static func shape(type: int, rot: int) -> Array:
	return _shapes[type][(rot % 4 + 4) % 4]

# Couleur d'affichage/marqueur de pile pour un type (1..7 ; 0 reste "vide").
static func color_of(type: int) -> int:
	return type + 1

static func _build_shapes() -> Array:
	var i_p := [
		[Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)],
		[Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3)],
		[Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2)],
		[Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3)],
	]
	var o_p := [
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1)],
	]
	var t_p := [
		[Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)],
		[Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)],
		[Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2)],
	]
	var s_p := [
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)],
		[Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 2)],
		[Vector2i(1, 1), Vector2i(2, 1), Vector2i(0, 2), Vector2i(1, 2)],
		[Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2)],
	]
	var z_p := [
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)],
		[Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 2)],
		[Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2)],
	]
	var j_p := [
		[Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(1, 2)],
		[Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 2)],
		[Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 2), Vector2i(1, 2)],
	]
	var l_p := [
		[Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 2)],
		[Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(0, 2)],
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2)],
	]
	return [i_p, o_p, t_p, s_p, z_p, j_p, l_p]
