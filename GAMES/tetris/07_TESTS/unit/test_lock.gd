# test_lock.gd — R3 Empilement irreversible. lock_piece ecrit EXACTEMENT les 4 cellules dans une
# copie ; l'entree n'est jamais mutee ; et une fois verrouillee, aucune intention ne modifie la pile.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const Collision = preload("res://05_SYSTEMS/collision/collision.gd")
const Lock = preload("res://05_SYSTEMS/lock_rules/lock.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const InputRules = preload("res://05_SYSTEMS/input_rules/input.gd")

func run(h) -> void:
	var grid: Array = State.empty_grid()
	var p := Collision.make_piece(1, 0, Vector2i(3, P.ROWS - 2))
	var g2: Array = Lock.lock_piece(grid, p)
	for c in Collision.piece_cells(p):
		h.eq(g2[c.y][c.x], P.color_of(1), "cellule verrouillee %s" % str(c))
	h.eq(grid[P.ROWS - 1][4], 0, "grille d'origine inchangee (copie)")
	var filled := 0
	for y in range(P.ROWS):
		for x in range(P.COLS):
			if g2[y][x] != 0:
				filled += 1
	h.eq(filled, 4, "exactement 4 cellules verrouillees")
	# Irreversibilite : apres verrou, la pile est inchangee sous les intentions sur la piece active.
	var s = State.initial(1)
	s = Loop.step(s, InputRules.HARD_DROP)["state"]   # verrouille la 1re piece, en fait apparaitre une 2e
	var pile: Array = []
	for row in s.grid:
		pile.append(row.duplicate())
	for it in [InputRules.LEFT, InputRules.RIGHT, InputRules.ROTATE_CW, InputRules.LEFT]:
		s = Loop.step(s, it)["state"]
	h.eq(s.grid, pile, "pile immuable sous input sur la piece active (R3)")
