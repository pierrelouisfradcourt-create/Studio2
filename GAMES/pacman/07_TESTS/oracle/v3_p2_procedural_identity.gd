# v3_p2_procedural_identity.gd — CAUSE RACINE P2.
#
# DEFAUT MESURE (playtest Pierre) : le rendu etait fait de PRIMITIVES SANS IDENTITE — un
# rectangle plein par case, un disque par entite. Aucun oracle ne le voyait, parce
# qu'aucun oracle ne mesurait autre chose que des couleurs et des rayons.
#
# INVARIANT NON NEGOCIABLE : aucun fichier importe (charter_v2.hors_scope[10]). La voie
# retenue par Pierre est PROCEDURALE. Cette preuve mesure donc les GRANDEURS de la forme
# et de l'animation, pas des pixels : silhouettes non degenerees, orientations deux a
# deux differentes, et — regle de variance ratifiee Pierre 2026-07-21 — au moins DEUX
# valeurs distinctes non triviales pour chaque grandeur animee. Une animation a variance
# nulle est un dessin fixe qui porte le nom d'une animation.
#
# CE QUI N'EST PAS MESURE ICI, ET POURQUOI : la comparaison de PIXELS exige une fenetre
# GPU reelle (`--headless` rend une texture nulle, mesure au studio le 2026-07-22). Le
# volet pixel reste NOT_MEASURED motive — il n'est pas transforme en vert.
extends RefCounted

const MazeView = preload("res://06_RUNTIME/adapters/presentation/maze_view.gd")
const Palette = preload("res://06_RUNTIME/adapters/palette/palette.gd")
const Purity = preload("res://06_RUNTIME/adapters/proof_harness/harness_purity_counts.gd")
const Maze = preload("res://05_SYSTEMS/maze/maze.gd")
const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")
const Pellets = preload("res://05_SYSTEMS/pellets/pellets.gd")
const InventoryV2 = preload("res://06_RUNTIME/adapters/proof_harness/harness_asset_inventory_v2.gd")
const Inventory = preload("res://06_RUNTIME/adapters/proof_harness/asset_inventory.gd")


