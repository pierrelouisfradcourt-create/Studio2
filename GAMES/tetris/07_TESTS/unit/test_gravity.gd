# test_gravity.gd — R2 Gravite discrete. Assert STRICT : Delta_y == 1 par pas dans le vide
# (jamais >=) ; blocage au sol -> landed, dy 0, position inchangee.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const Collision = preload("res://05_SYSTEMS/collision/collision.gd")
const Gravity = preload("res://05_SYSTEMS/gravity/gravity.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")

func run(h) -> void:
	var grid: Array = State.empty_grid()
	# Descente libre : exactement une case.
	var p := Collision.make_piece(2, 0, Vector2i(3, 0))
	var r: Dictionary = Gravity.apply_gravity(grid, p)
	h.eq(r["landed"], false, "pas d'atterrissage dans le vide")
	h.eq(r["dy"], 1, "dy exactement 1")
	h.eq(r["piece"]["pos"], Vector2i(3, 1), "descend d'exactement une case (strict)")
	# Blocage au sol : O en bas ne peut plus descendre.
	var low := Collision.make_piece(1, 0, Vector2i(3, P.ROWS - 2))
	var r2: Dictionary = Gravity.apply_gravity(grid, low)
	h.eq(r2["landed"], true, "atterri au sol")
	h.eq(r2["dy"], 0, "dy 0 quand bloque")
	h.eq(r2["piece"]["pos"], Vector2i(3, P.ROWS - 2), "position inchangee quand bloque")
