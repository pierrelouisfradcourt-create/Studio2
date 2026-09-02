# core_input_action.gd — oracle (bot_action) de la ligne core.input. Une action du vocabulaire
# ferme, passee par le MEME canal public que le clavier (Loop.step), deplace la raquette DES le
# meme tick ; gauche/droite -> effets opposes distincts ; AUCUNE -> immobile.
extends SceneTree

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const IA = preload("res://06_RUNTIME/adapters/input_adapter/input_adapter.gd")
const InputRules = preload("res://05_SYSTEMS/input_rules/input_rules.gd")

func _initialize() -> void:
	var fails: Array = []
	var s = State.initial(1)
	var x0: float = s.paddle_x

	# Traduction clavier -> action (canal public).
	var ad: Dictionary = IA.traduire_keycode(KEY_RIGHT)
	if ad.get("dir") != InputRules.DROITE:
		fails.append("KEY_RIGHT ne se traduit pas en DROITE")

	var xd: float = Loop.step(s, InputRules.DROITE)["etat"].paddle_x
	var xg: float = Loop.step(s, InputRules.GAUCHE)["etat"].paddle_x
	var xn: float = Loop.step(s, InputRules.AUCUNE)["etat"].paddle_x
	if not (xd > x0):
		fails.append("DROITE ne deplace pas a droite le meme tick")
	if not (xg < x0):
		fails.append("GAUCHE ne deplace pas a gauche le meme tick")
	if xd == xg:
		fails.append("gauche et droite -> meme position (pas d'effet directionnel)")
	if xn != x0:
		fails.append("AUCUNE deplace la raquette (devrait etre immobile)")

	print("ORACLE core_input_action: %s" % ("PASS" if fails.is_empty() else "FAIL"))
	for f in fails:
		print("  FAIL: ", f)
	quit(0 if fails.is_empty() else 1)
