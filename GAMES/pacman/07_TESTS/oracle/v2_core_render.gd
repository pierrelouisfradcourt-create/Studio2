# v2_core_render.gd — ligne core.render, capacites F110/F114.
# Le jeu affiche son etat, et l'affichage CHANGE quand l'etat change. En V2 toutes les
# couleurs rendues viennent du descripteur de palette unique, et les quatre elements
# interrogeables sont affiches.
#
# LES DEUX CAPTURES A DEUX ETATS DISTINCTS exigent une FENETRE GPU REELLE : en headless
# la texture est nulle. Ce volet vaut NOT_MEASURED MOTIVE, jamais un vert. Ce qui est
# mesure ici est le CHANGEMENT de la sortie affichee entre deux etats.
extends RefCounted

const Presentation = preload("res://06_RUNTIME/adapters/presentation/presentation.gd")
const MazeView = preload("res://06_RUNTIME/adapters/presentation/maze_view.gd")
const ShellView = preload("res://06_RUNTIME/adapters/shell_view/shell_view.gd")
const Purity = preload("res://06_RUNTIME/adapters/proof_harness/harness_purity_counts.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))


func run(h) -> void:
	# LES COULEURS viennent toutes du descripteur unique.
	h.eq(Purity.couleur_hors_palette().size(), 0, "core.render: 0 couleur hors du descripteur")
	h.eq(Purity.couleur_dans_logique().size(), 0, "core.render: 0 couleur dans la logique")
	h.eq(MazeView.couleurs_distinctes(), true, "core.render: quatre couleurs de fantomes distinctes")

	# L'AFFICHAGE CHANGE quand l'etat change.
	var jeu = State.initial(Maze, 1)
	var avant: String = Presentation.bandeau(Observable.projeter(jeu))
	for _t in range(20):
		jeu = Loop.step(jeu, Maze.DEPART_DIRECTION)["etat"]
	var apres: String = Presentation.bandeau(Observable.projeter(jeu))
	h.ok(avant != apres, "core.render: la sortie affichee change avec l'etat")
	h.ok(avant != "", "core.render: la sortie affichee n'est pas vide")

	# LES QUATRE ELEMENTS interrogeables sont affiches.
	h.eq(Presentation.elements_sans_representation(Observable.projeter(jeu)), 0,
		"core.render: 0 element sans representation")

	# LA CAPTURE reelle vaut NOT_MEASURED MOTIVE en headless — jamais un vert.
	var captures: Array = ShellView.captures(null)
	var mesurees: int = 0
	for c in captures:
		if c["mesure"]:
			mesurees += 1
	h.eq(mesurees, 0, "core.render: aucune capture mesuree sans fenetre GPU")
	h.eq(String(captures[0]["raison"]), ShellView.RAISON_HEADLESS, "core.render: la raison est nommee")
	h.gt(MazeView.largeur_pixels(Maze), 0, "core.render: la surface de rendu est declaree")