func run(h) -> void:
	# --- L'INVARIANT D'ABORD : l'identite est PROCEDURALE, donc zero fichier. ---
	var inv: Dictionary = Inventory.mesurer()
	h.eq(inv["assets_importes"], 0, "v3.p2: 0 asset importe apres l'habillage")
	h.eq(InventoryV2.mesurer()["fichiers_audio"], 0, "v3.p2: 0 fichier audio non plus")
	h.eq(Purity.couleur_hors_palette().size(), 0, "v3.p2: 0 couleur hors du descripteur")
	h.eq(Purity.couleur_dans_logique().size(), 0, "v3.p2: 0 couleur dans la logique")

	# --- SILHOUETTE DU JOUEUR : un secteur, pas un disque. ---
	var centre := Vector2(100.0, 100.0)
	var poly_ouvert: PackedVector2Array = MazeView.polygone_pacman(centre, 8.0, Maze.DROITE, 0)
	h.gt(poly_ouvert.size(), 3, "v3.p2: la silhouette du joueur a une vraie forme")
	h.eq(poly_ouvert[0], centre, "v3.p2: l'echancrure part du centre")
	var hors_rayon: int = 0
	for i in range(1, poly_ouvert.size()):
		if centre.distance_to(poly_ouvert[i]) > 8.0001:
			hors_rayon += 1
	h.eq(hors_rayon, 0, "v3.p2: aucun point de la silhouette ne sort de son rayon")

	# VARIANCE DE LA BOUCHE : la valeur PARCOURT son intervalle sur une periode.
	var ouvertures: Array = []
	for t in range(MazeView.PERIODE_BOUCHE * 2):
		var v: float = MazeView.ouverture_bouche(t)
		if not ouvertures.has(v):
			ouvertures.append(v)
	h.gt(ouvertures.size(), 1, "v3.p2: la bouche prend au moins deux valeurs distinctes")
	h.gt(int(MazeView.ouverture_bouche(MazeView.PERIODE_BOUCHE / 2) * 1000.0),
		int(MazeView.ouverture_bouche(0) * 1000.0),
		"v3.p2: la bouche s'ouvre reellement au cours du cycle")
	h.eq(MazeView.ouverture_bouche(0), MazeView.ouverture_bouche(MazeView.PERIODE_BOUCHE),
		"v3.p2: l'animation boucle sur sa periode")

	# ORIENTATION : quatre directions, quatre angles DEUX A DEUX DIFFERENTS.
	var angles: Array = []
	for d in Maze.DIRECTIONS:
		var a: float = MazeView.angle_regard(d)
		if not angles.has(a):
			angles.append(a)
	h.eq(angles.size(), 4, "v3.p2: quatre orientations distinctes")
	h.eq(MazeView.angle_regard(Maze.AUCUNE), MazeView.angle_regard(Maze.DROITE),
		"v3.p2: une direction nulle a une orientation declaree")
	# La silhouette SUIT l'orientation : deux directions donnent deux formes differentes.
	var poly_gauche: PackedVector2Array = MazeView.polygone_pacman(centre, 8.0, Maze.GAUCHE, 0)
	h.ok(poly_ouvert != poly_gauche, "v3.p2: la silhouette suit la direction du joueur")

	# --- SILHOUETTE DES FANTOMES : dome + jupe festonnee + yeux. ---
	var fantome: PackedVector2Array = MazeView.polygone_fantome(centre, 8.0)
	h.gt(fantome.size(), 8, "v3.p2: le fantome a une silhouette, pas un disque")
	var hauts: int = 0
	var bas: int = 0
	for p in fantome:
		if p.y < centre.y:
			hauts += 1
		if p.y > centre.y:
			bas += 1
	h.gt(hauts, 0, "v3.p2: la silhouette a un dome")
	h.gt(bas, 0, "v3.p2: la silhouette a une jupe")
	# FESTONNAGE : la jupe alterne deux hauteurs, sinon ce serait un rectangle.
	var hauteurs_jupe: Array = []
	for i in range(fantome.size()):
		if fantome[i].y > centre.y and not hauteurs_jupe.has(fantome[i].y):
			hauteurs_jupe.append(fantome[i].y)
	h.gt(hauteurs_jupe.size(), 1, "v3.p2: la jupe est festonnee, pas plate")

	# YEUX : deux, distincts, et la pupille SE DEPLACE avec la direction.
	var yeux: Array = MazeView.centres_yeux(centre, 8.0)
	h.eq(yeux.size(), 2, "v3.p2: deux yeux")
	h.ok(yeux[0] != yeux[1], "v3.p2: les deux yeux sont a deux endroits")
	var regards: Array = []
	for d in Maze.DIRECTIONS:
		var dec: Vector2 = MazeView.decalage_pupille(d, 8.0)
		if not regards.has(dec):
			regards.append(dec)
	h.eq(regards.size(), 4, "v3.p2: la pupille prend quatre positions distinctes")
	h.eq(MazeView.decalage_pupille(Maze.AUCUNE, 8.0), Vector2.ZERO,
		"v3.p2: sans direction, la pupille reste centree")

	# --- CLIGNOTEMENT DE FIN D'EFFROI : deux teintes, pas une. ---
	var teintes: Array = []
	for t in range(MazeView.PERIODE_CLIGNOTEMENT * 4):
		var c: Color = MazeView.couleur_fantome_animee(0, Chase.Mode.EFFRAYE, 1, t)
		if not teintes.has(c):
			teintes.append(c)
	h.eq(teintes.size(), 2, "v3.p2: la fin d'effroi alterne deux teintes")
	# LOIN de la fin, la teinte est STABLE : le clignotement porte une information.
	var stables: Array = []
	for t in range(MazeView.PERIODE_CLIGNOTEMENT * 4):
		var c2: Color = MazeView.couleur_fantome_animee(
			0, Chase.Mode.EFFRAYE, MazeView.SEUIL_CLIGNOTEMENT + 100, t)
		if not stables.has(c2):
			stables.append(c2)
	h.eq(stables.size(), 1, "v3.p2: loin de la fin, l'effroi ne clignote pas")
	h.eq(MazeView.couleur_fantome_animee(1, Chase.Mode.POURSUITE, 0, 3), Palette.FANTOMES[1],
		"v3.p2: hors effroi, le fantome garde sa couleur nominative")

	# --- COLLECTIBLES : halo, teinte propre, battement de la super-pastille. ---
	h.ok(MazeView.couleur_collectible(Pellets.Contenu.SUPER)
		!= MazeView.couleur_collectible(Pellets.Contenu.PASTILLE),
		"v3.p2: la super-pastille a sa propre teinte")
	var rayons: Array = []
	for t in range(MazeView.PERIODE_PULSATION * 2):
		var r: float = MazeView.rayon_collectible_anime(Pellets.Contenu.SUPER, t, MazeView.COTE_CASE)
		if not rayons.has(r):
			rayons.append(r)
	h.gt(rayons.size(), 1, "v3.p2: la super-pastille bat (au moins deux rayons distincts)")
	var rayons_simples: Array = []
	for t2 in range(MazeView.PERIODE_PULSATION * 2):
		var r2: float = MazeView.rayon_collectible_anime(Pellets.Contenu.PASTILLE, t2, MazeView.COTE_CASE)
		if not rayons_simples.has(r2):
			rayons_simples.append(r2)
	h.eq(rayons_simples.size(), 1, "v3.p2: une pastille ordinaire ne bat pas")

	# --- MURS EN RELIEF : arete et creux sont deux couleurs, contrastees. ---
	h.ok(Palette.MUR_ARETE != Palette.MUR_CREUX, "v3.p2: l'arete du mur differe de son creux")
	h.gt(int(Palette.ecart_de_luminance(Palette.MUR_ARETE, Palette.MUR_CREUX) * 1000.0), 50,
		"v3.p2: le relief du mur est contraste")
	h.gt(int(Palette.ecart_de_luminance(Palette.MUR_ARETE, Palette.COULOIR) * 1000.0), 50,
		"v3.p2: le mur se detache du couloir")
	h.ok(Palette.HORS_JEU != Palette.COULOIR, "v3.p2: le hors-jeu ne se lit pas comme un couloir")

	# --- LE DESCRIPTEUR NE REPETE PAS UNE TEINTE SOUS DEUX NOMS. ---
	h.eq(Palette.paires_identiques(), 0, "v3.p2: 0 paire de couleurs identiques dans la palette")
	h.eq(Palette.fantomes_distincts(), true, "v3.p2: les quatre fantomes restent distincts")
