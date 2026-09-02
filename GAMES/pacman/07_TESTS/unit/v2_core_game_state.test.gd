# v2_core_game_state.test.gd — ligne core.game_state, capacites F81/F99.
# L'etat de partie est observable et NOMME. En V2 il PORTE en outre sa carte courante et
# son mode de jeu, tous deux exposes dans le releve et n'admettant que des valeurs
# declarees.
extends RefCounted

const Reglages = preload("res://05_SYSTEMS/settings/settings.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))
var Alt = MazeClass.depuis_descripteur(ContentV2.descripteur(1))


func run(h) -> void:
	var jeu = State.initial(Maze, 1)
	var r: Dictionary = Observable.projeter(jeu)
	h.eq(r["carte"], "maze_classic", "core.state: la carte courante est exposee")
	h.eq(r["mode_jeu"], "NORMAL", "core.state: le mode de jeu est expose")
	h.eq(Reglages.valide(jeu.mode), true, "core.state: le mode appartient au vocabulaire ferme")
	h.eq(jeu.carte.meme_carte(Maze), true, "core.state: l'etat porte sa carte")
	h.eq(jeu.est_valide(), true, "core.state: l'etat initial est valide")

	# VALEURS DECLAREES SEULEMENT : un mode hors vocabulaire rend l'etat invalide.
	var casse = jeu.clone()
	casse.mode = 9
	h.eq(casse.est_valide(), false, "core.state: un mode hors vocabulaire est refuse")

	# A CHAQUE RELEVE : ni vide, ni double.
	var hors: int = 0
	var s = State.initial(Alt, 2)
	for _t in range(20):
		s = Loop.step(s, Alt.DEPART_DIRECTION)["etat"]
		var x: Dictionary = Observable.projeter(s)
		if String(x["mode_jeu"]) != "NORMAL" and String(x["mode_jeu"]) != "TEST":
			hors += 1
		if String(x["carte"]) == "":
			hors += 1
	h.eq(hors, 0, "core.state: 0 releve hors vocabulaire sur 20 ticks")
	h.eq(Observable.projeter(s)["carte"], "maze_alt", "core.state: la carte de la seconde partie est exposee")

	# LE MODE TEST est aussi une valeur declaree, exposee telle quelle.
	var test = State.initial(Maze, 1, 0, {"mode": Reglages.Mode.TEST})
	h.eq(Observable.projeter(test)["mode_jeu"], "TEST", "core.state: le mode test est expose")
	h.eq(test.est_valide(), true, "core.state: il reste un etat valide")
