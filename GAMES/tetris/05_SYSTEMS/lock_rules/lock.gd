# lock.gd — ligne core.lock_rules (R3 Empilement irreversible).
# genre.tetris.irreversible_stack : une piece figee ne bouge plus JAMAIS. Ce systeme integre la
# piece active a la pile (grille) ; il ne nettoie aucune ligne (c'est line_clear) et ne calcule
# aucun score. Rend une NOUVELLE grille (ne mute jamais l'entree). RefCounted (logique pure).
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const Collision = preload("res://05_SYSTEMS/collision/collision.gd")

# Ecrit les cellules de la piece dans une copie de la grille et la retourne. La piece cesse
# alors d'exister en tant qu'entite mobile : ses cellules sont desormais de la pile.
static func lock_piece(grid: Array, piece: Dictionary) -> Array:
	var g := clone_grid(grid)
	var color: int = P.color_of(piece["type"])
	for c in Collision.piece_cells(piece):
		g[c.y][c.x] = color
	return g

# Copie profonde d'une grille (rangees independantes) : l'entree n'est jamais mutee.
static func clone_grid(grid: Array) -> Array:
	var out: Array = []
	for row in grid:
		out.append(row.duplicate())
	return out
