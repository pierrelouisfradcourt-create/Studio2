# line_clear.gd — ligne core.line_clear (R4 Nettoyage et compactage strict).
# genre.tetris.line_clear_compaction : une rangee entierement remplie disparait et tout ce qui
# est au-dessus descend d'AUTANT — seul moyen de liberer de l'espace. Compactage STRICT : la
# descente vaut EXACTEMENT le nombre de rangees nettoyees (jamais un >=). Ne calcule aucun score.
# Rend une NOUVELLE grille de meme hauteur (ROWS). RefCounted (logique pure).
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")

# Detecte les rangees pleines, les retire, compacte vers le bas, rembourre le haut de rangees
# vides. Retour : {grid:Array, cleared:int}.
static func clear_lines(grid: Array) -> Dictionary:
	var kept: Array = []
	var cleared: int = 0
	for y in range(P.ROWS):
		if _row_full(grid[y]):
			cleared += 1
		else:
			kept.append(grid[y].duplicate())
	var out: Array = []
	for _i in range(cleared):
		out.append(empty_row())
	for row in kept:
		out.append(row)
	return {"grid": out, "cleared": cleared}

# Une rangee est pleine ssi aucune cellule n'est vide (0).
static func _row_full(row: Array) -> bool:
	for cell in row:
		if cell == 0:
			return false
	return true

# Rangee vide de largeur COLS.
static func empty_row() -> Array:
	var r: Array = []
	for _x in range(P.COLS):
		r.append(0)
	return r
