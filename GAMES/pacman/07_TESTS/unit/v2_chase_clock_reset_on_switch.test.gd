# v2_chase_clock_reset_on_switch.test.gd — ligne chase.clock_reset_on_switch, F106.
# L'horloge des etats REVIENT A SA PHASE INITIALE lors d'une bascule de niveau : la
# carte suivante n'herite JAMAIS de l'horloge de la precedente.
extends RefCounted

const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Progression = preload("res://05_SYSTEMS/level_progression/level_progression.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))
var Alt = MazeClass.depuis_descripteur(ContentV2.descripteur(1))


func run(h) -> void:
	var jeu = State.initial(Maze, 5)
	# Fixture d isolement : les fantomes restent en maison, sinon une perte de vie
	# remettrait l horloge a zero au milieu de la mesure et le releve ne mesurerait plus
	# l horloge, mais la survie du joueur.
	for i in range(jeu.fantomes.size()):
		jeu.dehors[i] = false
		jeu.sorties_maison[i] = 10000
	for _t in range(60):
		jeu = Loop.step(jeu, Maze.DEPART_DIRECTION)["etat"]
	h.gt(jeu.horloge, 0, "chase.reset: l'horloge a avance avant la bascule")

	var suite = Progression.basculer(jeu, Alt, ContentV2.cadence(1), 5)
	h.eq(suite.horloge, 0, "chase.reset: l'horloge repart a sa phase initiale")
	h.eq(suite.effraye_restant, 0, "chase.reset: la fenetre Effraye est fermee")
	h.eq(suite.rang_capture, 0, "chase.reset: le rang de capture repart")
	var effrayes: int = 0
	for e in suite.effrayes:
		if e:
			effrayes += 1
	h.eq(effrayes, 0, "chase.reset: aucun fantome n'herite de l'etat Effraye")
	h.ok(suite.horloge != jeu.horloge, "chase.reset: egalite stricte violee de part et d'autre")

	# LE RESET DIRECT pose exactement la meme phase.
	var copie = jeu.clone()
	Chase.armer_effraye(copie)
	copie.rang_capture = 3
	Chase.reinitialiser_horloge(copie)
	h.eq(copie.horloge, 0, "chase.reset: horloge remise")
	h.eq(copie.effraye_restant, 0, "chase.reset: fenetre fermee")
	h.eq(copie.rang_capture, 0, "chase.reset: rang remis")
	h.eq(copie.etats_fantomes[0], Chase.mode_global(0), "chase.reset: les etats exposes suivent la phase")
	h.eq(Chase.MODES_VALIDES.has(copie.etats_fantomes[0]), true, "chase.reset: vocabulaire ferme respecte")
