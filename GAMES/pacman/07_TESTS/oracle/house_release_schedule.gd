# house_release_schedule.gd — ligne house.release_schedule, capacite F23.
# Etat au tick 0 : EXACTEMENT un fantome est hors de la maison et c'est le ROUGE ; les
# trois autres en sortent a des ticks STRICTEMENT CROISSANTS et declares ; au terme du
# dernier delai, les quatre sont dehors.
extends RefCounted

const House = preload("res://05_SYSTEMS/ghost_house/ghost_house.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Targeting = preload("res://05_SYSTEMS/ghost_targeting/ghost_targeting.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/bot_driver.gd")


func run(h) -> void:
	# Delais DECLARES et strictement croissants.
	h.eq(House.DELAIS_SORTIE.size(), 4, "house.release: quatre delais declares")
	h.eq(House.DELAIS_SORTIE[0], 0, "house.release: le rouge sort au tick 0")
	var non_croissants: int = 0
	for i in range(1, House.DELAIS_SORTIE.size()):
		if not (House.DELAIS_SORTIE[i] > House.DELAIS_SORTIE[i - 1]):
			non_croissants += 1
	h.eq(non_croissants, 0, "house.release: delais STRICTEMENT croissants")

	# ETAT AU TICK 0 : exactement un fantome dehors, et c'est le rouge.
	var s = State.initial(Maze, 1)
	var releve: Dictionary = Observable.projeter(s)
	var dehors: int = 0
	for d in releve["dehors"]:
		if d:
			dehors += 1
	h.eq(dehors, 1, "house.release: EXACTEMENT un fantome dehors au tick 0")
	h.eq(releve["dehors"][Targeting.ROUGE], true, "house.release: et c'est le rouge")
	h.eq(releve["dehors"][Targeting.ROSE], false, "house.release: le rose est dedans")
	h.eq(releve["dehors"][Targeting.CYAN], false, "house.release: le cyan est dedans")
	h.eq(releve["dehors"][Targeting.ORANGE], false, "house.release: l'orange est dedans")

	# Sorties observees, tick par tick : chacune au tick DECLARE, ni avant ni apres.
	# La partie est pilotee par le bot sur le CANAL PUBLIC : un Pac-Man immobile se
	# ferait prendre avant le dernier delai, et une perte de vie remettrait tous les
	# delais a zero — on mesurerait alors la mort, pas le calendrier de sortie.
	var sorties: Array = [0, -1, -1, -1]
	var dernier: int = House.DELAIS_SORTIE[3]
	var vies_depart: int = s.vies
	var dehors_simultanes_max: int = 1
	for t in range(1, dernier + 200):
		s = Loop.step(s, Bot.choisir_action(s))["etat"]
		var simultanes: int = 0
		for i in range(4):
			if s.dehors[i]:
				simultanes += 1
			if i > 0 and sorties[i] < 0 and s.dehors[i]:
				sorties[i] = t
		if simultanes > dehors_simultanes_max:
			dehors_simultanes_max = simultanes
		if simultanes == 4:
			break
	h.eq(sorties[1], House.DELAIS_SORTIE[1], "house.release: le rose sort au tick declare")
	h.eq(sorties[2], House.DELAIS_SORTIE[2], "house.release: le cyan sort au tick declare")
	h.eq(sorties[3], House.DELAIS_SORTIE[3], "house.release: l'orange sort au tick declare")
	var non_croissants_observes: int = 0
	for i in range(1, sorties.size()):
		if not (sorties[i] > sorties[i - 1]):
			non_croissants_observes += 1
	h.eq(non_croissants_observes, 0, "house.release: sorties observees strictement croissantes")

	# Au terme du dernier delai, les QUATRE ont ete dehors SIMULTANEMENT. La mesure porte
	# sur le maximum atteint : un fantome CAPTURE par Pac-Man retourne legitimement en
	# maison, et compter l'etat du dernier tick confondrait « jamais sorti » et
	# « sorti puis capture ».
	h.eq(dehors_simultanes_max, 4, "house.release: les quatre sont dehors au terme du dernier delai")
	h.eq(s.vies, vies_depart, "house.release: aucune vie perdue pendant la mesure")

	# Chacun sort PAR la sortie de maison declaree, et cette case est praticable.
	h.eq(Maze.praticable(Maze.SORTIE_MAISON), true, "house.release: la sortie de maison est praticable")
	h.eq(Maze.type_case(Maze.MAISON_CENTRE), Maze.Type.MAISON, "house.release: le centre est bien la maison")
