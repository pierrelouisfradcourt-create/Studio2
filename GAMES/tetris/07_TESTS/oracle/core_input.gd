# core_input.gd — oracle produit de la ligne core.input. SceneTree headless.
# Observable : une touche physique est traduite en intention du vocabulaire ferme, et une touche inconnue ne produit AUCUNE action.
# Sortie : "FORGE_ORACLE core_input {json}", exit 0 si vert.
extends SceneTree

const InputRules = preload("res://05_SYSTEMS/input_rules/input.gd")
const RL = preload("res://06_RUNTIME/adapters/runtime_loop/runtime_loop.gd")

func _initialize() -> void:
	var fails: Array = []
	var data: Dictionary = {}
	var rl = RL.new()
	var attendu := {
		KEY_LEFT: InputRules.LEFT, KEY_A: InputRules.LEFT,
		KEY_RIGHT: InputRules.RIGHT, KEY_D: InputRules.RIGHT,
		KEY_DOWN: InputRules.SOFT_DROP, KEY_S: InputRules.SOFT_DROP,
		KEY_UP: InputRules.ROTATE_CW, KEY_W: InputRules.ROTATE_CW,
		KEY_SPACE: InputRules.HARD_DROP,
	}
	for kc in attendu:
		var got: int = rl._intent_de_touche(kc)
		if got != attendu[kc]:
			fails.append("touche %d -> %d, attendu %d" % [kc, got, attendu[kc]])
	# Touche hors vocabulaire : aucune action.
	if rl._intent_de_touche(KEY_F7) != InputRules.NONE:
		fails.append("touche inconnue produit une action")
	rl.free()
	data = {"touches_mappees": attendu.size()}
	_emit(fails, data)

func _emit(fails: Array, data: Dictionary) -> void:
	print("FORGE_ORACLE core_input " + JSON.stringify({"ok": fails.is_empty(), "fails": fails, "data": data}))
	quit(0 if fails.is_empty() else 1)
