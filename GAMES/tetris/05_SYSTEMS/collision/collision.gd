# collision.gd — ligne core.collision. Predicat PUR : « cette position est-elle legale ? ».
# Service partage sans etat. NE MODIFIE JAMAIS la grille ni la piece — il repond, il n'agit pas.
# RefCounted (logique pure). Une piece est un Dictionary {type:int, rot:int, pos:Vector2i}.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")

# Fabrique canonique d'une piece (un seul endroit ou la forme du dict est fixee).
static func make_piece(type: int, rot: int, pos: Vector2i) -> Dictionary:
	return {"type": type, "rot": rot, "pos": pos}

# Cellules-monde occupees par une piece (offsets de forme translates par pos).
static func piece_cells(piece: Dictionary) -> Array:
	var out: Array = []
	for off in P.shape(piece["type"], piece["rot"]):
		out.append(piece["pos"] + off)
	return out

# Une cellule est-elle dans le puits ?
static func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < P.COLS and cell.y >= 0 and cell.y < P.ROWS

# La cellule est-elle vide dans la grille (0 = vide) ?
static func cell_empty(grid: Array, cell: Vector2i) -> bool:
	return grid[cell.y][cell.x] == 0

# Toutes ces cellules sont-elles dans le puits ET vides ?
static func fits(grid: Array, cells: Array) -> bool:
	for c in cells:
		if not in_bounds(c):
			return false
		if not cell_empty(grid, c):
			return false
	return true

# La piece tient-elle a sa position/orientation courante ?
static func piece_fits(grid: Array, piece: Dictionary) -> bool:
	return fits(grid, piece_cells(piece))
