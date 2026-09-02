# boot_zero_gesture.test.gd — ligne runtime.immediate_start. Au boot, l'etat jouable est
# atteint sans aucun geste ni ecran intercale ; la balle bouge deja (demarrage immediat).
extends RefCounted

const Boot = preload("res://06_RUNTIME/adapters/runtime_loop/boot.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Ball = preload("res://05_SYSTEMS/game_state/ball.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

func run(h) -> void:
	h.eq(Boot.GESTES_AVANT_DEMARRAGE, 0, "0 geste avant demarrage")
	h.eq(Boot.ECRANS_INTERCALES, 0, "0 ecran intercale")

	var e = Boot.etat_initial(P.SEED_REFERENCE)
	h.eq(e.statut, State.Statut.EN_COURS, "boot -> etat EN_COURS immediat")
	h.ok(e.est_valide(), "etat de boot structurellement valide")
	h.eq(e.ball_vel, Ball.vitesse_service(), "balle deja lancee au boot (aucun appui requis)")
	h.ok(e.ball_vel.length() > 0.0, "la balle bouge DES le boot (demarrage immediat)")
