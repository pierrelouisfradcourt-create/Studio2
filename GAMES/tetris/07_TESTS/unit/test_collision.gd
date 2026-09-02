# test_collision.gd — predicat de legalite. Bornes STRICTES du puits (in_bounds), vide/occupe,
# fits sur cellules et pieces. Chaque borne >= / == est pinnee des deux cotes.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const Collision = preload("res://05_SYSTEMS/collision/collision.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")

func run(h) -> void:
	# in_bounds : les quatre bornes, chacune des deux cotes.
	h.eq(Collision.in_bounds(Vector2i(0, 0)), true, "0,0 dans le puits")
	h.eq(Collision.in_bounds(Vector2i(-1, 5)), false, "x=-1 hors")
	h.eq(Collision.in_bounds(Vector2i(P.COLS, 5)), false, "x=COLS hors")
	h.eq(Collision.in_bounds(Vector2i(P.COLS - 1, 5)), true, "x=COLS-1 dans")
	h.eq(Collision.in_bounds(Vector2i(5, -1)), false, "y=-1 hors")
	h.eq(Collision.in_bounds(Vector2i(5, P.ROWS)), false, "y=ROWS hors")
	h.eq(Collision.in_bounds(Vector2i(5, P.ROWS - 1)), true, "y=ROWS-1 dans")
	# cell_empty.
	var grid: Array = State.empty_grid()
	h.eq(Collision.cell_empty(grid, Vector2i(2, 2)), true, "cellule vide")
	grid[2][2] = 5
	h.eq(Collision.cell_empty(grid, Vector2i(2, 2)), false, "cellule occupee")
	# piece_fits : dans le vide, sous le sol, sur une cellule occupee.
	var g2: Array = State.empty_grid()
	var p := Collision.make_piece(0, 0, Vector2i(3, 0))
	h.eq(Collision.piece_fits(g2, p), true, "I tient en haut du vide")
	var pb := Collision.make_piece(0, 0, Vector2i(3, P.ROWS))
	h.eq(Collision.piece_fits(g2, pb), false, "piece sous le sol refusee")
	var g3: Array = State.empty_grid()
	var pi := Collision.make_piece(0, 0, Vector2i(3, P.ROWS - 2))
	for c in Collision.piece_cells(pi):
		g3[c.y][c.x] = 9
	h.eq(Collision.piece_fits(g3, pi), false, "piece sur cellules occupees refusee")
	# fits sur une liste de cellules.
	h.eq(Collision.fits(g2, [Vector2i(0, 0), Vector2i(P.COLS - 1, P.ROWS - 1)]), true, "coins opposes tiennent")
	h.eq(Collision.fits(g2, [Vector2i(0, 0), Vector2i(P.COLS, 0)]), false, "une cellule hors -> false")
