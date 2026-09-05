# input_adapter.gd — ADAPTATEUR D'ENTREE (category system.adapter, allowed_deps
# [economy, collection, upgrades, prestige, pricing]).
#
# CANAL D'ENTREE PUBLIC UNIQUE : traduit les clics (pelote, acheter_chaton,
# acheter_amelioration, prestige) en actions sur la LOGIQUE PURE. Le bot de solvabilite et
# la sonde player_loop passent par lui, jamais par une ecriture directe dans l'etat. Ne rend
# rien, ne joue aucun son : il EMET des signaux, le controleur orchestre presentation/audio.
#
# MECANISME headless-robuste (mesure 2026-08-23) : le picking GUI du viewport ne route PAS un
# InputEvent injecte vers un Button en `--headless` ; un `_input` qui teste le rect global de
# chaque affordance, LUI, recoit l'evenement dans les deux modes. C'est donc `_input` +
# hit-test manuel, jamais `Button.pressed`.
extends Node

const Economy = preload("res://05_SYSTEMS/economy/economy.gd")
const Collection = preload("res://05_SYSTEMS/collection/collection.gd")
const Upgrades = preload("res://05_SYSTEMS/upgrades/upgrades.gd")
const Prestige = preload("res://05_SYSTEMS/prestige/prestige.gd")
const Pricing = preload("res://05_SYSTEMS/pricing/pricing.gd")

signal pelote_clicked(gain: int)
signal kitten_adopted(index: int)
signal upgrade_bought(level: int)
signal prestiged()

var _state: Dictionary = {}
var _kittens: Array = []
var _tick: int = 0


func setup(state: Dictionary, kittens_array: Array) -> void:
	_state = state
	_kittens = kittens_array


func set_tick(tick: int) -> void:
	_tick = tick


func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var target := _affordance_at(mb.position)
	if target != "":
		act(target)


# Nom de l'affordance dont le rect global contient le point, ou "" (chaine vide).
func _affordance_at(pos: Vector2) -> String:
	for n in get_tree().get_nodes_in_group("affordance"):
		if n is Control and (n as Control).is_visible_in_tree():
			if (n as Control).get_global_rect().has_point(pos):
				return String(n.name)
	return ""


# Valeur d'un clic pelote = base x multiplicateur d'amelioration (compose ici, pas dans
# economy qui ne connait pas upgrades).
func click_value() -> int:
	return Economy.base_click() * Upgrades.click_multiplier(_state)


# Execute l'action d'une affordance sur la logique pure et emet le signal correspondant.
# Point d'entree public UNIQUE : le bot de solvabilite appelle `act(nom)` OU clique le rect.
func act(affordance: String) -> void:
	match affordance:
		"pelote":
			var gain: int = click_value()
			Economy.add(_state, float(gain))
			pelote_clicked.emit(gain)
		"acheter_chaton":
			var cost: int = Pricing.kitten_cost(Collection.count(_state))
			if Economy.spend(_state, cost) and Collection.adopt(_state, _kittens):
				kitten_adopted.emit(Collection.count(_state) - 1)
		"acheter_amelioration":
			var ucost: int = Pricing.upgrade_cost(Upgrades.level(_state))
			if Economy.spend(_state, ucost):
				upgrade_bought.emit(Upgrades.buy(_state))
		"prestige":
			if Prestige.prestige(_state):
				prestiged.emit()
		_:
			pass
