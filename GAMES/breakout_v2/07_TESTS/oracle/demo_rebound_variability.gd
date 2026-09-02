# demo_rebound_variability.gd — oracle (bot_action) de la ligne render.rebound_variability.
# VARIANCE PROUVEE : sur une vraie partie, l'angle de rebond raquette prend >= 2 valeurs
# DISTINCTES non triviales (l'angle depend reellement du point d'impact, pas un rebond fige).
extends SceneTree

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const Interc = preload("res://06_RUNTIME/adapters/solvability_bot/interception_bot.gd")

func _initialize() -> void:
	var fails: Array = []
	var offsets := {}
	var vx_apres := {}

	var s = State.initial(1)
	var t := 0
	while t < 4000 and s.statut == State.Statut.EN_COURS:
		var r: Dictionary = Loop.step(s, Interc.choisir_action(s))
		for e in r["evenements"]:
			if e["type"] == "rebond_raquette":
				offsets[snappedf(e["offset"], 0.001)] = true
				vx_apres[snappedf(r["etat"].ball_vel.x, 0.01)] = true
		s = r["etat"]
		t += 1

	if offsets.size() < 2:
		fails.append("angle de rebond non variable : %d valeur(s) d'offset distincte(s) (< 2)" % offsets.size())
	if vx_apres.size() < 2:
		fails.append("vitesse horizontale post-rebond non variable : %d valeur(s) (< 2)" % vx_apres.size())

	print("FORGE_ORACLE demo_rebound_variability " + JSON.stringify({
		"ok": fails.is_empty(), "fails": fails,
		"data": {"offsets_distincts": offsets.size(), "vx_distincts": vx_apres.size(), "seuil": 2}}))
	quit(0 if fails.is_empty() else 1)
