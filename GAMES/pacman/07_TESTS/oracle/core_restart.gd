# core_restart.gd — ligne CORE core.restart.
# Apres une fin de partie, une SEULE pression relance : score = 0, vies = valeur
# initiale, consommes = 0, restantes = total pose, ticks = 0, horloge au premier segment,
# rang de capture a la premiere valeur, statut = EN COURS (egalites STRICTES).
# Le nombre de champs de l'etat de partie qui SURVIVENT d'une partie a l'autre est
# EXACTEMENT 0.
extends RefCounted

const Restart = preload("res://05_SYSTEMS/game_state/restart.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Status = preload("res://05_SYSTEMS/game_state/status.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const InputAdapter = preload("res://06_RUNTIME/adapters/input_adapter/input_adapter.gd")
const Boot = preload("res://06_RUNTIME/adapters/runtime_loop/boot.gd")
const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/bot_driver.gd")


func run(h) -> void:
	# Une partie REELLEMENT jouee, menee a une fin de partie.
	var jouee = State.initial(Maze, 1)
	for _t in range(200):
		jouee = Loop.step(jouee, Bot.choisir_action(jouee))["etat"]
	jouee.vies = 0
	Status.appliquer(jouee)
	h.eq(Status.est_terminal(jouee.statut), true, "core.restart: la partie precedente est terminee")
	h.gt(jouee.score, 0, "core.restart: elle avait accumule un score")
	h.gt(jouee.consommees, 0, "core.restart: elle avait consomme des collectibles")
	h.gt(jouee.ticks, 0, "core.restart: elle avait avance dans le temps")

	# UNE SEULE PRESSION relance.
	h.eq(InputAdapter.est_relance(KEY_R), true, "core.restart: une seule touche suffit")
	var neuf = Restart.relancer(Maze, Boot.GRAINE_INITIALE)

	# EGALITES STRICTES, champ par champ.
	var reference = State.initial(Maze, Boot.GRAINE_INITIALE)
	h.eq(neuf.score, 0, "core.restart: score = 0")
	h.eq(neuf.vies, reference.vies, "core.restart: vies = valeur initiale declaree")
	h.eq(neuf.consommees, 0, "core.restart: consommes = 0")
	h.eq(neuf.total_pose - neuf.consommees, neuf.total_pose, "core.restart: restantes = total pose")
	h.eq(neuf.ticks, 0, "core.restart: ticks = 0")
	h.eq(neuf.horloge, 0, "core.restart: horloge au premier segment")
	h.eq(neuf.rang_capture, 0, "core.restart: rang de capture a la premiere valeur")
	h.eq(neuf.statut, State.Statut.EN_COURS, "core.restart: statut = EN COURS")
	h.eq(neuf.effraye_restant, 0, "core.restart: aucune fenetre Effraye active")
	h.eq(neuf.pac, Maze.DEPART_PACMAN, "core.restart: Pac-Man a sa case de depart")
	h.eq(neuf.pac_dir, Maze.DEPART_DIRECTION, "core.restart: direction de depart")
	h.eq(neuf.pac_attente, Maze.AUCUNE, "core.restart: aucune demande en attente")
	h.eq(neuf.dehors, reference.dehors, "core.restart: la maison repart de son etat declare")
	h.eq(neuf.rng_etat, reference.rng_etat, "core.restart: le generateur repart de sa graine")

	# ZERO CHAMP SURVIVANT : l'egalite profonde avec un etat neuf le constate d'un coup.
	h.eq(neuf.egal_profond(reference), true, "core.restart: 0 champ ne survit d'une partie a l'autre")
	h.eq(Restart.aucune_fuite(neuf, Maze, Boot.GRAINE_INITIALE), true, "core.restart: aucune fuite constatee")

	# Constate depuis l'ETAT EXPOSE, pas seulement depuis l'etat interne.
	var releve: Dictionary = Observable.projeter(neuf)
	h.eq(releve["score"], 0, "core.restart: score 0 expose")
	h.eq(releve["restantes"], neuf.total_pose, "core.restart: restantes exposees au total pose")
	h.eq(releve["statut_nom"], "EN COURS", "core.restart: statut EN COURS expose")
	h.eq(releve["tick"], 0, "core.restart: tick 0 expose")

	# La partie relancee est REELLEMENT jouable.
	var apres = Loop.step(neuf, Bot.choisir_action(neuf))["etat"]
	h.eq(apres.ticks, 1, "core.restart: la partie relancee avance")
	h.eq(apres.statut, State.Statut.EN_COURS, "core.restart: elle reste jouable")

	# CONTRE-EPREUVE : le detecteur de fuite REFUSE un etat pollue, champ par champ.
	for champ in ["score", "consommees", "ticks", "horloge", "rang_capture"]:
		var pollue = Restart.relancer(Maze, Boot.GRAINE_INITIALE)
		pollue.set(champ, 1)
		h.eq(Restart.aucune_fuite(pollue, Maze, Boot.GRAINE_INITIALE), false,
			"core.restart: une fuite du champ %s est detectee" % champ)
