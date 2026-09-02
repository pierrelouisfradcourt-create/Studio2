# ghosts_cadence.gd — ligne ghosts.cadence, capacite F22.
# Sur une fenetre DECLAREE de ticks, chacun des quatre fantomes sortis de la maison a
# change de position au moins une fois par cycle de deplacement.
#
# CORRECTION M3 : la cadence est CHIFFREE dans le bloc unique de parametres, et la
# contrainte dure (« le fantome est TOUJOURS strictement plus lent que Pac-Man ») est
# asseree ici, cycle par cycle.
extends RefCounted

const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const Ghosts = preload("res://05_SYSTEMS/ghost_movement/ghost_movement.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")
const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/bot_driver.gd")


func run(h) -> void:
	# La cadence est une fonction PURE du tick : un fantome saute EXACTEMENT un tick par
	# periode declaree.
	var mobiles: int = 0
	for t in range(1, P.CADENCE_FANTOME_PERIODE + 1):
		if Ghosts.bouge_ce_tick(t, false, 0):
			mobiles += 1
	h.eq(mobiles, P.CADENCE_FANTOME_PERIODE - 1, "ghosts.cadence: 19 ticks mobiles sur 20")
	h.lt(mobiles, P.CADENCE_FANTOME_PERIODE,
		"ghosts.cadence: STRICTEMENT moins mobile que Pac-Man, qui avance a chaque tick")
	h.eq(Ghosts.bouge_ce_tick(P.CADENCE_FANTOME_PERIODE, false, 0), false,
		"ghosts.cadence: le tick saute est celui de la periode")

	# En etat Effraye, la cadence est encore plus lente.
	var mobiles_effraye: int = 0
	for t in range(1, P.CADENCE_FANTOME_PERIODE + 1):
		if Ghosts.bouge_ce_tick(t, true, 0):
			mobiles_effraye += 1
	h.eq(mobiles_effraye, P.CADENCE_FANTOME_PERIODE / P.CADENCE_EFFRAYE_PERIODE,
		"ghosts.cadence: un tick sur deux en Effraye")
	h.lt(mobiles_effraye, mobiles, "ghosts.cadence: Effraye est STRICTEMENT plus lent que la poursuite")

	# La contrainte dure est declaree ET tenue : le ratio est strictement inferieur a 1.
	h.lt(int(P.RATIO_VITESSE_FANTOME * 100), 100, "ghosts.cadence: ratio declare strictement < 1")
	h.eq(int(P.RATIO_VITESSE_FANTOME * 100), 95, "ghosts.cadence: ratio declare a 95 %")

	# SUR UNE PARTIE : chacun des quatre fantomes SORTIS a change de position au moins
	# une fois par cycle de deplacement.
	var s = State.initial(Maze, 6)
	# Partie pilotee par le bot sur le canal public : un Pac-Man immobile mourrait avant
	# la sortie du quatrieme fantome et la mesure porterait sur autre chose.
	var vies_depart: int = s.vies
	var dehors_simultanes_max: int = 1
	for _t in range(200):
		s = Loop.step(s, Bot.choisir_action(s))["etat"]
		var simultanes: int = 0
		for d in s.dehors:
			if d:
				simultanes += 1
		if simultanes > dehors_simultanes_max:
			dehors_simultanes_max = simultanes
		if simultanes == 4:
			break
	h.eq(s.vies, vies_depart, "ghosts.cadence: aucune vie perdue avant la mesure")
	h.eq(dehors_simultanes_max, 4, "ghosts.cadence: les quatre fantomes sont sortis")

	var immobiles_sur_un_cycle: int = 0
	for _cycle in range(3):
		var avant: Array = s.fantomes.duplicate()
		for _t in range(P.CADENCE_FANTOME_PERIODE):
			s = Loop.step(s, Bot.choisir_action(s))["etat"]
		for i in range(4):
			if s.dehors[i] and s.fantomes[i] == avant[i]:
				immobiles_sur_un_cycle += 1
	h.eq(immobiles_sur_un_cycle, 0,
		"ghosts.cadence: aucun fantome dehors n'est immobile sur un cycle de deplacement")
