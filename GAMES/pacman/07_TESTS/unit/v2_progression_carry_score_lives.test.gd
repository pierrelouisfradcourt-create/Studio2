# v2_progression_carry_score_lives.test.gd — ligne progression.carry_score_lives, F105.
# Declare EXACTEMENT ce qui survit a la bascule : le score et le nombre de vies.
# L'egalite STRICTE de part et d'autre tue un mutant qui les remettrait a l'initial.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Progression = preload("res://05_SYSTEMS/level_progression/level_progression.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))
var Alt = MazeClass.depuis_descripteur(ContentV2.descripteur(1))


func run(h) -> void:
	h.eq(Progression.CONSERVES.size(), 2, "progression.carry: deux grandeurs declarees conservees")
	h.eq(Progression.CONSERVES.has("score"), true, "progression.carry: le score est declare conserve")
	h.eq(Progression.CONSERVES.has("vies"), true, "progression.carry: les vies sont declarees conservees")

	# EGALITE STRICTE de part et d'autre, sur plusieurs valeurs.
	for couple in [[0, 3], [1230, 2], [99999, 1]]:
		var jeu = State.initial(Maze, 1)
		jeu.score = couple[0]
		jeu.vies = couple[1]
		var suite = Progression.basculer(jeu, Alt, ContentV2.cadence(1), 1)
		h.eq(suite.score, couple[0], "progression.carry: le score traverse la bascule")
		h.eq(suite.vies, couple[1], "progression.carry: les vies traversent la bascule")

	# CONTRE-EPREUVE : un etat neuf sur la carte suivante NE porte PAS ces valeurs — la
	# conservation n'est donc pas un effet de bord de la construction.
	var neuf = State.initial(Alt, 1)
	h.eq(neuf.score, 0, "progression.carry: un etat neuf part d'un score nul")
	h.ok(neuf.score != 1230, "progression.carry: la conservation n'est pas une coincidence")
