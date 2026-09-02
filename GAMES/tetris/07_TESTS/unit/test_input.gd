# test_input.gd — R6 Piece active seule. Chaque intention n'affecte QUE la piece active ; la pile
# (grille) est inchangee sous tout input ; mouvement illegal refuse.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const Collision = preload("res://05_SYSTEMS/collision/collision.gd")
const InputRules = preload("res://05_SYSTEMS/input_rules/input.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")

func run(h) -> void:
	var grid: Array = State.empty_grid()
	var p := Collision.make_piece(2, 0, Vector2i(3, 3))
	# LEFT / RIGHT / SOFT_DROP / ROTATE : effets stricts.
	var rl: Dictionary = InputRules.move_active_piece(grid, p, InputRules.LEFT)
	h.eq(rl["piece"]["pos"], Vector2i(2, 3), "LEFT decale x-1")
	h.eq(rl["moved"], true, "LEFT a bouge")
	var rr: Dictionary = InputRules.move_active_piece(grid, p, InputRules.RIGHT)
	h.eq(rr["piece"]["pos"], Vector2i(4, 3), "RIGHT decale x+1")
	var rd: Dictionary = InputRules.move_active_piece(grid, p, InputRules.SOFT_DROP)
	h.eq(rd["piece"]["pos"], Vector2i(3, 4), "SOFT_DROP decale y+1")
	var ro: Dictionary = InputRules.move_active_piece(grid, p, InputRules.ROTATE_CW)
	h.eq(ro["piece"]["rot"], 1, "ROTATE_CW avance l'orientation")
	# HARD_DROP : atteint le sol (strict) et signale landed.
	var rh: Dictionary = InputRules.move_active_piece(grid, p, InputRules.HARD_DROP)
	h.eq(rh["landed"], true, "HARD_DROP a atterri")
	h.eq(rh["moved"], true, "HARD_DROP a bouge")
	h.eq(rh["piece"]["pos"].y, P.ROWS - 2, "HARD_DROP atteint le sol (strict)")
	# NONE : rien ne change.
	var rn: Dictionary = InputRules.move_active_piece(grid, p, InputRules.NONE)
	h.eq(rn["piece"]["pos"], Vector2i(3, 3), "NONE laisse la piece inchangee")
	h.eq(rn["moved"], false, "NONE n'a pas bouge")
	# Mouvement illegal (contre le mur) : refuse.
	var pw := Collision.make_piece(1, 0, Vector2i(-1, 3))   # O, cellules aux colonnes 0 et 1
	var rw: Dictionary = InputRules.move_active_piece(grid, pw, InputRules.LEFT)
	h.eq(rw["moved"], false, "LEFT contre le mur refuse")
	h.eq(rw["landed"], false, "mouvement refuse ne fait pas atterrir")
	h.eq(rw["piece"]["pos"], Vector2i(-1, 3), "piece inchangee au mur")
	# Pile inchangee par n'importe quel input (R6).
	var gcopy: Array = []
	for row in grid:
		gcopy.append(row.duplicate())
	InputRules.move_active_piece(grid, p, InputRules.HARD_DROP)
	h.eq(grid, gcopy, "pile (grille) intacte sous input (R6)")
