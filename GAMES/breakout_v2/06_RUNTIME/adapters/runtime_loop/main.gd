# main.gd — PILOTE DE SCENE (adaptateur runtime, categorie system.adapter, system_parent
# runtime_loop, main_scene du projet via res://main.tscn). Vit sous l'adresse de la ligne
# runtime.fixed_step_accumulator (06_RUNTIME/adapters/runtime_loop/) : couverte par la carte.
# Node2D : la SEULE couche autorisee a toucher le moteur (Input, _process, _draw, get_tree).
# Il compose la logique pure (05_SYSTEMS) et les adaptateurs (06_RUNTIME) : le delta REEL du
# moteur entre ICI et est arrete par l'accumulateur a pas fixe (runtime_loop) — la logique pure
# ne voit jamais l'horloge. Aucune regle de jeu n'est decidee ici : ce module LIT l'etat et le rend.
extends Node2D

const P = preload("res://05_SYSTEMS/params/params.gd")
const Boot = preload("res://06_RUNTIME/adapters/runtime_loop/boot.gd")
const RL = preload("res://06_RUNTIME/adapters/runtime_loop/runtime_loop.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const InputRules = preload("res://05_SYSTEMS/input_rules/input_rules.gd")
const IA = preload("res://06_RUNTIME/adapters/input_adapter/input_adapter.gd")
const Exit = preload("res://06_RUNTIME/adapters/runtime_loop/exit.gd")
const Hud = preload("res://06_RUNTIME/adapters/presentation/hud.gd")
const EndScreen = preload("res://06_RUNTIME/adapters/presentation/end_screen.gd")
const FieldView = preload("res://06_RUNTIME/adapters/presentation/field_view.gd")
const BrickView = preload("res://06_RUNTIME/adapters/presentation/brick_view.gd")

var _state
var _acc: float = 0.0
var _dir: int = 0
var _font: Font

func _ready() -> void:
	# DEMARRAGE IMMEDIAT : l'etat jouable est atteint des le boot, sans menu ni appui.
	_state = Boot.etat_initial(P.SEED_REFERENCE)
	_font = ThemeDB.fallback_font

func _process(delta: float) -> void:
	var gelee: bool = _state.statut != State.Statut.EN_COURS
	if not gelee:
		# Direction TENUE, traduite dans le vocabulaire ferme (jamais lue par la logique pure).
		_dir = InputRules.AUCUNE
		if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
			_dir = InputRules.GAUCHE
		elif Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
			_dir = InputRules.DROITE
	# Accumulateur a pas FIXE : le delta reel du moteur est converti en un nombre BORNE de ticks
	# (rattrapage plafonne, reste conserve — voir runtime_loop.avancer).
	var r: Dictionary = RL.avancer(_acc, delta * 1000.0, gelee)
	_acc = r["accumulateur"]
	# Applique chaque tick rendu par l'accumulateur. Loop.step est inerte sur un etat terminal :
	# si la partie se termine en cours de rattrapage, les ticks restants sont sans effet.
	for _i in range(r["ticks"]):
		_state = Loop.step(_state, _dir)["etat"]
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	var kc: int = IA.keycode_de_event(event)
	if kc == -1:
		return
	var a: Dictionary = IA.traduire_keycode(kc)
	if a.get("kind") == "commande":
		match a.get("commande"):
			IA.CMD_RELANCE:
				# REJOUER EN UN GESTE : etat neuf, aucun residu.
				_state = Boot.etat_initial(P.SEED_REFERENCE)
				_acc = 0.0
			IA.CMD_SORTIE:
				# QUITTER OBSERVABLE : arret du processus, code 0.
				get_tree().quit(Exit.CODE_SORTIE)

func _draw() -> void:
	for p in FieldView.primitives(_state):
		if p["kind"] == "rect":
			draw_rect(p["rect"], p["color"])
		elif p["kind"] == "circle":
			draw_circle(p["center"], p["radius"], p["color"])
	for b in BrickView.primitives(_state):
		draw_rect(b["rect"], b["color"])
	if _font != null:
		draw_string(_font, Vector2(8.0, 20.0), Hud.texte_vies(_state.vies), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color.WHITE)
		draw_string(_font, Vector2(120.0, 20.0), Hud.texte_score(_state.score), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color.WHITE)
		if EndScreen.est_actif(_state.statut):
			var cx: float = P.TERRAIN_LARGEUR / 2.0
			var cy: float = P.TERRAIN_HAUTEUR / 2.0
			draw_string(_font, Vector2(cx - 90.0, cy), EndScreen.message(_state.statut), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 28, Color.WHITE)
			draw_string(_font, Vector2(cx - 110.0, cy + 30.0), "R: rejouer    Echap: quitter", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(0.82, 0.82, 0.88))
