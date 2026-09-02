# test_line_clear.gd — R4 Nettoyage et compactage strict. Assert STRICT : rangee pleine retiree,
# le dessus descend d'EXACTEMENT N rangees nettoyees (jamais >=). Rangee partielle jamais nettoyee.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const LineClear = preload("res://05_SYSTEMS/line_clear/line_clear.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")

func run(h) -> void:
	# Grille vide : 0 nettoyee, hauteur preservee.
	var g0: Array = State.empty_grid()
	var r0: Dictionary = LineClear.clear_lines(g0)
	h.eq(r0["cleared"], 0, "aucune rangee pleine -> 0 nettoyee")
	h.eq(r0["grid"].size(), P.ROWS, "hauteur preservee (vide)")
	# Une rangee pleine en bas + un bloc juste au-dessus -> descente d'exactement 1.
	var g1: Array = State.empty_grid()
	for x in range(P.COLS):
		g1[P.ROWS - 1][x] = 3
	g1[P.ROWS - 2][0] = 7
	var r1: Dictionary = LineClear.clear_lines(g1)
	h.eq(r1["cleared"], 1, "une rangee pleine nettoyee (strict)")
	h.eq(r1["grid"].size(), P.ROWS, "hauteur preservee")
	h.eq(r1["grid"][P.ROWS - 1][0], 7, "bloc descendu d'exactement 1 rangee")
	h.eq(r1["grid"][P.ROWS - 2][0], 0, "ancienne position vide")
	# Rangee partielle (9/10) jamais nettoyee.
	var g2: Array = State.empty_grid()
	for x in range(P.COLS - 1):
		g2[P.ROWS - 1][x] = 3
	var r2: Dictionary = LineClear.clear_lines(g2)
	h.eq(r2["cleared"], 0, "rangee partielle non nettoyee")
	# Deux rangees pleines -> descente d'exactement 2.
	var g3: Array = State.empty_grid()
	for x in range(P.COLS):
		g3[P.ROWS - 1][x] = 3
		g3[P.ROWS - 2][x] = 3
	g3[P.ROWS - 3][5] = 7
	var r3: Dictionary = LineClear.clear_lines(g3)
	h.eq(r3["cleared"], 2, "deux rangees pleines nettoyees")
	h.eq(r3["grid"][P.ROWS - 1][5], 7, "bloc descendu d'exactement 2 rangees")
	h.eq(r3["grid"][P.ROWS - 2][5], 0, "position intermediaire vide")
	h.eq(r3["grid"][P.ROWS - 3][5], 0, "ancienne position vide")
