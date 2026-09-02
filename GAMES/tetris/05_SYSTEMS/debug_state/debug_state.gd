# debug_state.gd — ligne debug.observation_point. Expose l'etat sous une forme LISIBLE par
# l'oracle (jamais par le joueur). AUCUN effet de bord : rend une copie profonde, la mutation de
# la sortie ne touche jamais l'etat source. RefCounted (logique pure).
extends RefCounted

# Instantane observable de l'etat de partie. Copies profondes (grille, piece) pour garantir
# l'absence d'effet de bord.
static func snapshot(state) -> Dictionary:
	var g: Array = []
	for row in state.grid:
		g.append(row.duplicate())
	return {
		"grid": g,
		"active": state.active.duplicate(),   # dict PLAT (types valeur) : copie superficielle deja independante
		"score": state.score,
		"lines": state.lines_cleared,
		"status": state.status,
		"ticks": state.ticks,
		"pieces": state.pieces_spawned,
	}
