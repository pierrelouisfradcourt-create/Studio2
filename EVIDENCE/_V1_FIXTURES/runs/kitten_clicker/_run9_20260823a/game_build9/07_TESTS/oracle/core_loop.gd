# core_loop.gd — VOLET PRODUIT (category test.oracle). Charge la VRAIE scene
# res://main.tscn et prouve la boucle de base DEPUIS L'ECRAN : un clic sur la pelote fait
# monter le HUD `ronrons`, un clic sur `acheter_chaton` fait monter le HUD `collection`.
# Entrees d'un JOUEUR uniquement (InputEvent + lecture de Label du groupe "hud") — jamais
# d'appel a la logique interne (garde anti-contournement V4). Sortie : FORGE_ORACLE core_loop.
extends SceneTree

var _f := 0
var _phase := 0
var _ronrons_avant := -1
var _collection_avant := -1
var _fails: Array = []


func _init() -> void:
	var packed = load("res://main.tscn")
	if packed == null or not (packed is PackedScene):
		_fails.append("main.tscn introuvable")
		_emit()
		return
	get_root().add_child(packed.instantiate())


func _num(hud_name: String) -> int:
	var l := _find_hud(hud_name)
	if l == null:
		return -999999
	var re := RegEx.new()
	re.compile("-?\\d+")
	var m := re.search(l.text)
	return int(m.get_string()) if m != null else -999999


func _find_hud(hud_name: String) -> Label:
	for n in get_root().get_tree().get_nodes_in_group("hud"):
		if n is Label and n.name == hud_name:
			return n
	return null


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
	_f += 1
	if not _fails.is_empty():
		return true
	# Sequence : mesurer ronrons, cliquer pelote 5x, verifier hausse ; puis accumuler et
	# acheter un chaton, verifier collection +1.
	if _f == 20:
		if _find_hud("ronrons") == null:
			_fails.append("HUD ronrons introuvable")
			_emit()
			return true
		_ronrons_avant = _num("ronrons")
	elif _f > 20 and _f <= 40:
		_click("pelote")
	elif _f == 55:
		if not (_num("ronrons") > _ronrons_avant):
			_fails.append("ronrons n'a pas augmente au clic pelote (%d -> %d)" % [_ronrons_avant, _num("ronrons")])
			_emit()
			return true
		_collection_avant = _num("collection")
	elif _f > 55 and _f <= 90:
		# assez de ronrons ont ete gagnes : adopter un chaton.
		_click("acheter_chaton")
	elif _f == 110:
		if not (_num("collection") > _collection_avant):
			_fails.append("collection n'a pas augmente a l'adoption (%d -> %d)" % [_collection_avant, _num("collection")])
		_emit()
		return true
	return false


func _emit() -> void:
	var ok: bool = _fails.is_empty()
	print("FORGE_ORACLE core_loop " + JSON.stringify({
		"ok": ok, "fails": _fails,
		"data": {"ronrons_avant": _ronrons_avant, "collection_avant": _collection_avant},
	}))
	quit(0 if ok else 1)
