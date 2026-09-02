# pellets_map_invariants.test.gd — ligne pellets.map_invariants, capacite F10.
# Une et une seule super-pastille par quadrant ; chacune STRICTEMENT plus proche de son
# coin que de la maison centrale ; chaque collectible atteignable depuis le depart.
extends RefCounted

const Pellets = preload("res://05_SYSTEMS/pellets/pellets.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())


func run(h) -> void:
	var grille: PackedByteArray = Pellets.poser(Maze)
	var supers: Array = Pellets.positions_super(Maze, grille)
	h.eq(supers.size(), 4, "pellets.invariants: quatre super-pastilles")

	# Une par quadrant — quadrants EXHAUSTIFS et deux a deux exclusifs.
	var vus := {0: 0, 1: 0, 2: 0, 3: 0}
	for p in supers:
		vus[Pellets.quadrant(Maze, p)] += 1
	h.eq(vus[0], 1, "pellets.invariants: une super-pastille au quadrant haut-gauche")
	h.eq(vus[1], 1, "pellets.invariants: une super-pastille au quadrant haut-droit")
	h.eq(vus[2], 1, "pellets.invariants: une super-pastille au quadrant bas-gauche")
	h.eq(vus[3], 1, "pellets.invariants: une super-pastille au quadrant bas-droit")
	h.eq(Pellets.une_super_par_quadrant(Maze, grille), true, "pellets.invariants: predicat de quadrant")

	# STRICTEMENT plus proche de son coin que de la maison — mesure par mesure.
	for p in supers:
		var d_coin: int = Maze.distance(p, Pellets.coin_le_plus_proche(Maze, p))
		var d_maison: int = Maze.distance(p, Maze.MAISON_CENTRE)
		h.lt(d_coin, d_maison, "pellets.invariants: super %s plus proche de son coin" % str(p))
	h.eq(Pellets.supers_plus_proches_de_leur_coin(Maze, grille), true,
		"pellets.invariants: predicat de proximite au coin")

	# Atteignabilite depuis la case de depart, collectible par collectible.
	var vues: Dictionary = Pellets.cases_atteignables(Maze, Maze.DEPART_PACMAN)
	var inatteignables: int = 0
	for i in range(grille.size()):
		if grille[i] != Pellets.Contenu.VIDE and not vues.has(Maze.case_de(i)):
			inatteignables += 1
	h.eq(inatteignables, 0, "pellets.invariants: aucun collectible inatteignable")
	h.eq(Pellets.tous_atteignables(Maze, grille, Maze.DEPART_PACMAN), true,
		"pellets.invariants: predicat d'atteignabilite")

	# CONTRE-EPREUVE du verificateur : un collectible pose sur une case de mur doit etre
	# declare inatteignable. Sans elle, le predicat pourrait rendre vrai en toutes
	# circonstances et l'invariant ne prouverait rien.
	var cassee: PackedByteArray = grille.duplicate()
	cassee[Maze.index_de(Vector2i(0, 0))] = Pellets.Contenu.PASTILLE
	h.eq(Pellets.tous_atteignables(Maze, cassee, Maze.DEPART_PACMAN), false,
		"pellets.invariants: une carte cassee est declaree inatteignable")

	# --- BRANCHES NEGATIVES DES DEUX VERIFICATEURS -----------------------------------
	# Le gate de mutation a montre que seules les branches CONFORMES etaient exercees :
	# un verificateur qu'on n'observe que sur un cas valide ne prouve pas qu'il refuse.
	# On lui donne donc des cartes qui VIOLENT chaque invariant, une par une.

	# (a) DEUX super-pastilles dans le meme quadrant, zero dans un autre.
	var deux_dans_un_quadrant: PackedByteArray = grille.duplicate()
	var a_deplacer: Vector2i = supers[3]
	deux_dans_un_quadrant[Maze.index_de(a_deplacer)] = Pellets.Contenu.PASTILLE
	var voisine_du_premier := Vector2i(supers[0].x + 1, supers[0].y)
	deux_dans_un_quadrant[Maze.index_de(voisine_du_premier)] = Pellets.Contenu.SUPER
	h.eq(Pellets.quadrant(Maze, voisine_du_premier), Pellets.quadrant(Maze, supers[0]),
		"pellets.invariants: fixture — la super deplacee tombe dans le meme quadrant")
	h.eq(Pellets.une_super_par_quadrant(Maze, deux_dans_un_quadrant), false,
		"pellets.invariants: deux super-pastilles dans un quadrant sont REFUSEES")

	# (b) Un quadrant SANS aucune super-pastille (une seule retiree).
	var un_quadrant_vide: PackedByteArray = grille.duplicate()
	un_quadrant_vide[Maze.index_de(supers[2])] = Pellets.Contenu.PASTILLE
	h.eq(Pellets.une_super_par_quadrant(Maze, un_quadrant_vide), false,
		"pellets.invariants: un quadrant sans super-pastille est REFUSE")

	# (c) Une super-pastille STRICTEMENT plus proche de la maison que de son coin.
	var collee_a_la_maison: PackedByteArray = grille.duplicate()
	var pres_maison: Vector2i = Vector2i(Maze.MAISON_CENTRE.x, Maze.MAISON_CENTRE.y + 3)
	collee_a_la_maison[Maze.index_de(pres_maison)] = Pellets.Contenu.SUPER
	h.lt(Maze.distance(pres_maison, Maze.MAISON_CENTRE),
		Maze.distance(pres_maison, Pellets.coin_le_plus_proche(Maze, pres_maison)),
		"pellets.invariants: fixture — cette case est bien plus proche de la maison")
	h.eq(Pellets.supers_plus_proches_de_leur_coin(Maze, collee_a_la_maison), false,
		"pellets.invariants: une super-pastille collee a la maison est REFUSEE")

	# (d) EGALITE des deux distances : le predicat exige du STRICT, donc il refuse.
	var equidistante: PackedByteArray = PackedByteArray()
	equidistante.resize(grille.size())
	# (7,8) : 15 cases du coin (0,0), 15 cases de la maison (13,17). Egalite exacte.
	var mi_chemin := Vector2i(7, 8)
	equidistante[Maze.index_de(mi_chemin)] = Pellets.Contenu.SUPER
	h.eq(Maze.distance(mi_chemin, Pellets.coin_le_plus_proche(Maze, mi_chemin)),
		Maze.distance(mi_chemin, Maze.MAISON_CENTRE),
		"pellets.invariants: fixture — distances au coin et a la maison EGALES")
	h.eq(Pellets.supers_plus_proches_de_leur_coin(Maze, equidistante), false,
		"pellets.invariants: l'egalite est REFUSEE — l'exigence est stricte")

	# La carte de reference passe toujours les deux verificateurs : ils refusent le
	# faux SANS refuser le vrai.
	h.eq(Pellets.une_super_par_quadrant(Maze, grille), true, "pellets.invariants: la carte de reference passe (quadrants)")
	h.eq(Pellets.supers_plus_proches_de_leur_coin(Maze, grille), true, "pellets.invariants: la carte de reference passe (coins)")

	# Toutes les cases praticables sont atteignables : le labyrinthe est d'un seul tenant.
	var praticables: int = 0
	for y in range(Maze.HAUTEUR):
		for x in range(Maze.LARGEUR):
			if Maze.praticable(Vector2i(x, y)):
				praticables += 1
	h.eq(vues.size(), praticables, "pellets.invariants: le labyrinthe est d'un seul tenant")
