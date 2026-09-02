# demo_solo_session.gd — oracle du volet observable demo_solo_session (ligne runtime.solo_session).
# Protocole FORGE_ORACLE lu par product_oracle_godot.py. Sonde CREEE au run 3 : la wiremap
# nommait le volet `demo_solo_session` mais aucun fichier de ce nom n'existait dans 07_TESTS/oracle/
# (l'oracle voisin solo_session.gd portait un nom different et emettait l'ancien protocole). La
# LOGIQUE testee est celle, deja en place, de solo_session.gd — une session complete par le seul
# canal public : boot -> jeu (rebonds raquette + briques detruites) -> statut terminal -> relance
# == boot neuf, etat valide a chaque tick. Seuils alignes sur l'expected_proof de la wiremap
# (au moins 3 rebonds raquette, au moins 5 briques detruites) : plancher de session substantielle,
# pas une egalite (le compte varie avec le jeu). Aucun module ajoute.
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
		fails.append("session solo n'atteint pas un statut terminal de victoire (statut=%d)" % s.statut)
	if rebonds < 3:
		fails.append("moins de 3 rebonds raquette sur la session (%d)" % rebonds)
	if briques_cassees < 5:
		fails.append("moins de 5 briques detruites sur la session (%d)" % briques_cassees)

	# Relance en un geste -> etat neuf identique au boot.
	var neuf = Restart.relancer(1)
	if not neuf.egal_profond(Boot.etat_initial(1)):
		fails.append("relance != boot neuf")

	var ok: bool = fails.is_empty()
	print("FORGE_ORACLE demo_solo_session " + JSON.stringify({
		"ok": ok, "fails": fails,
		"data": {"briques_cassees": briques_cassees, "rebonds": rebonds, "ticks": t, "statut_final": s.statut}}))
	quit(0 if ok else 1)
