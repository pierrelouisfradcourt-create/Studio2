# v2_presentation_level_number.gd — ligne presentation.level_number, capacite F109.
# Le NUMERO DE NIVEAU affiche a l'ecran est EGAL au niveau courant de l'etat AU MEME
# TICK : deux lectures d'une source unique, jamais deux calculs paralleles.
extends RefCounted

const Presentation = preload("res://06_RUNTIME/adapters/presentation/presentation.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const Progression = preload("res://05_SYSTEMS/level_progression/level_progression.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))
var Alt = MazeClass.depuis_descripteur(ContentV2.descripteur(1))


func run(h) -> void:
	var jeu = State.initial(Maze, 1)
	var divergences: int = 0
	for _t in range(25):
		jeu = Loop.step(jeu, Maze.DEPART_DIRECTION)["etat"]
		var releve: Dictionary = Observable.projeter(jeu)
		if Presentation.relire_niveau(Presentation.texte_niveau(releve)) != jeu.niveau:
			divergences += 1
	h.eq(divergences, 0, "presentation.niveau: 0 divergence sur 25 ticks")

	# APRES BASCULE : l'affichage suit, au meme tick.
	var suite = Progression.basculer(jeu, Alt, ContentV2.cadence(1), 1)
	var r: Dictionary = Observable.projeter(suite)
	h.eq(Presentation.relire_niveau(Presentation.texte_niveau(r)), 2, "presentation.niveau: 2 affiche")
	h.eq(r["niveau"], 2, "presentation.niveau: 2 dans l'etat")
	h.eq(Presentation.relire_niveau(Presentation.texte_niveau(r)), r["niveau"],
		"presentation.niveau: l'affiche egale l'etat au meme tick")

	# UNE SOURCE UNIQUE : l'affichage lit le releve, il ne recalcule rien.
	var f := FileAccess.open("res://06_RUNTIME/adapters/presentation/presentation.gd", FileAccess.READ)
	var texte: String = f.get_as_text() if f != null else ""
	h.eq(texte.contains("Progression"), false, "presentation.niveau: l'affichage ne calcule aucun niveau")
	h.eq(texte.contains("State.initial"), false, "presentation.niveau: il ne construit aucun etat")
	h.eq(texte.contains('releve["niveau"]'), true, "presentation.niveau: il lit le releve")

	# LE BANDEAU porte le numero.
	h.eq(Presentation.bandeau(r).contains(Presentation.ETIQUETTE_NIVEAU), true,
		"presentation.niveau: le bandeau porte l'etiquette de niveau")
	h.eq(Presentation.relire_niveau(Presentation.bandeau(r)), 2, "presentation.niveau: relisible dans le bandeau")
