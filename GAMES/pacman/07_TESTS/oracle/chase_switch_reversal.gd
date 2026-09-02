# chase_switch_reversal.gd — ligne chase.switch_reversal, capacite F29.
# Releves au tick PRECEDANT le seuil et au tick DU seuil : la direction de chaque
# fantome hors maison s'est INVERSEE. C'est ce qui rend la bascule perceptible.
extends RefCounted

const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")
const Ghosts = preload("res://05_SYSTEMS/ghost_movement/ghost_movement.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/bot_driver.gd")


func run(h) -> void:
	# Fonction pure d'inversion, valeurs exactes.
	h.eq(Chase.inverser(Maze.HAUT), Maze.BAS, "chase.reversal: haut s'inverse en bas")
	h.eq(Chase.inverser(Maze.GAUCHE), Maze.DROITE, "chase.reversal: gauche s'inverse en droite")
	h.eq(Chase.inverser(Chase.inverser(Maze.HAUT)), Maze.HAUT, "chase.reversal: l'inversion est involutive")

	# Inversion collective : seuls les fantomes DEHORS sont inverses.
	var f = State.initial(Maze, 1)
	f.dirs_fantomes = [Maze.HAUT, Maze.GAUCHE, Maze.BAS, Maze.DROITE]
	f.dehors = [true, false, true, false]
	Ghosts.inverser_tous(f)
	h.eq(f.dirs_fantomes[0], Maze.BAS, "chase.reversal: le fantome dehors est inverse")
	h.eq(f.dirs_fantomes[1], Maze.GAUCHE, "chase.reversal: le fantome en maison n'est pas inverse")
	h.eq(f.dirs_fantomes[2], Maze.HAUT, "chase.reversal: deuxieme fantome dehors inverse")
	h.eq(f.dirs_fantomes[3], Maze.DROITE, "chase.reversal: deuxieme fantome en maison intact")

	# SUR UNE PARTIE : au premier seuil de l'horloge, les directions s'inversent.
	var premier_seuil: int = Chase.seuils()[0]
	var s = State.initial(Maze, 1)
	# Les quatre sont dehors des le depart pour que la mesure porte sur les quatre.
	for i in range(4):
		s.dehors[i] = true
		s.sorties_maison[i] = 0
	var avant: Array = []
	var apres: Array = []
	var horloge_au_seuil: int = -1
	# Boucle BORNEE, pilotee par le BOT sur le canal public : un Pac-Man immobile serait
	# pris bien avant le premier seuil, et la perte de vie remettrait l'horloge a zero —
	# on mesurerait alors la mort, pas la bascule.
	for _t in range(premier_seuil + 50):
		if s.statut != State.Statut.EN_COURS:
			break
		var dirs_avant: Array = s.dirs_fantomes.duplicate()
		s = Loop.step(s, Bot.choisir_action(s))["etat"]
		if Chase.est_seuil(s.horloge):
			avant = dirs_avant
			apres = s.dirs_fantomes.duplicate()
			horloge_au_seuil = s.horloge
			break
	h.eq(horloge_au_seuil, premier_seuil, "chase.reversal: la fixture atteint bien le premier seuil")
	h.eq(avant.size(), 4, "chase.reversal: releve des quatre directions au tick precedent")
	h.eq(apres.size(), 4, "chase.reversal: releve des quatre directions au tick du seuil")

	# Chaque fantome hors maison a change de direction au tick du seuil. Il peut avoir
	# ensuite choisi une autre sortie : l'assertion porte donc sur le CHANGEMENT, qui est
	# le fait observable, et sur l'inversion effective d'au moins un fantome.
	var inchanges: int = 0
	var inverses: int = 0
	for i in range(4):
		if avant[i] == apres[i]:
			inchanges += 1
		if apres[i] == Chase.inverser(avant[i]):
			inverses += 1
	h.eq(inchanges, 0, "chase.reversal: aucun fantome hors maison ne garde sa direction au seuil")
	h.gt(inverses, 0, "chase.reversal: au moins un fantome porte exactement la direction inverse")

	# Le mode a bien BASCULE a ce tick : la mesure porte sur un vrai seuil.
	h.ok(Chase.mode_global(premier_seuil) != Chase.mode_global(premier_seuil - 1),
		"chase.reversal: le mode a bascule au tick mesure")

	# HORS SEUIL, aucune inversion collective n'a lieu.
	var t = State.initial(Maze, 1)
	for i in range(4):
		t.dehors[i] = true
		t.sorties_maison[i] = 0
	t = Loop.step(t, Bot.choisir_action(t))["etat"]
	var avant_hors: Array = t.dirs_fantomes.duplicate()
	var t2 = Loop.step(t, Bot.choisir_action(t))["etat"]
	var inversions_hors_seuil: int = 0
	for i in range(4):
		if t2.dirs_fantomes[i] == Chase.inverser(avant_hors[i]):
			inversions_hors_seuil += 1
	h.eq(Chase.est_seuil(t2.ticks), false, "chase.reversal: le tick temoin n'est pas un seuil")
	h.eq(inversions_hors_seuil, 0, "chase.reversal: aucune inversion hors des seuils")
