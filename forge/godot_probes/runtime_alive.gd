extends SceneTree
# runtime_alive — sonde Forge HORS projet (lancee `--path <jeu> --script <chemin absolu>` en fenetre GPU).
# Charge la VRAIE scene principale (run/main_scene), la laisse vivre, injecte UN clic au centre,
# et mesure si l'image change. Ne construit aucune scene. Emet une ligne FORGE_ORACLE (protocole
# product_oracle_godot). Decision Pierre 2026-08-22 : un oracle qui reconstruit son environnement
# peut prouver un jeu qui n'existe pas.
const FRAMES_SETTLE := 60
const FRAMES_AFTER_CLICK := 60
var _frames := 0
var _img_a: Image = null
var _data := {"scene": "", "loaded": false, "root_children": 0, "nodes_total": 0, "scripted_nodes": 0,
              "system_scripts": 0, "nonmonochrome": false, "changed_after_click": false, "frames": 0}
var _fails: Array[String] = []

func _init() -> void:
	var scene_path: String = ProjectSettings.get_setting("run/main_scene", "res://main.tscn")
	_data["scene"] = scene_path
	var packed = load(scene_path)
	if packed == null or not (packed is PackedScene):
		_fails.append("scene principale introuvable : %s" % scene_path)
		_emit(); return
	var inst: Node = packed.instantiate()
	get_root().add_child(inst)
	_data["loaded"] = true

func _process(_delta: float) -> bool:
	_frames += 1
	_data["frames"] = _frames
	if _frames == FRAMES_SETTLE:
		_inventory()
		_img_a = _capture()
		_data["nonmonochrome"] = _nonmonochrome(_img_a)
		var vp := get_root()
		var center: Vector2 = vp.get_visible_rect().size / 2.0
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true; press.position = center
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT; release.pressed = false; release.position = center
		Input.parse_input_event(press); Input.parse_input_event(release)
	elif _frames == FRAMES_SETTLE + FRAMES_AFTER_CLICK:
		var img_b := _capture()
		_data["changed_after_click"] = _img_a != null and img_b.get_data() != _img_a.get_data()
		if not _data["nonmonochrome"]:
			_fails.append("image monochrome avant le clic")
		if not _data["changed_after_click"]:
			_fails.append("aucun changement d'image apres le clic (jeu statique)")
		if _data["scripted_nodes"] == 0:
			_fails.append("aucun noeud scripte dans la scene chargee")
		_emit()
	return false

func _inventory() -> void:
	var root := get_root()
	_data["root_children"] = root.get_child_count()
	var stack: Array = [root]; var total := 0; var scripted := 0; var sys := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back(); total += 1
		var s = n.get_script()
		if s != null:
			scripted += 1
			var p: String = s.resource_path
			if p.begins_with("res://05_SYSTEMS") or p.begins_with("res://06_RUNTIME"): sys += 1
		for c in n.get_children(): stack.push_back(c)
	_data["nodes_total"] = total; _data["scripted_nodes"] = scripted; _data["system_scripts"] = sys

func _capture() -> Image:
	return get_root().get_texture().get_image()

func _nonmonochrome(img: Image) -> bool:
	if img == null: return false
	var first := img.get_pixel(0, 0); var step := maxi(1, img.get_width() / 32)
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			if img.get_pixel(x, y).is_equal_approx(first) == false: return true
	return false

func _emit() -> void:
	var ok: bool = _fails.is_empty() and bool(_data["loaded"])
	print("FORGE_ORACLE runtime_alive " + JSON.stringify({"ok": ok, "fails": _fails, "data": _data}))
	quit(0 if ok else 1)
