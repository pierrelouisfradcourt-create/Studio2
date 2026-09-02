# v2_house_positions_from_state_map.test.gd — ligne house.positions_from_state_map, F100/F106.
# Les positions de maison sont lues sur la carte PORTEE PAR L'ETAT, jamais sur une
# constante globale ; a la bascule, ce sont celles de la carte suivante.
extends RefCounted

const House = preload("res://05_SYSTEMS/ghost_house/ghost_house.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Progression = preload("res://05_SYSTEMS/level_progression/level_progression.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))
var Alt = MazeClass.depuis_descripteur(ContentV2.descripteur(1))


func run(h) -> void:
	# Chaque carte a SES places, lues sur elle.
	h.eq(House.place(Maze, 0), Maze.PLACES_MAISON[0], "house.positions: place lue sur la carte")
	h.eq(House.place(Alt, 0), Alt.PLACES_MAISON[0], "house.positions: idem sur la seconde carte")
	h.ok(House.place(Maze, 1) != House.place(Alt, 1), "house.positions: les places different entre cartes")
	h.eq(House.etat_initial(Maze)["positions"].size(), 4, "house.positions: quatre positions initiales")
	h.eq(House.etat_initial(Alt)["positions"][1], Alt.PLACES_MAISON[1], "house.positions: seconde carte")
	h.eq(House.etat_initial(Maze)["dehors"][0], true, "house.positions: le rouge est dehors au tick 0")

	# LA SORTIE lue sur la carte de l'etat.
	var jeu = State.initial(Alt, 3)
	jeu.ticks = 1000
	House.mettre_a_jour(jeu)
	var sorties: int = 0
	for i in range(jeu.fantomes.size()):
		if jeu.fantomes[i] == Alt.SORTIE_MAISON:
			sorties += 1
	h.gt(sorties, 0, "house.positions: la sortie utilisee est celle de la carte de l'etat")

	# A LA BASCULE : les positions sont celles de la carte suivante.
	var avant = State.initial(Maze, 3)
	var apres = Progression.basculer(avant, Alt, ContentV2.cadence(1), 3)
	h.eq(apres.fantomes[1], Alt.PLACES_MAISON[1], "house.positions: places de la carte suivante")
	h.ok(apres.fantomes[1] != avant.fantomes[1], "house.positions: elles ne sont plus celles de la precedente")

	# AUCUNE constante de maison dans le module.
	var f := FileAccess.open("res://05_SYSTEMS/ghost_house/ghost_house.gd", FileAccess.READ)
	var texte: String = f.get_as_text() if f != null else ""
	h.eq(texte.contains("Vector2i(13"), false, "house.positions: aucune coordonnee de carte")
	h.eq(texte.contains("const PLACES"), false, "house.positions: aucune constante de places")
