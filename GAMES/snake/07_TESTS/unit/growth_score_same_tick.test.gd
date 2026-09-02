# growth_score_same_tick.test.gd — ligne core.growth_score. Sur la fixture tete-sur-
# nourriture : longueur = avant + 1 ET score = avant + points, au MEME tick, sans tick
# intercale ; le franchissement d'un palier se produit a ce meme tick.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const DR = preload("res://05_SYSTEMS/input_rules/direction_rules.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")
const TickRate = preload("res://05_SYSTEMS/tick_rate/tick_rate.gd")

func run(h) -> void:
	# Tete en (5,5) allant a droite, nourriture juste devant en (6,5).
	var s = State.initial(3)
	s.segments = [Vector2i(5, 5), Vector2i(4, 5), Vector2i(3, 5)]
	s.longueur = 3
	s.dir_effectuee = DR.DROITE
	s.dir_en_attente = DR.DROITE
	s.nourriture = Vector2i(6, 5)
	s.score = 0
	s.fruits = 0
	var r = Loop.step(s, Loop.AUCUNE)
	var e = r["etat"]
	# DEUX egalites STRICTES au meme tick.
	h.eq(e.longueur, 3 + 1, "longueur = avant + 1 (croissance)")
	h.eq(e.score, 0 + P.POINTS_PAR_NOURRITURE, "score = avant + points")
	h.eq(e.fruits, 1, "fruits = 1")
	h.eq(e.ticks, 1, "un seul tick applique (pas de tick intercale)")
	# La queue n'a PAS ete retiree (croissance) : les 4 segments sont presents.
	h.eq(e.segments.size(), 4, "les 4 segments presents (queue conservee)")
	h.eq(e.segments[0], Vector2i(6, 5), "tete sur l'ancienne nourriture")

	# Franchissement de palier au MEME tick que la consommation : fruits passe de 4 a 5.
	var s2 = State.initial(3)
	s2.segments = [Vector2i(5, 5), Vector2i(4, 5), Vector2i(3, 5)]
	s2.longueur = 3
	s2.dir_effectuee = DR.DROITE
	s2.dir_en_attente = DR.DROITE
	s2.nourriture = Vector2i(6, 5)
	s2.fruits = 4
	s2.palier = TickRate.palier(4)  # = 0
	s2.periode = TickRate.periode(4)  # = 200
	var r2 = Loop.step(s2, Loop.AUCUNE)
	var e2 = r2["etat"]
	h.eq(e2.fruits, 5, "fruits = 5 apres consommation")
	h.eq(e2.palier, 1, "palier passe a 1 au meme tick")
	h.ok(is_equal_approx(e2.periode, 184.0), "periode recalculee a 184 au meme tick")
	# L'evenement palier_franchi est present a ce tick.
	var a_palier := false
	for ev in r2["evenements"]:
		if ev["type"] == "palier_franchi":
			a_palier = true
	h.eq(a_palier, true, "evenement palier_franchi emis au tick de consommation")
