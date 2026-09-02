# core_end_condition.gd — oracle (bot_action) de la ligne core.end_condition. Un bot atteint
# une fin de partie par le canal public : l'etat final vaut EXACTEMENT GAGNE ou EXACTEMENT
# PERDU, jamais indefini ; 0 sortie de boucle sans statut terminal ; jamais les deux a la fois.
extends SceneTree

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const InputRules = preload("res://05_SYSTEMS/input_rules/input_rules.gd")
const Interc = preload("res://06_RUNTIME/adapters/solvability_bot/interception_bot.gd")

# bot_interc=true : interception (gagne). false : fuite vers le coin gauche (rate la balle,
# perd ses vies) — bot volontairement PERDANT pour prouver le terminal PERDU atteignable.
func _jouer(bot_interc: bool, max_ticks: int):
	var s = State.initial(1)
	var t := 0
	while t < max_ticks and s.statut == State.Statut.EN_COURS:
		var a: int = Interc.choisir_action(s) if bot_interc else InputRules.GAUCHE
		s = Loop.step(s, a)["etat"]
		t += 1
	return s

func _initialize() -> void:
	var fails: Array = []
	# Bot d'interception -> VICTOIRE (terminal GAGNE).
	var g = _jouer(true, 10000)
	if g.statut != State.Statut.GAGNE:
		fails.append("bot interception n'atteint pas GAGNE (statut=%d)" % g.statut)
	# Bot fuyant (rate la balle) -> DEFAITE (terminal PERDU) : il epuise ses vies.
	var p = _jouer(false, 10000)
	if p.statut != State.Statut.PERDU:
		fails.append("bot fuyant n'atteint pas PERDU (statut=%d)" % p.statut)
	# Exclusivite : jamais indefini, jamais les deux.
	for s in [g, p]:
		var term: bool = (s.statut == State.Statut.GAGNE) or (s.statut == State.Statut.PERDU)
		if not term:
			fails.append("sortie de boucle sans statut terminal (statut=%d)" % s.statut)
		if (s.statut == State.Statut.GAGNE) and (s.statut == State.Statut.PERDU):
			fails.append("GAGNE et PERDU simultanes (impossible)")
	print("ORACLE core_end_condition: %s" % ("PASS" if fails.is_empty() else "FAIL"))
	for f in fails:
		print("  FAIL: ", f)
	quit(0 if fails.is_empty() else 1)
