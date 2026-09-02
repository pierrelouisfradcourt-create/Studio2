# v2_score_survives_switch.test.gd — ligne score.survives_switch, capacite F105.
# Le score est l'une des DEUX grandeurs qui SURVIVENT a une bascule de niveau. Un seul
# endroit ou il change, donc un seul endroit ou sa conservation se prouve.
extends RefCounted

const Score = preload("res://05_SYSTEMS/score/score.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Progression = preload("res://05_SYSTEMS/level_progression/level_progression.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))
var Alt = MazeClass.depuis_descripteur(ContentV2.descripteur(1))


func run(h) -> void:
	var jeu = State.initial(Maze, 5)
	for _t in range(40):
		jeu = Loop.step(jeu, Maze.DEPART_DIRECTION)["etat"]
	h.gt(jeu.score, 0, "score.survit: un score a ete marque avant la bascule")
	var score_avant: int = jeu.score
	var vies_avant: int = jeu.vies

	var suite = Progression.basculer(jeu, Alt, ContentV2.cadence(1), 5)
	h.eq(suite.score, score_avant, "score.survit: egalite stricte du score de part et d'autre")
	h.eq(suite.vies, vies_avant, "score.survit: egalite stricte des vies")
	h.ok(suite.score != 0, "score.survit: le score n'est pas remis a sa valeur initiale")

	# LE RANG DE CAPTURE, lui, repart : il ne survit pas.
	jeu.rang_capture = 2
	var suite2 = Progression.basculer(jeu, Alt, ContentV2.cadence(1), 5)
	h.eq(suite2.rang_capture, 0, "score.survit: le rang de capture repart a sa premiere valeur")

	# POINT DE MUTATION UNIQUE : un seul endroit ou le score change.
	var s = State.initial(Maze, 1)
	Score.ajouter(s, 30)
	h.eq(s.score, 30, "score.survit: l'ajout passe par le point unique")
	h.eq(Score.valeur_collectible(false), 10, "score.survit: bareme de pastille")
	h.eq(Score.valeur_collectible(true), 50, "score.survit: bareme de super-pastille")
	h.eq(Score.valeur_capture(0), 200, "score.survit: premiere capture")
	h.eq(Score.valeur_capture(3), 1600, "score.survit: quatrieme capture")
	h.eq(Score.valeur_capture(9), 1600, "score.survit: au-dela, la derniere valeur declaree")
