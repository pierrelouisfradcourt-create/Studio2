# core_gravity.gd — oracle produit de la ligne core.gravity. SceneTree headless.
# Observable : la piece descend d'EXACTEMENT une case par pas, et signale le contact quand elle est bloquee.
# Sortie : "FORGE_ORACLE core_gravity {json}", exit 0 si vert.
extends SceneTree

const P = preload("res://05_SYSTEMS/params/params.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Collision = preload("res://05_SYSTEMS/collision/collision.gd")
const Gravity = preload("res://05_SYSTEMS/gravity/gravity.gd")

func _initialize() -> void:
	var fails: Array = []
	var data: Dictionary = {}
	var grid: Array = State.empty_grid()
	var p := Collision.make_piece(1, 0, Vector2i(3, 3))
	var r: Dictionary = Gravity.apply_gravity(grid, p)
	if r["dy"] != 1:
		fails.append("descente != 1 case (dy=%d)" % r["dy"])
	if r["landed"]:
		fails.append("landed vrai alors que la case est libre")
	if r["piece"]["pos"] != p["pos"] + Vector2i(0, 1):
		fails.append("position non decalee de +1 en y")
	# Bloque au sol : piece INCHANGEE, landed vrai, dy == 0.
	var bas := Collision.make_piece(1, 0, Vector2i(3, P.ROWS - 2))
	var rb: Dictionary = Gravity.apply_gravity(grid, bas)
	if not rb["landed"]:
		fails.append("pas de contact signale au sol")
	if rb["dy"] != 0:
		fails.append("dy != 0 sur blocage")
	if rb["piece"]["pos"] != bas["pos"]:
		fails.append("piece deplacee malgre le blocage")
	data = {"dy_libre": r["dy"], "landed_sol": rb["landed"], "dy_sol": rb["dy"]}
	_emit(fails, data)

func _emit(fails: Array, data: Dictionary) -> void:
	print("FORGE_ORACLE core_gravity " + JSON.stringify({"ok": fails.is_empty(), "fails": fails, "data": data}))
	quit(0 if fails.is_empty() else 1)
