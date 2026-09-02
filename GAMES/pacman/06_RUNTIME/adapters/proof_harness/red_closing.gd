# red_closing.gd — rapprochement STRICT du fantome rouge (ligne harness.red_ghost_closing).
#
# Protocole IMPOSE : Pac-Man est ARRETE contre un mur et aucune entree n'est injectee.
# Un joueur qui bouge rend la mesure ambigue — la distance pourrait decroitre parce que
# le joueur s'approche, pas parce que le fantome poursuit.
#
# Fixture de MESURE : Pac-Man est place au bout du couloir droit du bas (ligne 32),
# direction droite, mur immediatement a sa droite ; le fantome rouge est place a l'autre
# bout du meme couloir ; les trois autres fantomes restent dans la maison.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const Maze = preload("res://05_SYSTEMS/maze/maze.gd")
const Targeting = preload("res://05_SYSTEMS/ghost_targeting/ghost_targeting.gd")

const GRAINE_MESURE: int = 11
const LIGNE_COULOIR: int = 32
const PAC_X: int = 26
const ROUGE_X: int = 1
# Fenetre : assez courte pour que le fantome n'ait pas encore atteint Pac-Man (le
# contact arreterait la mesure et la rendrait ininterpretable).
const FENETRE: int = 15


static func fixture(carte) -> Object:
	var s = State.initial(carte, GRAINE_MESURE)
	s.pac = Vector2i(PAC_X, LIGNE_COULOIR)
	s.pac_dir = Maze.DROITE
	s.pac_attente = Maze.AUCUNE
	s.fantomes[Targeting.ROUGE] = Vector2i(ROUGE_X, LIGNE_COULOIR)
	s.dirs_fantomes[Targeting.ROUGE] = Maze.DROITE
	s.dehors[Targeting.ROUGE] = true
	for i in range(1, s.fantomes.size()):
		s.dehors[i] = false
		s.fantomes[i] = carte.PLACES_MAISON[i]
		s.sorties_maison[i] = FENETRE + 1
	return s


# Suite des distances Pac-Man / rouge relevees a chaque DEPLACEMENT du fantome (jamais
# a chaque tick : le fantome saute un tick sur vingt, un tick sans deplacement ne dit
# rien du rapprochement).
static func distances(carte) -> Array:
	var s = fixture(carte)
	var suite: Array = []
	var precedente: Vector2i = s.fantomes[Targeting.ROUGE]
	suite.append(Targeting.distance(s.pac, precedente))
	for _t in range(FENETRE):
		s = Loop.step(s, Maze.AUCUNE)["etat"]
		var courante: Vector2i = s.fantomes[Targeting.ROUGE]
		if courante != precedente:
			suite.append(Targeting.distance(s.pac, courante))
			precedente = courante
	return suite


# Nombre de deplacements du fantome qui n'ont PAS strictement reduit la distance.
static func non_decroissances(suite: Array) -> int:
	var n: int = 0
	for i in range(1, suite.size()):
		if not (suite[i] < suite[i - 1]):
			n += 1
	return n


# La position de Pac-Man est-elle restee STRICTEMENT immobile sur la fenetre ?
static func pac_immobile(carte) -> bool:
	var s = fixture(carte)
	var depart: Vector2i = s.pac
	for _t in range(FENETRE):
		s = Loop.step(s, Maze.AUCUNE)["etat"]
		if s.pac != depart:
			return false
	return true


static func mesurer(carte) -> Dictionary:
	var suite: Array = distances(carte)
	return {
		"deplacements": suite.size() - 1,
		"non_decroissances": non_decroissances(suite),
		"distance_debut": suite[0],
		"distance_fin": suite[suite.size() - 1],
		"pac_immobile": pac_immobile(carte),
	}
