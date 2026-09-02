# house_return_captured.test.gd — ligne house.return_captured, capacite F24.
# Au tick du contact avec un fantome Effraye : la position du fantome est DANS la maison
# centrale et le compteur de vies est INCHANGE.
extends RefCounted

const House = preload("res://05_SYSTEMS/ghost_house/ghost_house.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Contacts = preload("res://05_SYSTEMS/contacts/contacts.gd")


func run(h) -> void:
	var s = State.initial(Maze, 1)
	Chase.armer_effraye(s)
	# Le fantome rouge est dehors, Effraye, sur la case de Pac-Man.
	s.dehors[0] = true
	s.fantomes[0] = s.pac
	Chase.rafraichir_etats(s)
	var vies_avant: int = s.vies
	var score_avant: int = s.score

	var issue: Dictionary = Contacts.resoudre(s, [0])
	h.eq(issue["captures"], [0], "house.return: le contact Effraye est une capture")
	h.eq(issue["hostile"], false, "house.return: aucune issue hostile")
	h.eq(s.vies, vies_avant, "house.return: le compteur de vies est INCHANGE")
	h.eq(s.score - score_avant, 200, "house.return: la capture rapporte 200 au premier rang")

	# Le fantome est DANS la maison centrale, a sa place declaree.
	h.eq(s.fantomes[0], House.place(Maze, 0), "house.return: le fantome est a sa place de maison")
	h.eq(Maze.type_case(House.place(Maze, 0)) == Maze.Type.MAISON
		or House.place(Maze, 0) == Maze.SORTIE_MAISON, true,
		"house.return: la place de repos appartient a la maison ou a sa sortie")
	h.eq(s.dehors[0], false, "house.return: le fantome n'est plus dehors")

	# Il est SORTI de l'etat Effraye : il ne peut plus etre capture une seconde fois.
	h.eq(s.effrayes[0], false, "house.return: le fantome capture n'est plus Effraye")
	h.ok(s.etats_fantomes[0] != Chase.Mode.EFFRAYE, "house.return: l'etat expose n'est plus Effraye")

	# Le delai de retour est declare et STRICTEMENT posterieur au tick courant.
	h.eq(s.sorties_maison[0], s.ticks + House.DELAI_RETOUR, "house.return: delai de retour declare")
	h.gt(s.sorties_maison[0], s.ticks, "house.return: la sortie est posterieure a la capture")

	# Les autres fantomes ne sont pas touches par la capture d'un seul.
	h.eq(s.effrayes[1], true, "house.return: les autres restent Effrayes")
	h.eq(s.rang_capture, 1, "house.return: le rang a avance d'exactement un cran")

	# Sortie effective apres le delai : le fantome revient a la sortie de maison.
	s.ticks = s.sorties_maison[0]
	House.mettre_a_jour(s)
	h.eq(s.dehors[0], true, "house.return: le fantome ressort au tick declare")
	h.eq(s.fantomes[0], Maze.SORTIE_MAISON, "house.return: il ressort par la sortie de maison")
