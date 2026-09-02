# replay_determinism.gd — oracle (test) de la ligne proof.replay_determinism. A etat initial,
# seed et SEQUENCE D'ENTREES identiques, deux executions produisent un etat final STRICTEMENT
# identique. La sequence est assez longue pour inclure plusieurs rebonds raquette ET plusieurs
# briques detruites (point dur : pas de temps fixe, aucune horloge).
extends SceneTree

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const Interc = preload("res://06_RUNTIME/adapters/solvability_bot/interception_bot.gd")

const N := 2500

func _initialize() -> void:
	var fails: Array = []

	# Run 1 : bot deterministe, on ENREGISTRE la sequence d'actions ET on compte les evenements.
	var s1 = State.initial(1)
	var actions: Array = []
	var rebonds := 0
	var briques := 0
	for _i in range(N):
		if s1.statut != State.Statut.EN_COURS:
			break
		var a: int = Interc.choisir_action(s1)
		actions.append(a)
		var r: Dictionary = Loop.step(s1, a)
		s1 = r["etat"]
		for e in r["evenements"]:
			if e["type"] == "rebond_raquette":
				rebonds += 1
			if e["type"] == "brique_detruite":
				briques += 1

	# Run 2 : REJOUE la sequence enregistree (entrees fixes), meme seed.
	var s2 = State.initial(1)
	for a in actions:
		if s2.statut != State.Statut.EN_COURS:
			break
		s2 = Loop.step(s2, a)["etat"]

	if not s1.egal_profond(s2):
		fails.append("etats finaux differents a sequence identique (non deterministe)")
	if rebonds < 2:
		fails.append("sequence trop courte : %d rebonds raquette (< 2)" % rebonds)
	if briques < 2:
		fails.append("sequence trop courte : %d briques detruites (< 2)" % briques)

	print("ORACLE replay_determinism: %s (rebonds=%d briques=%d)" % [
		("PASS" if fails.is_empty() else "FAIL"), rebonds, briques])
	for f in fails:
		print("  FAIL: ", f)
	quit(0 if fails.is_empty() else 1)
