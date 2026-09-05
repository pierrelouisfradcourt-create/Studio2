# solvability.gd — ORACLE DE SOLVABILITE (category godot.project_root).
# A la racine du projet, lance par scripts/forge/solvability_godot.mjs (headless) via
# `--seed=<n> --max_ticks=<m>`. Charge la VRAIE scene res://main.tscn et joue par le SEUL
# canal du joueur : InputEvent sur les affordances (groupe "affordance") + lecture des Label
# (groupe "hud"). JAMAIS Economy/api_*/05_SYSTEMS/runtime.gd (garde anti-contournement V4).
#
# CRITERE : le bot atteint le 3e palier de progression — 3 chatons adoptes — en un nombre
# FINI de trames. Politique deterministe : si le solde suffit pour le prochain chaton (cout lu
# sur le HUD), adopter ; sinon caresser la pelote pour accumuler.
#
# PROTOCOLE : une seule ligne `FORGE_TRIAL {"succeeded": bool, "ticks": number|null}` puis
# `quit(0)` DANS TOUS LES CAS (l'echec s'exprime par succeeded:false, jamais par un exit != 0).
extends SceneTree

const PALIER_CIBLE := 3
const MAX_TICKS_DEFAUT := 4000

var _ticks := 0
var _max_ticks := MAX_TICKS_DEFAUT
var _dead := false


func _lire_arg(nom: String, defaut: int) -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(nom + "="):
			var v := a.substr((nom + "=").length())
			if v.is_valid_int():
				return int(v)
	return defaut


func _init() -> void:
	seed(_lire_arg("--seed", 1))
	_max_ticks = _lire_arg("--max_ticks", MAX_TICKS_DEFAUT)
	if _max_ticks <= 0:
		_max_ticks = MAX_TICKS_DEFAUT
	var packed = load("res://main.tscn")
	if packed == null or not (packed is PackedScene):
		print("FORGE_TRIAL ", JSON.stringify({"succeeded": false, "ticks": null}))
		_dead = true
		quit(0)
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
	if _dead:
		return true
	_ticks += 1
	# laisser la scene se construire quelques trames.
	if _ticks < 5:
		return false
	var chatons := _num("collection")
	if chatons >= PALIER_CIBLE:
		print("FORGE_TRIAL ", JSON.stringify({"succeeded": true, "ticks": _ticks}))
		quit(0)
		return true
	if _ticks >= _max_ticks:
		print("FORGE_DIAG ", JSON.stringify({"chatons": chatons, "ronrons": _num("ronrons"), "ticks": _ticks}))
		print("FORGE_TRIAL ", JSON.stringify({"succeeded": false, "ticks": null}))
		quit(0)
		return true
	# politique : adopter si finançable (cout lu sur le HUD), sinon caresser la pelote.
	var ronrons := _num("ronrons")
	var cout := _num("cout_acheter_chaton")
	if cout > 0 and ronrons >= cout:
		_click("acheter_chaton")
	else:
		_click("pelote")
	return false
