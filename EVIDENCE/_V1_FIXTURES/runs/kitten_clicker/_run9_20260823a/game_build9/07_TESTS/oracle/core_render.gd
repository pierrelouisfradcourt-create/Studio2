# core_render.gd — VOLET PRODUIT PIXEL (category test.oracle).
#
# forge:run_mode = gpu_window
#
# La directive ci-dessus route ce volet vers une fenetre GPU hors ecran (le driver dummy du
# mode --headless rend une texture NULLE). Charge la VRAIE scene res://main.tscn et prouve,
# EN PIXELS : (1) l'image n'est pas monochrome ; (2) deux chatons de raretes differentes de la
# galerie different en pixels au-dela d'un seuil ; (3) la zone pelote CHANGE en pixels entre
# avant et apres un clic (rebond + touffe de laine + texte flottant). Sortie : FORGE_ORACLE
# core_render.
extends SceneTree

const SETTLE := 40
const AFTER := 40
const SEUIL := 0.12

var _f := 0
var _img_pelote_avant: Image = null
var _pelote_rect: Rect2 = Rect2()
var _fails: Array = []
var _dead := false
var _rarity_diff := 0.0


func _init() -> void:
	get_root().size = Vector2i(640, 480)
	var packed = load("res://main.tscn")
	if packed == null or not (packed is PackedScene):
		_fails.append("main.tscn introuvable")
		_dead = true
		_emit()
		return
	get_root().add_child(packed.instantiate())


func _capture() -> Image:
	return get_root().get_texture().get_image()


func _avg_color(img: Image, r: Rect2) -> Color:
	var acc := Color(0, 0, 0, 0)
	var n := 0
	var x0 := int(max(0.0, r.position.x))
	var y0 := int(max(0.0, r.position.y))
	var x1 := int(min(float(img.get_width()), r.position.x + r.size.x))
	var y1 := int(min(float(img.get_height()), r.position.y + r.size.y))
	for y in range(y0, y1, 2):
		for x in range(x0, x1, 2):
			acc += img.get_pixel(x, y)
			n += 1
	if n == 0:
		return Color(0, 0, 0)
	return acc / float(n)


func _color_dist(a: Color, b: Color) -> float:
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0


func _nonmonochrome(img: Image) -> bool:
	var first := img.get_pixel(0, 0)
	var step: int = maxi(1, img.get_width() / 32)
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			if not img.get_pixel(x, y).is_equal_approx(first):
				return true
	return false


func _gallery_panels() -> Array:
	for g in get_root().get_tree().get_nodes_in_group("gallery"):
		if g is Control:
			var kids: Array = []
			for c in (g as Control).get_children():
				if c is Control:
					kids.append(c)
			return kids
	return []


func _affordance_rect(nom: String) -> Rect2:
	for n in get_root().get_tree().get_nodes_in_group("affordance"):
		if n is Control and n.name == nom:
			return (n as Control).get_global_rect()
	return Rect2()


func _process(_d: float) -> bool:
	if _dead:
		return true
	_f += 1
	if _f == SETTLE:
		var img := _capture()
		if not _nonmonochrome(img):
			_fails.append("image monochrome (rien rendu ?)")
		# rarete : deux panneaux de raretes differentes different en pixels.
		var panels := _gallery_panels()
		if panels.size() >= 2:
			var c0 := _avg_color(img, (panels[0] as Control).get_global_rect())
			var c1 := _avg_color(img, (panels[panels.size() - 1] as Control).get_global_rect())
			_rarity_diff = _color_dist(c0, c1)
			if _rarity_diff < SEUIL:
				_fails.append("deux raretes trop proches en pixels (%.3f < %.3f)" % [_rarity_diff, SEUIL])
		else:
			_fails.append("galerie de raretes absente (<2 panneaux)")
		# feedback clic : capturer la zone pelote AVANT le clic, puis cliquer.
		_pelote_rect = _affordance_rect("pelote")
		if _pelote_rect.size == Vector2.ZERO:
			_fails.append("affordance pelote absente")
			_emit()
			return true
		_img_pelote_avant = img.get_region(Rect2i(_pelote_rect))
		var c: Vector2 = _pelote_rect.get_center()
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
	elif _f == SETTLE + AFTER:
		var apres := _capture().get_region(Rect2i(_pelote_rect))
		if _img_pelote_avant == null or apres.get_data() == _img_pelote_avant.get_data():
			_fails.append("zone pelote inchangee apres le clic (aucun feedback visuel)")
		_emit()
		return true
	return false


func _emit() -> void:
	var ok: bool = _fails.is_empty()
	print("FORGE_ORACLE core_render " + JSON.stringify({
		"ok": ok, "fails": _fails, "rarity_diff": _rarity_diff,
	}))
	quit(0 if ok else 1)
