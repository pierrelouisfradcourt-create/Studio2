# ball_kinematics.test.gd — ligne state.ball. Position et vitesse sont des flottants a 2
# composantes ; un pas libre = position + vitesse*dt (STRICT) ; aucune action ne touche la balle.
extends RefCounted

const Ball = preload("res://05_SYSTEMS/game_state/ball.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")

func run(h) -> void:
	# Deux composantes flottantes.
	var ps = Ball.position_service()
	var vs = Ball.vitesse_service()
	h.ok(ps is Vector2, "position de service est un Vector2")
	h.ok(vs is Vector2, "vitesse de service est un Vector2")
	h.eq(vs.length(), P.BALLE_VITESSE_INITIALE, "vitesse de service = vitesse initiale (norme)")

	# Pas libre STRICT : p' == p + v*dt (egalite bit-a-bit, sur les DEUX composantes).
	# L'enonce du charter est « position + vitesse*dt » : la valeur attendue EST cette
	# expression Vector2 (domaine flottant du moteur, real_t), jamais un litteral f64 recopie
	# (un 123.8 ecrit a la main serait un f64 != du real_t produit -> faux echec de precision).
	var pos := Vector2(123.0, 77.0)
	var vel := Vector2(50.0, -30.0)
	var dt := P.dt_s()
	var attendu := pos + vel * dt
	var suivant := Ball.pas_libre(pos, vel, dt)
	h.eq(suivant.x, attendu.x, "x' == x + vx*dt (strict, composante x)")
	h.eq(suivant.y, attendu.y, "y' == y + vy*dt (strict, composante y)")
	h.eq(suivant, attendu, "p' == p + v*dt (forme Vector2)")
	# Cas EXACTEMENT representable (dt=0.5, produits entiers) : valeur concrete non
	# tautologique -> tue un mutant qui renverrait pos, ou pos-v*dt, ou un facteur different.
	h.eq(Ball.pas_libre(Vector2(100.0, 50.0), Vector2(20.0, -8.0), 0.5), Vector2(110.0, 46.0),
		"pas_libre valeur exacte : (100,50)+(20,-8)*0.5 == (110,46)")

	# Aucune action ne modifie la balle : deux actions distinctes -> meme balle ce tick.
	var s = State.initial(1)
	var gauche = Loop.step(s, -1)["etat"]
	var droite = Loop.step(s, 1)["etat"]
	var aucune = Loop.step(s, 0)["etat"]
	h.eq(gauche.ball_pos, aucune.ball_pos, "action GAUCHE ne change pas la balle")
	h.eq(droite.ball_pos, aucune.ball_pos, "action DROITE ne change pas la balle")
	h.eq(gauche.ball_vel, aucune.ball_vel, "action GAUCHE ne change pas la vitesse de balle")
	h.ok(gauche.paddle_x != droite.paddle_x, "les actions DEPLACENT bien la raquette (controle)")
