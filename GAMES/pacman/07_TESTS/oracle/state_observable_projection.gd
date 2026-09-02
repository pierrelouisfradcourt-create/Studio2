# state_observable_projection.gd — ligne state.observable_projection, capacite F2.
# Les TROIS nombres du releve observable (score, pastilles restantes, vies) sont EGAUX
# aux valeurs de l'etat de partie au meme tick, apres CHAQUE evenement.
extends RefCounted

const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())

const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/bot_driver.gd")


func run(h) -> void:
	var s = State.initial(Maze, 1)
	var releve: Dictionary = Observable.projeter(s)

	# Les cles du releve sont un vocabulaire FERME et complet.
	var manquantes: int = 0
	for cle in Observable.CLES:
		if not releve.has(cle):
			manquantes += 1
	h.eq(manquantes, 0, "state.observable: toutes les cles declarees sont presentes")
	# V2 : cinq cles s ajoutent (niveau, carte, mode de jeu, dash actif, recharge du dash).
	h.eq(Observable.CLES.size(), 22, "state.observable: vingt-deux cles declarees")

	# Les trois nombres, au tick 0.
	h.eq(releve["score"], s.score, "state.observable: score egal a l'etat")
	h.eq(releve["vies"], s.vies, "state.observable: vies egales a l'etat")
	h.eq(releve["restantes"], s.total_pose - s.consommees, "state.observable: restantes egales a l'etat")

	# APRES CHAQUE EVENEMENT d'une partie pilotee : les trois nombres restent egaux.
	var jeu = State.initial(Maze, 1)
	var divergences: int = 0
	var evenements: int = 0
	for _t in range(400):
		if jeu.statut != State.Statut.EN_COURS:
			break
		var sortie: Dictionary = Loop.step(jeu, Bot.choisir_action(jeu))
		jeu = sortie["etat"]
		if sortie["evenements"].size() == 0:
			continue
		evenements += 1
		var r: Dictionary = Observable.projeter(jeu)
		if r["score"] != jeu.score:
			divergences += 1
		if r["vies"] != jeu.vies:
			divergences += 1
		if r["restantes"] != jeu.total_pose - jeu.consommees:
			divergences += 1
	h.gt(evenements, 0, "state.observable: des evenements ont reellement eu lieu")
	h.eq(divergences, 0, "state.observable: 0 divergence apres chaque evenement")

	# La projection ne CALCULE rien de neuf : elle recopie. Une valeur forcee dans l'etat
	# se retrouve telle quelle dans le releve.
	jeu.score = 777
	jeu.vies = 2
	h.eq(Observable.projeter(jeu)["score"], 777, "state.observable: le score est recopie")
	h.eq(Observable.projeter(jeu)["vies"], 2, "state.observable: les vies sont recopiees")

	# Aucune structure PARALLELE : deux projections du meme etat sont egales.
	h.eq(Observable.egaux(Observable.projeter(jeu), Observable.projeter(jeu)), true,
		"state.observable: la projection est pure et reproductible")

	# Le comparateur de releves DETECTE une difference — sans quoi il ne prouverait rien.
	var autre = jeu.clone()
	autre.score = 778
	h.eq(Observable.egaux(Observable.projeter(jeu), Observable.projeter(autre)), false,
		"state.observable: le comparateur detecte une divergence")
