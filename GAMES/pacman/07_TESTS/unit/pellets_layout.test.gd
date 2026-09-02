# pellets_layout.test.gd — ligne pellets.layout, capacite F9.
# Comptage des collectibles poses au tick 0 : 240 pastilles ordinaires plus 4
# super-pastilles, total EXACTEMENT 244.
extends RefCounted

const Pellets = preload("res://05_SYSTEMS/pellets/pellets.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")


func run(h) -> void:
	var grille: PackedByteArray = Pellets.poser(Maze)
	h.eq(grille.size(), Maze.LARGEUR * Maze.HAUTEUR, "pellets.layout: un emplacement par case")

	var pastilles: int = Pellets.compter(grille, Pellets.Contenu.PASTILLE)
	var supers: int = Pellets.compter(grille, Pellets.Contenu.SUPER)
	h.eq(pastilles, P.PASTILLES_ATTENDUES, "pellets.layout: 240 pastilles ordinaires")
	h.eq(supers, P.SUPER_ATTENDUES, "pellets.layout: 4 super-pastilles")
	h.eq(Pellets.total_pose(grille), P.COLLECTIBLES_ATTENDUS, "pellets.layout: total pose 244")
	h.eq(pastilles + supers, Pellets.total_pose(grille),
		"pellets.layout: le total est la somme des deux natures")

	# Aucun collectible sur une case impraticable : un collectible dans un mur serait
	# inatteignable et rendrait la victoire impossible.
	var hors_couloir: int = 0
	for i in range(grille.size()):
		if grille[i] != Pellets.Contenu.VIDE and not Maze.praticable(Maze.case_de(i)):
			hors_couloir += 1
	h.eq(hors_couloir, 0, "pellets.layout: aucun collectible hors couloir")

	# Le total qui definit la victoire est PRODUIT, pas recopie : l'etat de partie porte
	# EXACTEMENT ce que la pose a compte.
	var s = State.initial(Maze, 1)
	h.eq(s.total_pose, Pellets.total_pose(grille), "pellets.layout: l'etat porte le total produit")
	h.eq(s.consommees, 0, "pellets.layout: aucun collectible consomme au tick 0")

	# Case de depart de Pac-Man : SANS collectible, sinon le premier tick consommerait
	# avant tout deplacement et fausserait chaque compte.
	h.eq(Pellets.contenu_de(Maze, grille, Maze.DEPART_PACMAN), Pellets.Contenu.VIDE,
		"pellets.layout: la case de depart ne porte pas de collectible")
