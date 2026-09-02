# score_single_mutation_point.gd — ligne score.mutation_point, capacite F33.
# Le score LU a l'ecran est egal a la valeur de score de l'etat au meme tick, apres
# CHAQUE evenement : les deux descendent d'un point de mutation UNIQUE.
extends RefCounted

const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())

const Score = preload("res://05_SYSTEMS/score/score.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const Hud = preload("res://06_RUNTIME/adapters/presentation/hud.gd")
const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/bot_driver.gd")


func run(h) -> void:
	# Le point de mutation applique EXACTEMENT ce qu'on lui donne, et rien d'autre.
	var s = State.initial(Maze, 1)
	h.eq(s.score, 0, "score.mutation: score a zero au depart")
	Score.ajouter(s, 10)
	h.eq(s.score, 10, "score.mutation: +10 exactement")
	Score.ajouter(s, 50)
	h.eq(s.score, 60, "score.mutation: +50 exactement, cumule")
	Score.ajouter(s, 0)
	h.eq(s.score, 60, "score.mutation: +0 ne change rien")

	# SUR UNE PARTIE PILOTEE : a chaque tick, le chiffre affiche EGALE le chiffre d'etat.
	var jeu = State.initial(Maze, 1)
	var divergences: int = 0
	var evenements_vus: int = 0
	var score_precedent: int = 0
	for _t in range(400):
		if jeu.statut != State.Statut.EN_COURS:
			break
		var sortie: Dictionary = Loop.step(jeu, Bot.choisir_action(jeu))
		jeu = sortie["etat"]
		if sortie["evenements"].size() > 0:
			evenements_vus += 1
		var releve: Dictionary = Observable.projeter(jeu)
		var affiche: int = Hud.relire(Hud.ligne(releve), Hud.ETIQUETTE_SCORE)
		if affiche != jeu.score:
			divergences += 1
		score_precedent = jeu.score
	h.gt(evenements_vus, 0, "score.mutation: des evenements ont reellement eu lieu")
	h.eq(divergences, 0, "score.mutation: 0 divergence entre le chiffre affiche et l'etat sur 400 ticks")
	h.gt(score_precedent, 0, "score.mutation: le score a reellement progresse")

	# Le score expose est le MEME objet que le score d'etat : la projection ne recalcule
	# rien. Une valeur forcee dans l'etat se retrouve telle quelle a l'ecran.
	jeu.score = 12345
	var releve2: Dictionary = Observable.projeter(jeu)
	h.eq(releve2["score"], 12345, "score.mutation: la projection recopie le score d'etat")
	h.eq(Hud.relire(Hud.ligne(releve2), Hud.ETIQUETTE_SCORE), 12345,
		"score.mutation: le HUD relit exactement la valeur d'etat")

	# Le score ne DECROIT jamais : aucun autre chemin ne le modifie.
	var k = State.initial(Maze, 2)
	var decroissances: int = 0
	var precedent: int = k.score
	for _t in range(200):
		if k.statut != State.Statut.EN_COURS:
			break
		k = Loop.step(k, Bot.choisir_action(k))["etat"]
		if k.score < precedent:
			decroissances += 1
		precedent = k.score
	h.eq(decroissances, 0, "score.mutation: le score ne decroit jamais sur 200 ticks")
