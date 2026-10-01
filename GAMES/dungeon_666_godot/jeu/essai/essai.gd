extends Node2D
## Banc d'essai (provisoire) : la simulation portée, jouée au clavier et dessinée en formes
## simples. Sert à vérifier à l'œil que la partie tourne avant que les vraies vues existent.
##   ZQSD / flèches : bouger · J ou clic gauche : attaquer · Espace : dash · L : compétence
##   E : gadget · F : Super · 1 2 3 : choix de menu · Entrée : fermer / reprendre

const Partie = preload("res://jeu/partie.gd")

var partie: Node
var _fronts := {}

func _ready() -> void:
	partie = Partie.new()
	add_child(partie)
	partie.entrees = _lire
	partie.demarrer({"seed": 7.0, "startFloor": 1.0})

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		_fronts[ev.keycode] = true
		_menu(ev.keycode)

func _menu(touche: int) -> void:
	var g = partie.game
	if g == null:
		return
	if g.mode == "choice":
		for cmd in _commandes(touche):
			if partie.commande(cmd):
				return
	elif g.mode == "dead" and touche == KEY_ENTER:
		partie.commande({"type": "respawn", "floor": D6Run.last_checkpoint(g)})

func _commandes(touche: int) -> Array:
	match touche:
		KEY_1: return [{"type": "choose", "index": 0.0}, {"type": "equip"}]
		KEY_2: return [{"type": "choose", "index": 1.0}, {"type": "stash"}]
		KEY_3: return [{"type": "choose", "index": 2.0}, {"type": "salvage"}]
		KEY_ENTER: return [{"type": "close"}]
	return []

func _front(touche: int) -> bool:
	return _fronts.erase(touche)

func _lire() -> Dictionary:
	var input: Dictionary = D6Game.empty_input()
	var mx := float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT))
	var my := float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
	input.moveX = mx
	input.moveY = my
	input.attack = Input.is_key_pressed(KEY_J) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	input.attackPressed = _front(KEY_J)
	input.dashPressed = _front(KEY_SPACE)
	input.skillPressed = _front(KEY_L)
	input.gadgetPressed = _front(KEY_E)
	input.superPressed = _front(KEY_F)
	return input

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var g = partie.game
	if g == null:
		return
	var room: Dictionary = g.room
	var vue := get_viewport_rect().size
	var p: Vector2 = partie.position_dessin(g.player, true)
	draw_set_transform(vue / 2.0 - p * 0.6, 0.0, Vector2(0.6, 0.6))
	draw_rect(Rect2(0, 0, room.w, room.h), Color("#1a1216"))
	draw_rect(Rect2(room.pad, room.pad, room.w - 2 * room.pad, room.h - 2 * room.pad), Color("#2a1c22"))
	for o in room.obstacles:
		draw_rect(Rect2(o.x0, o.y0, o.x1 - o.x0, o.y1 - o.y0), Color("#3d2a33"))
	for d in room.doors:
		draw_rect(Rect2(d.x, d.y, d.w, d.h), Color("#ffd23c") if D6Js.truthy(d.get("open")) else Color("#5a4a30"))
	var it = room.get("interact")
	if it is Dictionary and not D6Js.truthy(it.get("used")):
		draw_circle(Vector2(it.x, it.y), it.r, Color("#b98cff"))
	for h in g.hazards:
		if not D6Js.truthy(h.get("done")) and h.shape == "circle":
			draw_arc(Vector2(h.x, h.y), h.r, 0.0, TAU, 48, Color("#ff3a1a"), 3.0)
	for s in g.spawns:
		draw_arc(Vector2(s.x, s.y), 20.0, 0.0, TAU, 24, Color("#a04060"), 2.0)
	for k in g.pickups:
		draw_circle(partie.position_dessin(k), k.r, Color("#ffd23c") if k.kind == "gold" else Color("#6dff8a"))
	for e in g.enemies:
		if D6Js.truthy(e.get("dead")):
			continue
		var c := Color("#ff5a3c") if D6Js.truthy(e.get("boss")) else Color("#e03a4a")
		draw_circle(partie.position_dessin(e), e.r, c.lightened(0.5) if e.flash > 0.0 else c)
	for pr in g.projectiles:
		draw_circle(partie.position_dessin(pr), pr.r, Color("#ffffff") if pr.owner == "player" else Color("#ff9c2a"))
	draw_circle(p, g.player.r, Color("#6dd8ff") if g.player.iframes <= 0.0 else Color("#ffffff"))
	draw_line(p, p + Vector2.from_angle(g.player.facing) * 30.0, Color.WHITE, 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var texte := "étage %s · %s · PV %s/%s · or %s" % [D6Js.num_str(g.run.floor), g.mode, D6Js.num_str(roundf(g.player.hp)), D6Js.num_str(g.player.maxHp), D6Js.num_str(g.run.gold)]
	var ch = g.get("choice")
	if ch is Dictionary:
		texte += "  |  menu « %s » : 1 2 3 ou Entrée" % ch.kind
	draw_string(ThemeDB.fallback_font, Vector2(16, 28), texte, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
