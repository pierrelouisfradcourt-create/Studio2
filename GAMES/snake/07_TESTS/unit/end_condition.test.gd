# end_condition.test.gd — ligne core.end_condition. Lorsque la longueur atteint la cible,
# le statut vaut EXACTEMENT termine-gagne ; apres passage dans un statut terminal, le
# compteur de ticks reste STRICTEMENT EGAL a sa valeur au moment du passage.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const End = preload("res://05_SYSTEMS/game_state/end_condition.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const DR = preload("res://05_SYSTEMS/input_rules/direction_rules.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

func run(h) -> void:
	# Bornes STRICTES de la cible de victoire.
	h.eq(End.est_gagne(P.CIBLE_VICTOIRE - 1), false, "longueur cible-1 : pas encore gagne")
	h.eq(End.est_gagne(P.CIBLE_VICTOIRE), true, "longueur = cible : gagne")
	h.eq(End.est_gagne(P.CIBLE_VICTOIRE + 1), true, "longueur > cible : gagne")

	# Serpent serpentin de longueur cible-1 (24), tete en (16,1), qui va manger la
	# nourriture en (15,1) et atteindre la cible (25) au meme tick.
	var segs := [Vector2i(16, 1), Vector2i(17, 1), Vector2i(18, 1), Vector2i(19, 1), Vector2i(19, 0)]
	for x in range(18, -1, -1):
		segs.append(Vector2i(x, 0))
	h.eq(segs.size(), P.CIBLE_VICTOIRE - 1, "serpent de longueur cible-1 construit")
	var s = State.initial(4)
	s.segments = segs
	s.longueur = segs.size()
	s.dir_effectuee = DR.GAUCHE
	s.dir_en_attente = DR.GAUCHE
	s.nourriture = Vector2i(15, 1)
	h.ok(s.est_valide(), "etat pre-victoire valide")
	var r = Loop.step(s, Loop.AUCUNE)
	var e = r["etat"]
	h.eq(e.longueur, P.CIBLE_VICTOIRE, "longueur atteint la cible")
	h.eq(e.statut, State.Statut.TERMINE_GAGNE, "statut = termine-gagne EXACTEMENT")

	# Apres le statut terminal, aucun tick supplementaire n'est applique (gel).
	var ticks_au_passage = e.ticks
	var apres = e
	for i in range(10):
		apres = Loop.step(apres, DR.HAUT)["etat"]
	h.eq(apres.ticks, ticks_au_passage, "ticks STRICTEMENT egaux apres le passage terminal")
	h.eq(apres.statut, State.Statut.TERMINE_GAGNE, "statut terminal conserve apres attente")

	# Mort par collision -> termine-perdu, distinct de gagne.
	var d = State.initial(4)
	d.segments = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	d.longueur = 3
	d.dir_effectuee = DR.GAUCHE
	d.dir_en_attente = DR.GAUCHE
	d.nourriture = Vector2i(10, 10)
	var rd = Loop.step(d, Loop.AUCUNE)["etat"]
	h.eq(rd.statut, State.Statut.TERMINE_PERDU, "collision -> termine-perdu")
