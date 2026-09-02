# core_restart.gd — oracle (bot_action) de la ligne core.restart. Apres une fin de partie,
# une relance produit un etat STRICTEMENT identique au premier demarrage a seed egale : le
# nombre de champs differant de l'etat initial est EXACTEMENT 0 (0 residu).
extends SceneTree

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const Restart = preload("res://05_SYSTEMS/game_state/restart.gd")
const InputRules = preload("res://05_SYSTEMS/input_rules/input_rules.gd")

func _initialize() -> void:
	var fails: Array = []
	var graine := 1
	var initial = State.initial(graine)

	# Jouer une partie jusqu'a une fin (defaite : la raquette fuit vers le coin et rate la
	# balle jusqu'a epuisement des vies), etat bien pollue.
	var s = State.initial(graine)
	var t := 0
	while t < 10000 and s.statut == State.Statut.EN_COURS:
		s = Loop.step(s, InputRules.GAUCHE)["etat"]
		t += 1
	if s.statut == State.Statut.EN_COURS:
		fails.append("la partie n'a pas atteint de fin (pre-condition)")

	# Relance a meme graine -> etat identique au premier demarrage.
	var neuf = Restart.relancer(graine)
	if not neuf.egal_profond(initial):
		fails.append("etat relance != etat initial (residu detecte)")
	if not s.egal_profond(initial):
		pass  # controle : l'etat AVANCE differe bien (non exige, informatif)
	else:
		fails.append("controle: l'etat de fin egalait deja l'initial (test trivial)")

	print("ORACLE core_restart: %s" % ("PASS" if fails.is_empty() else "FAIL"))
	for f in fails:
		print("  FAIL: ", f)
	quit(0 if fails.is_empty() else 1)
