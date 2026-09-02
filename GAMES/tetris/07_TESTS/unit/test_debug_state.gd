# test_debug_state.gd — point d'observation de l'oracle. L'instantane reflete l'etat et n'a AUCUN
# effet de bord (copie profonde : muter la sortie ne touche jamais la source).
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const DebugState = preload("res://05_SYSTEMS/debug_state/debug_state.gd")

func run(h) -> void:
	var s = State.initial(1)
	var snap: Dictionary = DebugState.snapshot(s)
	h.eq(snap["score"], s.score, "instantane : score")
	h.eq(snap["status"], s.status, "instantane : statut")
	h.eq(snap["ticks"], s.ticks, "instantane : ticks")
	h.eq(snap["lines"], s.lines_cleared, "instantane : lignes")
	h.eq(snap["pieces"], s.pieces_spawned, "instantane : pieces")
	h.eq(snap["grid"].size(), P.ROWS, "instantane : hauteur de grille")
	snap["grid"][0][0] = 99
	h.eq(s.grid[0][0], 0, "instantane = copie profonde (aucun effet de bord)")
