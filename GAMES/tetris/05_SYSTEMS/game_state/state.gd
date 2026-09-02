# state.gd — ligne core.game_state (R7 Fin par blocage, R8 pas de victoire en marathon).
# DETIENT l'etat (grille, piece active, file d'apercu, score, lignes, statut), N'AGIT sur aucune
# regle : la physique et la fin vivent dans les autres systemes qui operent sur lui.
#
# Statut EXACTEMENT parmi 2 (genre.tetris.no_victory_in_marathon : PAS d'etat GAGNE) :
#   EN_COURS / GAME_OVER. La defaite est une CONSEQUENCE de l'etat (spawn illegal), jamais un
#   compteur qui expire (genre.tetris.loss_by_blocking). RefCounted (logique pure, deterministe).
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const Collision = preload("res://05_SYSTEMS/collision/collision.gd")
const Bag = preload("res://05_SYSTEMS/piece_bag/bag.gd")

# --- Enumeration GELEE des 2 statuts (aucune victoire en marathon) ---
enum Statut { EN_COURS, GAME_OVER }

var grid: Array = []                 # ROWS rangees de COLS entiers (0 = vide, 1..7 = pile)
var active: Dictionary = {}          # piece courante {type, rot, pos} ; vide si aucune
var queue: Array = []                # file des prochains types, alimentee par sacs de 7
var bag_seed: int = 0                # graine du prochain sac a generer
var score: int = 0
var lines_cleared: int = 0           # total cumule de lignes nettoyees
var status: int = Statut.EN_COURS
var seed: int = 0
var ticks: int = 0
var gravity_counter: int = 0         # ticks ecoules depuis la derniere descente auto
var pieces_spawned: int = 0          # nombre de pieces apparues (survie)

# Etat initial neuf, deterministe par graine. La premiere piece est deja apparue.
static func initial(seed_val: int) -> Object:
	var s = load("res://05_SYSTEMS/game_state/state.gd").new()
	s.seed = seed_val
	s.bag_seed = seed_val
	s.grid = empty_grid()
	s.queue = []
	s.active = {}
	s.score = 0
	s.lines_cleared = 0
	s.status = Statut.EN_COURS
	s.ticks = 0
	s.gravity_counter = 0
	s.pieces_spawned = 0
	s.spawn_piece(s.next_type())
	return s

# Grille vide ROWS x COLS.
static func empty_grid() -> Array:
	var g: Array = []
	for _y in range(P.ROWS):
		var row: Array = []
		for _x in range(P.COLS):
			row.append(0)
		g.append(row)
	return g

# Type suivant : tire en tete de file ; recharge un sac complet quand la file est vide.
func next_type() -> int:
	if queue.is_empty():
		queue = Bag.generate_bag(bag_seed)
		bag_seed = Bag.next_seed(bag_seed)
	var t: int = queue[0]
	queue.remove_at(0)
	return t

# R7 : fait apparaitre une piece de type `type` a l'origine de spawn. Si elle ne peut PAS
# apparaitre legalement (collision immediate avec la pile ou les bords), l'etat devient TERMINAL
# (GAME_OVER) et la fonction retourne false. Sinon la piece devient active et retourne true.
func spawn_piece(type: int) -> bool:
	var piece := Collision.make_piece(type, 0, P.SPAWN)
	pieces_spawned += 1
	active = piece
	if Collision.piece_fits(grid, piece):
		status = Statut.EN_COURS
		return true
	status = Statut.GAME_OVER
	return false

# Copie profonde independante (le tick et les tests ne mutent jamais l'entree).
func clone() -> Object:
	var c = load("res://05_SYSTEMS/game_state/state.gd").new()
	var g: Array = []
	for row in grid:
		g.append(row.duplicate())
	c.grid = g
	c.active = active.duplicate()   # dict PLAT (int/Vector2i, types valeur) : copie superficielle deja independante
	c.queue = queue.duplicate()
	c.bag_seed = bag_seed
	c.score = score
	c.lines_cleared = lines_cleared
	c.status = status
	c.seed = seed
	c.ticks = ticks
	c.gravity_counter = gravity_counter
	c.pieces_spawned = pieces_spawned
	return c
