# v2_state_exposes_level_number.test.gd — ligne state.exposes_level_number, capacite F109.
# Le releve observable expose le NUMERO DE NIVEAU, le mode de jeu et le compteur de
# ticks : SOURCE UNIQUE lue a la fois par l'affichage et par le lecteur exterieur.
extends RefCounted

const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const Presentation = preload("res://06_RUNTIME/adapters/presentation/presentation.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Progression = preload("res://05_SYSTEMS/level_progression/level_progression.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))
var Alt = MazeClass.depuis_descripteur(ContentV2.descripteur(1))


func run(h) -> void:
	var jeu = State.initial(Maze, 1)
	var r: Dictionary = Observable.projeter(jeu)
	h.eq(r.has("niveau"), true, "state.niveau: le releve porte le numero de niveau")
	h.eq(r.has("mode_jeu"), true, "state.niveau: il porte le mode de jeu")
	h.eq(r.has("tick"), true, "state.niveau: il porte le compteur de ticks")
	h.eq(r.has("carte"), true, "state.niveau: il porte l'identifiant de carte")
	h.eq(r["niveau"], State.PREMIER_NIVEAU, "state.niveau: la partie neuve est au premier niveau")
	h.eq(r["carte"], "maze_classic", "state.niveau: la carte courante est exposee")
	h.eq(r["tick"], 0, "state.niveau: compteur a 0 au depart")

	# APRES BASCULE : le numero suit, la carte aussi.
	var suite = Progression.basculer(jeu, Alt, ContentV2.cadence(1), 1)
	var r2: Dictionary = Observable.projeter(suite)
	h.eq(r2["niveau"], 2, "state.niveau: le second niveau est expose")
	h.eq(r2["carte"], "maze_alt", "state.niveau: la carte suivante est exposee")

	# DEUX LECTURES D'UNE SOURCE UNIQUE, au MEME tick : l'affichage relit le releve.
	jeu = Loop.step(jeu, Maze.DEPART_DIRECTION)["etat"]
	var releve: Dictionary = Observable.projeter(jeu)
	h.eq(Presentation.relire_niveau(Presentation.texte_niveau(releve)), releve["niveau"],
		"state.niveau: le chiffre affiche egale le niveau de l'etat au meme tick")
	h.eq(Presentation.relire_niveau(Presentation.texte_niveau(r2)), 2,
		"state.niveau: idem apres la bascule")
	h.eq(Presentation.relire_niveau("aucun chiffre"), -1, "state.niveau: une lecture impossible est nommee")
