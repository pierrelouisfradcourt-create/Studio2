# pellets_consume.test.gd — ligne pellets.consume, capacite F30.
# Invariant d'incrementation soumis au gate de mutation : un mutant qui n'efface pas la
# case, ou qui recompte une case deja videe, doit etre tue ICI.
extends RefCounted

const Pellets = preload("res://05_SYSTEMS/pellets/pellets.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())


func _premiere(grille: PackedByteArray, contenu: int) -> Vector2i:
	for i in range(grille.size()):
		if grille[i] == contenu:
			return Maze.case_de(i)
	return Vector2i(-1, -1)


func run(h) -> void:
	var grille: PackedByteArray = Pellets.poser(Maze)
	var total: int = Pellets.total_pose(grille)
	var case_pastille: Vector2i = _premiere(grille, Pellets.Contenu.PASTILLE)
	var case_super: Vector2i = _premiere(grille, Pellets.Contenu.SUPER)

	# Consommation d'une pastille ordinaire : la case est EFFACEE, le compteur monte de 1.
	var r: Dictionary = Pellets.consommer(Maze, grille, case_pastille, 0)
	h.eq(r["contenu"], Pellets.Contenu.PASTILLE, "pellets.consume: nature du collectible consomme")
	h.eq(r["consommees"], 1, "pellets.consume: le compteur monte de 1 exactement")
	h.eq(Pellets.contenu_de(Maze, r["grille"], case_pastille), Pellets.Contenu.VIDE,
		"pellets.consume: la case est effacee")
	h.eq(Pellets.total_pose(r["grille"]), total - 1, "pellets.consume: un collectible de moins")

	# L'entree n'est JAMAIS mutee : la grille d'origine porte toujours son collectible.
	h.eq(Pellets.contenu_de(Maze, grille, case_pastille), Pellets.Contenu.PASTILLE,
		"pellets.consume: la grille d'entree n'est pas mutee")

	# Une case DEJA VIDEE n'est jamais recomptee.
	var r2: Dictionary = Pellets.consommer(Maze, r["grille"], case_pastille, r["consommees"])
	h.eq(r2["contenu"], Pellets.Contenu.VIDE, "pellets.consume: rien a consommer sur case videe")
	h.eq(r2["consommees"], 1, "pellets.consume: le compteur ne bouge pas sur case videe")
	h.eq(Pellets.total_pose(r2["grille"]), total - 1, "pellets.consume: le total reste stable")

	# Super-pastille : meme mecanique, nature differente.
	var rs: Dictionary = Pellets.consommer(Maze, grille, case_super, 5)
	h.eq(rs["contenu"], Pellets.Contenu.SUPER, "pellets.consume: nature super-pastille")
	h.eq(rs["consommees"], 6, "pellets.consume: le compteur monte de 1 sur une super-pastille")
	h.eq(Pellets.contenu_de(Maze, rs["grille"], case_super), Pellets.Contenu.VIDE,
		"pellets.consume: la super-pastille est effacee")

	# Case sans collectible (couloir vide) : aucun effet, aucun comptage.
	var r3: Dictionary = Pellets.consommer(Maze, grille, Maze.DEPART_PACMAN, 3)
	h.eq(r3["consommees"], 3, "pellets.consume: couloir vide ne compte rien")
	h.eq(Pellets.total_pose(r3["grille"]), total, "pellets.consume: couloir vide ne retire rien")

	# Case de mur : aucun effet, aucune exception.
	var r4: Dictionary = Pellets.consommer(Maze, grille, Vector2i(0, 0), 3)
	h.eq(r4["consommees"], 3, "pellets.consume: case de mur ne compte rien")

	# INVARIANT DE CONSERVATION : consommes + restants == total pose, a chaque etape.
	var g: PackedByteArray = grille
	var consommees: int = 0
	var ruptures: int = 0
	for i in range(grille.size()):
		if grille[i] == Pellets.Contenu.VIDE:
			continue
		var etape: Dictionary = Pellets.consommer(Maze, g, Maze.case_de(i), consommees)
		g = etape["grille"]
		consommees = etape["consommees"]
		if consommees + Pellets.total_pose(g) != total:
			ruptures += 1
	h.eq(ruptures, 0, "pellets.consume: consommes + restants == total pose a chaque etape")
	h.eq(consommees, total, "pellets.consume: tout consommer donne exactement le total")
	h.eq(Pellets.total_pose(g), 0, "pellets.consume: plus aucun collectible a la fin")
