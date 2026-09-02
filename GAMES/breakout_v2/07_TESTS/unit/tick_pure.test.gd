# tick_pure.test.gd — ligne core.main_loop. Le tick est PUR : il ne mute pas l'entree, il est
# deterministe, il avance d'exactement 1 tick, et il est inerte sur un etat terminal.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

func run(h) -> void:
	# --- purete : l'etat d'entree n'est PAS mute ---
	var s = State.initial(1)
	var snap = s.clone()
	var r: Dictionary = Loop.step(s, 1)
	h.ok(s.egal_profond(snap), "step ne mute PAS l'etat d'entree (clone)")
	h.ok(r["evenements"] is Array, "step renvoie une liste d'evenements")

	# --- avance de 1 tick ---
	h.eq(r["etat"].ticks, s.ticks + 1, "un step avance ticks de EXACTEMENT 1")

	# --- determinisme : meme etat + meme action -> resultat strictement identique ---
	var a = Loop.step(State.initial(7), 1)["etat"]
	var b = Loop.step(State.initial(7), 1)["etat"]
	h.ok(a.egal_profond(b), "meme etat + action -> etat resultant identique (deterministe)")

	# --- inerte sur un etat terminal ---
	var t = State.initial(1)
	t.statut = State.Statut.GAGNE
	var rt: Dictionary = Loop.step(t, 1)
	h.eq(rt["etat"].ticks, t.ticks, "etat terminal -> ticks inchanges (step inerte)")
	h.eq(rt["evenements"].size(), 0, "etat terminal -> aucun evenement")

	# ============================================================================
	# DURCISSEMENT MUTATION — loop.gd _touche_raquette : bornes STRICTES du contact
	# raquette (charter : jamais un >= tautologique ; le contact est une regle DURABLE,
	# pas une valeur figee). Le predicat pur est teste directement a ses bornes.
	# ============================================================================
	# (borne <= sur vy, return false) balle NON descendante -> aucun contact, meme alignee.
	var g0 = State.initial(1)
	g0.ball_vel = Vector2(120.0, 0.0)   # vy == 0 : ne descend pas (borne <=, pas <)
	g0.ball_pos = Vector2(g0.paddle_x, P.raquette_y())
	h.eq(Loop._touche_raquette(g0), false, "vy==0 (balle non descendante) -> aucun contact raquette")
	var g1 = State.initial(1)
	g1.ball_vel = Vector2(0.0, -120.0)  # vy < 0 : monte
	g1.ball_pos = Vector2(g1.paddle_x, P.raquette_y())
	h.eq(Loop._touche_raquette(g1), false, "balle montante (vy<0) -> aucun contact raquette (return false)")
	# (return false, balle passee SOUS le bas de la raquette) -> aucun contact.
	var g2 = State.initial(1)
	g2.ball_vel = Vector2(0.0, 120.0)   # descend
	g2.ball_pos = Vector2(g2.paddle_x, P.raquette_y() + P.RAQUETTE_HAUTEUR + P.BALLE_RAYON + 2.0)
	h.eq(Loop._touche_raquette(g2), false, "balle sous le bas de la raquette -> aucun contact (return false)")
	# (borne <= sur la portee horizontale) contact au bord EXACT (distance == demi_largeur+rayon).
	var g3 = State.initial(1)
	g3.ball_vel = Vector2(0.0, 120.0)
	var hw3 = P.raquette_demi_largeur()
	g3.ball_pos = Vector2(g3.paddle_x + hw3 + P.BALLE_RAYON, P.raquette_y())
	h.eq(Loop._touche_raquette(g3), true, "contact au bord horizontal exact (== demi_largeur+rayon) -> vrai (borne <=)")
	var g4 = State.initial(1)
	g4.ball_vel = Vector2(0.0, 120.0)
	g4.ball_pos = Vector2(g4.paddle_x + hw3 + P.BALLE_RAYON + 1.0, P.raquette_y())
	h.eq(Loop._touche_raquette(g4), false, "juste au-dela du bord horizontal -> aucun contact")
