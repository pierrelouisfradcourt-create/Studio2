# gravity.gd — ligne core.gravity (R2 Gravite discrete).
# genre.tetris.discrete_gravity : la piece descend d'EXACTEMENT une case a intervalle regulier.
# Ce systeme decide le pas de descente ; il ne teste pas la collision lui-meme (il DELEGUE a
# collision) et n'ordonne pas le tick (c'est game_loop). RefCounted (logique pure).
extends RefCounted

const Collision = preload("res://05_SYSTEMS/collision/collision.gd")

# Tente de descendre la piece d'exactement une case. Retour :
#   {piece:Dictionary, landed:bool, dy:int}
# - place libre  -> piece descendue de 1 (dy == 1), landed == false
# - blocage      -> piece INCHANGEE (dy == 0), landed == true (elle doit se verrouiller)
static func apply_gravity(grid: Array, piece: Dictionary) -> Dictionary:
	var down := Collision.make_piece(piece["type"], piece["rot"], piece["pos"] + Vector2i(0, 1))
	if Collision.piece_fits(grid, down):
		return {"piece": down, "landed": false, "dy": 1}
	return {"piece": piece, "landed": true, "dy": 0}
