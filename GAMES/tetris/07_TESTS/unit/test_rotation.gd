# test_rotation.gd — R5 Rotation contrainte. Rotation libre acceptee ; rotation en collision
# REFUSEE (V1 sans wall-kick), orientation/position/terrain inchanges.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const Collision = preload("res://05_SYSTEMS/collision/collision.gd")
const Rotation = preload("res://05_SYSTEMS/rotation_rules/rotation.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")

func run(h) -> void:
	var grid: Array = State.empty_grid()
	# Rotation libre : acceptee, orientation avance, position inchangee.
	var p := Collision.make_piece(2, 0, Vector2i(3, 3))
	var r: Dictionary = Rotation.rotate_piece(grid, p, 1)
	h.eq(r["rotated"], true, "rotation dans le vide acceptee")
	h.eq(r["piece"]["rot"], 1, "orientation -> 1")
	h.eq(r["piece"]["pos"], Vector2i(3, 3), "position inchangee par la rotation")
	# Rotation en collision : refusee, tout inchange.
	var g2: Array = State.empty_grid()
	var pi := Collision.make_piece(0, 0, Vector2i(3, 5))   # I horizontal
	g2[6][5] = 9                                           # occupe une cellule de la version tournee
	var r2: Dictionary = Rotation.rotate_piece(g2, pi, 1)
	h.eq(r2["rotated"], false, "rotation en collision refusee")
	h.eq(r2["piece"]["rot"], 0, "orientation inchangee au refus")
	h.eq(r2["piece"]["pos"], Vector2i(3, 5), "position inchangee au refus")
	h.eq(g2[6][5], 9, "terrain intact apres refus")
