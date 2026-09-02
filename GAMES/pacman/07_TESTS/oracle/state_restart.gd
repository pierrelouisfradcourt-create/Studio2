# state_restart.gd — ligne state.restart, capacite F41.
# Une SEULE pression de touche depuis l'ecran de fin : au tick suivant, le statut expose
# vaut EN COURS et le labyrinthe est de nouveau REMPLI de collectibles.
extends RefCounted

const Restart = preload("res://05_SYSTEMS/game_state/restart.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Status = preload("res://05_SYSTEMS/game_state/status.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const Pellets = preload("res://05_SYSTEMS/pellets/pellets.gd")
const InputAdapter = preload("res://06_RUNTIME/adapters/input_adapter/input_adapter.gd")
const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/bot_driver.gd")


func run(h) -> void:
	# Partie reellement jouee, puis menee a une fin de partie.
	var jeu = State.initial(Maze, 1)
	for _t in range(150):
		jeu = Loop.step(jeu, Bot.choisir_action(jeu))["etat"]
	jeu.vies = 0
	Status.appliquer(jeu)
	h.eq(Status.est_terminal(jeu.statut), true, "state.restart: la partie est bien terminee")
	h.gt(jeu.consommees, 0, "state.restart: des collectibles avaient ete consommes")
	h.gt(jeu.score, 0, "state.restart: un score avait ete accumule")

	# UNE SEULE pression de touche relance — le canal public la reconnait.
	h.eq(InputAdapter.est_relance(KEY_R), true, "state.restart: la touche R est une relance")
	var neuf = Restart.relancer(Maze, 1)

	# Au tick suivant : statut EN COURS et labyrinthe de nouveau REMPLI.
	var releve: Dictionary = Observable.projeter(neuf)
	h.eq(releve["statut_nom"], "EN COURS", "state.restart: le statut expose vaut EN COURS")
	h.eq(releve["restantes"], neuf.total_pose, "state.restart: le labyrinthe est de nouveau rempli")
	h.eq(Pellets.total_pose(neuf.pastilles), 244, "state.restart: les 244 collectibles sont reposes")

	# RECONSTRUCTION INTEGRALE : aucun champ de la partie precedente ne survit.
	h.eq(Restart.aucune_fuite(neuf, Maze, 1), true, "state.restart: aucun champ ne fuit")
	h.eq(neuf.score, 0, "state.restart: score remis a zero")
	h.eq(neuf.vies, State.initial(Maze, 1).vies, "state.restart: vies remises a leur valeur initiale")
	h.eq(neuf.consommees, 0, "state.restart: aucun collectible consomme")
	h.eq(neuf.ticks, 0, "state.restart: compteur de ticks a zero")
	h.eq(neuf.horloge, 0, "state.restart: horloge au premier segment")
	h.eq(neuf.rang_capture, 0, "state.restart: rang de capture a la premiere valeur")
	h.eq(neuf.pac, Maze.DEPART_PACMAN, "state.restart: Pac-Man a sa case de depart")
	h.eq(neuf.effraye_restant, 0, "state.restart: aucune fenetre Effraye active")

	# La partie relancee est REJOUABLE : elle avance normalement.
	var apres = Loop.step(neuf, Maze.GAUCHE)["etat"]
	h.eq(apres.ticks, 1, "state.restart: la partie relancee avance")
	h.eq(apres.statut, State.Statut.EN_COURS, "state.restart: elle reste EN COURS")

	# CONTRE-EPREUVE : le detecteur de fuite REFUSE un etat qui ne serait pas neuf.
	var pollue = Restart.relancer(Maze, 1)
	pollue.score = 1
	h.eq(Restart.aucune_fuite(pollue, Maze, 1), false, "state.restart: une fuite de score est detectee")
