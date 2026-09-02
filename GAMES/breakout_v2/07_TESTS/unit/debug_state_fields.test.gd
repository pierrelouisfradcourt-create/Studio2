# debug_state_fields.test.gd — ligne debug.observation_point. Projection PURE de l'etat vers
# EXACTEMENT les 6 champs nommes du charter, valeurs fideles, sans effet de bord.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Debug = preload("res://05_SYSTEMS/debug_state/debug_state.gd")

func run(h) -> void:
	var s = State.initial(42)
	var d: Dictionary = Debug.projeter(s)

	# --- exactement 6 champs, tous nommes ---
	h.eq(d.size(), 6, "EXACTEMENT 6 champs d'observation")
	h.eq(d.has("balle_pos"), true, "champ balle_pos")
	h.eq(d.has("balle_vel"), true, "champ balle_vel")
	h.eq(d.has("raquette_x"), true, "champ raquette_x")
	h.eq(d.has("briques_restantes"), true, "champ briques_restantes")
	h.eq(d.has("vies"), true, "champ vies")
	h.eq(d.has("statut"), true, "champ statut")

	# --- valeurs fideles a l'etat ---
	h.eq(d["balle_pos"], s.ball_pos, "balle_pos fidele")
	h.eq(d["balle_vel"], s.ball_vel, "balle_vel fidele")
	h.eq(d["raquette_x"], s.paddle_x, "raquette_x fidele")
	h.eq(d["briques_restantes"], s.briques_restantes, "briques_restantes fidele")
	h.eq(d["vies"], s.vies, "vies fidele")
	h.eq(d["statut"], s.statut, "statut fidele")

	# --- sans effet de bord : deux projections consecutives identiques, etat inchange ---
	var snap = s.clone()
	var d2: Dictionary = Debug.projeter(s)
	h.eq(d["balle_pos"], d2["balle_pos"], "deux projections identiques (pas d'effet de bord)")
	h.ok(s.egal_profond(snap), "projeter ne mute pas l'etat")
