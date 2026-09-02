# core_input_rules.gd — oracle produit de la ligne core.input_rules. SceneTree headless.
# Observable : une intention n'agit QUE sur la piece active ; la pile est structurellement inchangee sous tout input.
# Sortie : "FORGE_ORACLE core_input_rules {json}", exit 0 si vert.
extends SceneTree

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Collision = preload("res://05_SYSTEMS/collision/collision.gd")
const InputRules = preload("res://05_SYSTEMS/input_rules/input.gd")

func _initialize() -> void:
	var fails: Array = []
	var data: Dictionary = {}
	var grid: Array = State.empty_grid()
	var p := Collision.make_piece(2, 0, Vector2i(3, 3))
	var gl: Dictionary = InputRules.move_active_piece(grid, p, InputRules.LEFT)
	if gl["piece"]["pos"] != Vector2i(2, 3):
		fails.append("LEFT ne decale pas de -1")
	var gr: Dictionary = InputRules.move_active_piece(grid, p, InputRules.RIGHT)
	if gr["piece"]["pos"] != Vector2i(4, 3):
		fails.append("RIGHT ne decale pas de +1")
	var hd: Dictionary = InputRules.move_active_piece(grid, p, InputRules.HARD_DROP)
	if not hd["landed"]:
		fails.append("HARD_DROP ne signale pas l'atterrissage")
	# La PILE doit rester intacte sous n'importe quelle intention (R6).
	var occupees := 0
	for row in grid:
		for c in row:
			if c != 0:
				occupees += 1
	if occupees != 0:
		fails.append("la pile a ete ecrite par un input (R6 violee)")
	data = {"left": [gl["piece"]["pos"].x, gl["piece"]["pos"].y], "hard_drop_landed": hd["landed"], "pile_occupee": occupees}
	_emit(fails, data)

func _emit(fails: Array, data: Dictionary) -> void:
	print("FORGE_ORACLE core_input_rules " + JSON.stringify({"ok": fails.is_empty(), "fails": fails, "data": data}))
	quit(0 if fails.is_empty() else 1)
