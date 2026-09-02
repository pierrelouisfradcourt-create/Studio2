# paddle_bounds.test.gd — ligne state.paddle. La raquette se borne EXACTEMENT aux limites du
# terrain (jamais au-dela, jamais en deca par arrondi) et ne bouge que sur l'axe horizontal.
extends RefCounted

const Paddle = preload("res://05_SYSTEMS/game_state/paddle.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

func run(h) -> void:
	var dt := P.dt_s()
	h.eq(Paddle.borne_min(), P.raquette_demi_largeur(), "borne min = demi-largeur")
	h.eq(Paddle.borne_max(), P.TERRAIN_LARGEUR - P.raquette_demi_largeur(), "borne max = largeur - demi-largeur")

	# N >= 1000 actions vers la droite -> position EXACTEMENT a la borne max.
	var x := P.TERRAIN_LARGEUR / 2.0
	var hors := 0
	for _i in range(1000):
		x = Paddle.deplacer(x, 1, dt)
		if x < Paddle.borne_min() or x > Paddle.borne_max():
			hors += 1
	h.eq(x, Paddle.borne_max(), "1000 DROITE -> position = borne max exacte")
	h.eq(hors, 0, "0 position hors borne sur 1000 actions droite")

	# N >= 1000 actions vers la gauche -> borne min exacte.
	x = P.TERRAIN_LARGEUR / 2.0
	for _i in range(1000):
		x = Paddle.deplacer(x, -1, dt)
		if x < Paddle.borne_min() or x > Paddle.borne_max():
			hors += 1
	h.eq(x, Paddle.borne_min(), "1000 GAUCHE -> position = borne min exacte")
	h.eq(hors, 0, "0 position hors borne sur 2000 actions")

	# Action AUCUNE -> immobile (0 deplacement).
	var x0 := 200.0
	h.eq(Paddle.deplacer(x0, 0, dt), x0, "action AUCUNE -> raquette immobile")
