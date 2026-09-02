# PONG — renderer Godot (ADAPTATEUR). Lit un ETAT de jeu (JSON produit par la
# logique JS pure), le DESSINE, capture le rendu en PNG et quitte proprement (code 0).
# Aucune physique ici : Godot ne fait que rendre un etat qu'on lui donne. Les
# constantes de terrain refletent 05_SYSTEMS/game_state/state.mjs (dessin, pas regles).
extends Node2D

const FIELD_W := 200.0
const FIELD_H := 120.0
const PADDLE_W := 4.0
const PADDLE_H := 24.0
const BALL_R := 2.0
const P1_X := 6.0
const P2_X := 194.0
const SCALE := 4.0

const BG := Color(0.047, 0.055, 0.078)
const FG := Color(0.921, 0.933, 0.960)
const MID := Color(0.156, 0.180, 0.235)
const ACCENT := Color(0.352, 0.784, 0.627)

var _state := {}
var _out_path := ""

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var state_path := ""
	for i in range(args.size()):
		if args[i] == "--state" and i + 1 < args.size():
			state_path = args[i + 1]
		elif args[i] == "--out" and i + 1 < args.size():
			_out_path = args[i + 1]
	if state_path != "":
		var f := FileAccess.open(state_path, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				_state = parsed
	queue_redraw()
	_capture()

func _num(dict, key, def := 0.0) -> float:
	if dict != null and dict.has(key):
		return float(dict[key])
	return def

func _draw() -> void:
	draw_rect(Rect2(0, 0, FIELD_W * SCALE, FIELD_H * SCALE), BG, true)

	# ligne mediane pointillee
	var y := 0.0
	while y < FIELD_H * SCALE:
		draw_rect(Rect2(FIELD_W * SCALE / 2.0 - SCALE / 2.0, y, SCALE, SCALE * 3.0), MID, true)
		y += SCALE * 6.0

	var p1 = _state.get("p1", {})
	var p2 = _state.get("p2", {})
	var ball = _state.get("ball", {})
	var score = _state.get("score", {})
	var p1y := _num(p1, "y", (FIELD_H - PADDLE_H) / 2.0)
	var p2y := _num(p2, "y", (FIELD_H - PADDLE_H) / 2.0)
	var bx := _num(ball, "x", FIELD_W / 2.0)
	var by := _num(ball, "y", FIELD_H / 2.0)

	# raquettes (P1_X = plan de collision = face droite de la raquette gauche)
	draw_rect(Rect2((P1_X - PADDLE_W) * SCALE, p1y * SCALE, PADDLE_W * SCALE, PADDLE_H * SCALE), FG, true)
	draw_rect(Rect2(P2_X * SCALE, p2y * SCALE, PADDLE_W * SCALE, PADDLE_H * SCALE), FG, true)

	# balle
	draw_rect(Rect2((bx - BALL_R) * SCALE, (by - BALL_R) * SCALE, BALL_R * 2.0 * SCALE, BALL_R * 2.0 * SCALE), FG, true)

	# score : pips en haut
	var s1 := int(_num(score, "p1", 0.0))
	var s2 := int(_num(score, "p2", 0.0))
	for i in range(s1):
		draw_rect(Rect2(FIELD_W * SCALE / 2.0 - SCALE * 12.0 - i * SCALE * 6.0, SCALE * 3.0, SCALE * 4.0, SCALE * 4.0), ACCENT, true)
	for i in range(s2):
		draw_rect(Rect2(FIELD_W * SCALE / 2.0 + SCALE * 8.0 + i * SCALE * 6.0, SCALE * 3.0, SCALE * 4.0, SCALE * 4.0), ACCENT, true)

func _count_colors(img: Image) -> int:
	var seen := {}
	var w := img.get_width()
	var h := img.get_height()
	var count := 0
	for yy in range(0, h, 3):
		for xx in range(0, w, 3):
			var c := img.get_pixel(xx, yy)
			var key := "%d,%d,%d" % [int(c.r * 255.0), int(c.g * 255.0), int(c.b * 255.0)]
			if not seen.has(key):
				seen[key] = true
				count += 1
				if count > 16:
					return count
	return count

func _capture() -> void:
	# Deux frames post-draw : garantit que le rendu GPU est present avant lecture.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var colors := _count_colors(img)
	var w := img.get_width()
	var h := img.get_height()
	if _out_path != "":
		var err := img.save_png(_out_path)
		print("PONG_CAPTURE out=%s colors=%d size=%dx%d err=%d" % [_out_path, colors, w, h, err])
	else:
		print("PONG_CAPTURE out= colors=%d size=%dx%d err=-1" % [colors, w, h])
	get_tree().quit(0)
