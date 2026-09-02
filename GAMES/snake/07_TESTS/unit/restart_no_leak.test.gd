# restart_no_leak.test.gd — ligne core.restart. Apres relance : score=0, longueur=
# longueur initiale, ticks=0, paliers=0, periode=initiale, statut=en cours (STRICT) ;
# aucun champ de l'etat de partie ne survit d'une partie a l'autre.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Restart = preload("res://05_SYSTEMS/game_state/restart.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const DR = preload("res://05_SYSTEMS/input_rules/direction_rules.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

func run(h) -> void:
	# Joue une partie jusqu'a la mort, puis relance.
	var s = State.initial(50)
	s.segments = [Vector2i(0, 5), Vector2i(1, 5), Vector2i(2, 5)]
	s.longueur = 3
	s.dir_effectuee = DR.GAUCHE
	s.dir_en_attente = DR.GAUCHE
	s.nourriture = Vector2i(10, 10)
	s.score = 7
	s.fruits = 3
	s.ticks = 40
	var apres_mort = Loop.step(s, Loop.AUCUNE)["etat"]
	h.eq(apres_mort.statut, State.Statut.TERMINE_PERDU, "partie perdue avant relance")

	var neuf = Restart.relancer(50)
	# Egalites STRICTES sur l'etat initial.
	h.eq(neuf.score, 0, "relance : score = 0")
	h.eq(neuf.longueur, P.LONGUEUR_INITIALE, "relance : longueur = longueur initiale")
	h.eq(neuf.ticks, 0, "relance : ticks = 0")
	h.eq(neuf.palier, 0, "relance : paliers = 0")
	h.eq(neuf.fruits, 0, "relance : fruits = 0")
	h.eq(neuf.periode, P.VITESSE_INITIALE_MS, "relance : periode = initiale")
	h.eq(neuf.statut, State.Statut.EN_COURS, "relance : statut = en cours")

	# Aucun champ de l'ancienne partie ne survit : etat neuf == etat initial de graine.
	var reference = State.initial(50)
	h.ok(neuf.egal_profond(reference), "relance = etat initial pur (0 champ survivant)")
	# Le meilleur score ne fait pas partie de l'etat de partie (aucun champ a comparer).
	h.ok(not ("meilleur_score" in neuf), "le record ne vit pas dans l'etat de partie")
