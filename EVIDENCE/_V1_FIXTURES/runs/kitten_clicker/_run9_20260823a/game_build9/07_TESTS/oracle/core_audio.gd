# core_audio.gd — VOLET PRODUIT (category test.oracle). Patron
# games/bomberman_3d/07_TESTS/oracle/core_audio.gd. Charge la VRAIE scene res://main.tscn,
# la joue DEPUIS L'ECRAN (InputEvent seulement) pour declencher les QUATRE evenements
# sonores — clic pelote, achat, deblocage, prestige — puis lit le JOURNAL de l'adaptateur
# audio et verifie qu'il porte exactement un id de son DISTINCT par evenement (4 ids).
#
# L'adaptateur audio (06_RUNTIME) est preloadé pour LIRE son journal : c'est autorise (garde
# anti-contournement V4 n'interdit que Economy/api_*/05_SYSTEMS/runtime.gd, jamais un
# adaptateur de presentation). Le son N'EST PAS declenche a la main : la scene le declenche
# sur ses propres evenements, le volet ne fait qu'observer la trace.
extends SceneTree

const Sound = preload("res://06_RUNTIME/adapters/audio/audio.gd")

var _f := 0
var _fails: Array = []
var _dead := false


func _init() -> void:
	Sound.reinitialiser()
	var packed = load("res://main.tscn")
	if packed == null or not (packed is PackedScene):
		_fails.append("main.tscn introuvable")
		_dead = true
		_emit()
		return
	get_root().add_child(packed.instantiate())


func _click(affordance: String) -> void:
	for n in get_root().get_tree().get_nodes_in_group("affordance"):
		if n is Control and n.name == affordance:
			var c: Vector2 = (n as Control).get_global_rect().get_center()
			var p := InputEventMouseButton.new()
			p.button_index = MOUSE_BUTTON_LEFT
			p.pressed = true
			p.position = c
			var r := InputEventMouseButton.new()
			r.button_index = MOUSE_BUTTON_LEFT
			r.pressed = false
			r.position = c
			Input.parse_input_event(p)
			Input.parse_input_event(r)
			return


func _process(_d: float) -> bool:
	if _dead:
		return true
	_f += 1
	# Accumuler par des clics, puis adopter 3 chatons (achat + deblocage au 3e), puis prestige.
	if _f >= 5 and _f <= 34:
		_click("pelote")
	elif _f == 50 or _f == 62 or _f == 74:
		_click("acheter_chaton")
	elif _f == 90:
		_click("prestige")
	elif _f == 110:
		var cues: Array = Sound.cues_distincts()
		for expected in [Sound.CUE_CLICK, Sound.CUE_PURCHASE, Sound.CUE_UNLOCK, Sound.CUE_PRESTIGE]:
			if not cues.has(expected):
				_fails.append("aucun son declenche pour l'evenement '%s'" % expected)
		if Sound.journal().is_empty():
			_fails.append("journal audio vide")
		_emit()
		return true
	return false


func _emit() -> void:
	var ok: bool = _fails.is_empty()
	print("FORGE_ORACLE core_audio " + JSON.stringify({
		"ok": ok, "fails": _fails,
		"declenchements": Sound.journal().size(),
		"cues_distincts": Sound.cues_distincts(),
	}))
	quit(0 if ok else 1)
