# negative_control.gd — oracle (bot_action) de la ligne proof.negative_control_bot. Sans
# controle negatif, un taux de victoire eleve ne prouve rien (leçon oracle_solvability_lesson).
# On mesure : le bot d'INTERCEPTION gagne STRICTEMENT plus que les bots naifs (camp-centre,
# suivi sans anticipation), prouves INSUFFISANTS. Determinisme pur, aucun alea.
extends SceneTree

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const Interc = preload("res://06_RUNTIME/adapters/solvability_bot/interception_bot.gd")
const Naive = preload("res://06_RUNTIME/adapters/solvability_bot/naive_bots.gd")

const SEEDS := 7
const MAX_TICKS := 10000

func _victoires(mode: String) -> int:
	var n := 0
	for graine in range(1, SEEDS + 1):
		var s = State.initial(graine)
		var t := 0
		while t < MAX_TICKS and s.statut == State.Statut.EN_COURS:
			var a: int
			match mode:
				"interception": a = Interc.choisir_action(s)
				"centre": a = Naive.action_camp_centre(s)
				_: a = Naive.action_suivi_naif(s)
			s = Loop.step(s, a)["etat"]
			t += 1
		if s.statut == State.Statut.GAGNE:
			n += 1
	return n

func _initialize() -> void:
	var fails: Array = []
	var interc := _victoires("interception")
	var centre := _victoires("centre")
	var naif := _victoires("suivi")

	if not (interc > centre):
		fails.append("interception (%d) PAS strictement > camp-centre (%d)" % [interc, centre])
	if not (interc > naif):
		fails.append("interception (%d) PAS strictement > suivi-naif (%d)" % [interc, naif])
	if interc != SEEDS:
		fails.append("le bot d'interception ne gagne pas tous les seeds (%d/%d)" % [interc, SEEDS])

	print("ORACLE negative_control: %s (interception=%d/%d, camp_centre=%d, suivi_naif=%d)" % [
		("PASS" if fails.is_empty() else "FAIL"), interc, SEEDS, centre, naif])
	for f in fails:
		print("  FAIL: ", f)
	quit(0 if fails.is_empty() else 1)
