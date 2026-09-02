# v2_core_main_loop.gd — ligne core.main_loop, capacite F77.
# Une boucle de jeu fait avancer l'etat de maniere DETERMINISTE. Volet V2 : deux
# executions pilotees par deux peripheriques differents, comparees tick par tick,
# donnent des traces d'etat STRICTEMENT EGALES.
extends RefCounted

const Parity = preload("res://06_RUNTIME/adapters/proof_harness/harness_input_parity.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const Intents = preload("res://05_SYSTEMS/input_intents/input_intents.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))


func run(h) -> void:
	# MEME ETAT + MEME INTENTION + MEME GRAINE -> MEME ETAT SUIVANT.
	var a = State.initial(Maze, 23)
	var b = State.initial(Maze, 23)
	for _t in range(30):
		a = Loop.step_intentions(a, [Intents.Intention.GAUCHE])["etat"]
		b = Loop.step_intentions(b, [Intents.Intention.GAUCHE])["etat"]
	h.eq(a.egal_profond(b), true, "core.loop: deux executions identiques donnent le meme etat")
	h.eq(a.ticks, 30, "core.loop: trente ticks joues")

	# DEUX PERIPHERIQUES, MEME TRACE.
	var m: Dictionary = Parity.mesurer(Maze)
	h.eq(m["intentions_divergentes"], 0, "core.loop: 0 divergence entre clavier et manette")
	h.gt(m["divergences_de_controle"], 0, "core.loop: le comparateur detecte une vraie difference")

	# LA BOUCLE ne mute pas son entree et produit un nouvel etat.
	var c = State.initial(Maze, 23)
	var copie = c.clone()
	var suite = Loop.step(c, MazeClass.GAUCHE)["etat"]
	h.eq(c.egal_profond(copie), true, "core.loop: l'etat d'entree est intact")
	h.eq(suite.ticks, 1, "core.loop: le nouvel etat a avance")
	h.eq(Observable.egaux(Observable.projeter(c), Observable.projeter(copie)), true,
		"core.loop: le releve de l'entree est inchange")
	h.ok(suite.pac != c.pac, "core.loop: le nouvel etat a bouge")
