# core_boot.gd — oracle (bot_action) de la ligne core.boot. Au lancement, l'etat jouable est
# atteint SANS geste ni ecran intercale, statut EN_COURS, balle deja en mouvement.
extends SceneTree

const Boot = preload("res://06_RUNTIME/adapters/runtime_loop/boot.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")

func _initialize() -> void:
	var fails: Array = []
	if Boot.GESTES_AVANT_DEMARRAGE != 0:
		fails.append("GESTES_AVANT_DEMARRAGE != 0")
	if Boot.ECRANS_INTERCALES != 0:
		fails.append("ECRANS_INTERCALES != 0")
	var e = Boot.etat_initial(1)
	if e.statut != State.Statut.EN_COURS:
		fails.append("boot: statut != EN_COURS")
	if not e.est_valide():
		fails.append("boot: etat invalide")
	if not (e.ball_vel.length() > 0.0):
		fails.append("boot: la balle ne bouge pas")
	print("ORACLE core_boot: %s" % ("PASS" if fails.is_empty() else "FAIL"))
	for f in fails:
		print("  FAIL: ", f)
	quit(0 if fails.is_empty() else 1)
