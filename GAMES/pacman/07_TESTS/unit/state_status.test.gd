# state_status.test.gd — ligne state.status, capacite F4.
# Le statut expose appartient a l'ensemble des trois valeurs a CHAQUE tick et APRES la
# derniere iteration de la boucle, sur les trois issues.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Status = preload("res://05_SYSTEMS/game_state/status.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")


func run(h) -> void:
	h.eq(State.STATUTS_VALIDES.size(), 3, "state.status: trois statuts exactement")

	# Vocabulaire ferme, exclusif et exhaustif.
	h.eq(Status.nom(State.Statut.EN_COURS), "EN COURS", "state.status: nom EN COURS")
	h.eq(Status.nom(State.Statut.GAGNE), "GAGNE", "state.status: nom GAGNE")
	h.eq(Status.nom(State.Statut.PERDU), "PERDU", "state.status: nom PERDU")

	# ISSUE 1 — partie en cours : statut valide a chaque tick.
	var s = State.initial(Maze, 1)
	var hors: int = 0
	for _t in range(120):
		s = Loop.step(s, Maze.AUCUNE)["etat"]
		if not (s.statut in State.STATUTS_VALIDES):
			hors += 1
	h.eq(hors, 0, "state.status: statut valide a chaque tick d'une partie en cours")

	# ISSUE 2 — victoire : le statut est GAGNE, exactement.
	var g = State.initial(Maze, 1)
	g.consommees = g.total_pose
	h.eq(Status.appliquer(g), State.Statut.GAGNE, "state.status: issue victoire")
	h.ok(g.statut in State.STATUTS_VALIDES, "state.status: la victoire est dans le vocabulaire")

	# ISSUE 3 — defaite : le statut est PERDU, exactement.
	var p = State.initial(Maze, 1)
	p.vies = 0
	h.eq(Status.appliquer(p), State.Statut.PERDU, "state.status: issue defaite")
	h.ok(p.statut in State.STATUTS_VALIDES, "state.status: la defaite est dans le vocabulaire")

	# APRES la derniere iteration : un tick joue sur un etat terminal n'efface pas le
	# statut et ne relance pas la partie.
	var apres_fin = Loop.step(g, Maze.GAUCHE)["etat"]
	h.eq(apres_fin.statut, State.Statut.GAGNE, "state.status: le statut terminal survit a un tick de plus")
	h.eq(apres_fin.ticks, g.ticks, "state.status: aucun tick n'est consomme apres la fin")
	var apres_fin2 = Loop.step(p, Maze.GAUCHE)["etat"]
	h.eq(apres_fin2.statut, State.Statut.PERDU, "state.status: le statut PERDU survit a un tick de plus")

	# Le statut est EXPOSE, avec son nom lisible.
	var releve: Dictionary = Observable.projeter(g)
	h.eq(releve["statut"], State.Statut.GAGNE, "state.status: statut expose")
	h.eq(releve["statut_nom"], "GAGNE", "state.status: nom expose")

	# Les trois statuts sont mutuellement EXCLUSIFS : aucun etat n'en porte deux.
	var doubles: int = 0
	for v in [State.Statut.EN_COURS, State.Statut.GAGNE, State.Statut.PERDU]:
		var compte: int = 0
		for w in State.STATUTS_VALIDES:
			if v == w:
				compte += 1
		if compte != 1:
			doubles += 1
	h.eq(doubles, 0, "state.status: chaque statut apparait une seule fois")
