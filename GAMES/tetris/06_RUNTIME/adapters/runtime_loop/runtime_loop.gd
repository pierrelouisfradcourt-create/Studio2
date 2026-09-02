# runtime_loop.gd — ligne core.game_loop cote RUNTIME (R9 Livrable jouable). Adaptateur de
# presentation/boucle : la SEULE couche autorisee a toucher le moteur (Node2D, Input, _process,
# _draw). Il COMPOSE la logique pure (05_SYSTEMS) ; il ne decide AUCUNE regle. Dependance a sens
# unique 06_RUNTIME -> 05_SYSTEMS (jamais l'inverse — deps_interdites blueprint #1..#3).
#
# start_game() amene un etat jouable des le boot (demarrage immediat, sans menu). Sans input, la
# gravite fait tomber et empiler les pieces jusqu'au game-over : une partie complete se joue
# seule (invariant de lancabilite prouve par l'oracle produit godot_oracle.mjs, fenetre GPU).
# Rendu = NOT_MEASURED en headless (texture nulle) — legitime, la mecanique reste prouvee ailleurs.
extends Node2D

const P = preload("res://05_SYSTEMS/params/params.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const InputRules = preload("res://05_SYSTEMS/input_rules/input.gd")

# Geometrie d'affichage (constantes de rendu, PAS des parametres de gameplay).
const CELL: int = 24
const MARGIN: int = 12
const STEP_MS: float = 16.0                    # un tick de logique toutes les 16 ms (~62,5 Hz)
const COLORS: Array = [
	Color(0.20, 0.80, 0.85),   # I
	Color(0.90, 0.85, 0.20),   # O
	Color(0.70, 0.35, 0.85),   # T
	Color(0.30, 0.80, 0.35),   # S
	Color(0.85, 0.30, 0.30),   # Z
	Color(0.30, 0.45, 0.85),   # J
	Color(0.90, 0.55, 0.20),   # L
]

var _state
var _acc: float = 0.0
var _font: Font

func _ready() -> void:
	start_game()
	_font = ThemeDB.fallback_font

# R9 : initialise une partie jouable (etat neuf deterministe). Appele au boot et pour rejouer.
func start_game() -> void:
	_state = State.initial(P.SPAWN.x + 1)   # graine de travail deterministe
	_acc = 0.0

func _process(delta: float) -> void:
	if _state == null:
		return
	# Accumulateur a pas FIXE : le delta reel du moteur est converti en ticks bornes de logique
	# pure (la logique ne voit jamais l'horloge). Sans input, la gravite auto suffit a jouer.
	_acc += delta * 1000.0
	var budget: int = 8   # borne anti-spirale si une trame est tres longue
	while _acc >= STEP_MS and budget > 0:
		_acc -= STEP_MS
		budget -= 1
		if _state.status == State.Statut.EN_COURS:
			_state = Loop.step(_state, InputRules.NONE)["state"]
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if _state == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var kc: int = event.keycode
		if kc == KEY_R:
			start_game()
			return
		if kc == KEY_ESCAPE:
			get_tree().quit(0)
			return
		if _state.status != State.Statut.EN_COURS:
			return
		var intent: int = _intent_de_touche(kc)
		if intent != InputRules.NONE:
			_state = Loop.step(_state, intent)["state"]
			queue_redraw()

func _intent_de_touche(kc: int) -> int:
	if kc == KEY_LEFT or kc == KEY_A:
		return InputRules.LEFT
	if kc == KEY_RIGHT or kc == KEY_D:
		return InputRules.RIGHT
	if kc == KEY_DOWN or kc == KEY_S:
		return InputRules.SOFT_DROP
	if kc == KEY_UP or kc == KEY_W:
		return InputRules.ROTATE_CW
	if kc == KEY_SPACE:
		return InputRules.HARD_DROP
	return InputRules.NONE

func _draw() -> void:
	if _state == null:
		return
	# Cadre du puits.
	var well := Rect2(MARGIN, MARGIN, P.COLS * CELL, P.ROWS * CELL)
	draw_rect(well, Color(0.08, 0.08, 0.12))
	draw_rect(well, Color(0.30, 0.30, 0.40), false, 2.0)
	# Pile.
	for y in range(P.ROWS):
		for x in range(P.COLS):
			var v: int = _state.grid[y][x]
			if v != 0:
				_draw_cell(x, y, COLORS[(v - 1) % COLORS.size()])
	# Piece active.
	if not _state.active.is_empty():
		var t: int = _state.active["type"]
		var col: Color = COLORS[t % COLORS.size()]
		for off in P.shape(t, _state.active["rot"]):
			var c: Vector2i = _state.active["pos"] + off
			_draw_cell(c.x, c.y, col)
	# HUD.
	if _font != null:
		var hud_x := MARGIN + P.COLS * CELL + 10
		draw_string(_font, Vector2(hud_x, 28), "SCORE %d" % _state.score, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color.WHITE)
		draw_string(_font, Vector2(hud_x, 52), "LIGNES %d" % _state.lines_cleared, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color.WHITE)
		if _state.status == State.Statut.GAME_OVER:
			draw_string(_font, Vector2(hud_x, 88), "GAME OVER", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color(0.95, 0.4, 0.4))
			draw_string(_font, Vector2(hud_x, 110), "R: rejouer", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(0.8, 0.8, 0.85))

func _draw_cell(x: int, y: int, col: Color) -> void:
	var r := Rect2(MARGIN + x * CELL + 1, MARGIN + y * CELL + 1, CELL - 2, CELL - 2)
	draw_rect(r, col)
