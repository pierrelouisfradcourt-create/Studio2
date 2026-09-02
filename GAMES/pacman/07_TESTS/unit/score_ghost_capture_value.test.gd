# score_ghost_capture_value.test.gd — ligne score.ghost_capture_value, capacite F32.
# Le gain est 200, 400, 800 ou 1600 selon le RANG ; a la super-pastille suivante, le
# rang repart de la premiere valeur.
extends RefCounted

const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())

const Score = preload("res://05_SYSTEMS/score/score.gd")
const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")


func run(h) -> void:
	h.eq(Score.valeur_capture(0), 200, "score.capture: rang 0 vaut 200")
	h.eq(Score.valeur_capture(1), 400, "score.capture: rang 1 vaut 400")
	h.eq(Score.valeur_capture(2), 800, "score.capture: rang 2 vaut 800")
	h.eq(Score.valeur_capture(3), 1600, "score.capture: rang 3 vaut 1600")
	h.eq(Score.VALEURS_CAPTURE.size(), 4, "score.capture: quatre rangs declares")

	# Hors domaine : jamais une extrapolation implicite, jamais une exception.
	h.eq(Score.valeur_capture(4), 1600, "score.capture: au-dela du quatrieme, la derniere valeur")
	h.eq(Score.valeur_capture(-1), 200, "score.capture: rang negatif retombe sur la premiere valeur")

	# Le rang repart de la premiere valeur a la super-pastille suivante.
	var s = State.initial(Maze, 1)
	h.eq(s.rang_capture, 0, "score.capture: rang a zero au tick 0")
	s.rang_capture = 3
	Chase.armer_effraye(s)
	h.eq(s.rang_capture, 0, "score.capture: l'armement remet le rang a zero")
	h.eq(Score.valeur_capture(s.rang_capture), 200,
		"score.capture: la capture suivante repart a 200")

	# Progression stricte : les quatre valeurs sont deux a deux differentes et croissantes.
	var non_croissants: int = 0
	for i in range(1, Score.VALEURS_CAPTURE.size()):
		if not (Score.VALEURS_CAPTURE[i] > Score.VALEURS_CAPTURE[i - 1]):
			non_croissants += 1
	h.eq(non_croissants, 0, "score.capture: valeurs strictement croissantes")

	# POINT DE MUTATION UNIQUE : le score ne monte que par score.ajouter.
	var t = State.initial(Maze, 1)
	var avant: int = t.score
	Score.ajouter(t, Score.valeur_capture(0))
	h.eq(t.score - avant, 200, "score.capture: ajouter applique exactement la valeur du rang")
