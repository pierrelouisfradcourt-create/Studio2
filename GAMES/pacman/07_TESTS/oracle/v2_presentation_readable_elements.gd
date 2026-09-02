# v2_presentation_readable_elements.gd — ligne presentation.readable_elements, F114.
# PROVENANCE, PAS PREUVE. Volet MACHINE : les quatre elements sont AFFICHES et
# distinguables — ce qui se mange, ce qui se fuit, ce qui arrive quand une carte est
# videe, comment la partie se termine ; le nombre d'elements sans representation vaut 0.
# Volet HUMAIN : que la personne les NOMME n'est tranche par aucun oracle — besoin
# remonte en fog HumanGate.
extends RefCounted

const Presentation = preload("res://06_RUNTIME/adapters/presentation/presentation.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))


func run(h) -> void:
	var jeu = State.initial(Maze, 1)
	var releve: Dictionary = Observable.projeter(jeu)
	h.eq(Presentation.ELEMENTS.size(), 4, "presentation.elements: quatre elements declares")
	h.eq(Presentation.elements_sans_representation(releve), 0,
		"presentation.elements: 0 element sans representation a l'ecran")

	# CHACUN a une representation NON VIDE et DISTINGUABLE des autres.
	var vues: Array = []
	var doublons: int = 0
	for e in Presentation.ELEMENTS:
		var r: String = Presentation.representation(String(e), releve)
		h.ok(r != "", "presentation.elements: l'element %s est represente" % e)
		if vues.has(r):
			doublons += 1
		vues.append(r)
	h.eq(doublons, 0, "presentation.elements: quatre representations deux a deux differentes")

	# UN ELEMENT INCONNU n'a pas de representation : le comptage n'est pas complaisant.
	h.eq(Presentation.representation("element_inconnu", releve), "",
		"presentation.elements: un element inconnu n'est pas represente")

	# LES REPRESENTATIONS SUIVENT l'etat : elles ne sont pas figees.
	for _t in range(15):
		jeu = Loop.step(jeu, Maze.DEPART_DIRECTION)["etat"]
	var apres: Dictionary = Observable.projeter(jeu)
	h.ok(Presentation.representation(Presentation.ELEMENT_A_MANGER, apres)
		!= Presentation.representation(Presentation.ELEMENT_A_MANGER, releve),
		"presentation.elements: ce qui se mange evolue a l'ecran")
	h.eq(Presentation.elements_sans_representation(apres), 0,
		"presentation.elements: toujours 0 element sans representation")

	# LE BANDEAU les porte tous.
	var bandeau: String = Presentation.bandeau(apres)
	var absents: int = 0
	for e in Presentation.ELEMENTS:
		if not bandeau.contains(Presentation.representation(String(e), apres)):
			absents += 1
	h.eq(absents, 0, "presentation.elements: le bandeau porte les quatre representations")
