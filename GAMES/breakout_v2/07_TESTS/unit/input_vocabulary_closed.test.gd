# input_vocabulary_closed.test.gd — ligne input.closed_vocabulary. Vocabulaire FERME de
# EXACTEMENT 3 actions ; toute autre valeur n'est pas une action ; appliquer ne touche que la
# raquette.
extends RefCounted

const InputRules = preload("res://05_SYSTEMS/input_rules/input_rules.gd")
const Paddle = preload("res://05_SYSTEMS/game_state/paddle.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

func run(h) -> void:
	# --- vocabulaire ferme : exactement 3 valeurs, nommees ---
	h.eq(InputRules.VOCABULAIRE.size(), 3, "vocabulaire = EXACTEMENT 3 actions")
	h.eq(InputRules.GAUCHE, -1, "GAUCHE = -1")
	h.eq(InputRules.AUCUNE, 0, "AUCUNE = 0")
	h.eq(InputRules.DROITE, 1, "DROITE = 1")

	# --- appartenance ---
	h.eq(InputRules.est_action(-1), true, "-1 est une action")
	h.eq(InputRules.est_action(0), true, "0 est une action")
	h.eq(InputRules.est_action(1), true, "1 est une action")
	h.eq(InputRules.est_action(2), false, "2 hors vocabulaire")
	h.eq(InputRules.est_action(-2), false, "-2 hors vocabulaire")
	h.eq(InputRules.est_action(99), false, "99 hors vocabulaire")

	# --- appliquer : delegue au bornage de la raquette (le joueur ne touche que la raquette) ---
	var dt := P.dt_s()
	var x0 := 300.0
	h.eq(InputRules.appliquer(x0, 0, dt), x0, "AUCUNE -> raquette immobile (strict)")
	h.eq(InputRules.appliquer(x0, 1, dt), Paddle.deplacer(x0, 1, dt), "DROITE == Paddle.deplacer(+1)")
	h.eq(InputRules.appliquer(x0, -1, dt), Paddle.deplacer(x0, -1, dt), "GAUCHE == Paddle.deplacer(-1)")
	h.ok(InputRules.appliquer(x0, 1, dt) != InputRules.appliquer(x0, -1, dt), "gauche et droite -> positions distinctes")
