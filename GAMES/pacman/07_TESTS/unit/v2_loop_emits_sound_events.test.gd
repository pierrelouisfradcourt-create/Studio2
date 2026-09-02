# v2_loop_emits_sound_events.test.gd — ligne loop.emits_sound_events, capacite F88.
# Le tick produit la liste d'evenements, evenements SONORES compris : c'est la PRISE
# unique a laquelle la couche de presentation se branche.
extends RefCounted

const Events = preload("res://05_SYSTEMS/game_events/game_events.gd")
const Purity = preload("res://06_RUNTIME/adapters/proof_harness/harness_purity_counts.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))


func run(h) -> void:
	var jeu = State.initial(Maze, 5)
	var sortie: Dictionary = Loop.step(jeu, Maze.DEPART_DIRECTION)
	h.eq(sortie.has("evenements"), true, "loop.sons: le tick rend les evenements de jeu")
	h.eq(sortie.has("evenements_sonores"), true, "loop.sons: il rend aussi les evenements sonores")
	h.eq(sortie["evenements_sonores"] is Array, true, "loop.sons: la sortie sonore est une liste")

	# Les noms emis appartiennent au vocabulaire ferme des six moments.
	var hors_vocabulaire: int = 0
	var vus: Array = []
	var s = State.initial(Maze, 5)
	for _t in range(120):
		var r: Dictionary = Loop.step(s, Maze.DEPART_DIRECTION)
		s = r["etat"]
		for e in r["evenements_sonores"]:
			if not Events.moment_connu(String(e)):
				hors_vocabulaire += 1
			if not vus.has(e):
				vus.append(e)
	h.eq(hors_vocabulaire, 0, "loop.sons: aucun evenement hors du vocabulaire ferme")
	h.gt(vus.size(), 1, "loop.sons: au moins deux moments distincts sont reellement emis")
	h.eq(vus.has(Events.SON_DEPLACEMENT), true, "loop.sons: le deplacement est emis")
	h.eq(vus.has(Events.SON_COLLECTE), true, "loop.sons: la collecte est emise")

	# TRANSPORT SEUL : la boucle ne joue aucun son et ne connait aucune API audio.
	var f := FileAccess.open("res://05_SYSTEMS/game_loop/game_loop.gd", FileAccess.READ)
	var texte: String = Purity.code_seul(f.get_as_text() if f != null else "")
	h.eq(texte.contains("AudioStream"), false, "loop.sons: aucune API audio dans la boucle")
	h.eq(texte.contains("Events.evenements_sonores"), true, "loop.sons: elle transporte la production de game_events")

	# L'ouverture de menu est REMISE par l'appelant, jamais devinee par la boucle.
	var avec_menu: Dictionary = Loop.step(State.initial(Maze, 5), MazeClass.AUCUNE, false, true)
	h.eq(avec_menu["evenements_sonores"].has(Events.SON_PAUSE), true,
		"loop.sons: l'ouverture de menu remonte le moment de pause")
