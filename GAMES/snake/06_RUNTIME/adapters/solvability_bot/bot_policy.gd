# bot_policy.gd — ligne proof.solvability_bot (politique). Pilote le MEME canal d'entree
# public que le clavier : renvoie une DIRECTION du vocabulaire ferme, jamais une ecriture
# directe dans l'etat. Strategie : plus court chemin BFS (grid_nav copie) de la tete vers
# la nourriture, corps + bords traites en murs. Deterministe (BFS a ordre de voisins fixe).
extends RefCounted

const GridNav = preload("res://06_RUNTIME/adapters/solvability_bot/grid_nav.gd")
const DR = preload("res://05_SYSTEMS/input_rules/direction_rules.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

# Construit les murs : segments du corps + anneau de bordure (grid_nav travaille sur un
# plan infini ; sans l'anneau, un chemin pourrait sortir de la grille). La queue, qui se
# libere au prochain tick, est retiree des murs (elle n'est pas un obstacle reel).
static func _murs(state) -> Dictionary:
	var n := P.TAILLE_GRILLE
	var walls := {}
	for seg in state.segments:
		walls[seg] = true
	# Anneau de bordure complet autour de [0, n-1]^2.
	for i in range(-1, n + 1):
		walls[Vector2i(i, -1)] = true
		walls[Vector2i(i, n)] = true
		walls[Vector2i(-1, i)] = true
		walls[Vector2i(n, i)] = true
	# La queue se libere ce tick (sauf croissance) : ne pas la traiter en obstacle.
	if state.segments.size() > 0:
		walls.erase(state.segments[state.segments.size() - 1])
	return walls

# Direction de repli : une direction legale (non demi-tour) dont la case cible est dans
# la grille et pas sur le corps (hors queue). Sinon on continue tout droit (mort assumee).
static func _repli(state, walls: Dictionary) -> Vector2i:
	var tete = state.segments[0]
	for d in DR.DIRECTIONS:
		if DR.est_demi_tour(d, state.dir_effectuee):
			continue
		var cible: Vector2i = tete + d
		if not walls.has(cible):
			return d
	return state.dir_effectuee

# Action a jouer : direction vers la nourriture par BFS ; repli si aucun chemin.
static func choisir_action(state) -> Vector2i:
	var tete = state.segments[0]
	var walls := _murs(state)
	var pas: Vector2i = GridNav.next_step(tete, state.nourriture, walls)
	var dir: Vector2i = pas - tete
	if dir == Vector2i(0, 0) or not DR.est_direction(dir):
		return _repli(state, walls)
	return dir
