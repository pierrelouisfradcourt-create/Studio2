# rotation.gd — ligne core.rotation_rules (R5 Rotation contrainte).
# genre.tetris.rotation_bounded_by_terrain : une rotation dont la position resultante
# collisionne est REFUSEE ; le terrain contraint la rotation, la rotation ne deforme jamais
# le terrain. V1 = refus strict sur collision, SANS wall-kick (decision ouverte Genre Bible §3
# non tranchee -> V1 assumee). RefCounted (logique pure). Ne dessine rien.
extends RefCounted

const Collision = preload("res://05_SYSTEMS/collision/collision.gd")

# Applique une rotation (dir = +1 horaire, -1 anti-horaire) si la position resultante est
# legale. Retour : {rotated:bool, piece:Dictionary}. Sur refus, la piece est rendue INCHANGEE
# (orientation, position et terrain intacts).
static func rotate_piece(grid: Array, piece: Dictionary, dir: int) -> Dictionary:
	var new_rot: int = ((piece["rot"] + dir) % 4 + 4) % 4
	var candidate := Collision.make_piece(piece["type"], new_rot, piece["pos"])
	if Collision.piece_fits(grid, candidate):
		return {"rotated": true, "piece": candidate}
	return {"rotated": false, "piece": piece}
