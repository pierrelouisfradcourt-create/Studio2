# v2_progression_reset_rest.test.gd — ligne progression.reset_rest, capacite F106.
# Declare EXACTEMENT ce qui repart. Complementaire strict de ce qui survit : ensemble,
# les deux ferment la question « qu'est-ce qui traverse la bascule ? » sans zone grise.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Progression = preload("res://05_SYSTEMS/level_progression/level_progression.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))
var Alt = MazeClass.depuis_descripteur(ContentV2.descripteur(1))


func run(h) -> void:
	# Les deux declarations sont COMPLEMENTAIRES et DISJOINTES.
	var chevauchement: int = 0
	for c in Progression.CONSERVES:
		if Progression.REINITIALISES.has(c):
			chevauchement += 1
	h.eq(chevauchement, 0, "progression.reset: aucune grandeur a la fois conservee et remise")
	h.gt(Progression.REINITIALISES.size(), 0, "progression.reset: des grandeurs sont declarees remises")

	# Etat bien avance, puis bascule.
	var jeu = State.initial(Maze, 5)
	for _t in range(50):
		jeu = Loop.step(jeu, Maze.DEPART_DIRECTION)["etat"]
	jeu.rang_capture = 2
	var suite = Progression.basculer(jeu, Alt, ContentV2.cadence(1), 5)

	h.eq(suite.consommees, 0, "progression.reset: les collectibles repartent")
	h.eq(suite.total_pose, State.initial(Alt, 1).total_pose, "progression.reset: total de la carte suivante")
	h.eq(suite.pac, Alt.DEPART_PACMAN, "progression.reset: position de depart de la carte suivante")
	h.eq(suite.horloge, 0, "progression.reset: horloge a sa phase initiale")
	h.eq(suite.rang_capture, 0, "progression.reset: rang de capture a sa premiere valeur")
	h.eq(suite.ticks, 0, "progression.reset: compteur de ticks du niveau remis")
	h.ok(suite.rng_etat != jeu.rng_etat, "progression.reset: generateur reseede")
	h.eq(suite.fantomes[1], Alt.PLACES_MAISON[1], "progression.reset: fantomes aux places de la carte suivante")
	h.eq(suite.dash_recharge, 0, "progression.reset: recharge du dash remise")

	# EGALITE STRICTE violee de part et d'autre pour chaque grandeur remise.
	h.ok(suite.consommees != jeu.consommees, "progression.reset: les consommees ne survivent pas")
	h.ok(suite.pac != jeu.pac, "progression.reset: la position ne survit pas")
	h.ok(suite.horloge != jeu.horloge, "progression.reset: l'horloge ne survit pas")
