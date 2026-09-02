# life_loss_serve.test.gd — ligne life.loss_and_serve. Perte de vie a la sortie basse
# (-1 EXACT), remise en jeu s'il reste des vies, aucune remise a la derniere vie perdue.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Life = preload("res://05_SYSTEMS/life_rules/life_rules.gd")
const Ball = preload("res://05_SYSTEMS/game_state/ball.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

func _sous_terrain() -> Vector2:
	return Vector2(320.0, P.TERRAIN_HAUTEUR + P.BALLE_RAYON + 5.0)

func run(h) -> void:
	# --- detection de sortie basse ---
	h.eq(Life.balle_perdue(Vector2(320.0, 240.0)), false, "balle en jeu -> non perdue")
	h.eq(Life.balle_perdue(_sous_terrain()), true, "balle sous le terrain -> perdue")
	# la limite basse pile au niveau du sol ne compte pas encore comme perdue.
	h.eq(Life.balle_perdue(Vector2(320.0, P.TERRAIN_HAUTEUR)), false, "balle au ras du sol -> pas encore perdue")

	# --- balle en jeu : perdre_et_servir ne change rien ---
	var s0 = State.initial(1)
	var v0: int = s0.vies
	h.eq(Life.perdre_et_servir(s0), false, "balle en jeu -> aucune perte")
	h.eq(s0.vies, v0, "vies inchangees")

	# --- perte avec vies restantes : -1 exact, balle reservie ---
	var s1 = State.initial(1)
	s1.ball_pos = _sous_terrain()
	var av: int = s1.vies
	h.eq(Life.perdre_et_servir(s1), true, "balle perdue -> true")
	h.eq(s1.vies, av - 1, "vies -1 EXACT")
	h.eq(s1.ball_pos, Ball.position_service(), "balle remise a la position de service")
	h.eq(s1.ball_vel, Ball.vitesse_service(), "vitesse remise au service")

	# --- derniere vie perdue : vies 0, aucune remise en jeu ---
	var s2 = State.initial(1)
	s2.vies = 1
	s2.ball_pos = _sous_terrain()
	h.eq(Life.perdre_et_servir(s2), true, "derniere balle perdue -> true")
	h.eq(s2.vies, 0, "vies 0 apres derniere perte")
	# la balle n'est pas remise a la position de service (elle reste sous le terrain).
	h.eq(s2.ball_pos, _sous_terrain(), "aucune remise en jeu a 0 vie")
