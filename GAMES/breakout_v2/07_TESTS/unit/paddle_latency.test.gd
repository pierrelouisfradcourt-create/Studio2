# paddle_latency.test.gd — ligne input.paddle_responsive. Un input deplace la raquette DES le
# meme tick (latence 0) ; gauche et droite -> effets opposes distincts ; AUCUNE -> immobile.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const Paddle = preload("res://05_SYSTEMS/game_state/paddle.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

func run(h) -> void:
	var s = State.initial(1)
	var x0: float = s.paddle_x

	# DROITE : deplacement immediat, EXACTEMENT vitesse_max*dt borne (le meme tick).
	var xd: float = Loop.step(s, 1)["etat"].paddle_x
	h.ok(xd != x0, "input DROITE deplace la raquette DES le meme tick (latence 0)")
	h.eq(xd, Paddle.deplacer(x0, 1, P.dt_s()), "deplacement immediat = Paddle.deplacer(+1)")

	# GAUCHE : effet oppose, distinct de droite.
	var xg: float = Loop.step(s, -1)["etat"].paddle_x
	h.ok(xg != x0, "input GAUCHE deplace la raquette DES le meme tick")
	h.ok(xg != xd, "gauche et droite -> positions distinctes")

	# AUCUNE : immobile le meme tick.
	h.eq(Loop.step(s, 0)["etat"].paddle_x, x0, "AUCUNE -> raquette immobile")
