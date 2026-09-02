# core_rotation_rules.gd — oracle produit de la ligne core.rotation_rules. SceneTree headless.
# Observable : la rotation est appliquee si legale, REFUSEE sinon — le terrain contraint l'orientation, jamais l'inverse.
# Sortie : "FORGE_ORACLE core_rotation_rules {json}", exit 0 si vert.
extends SceneTree

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Collision = preload("res://05_SYSTEMS/collision/collision.gd")
const Rotation = preload("res://05_SYSTEMS/rotation_rules/rotation.gd")

func _initialize() -> void:
	var fails: Array = []
	var data: Dictionary = {}
	var grid: Array = State.empty_grid()
	var p := Collision.make_piece(2, 0, Vector2i(4, 5))
	var ok_r: Dictionary = Rotation.rotate_piece(grid, p, 1)
	if not ok_r["rotated"]:
		fails.append("rotation legale refusee")
	if ok_r["piece"]["rot"] != 1:
		fails.append("orientation non avancee")
	# Rotation illegale : contre le mur gauche, refus STRICT et piece inchangee.
	var mur := Collision.make_piece(0, 1, Vector2i(-2, 5))
	var ko: Dictionary = Rotation.rotate_piece(grid, mur, 1)
	if ko["rotated"]:
		fails.append("rotation illegale acceptee")
	if ko["piece"]["rot"] != mur["rot"] or ko["piece"]["pos"] != mur["pos"]:
		fails.append("piece modifiee malgre le refus")
	data = {"legale": ok_r["rotated"], "illegale": ko["rotated"]}
	_emit(fails, data)

func _emit(fails: Array, data: Dictionary) -> void:
	print("FORGE_ORACLE core_rotation_rules " + JSON.stringify({"ok": fails.is_empty(), "fails": fails, "data": data}))
	quit(0 if fails.is_empty() else 1)
