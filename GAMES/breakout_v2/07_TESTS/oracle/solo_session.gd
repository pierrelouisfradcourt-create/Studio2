# solo_session.gd — oracle (bot_action) de la ligne runtime.solo_session. Une partie SOLO
# complete se deroule par le seul canal public : boot -> jeu (rebonds + briques) -> fin
# terminale -> relance -> boot neuf. L'etat reste valide a chaque tick.
extends SceneTree

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const Boot = preload("res://06_RUNTIME/adapters/runtime_loop/boot.gd")
const Restart = preload("res://05_SYSTEMS/game_state/restart.gd")
const Interc = preload("res://06_RUNTIME/adapters/solvability_bot/interception_bot.gd")

func _initialize() -> void:
	var fails: Array = []
	var briques_cassees := 0
	var rebonds := 0

	var s = Boot.etat_initial(1)
	if s.statut != State.Statut.EN_COURS:
		fails.append("boot non EN_COURS")
	var t := 0
	while t < 10000 and s.statut == State.Statut.EN_COURS:
		var r: Dictionary = Loop.step(s, Interc.choisir_action(s))
		s = r["etat"]
		for e in r["evenements"]:
			if e["type"] == "brique_detruite":
				briques_cassees += 1
			if e["type"] == "rebond_raquette":
				rebonds += 1
		if not s.est_valide():
			fails.append("etat invalide au tick %d" % t)
			break
		t += 1

	if s.statut != State.Statut.GAGNE:
		fails.append("session solo n'atteint pas la victoire (statut=%d)" % s.statut)
	if briques_cassees <= 0:
		fails.append("aucune brique cassee sur la session")
	if rebonds <= 0:
		fails.append("aucun rebond raquette sur la session")

	# Relance en un geste -> etat neuf identique au boot.
	var neuf = Restart.relancer(1)
	if not neuf.egal_profond(Boot.etat_initial(1)):
		fails.append("relance != boot neuf")

	print("ORACLE solo_session: %s (briques=%d rebonds=%d ticks=%d)" % [("PASS" if fails.is_empty() else "FAIL"), briques_cassees, rebonds, t])
	for f in fails:
		print("  FAIL: ", f)
	quit(0 if fails.is_empty() else 1)
