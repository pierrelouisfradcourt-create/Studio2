# input_restart_key.gd — ligne input.restart_key, capacite F49.
# Une SEULE pression de touche depuis l'ecran de fin, SANS menu intermediaire ni relance
# de l'application : au tick suivant, le statut expose vaut EN COURS.
extends RefCounted

const InputAdapter = preload("res://06_RUNTIME/adapters/input_adapter/input_adapter.gd")
const Restart = preload("res://05_SYSTEMS/game_state/restart.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Status = preload("res://05_SYSTEMS/game_state/status.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const EndScreen = preload("res://06_RUNTIME/adapters/presentation/end_screen.gd")
const Boot = preload("res://06_RUNTIME/adapters/runtime_loop/boot.gd")


func run(h) -> void:
	# La touche de relance appartient au vocabulaire ferme des commandes.
	h.eq(InputAdapter.est_relance(KEY_R), true, "input.restart: R relance")
	h.eq(InputAdapter.est_relance(KEY_SPACE), true, "input.restart: espace relance")
	h.eq(InputAdapter.est_relance(KEY_UP), false, "input.restart: une direction ne relance pas")
	h.eq(InputAdapter.est_relance(KEY_F7), false, "input.restart: une touche non liee ne relance pas")
	h.eq(InputAdapter.est_sortie(KEY_ESCAPE), true, "input.restart: echap est la commande de sortie")
	h.eq(InputAdapter.est_sortie(KEY_R), false, "input.restart: R n'est pas la sortie")

	# Fin de partie atteinte, ecran de fin ACTIF.
	var jeu = State.initial(Maze, 1)
	for _t in range(40):
		jeu = Loop.step(jeu, Maze.GAUCHE)["etat"]
	jeu.vies = 0
	Status.appliquer(jeu)
	h.eq(EndScreen.est_actif(jeu.statut), true, "input.restart: l'ecran de fin est affiche")
	h.eq(Observable.projeter(jeu)["statut_nom"], "PERDU", "input.restart: l'issue est nommee")

	# UNE SEULE pression, AUCUN menu intermediaire : la relance est immediate.
	h.eq(InputAdapter.est_relance(KEY_R), true, "input.restart: la pression est reconnue")
	var neuf = Restart.relancer(Maze, Boot.GRAINE_INITIALE)
	h.eq(Observable.projeter(neuf)["statut_nom"], "EN COURS",
		"input.restart: au tick suivant, le statut expose vaut EN COURS")

	# SANS relance de l'application : la partie neuve avance immediatement.
	var apres = Loop.step(neuf, Maze.GAUCHE)["etat"]
	h.eq(apres.ticks, 1, "input.restart: la partie neuve joue son premier tick")
	h.eq(apres.statut, State.Statut.EN_COURS, "input.restart: elle reste EN COURS")

	# Le clavier est TOUJOURS pris en compte apres l'affichage de l'ecran de fin : la
	# commande n'est pas inerte (defaut « Quitter inerte », playtest Pong 2026-07-27).
	h.ok(EndScreen.recap(Observable.projeter(jeu)).contains(EndScreen.MENTION_RELANCE),
		"input.restart: l'ecran de fin annonce la relance")
	h.eq(neuf.consommees, 0, "input.restart: la partie relancee est neuve")
	h.eq(neuf.score, 0, "input.restart: score remis a zero par la relance")
