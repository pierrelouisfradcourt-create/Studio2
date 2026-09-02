# render_end_screen.gd — ligne render.end_screen, capacite F48.
# Deux releves, une partie GAGNEE et une partie PERDUE : les textes d'issue DIFFERENT,
# le score final affiche est EGAL au score d'etat, et une pression au clavier est encore
# prise en compte apres l'affichage.
extends RefCounted

const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())

const EndScreen = preload("res://06_RUNTIME/adapters/presentation/end_screen.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Status = preload("res://05_SYSTEMS/game_state/status.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const InputAdapter = preload("res://06_RUNTIME/adapters/input_adapter/input_adapter.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/bot_driver.gd")


func run(h) -> void:
	# L'ecran de fin n'est actif QUE sur un statut terminal.
	h.eq(EndScreen.est_actif(State.Statut.EN_COURS), false, "render.end: inactif en cours de partie")
	h.eq(EndScreen.est_actif(State.Statut.GAGNE), true, "render.end: actif sur victoire")
	h.eq(EndScreen.est_actif(State.Statut.PERDU), true, "render.end: actif sur defaite")

	# Les deux textes d'issue DIFFERENT.
	h.ok(EndScreen.message(State.Statut.GAGNE) != EndScreen.message(State.Statut.PERDU),
		"render.end: les textes d'issue different")
	h.eq(EndScreen.message(State.Statut.GAGNE), EndScreen.MESSAGE_GAGNE, "render.end: texte de victoire")
	h.eq(EndScreen.message(State.Statut.PERDU), EndScreen.MESSAGE_PERDU, "render.end: texte de defaite")
	h.eq(EndScreen.message(State.Statut.EN_COURS), "", "render.end: aucun texte en cours de partie")

	# PARTIE JOUEE puis menee a la VICTOIRE : le score final affiche EGALE le score d'etat.
	var gagnee = State.initial(Maze, 1)
	for _t in range(120):
		gagnee = Loop.step(gagnee, Bot.choisir_action(gagnee))["etat"]
	gagnee.consommees = gagnee.total_pose
	Status.appliquer(gagnee)
	var r_gagnee: Dictionary = Observable.projeter(gagnee)
	var texte_gagnee: String = EndScreen.recap(r_gagnee)
	h.ok(texte_gagnee.contains(EndScreen.MESSAGE_GAGNE), "render.end: l'issue GAGNE est nommee")
	h.ok(texte_gagnee.contains(str(gagnee.score)), "render.end: le score final affiche egale l'etat")
	h.gt(gagnee.score, 0, "render.end: un score reel a ete accumule")

	# PARTIE PERDUE : texte different, score final egal a l'etat.
	var perdue = State.initial(Maze, 2)
	for _t in range(120):
		perdue = Loop.step(perdue, Bot.choisir_action(perdue))["etat"]
	perdue.vies = 0
	Status.appliquer(perdue)
	var texte_perdue: String = EndScreen.recap(Observable.projeter(perdue))
	h.ok(texte_perdue.contains(EndScreen.MESSAGE_PERDU), "render.end: l'issue PERDU est nommee")
	h.ok(texte_perdue.contains(str(perdue.score)), "render.end: le score final de la partie perdue")
	h.ok(texte_gagnee != texte_perdue, "render.end: les deux ecrans de fin different")

	# UNE PRESSION AU CLAVIER EST ENCORE PRISE EN COMPTE apres l'affichage : l'ecran
	# annonce la relance ET la touche est reconnue par le canal public.
	h.ok(texte_gagnee.contains(EndScreen.MENTION_RELANCE), "render.end: la relance est annoncee")
	h.ok(texte_perdue.contains(EndScreen.MENTION_RELANCE), "render.end: annoncee aussi en defaite")
	h.eq(InputAdapter.est_relance(KEY_R), true, "render.end: la touche de relance est reconnue apres la fin")
	h.eq(InputAdapter.est_sortie(KEY_ESCAPE), true, "render.end: la touche de sortie est reconnue apres la fin")

	# Aucun recapitulatif tant que la partie n'est pas terminee.
	h.eq(EndScreen.recap(Observable.projeter(State.initial(Maze, 1))), "",
		"render.end: aucun recapitulatif en cours de partie")
