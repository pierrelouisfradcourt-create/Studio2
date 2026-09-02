# pellets.gd — collectibles (lignes pellets.layout, pellets.map_invariants,
# pellets.consume, pellets.total_from_descriptor, pellets.total_on_switch).
#
# V2 : toutes les fonctions qui dependent d'une carte la recoivent EN ARGUMENT. Le
# TOTAL pose est PRODUIT par comptage de ce qui a ete pose — jamais un litteral recopie
# carte par carte : une carte a 172 collectibles se gagne sans qu'aucune constante bouge.
#
# Logique PURE. Ne depend que de maze.
extends RefCounted

const Maze = preload("res://05_SYSTEMS/maze/maze.gd")
const Schema = preload("res://05_SYSTEMS/map_schema/map_schema.gd")

# Vocabulaire ferme du contenu d'une case.
enum Contenu { VIDE, PASTILLE, SUPER }


# Pose les collectibles en lisant la LEGENDE de la carte RECUE (ligne pellets.layout).
# Retourne un tableau plat indexe par carte.index_de : ordre deterministe, jamais un
# parcours de Dictionary.
static func poser(carte) -> PackedByteArray:
	var grille := PackedByteArray()
	grille.resize(carte.LARGEUR * carte.HAUTEUR)
	for y in range(carte.HAUTEUR):
		for x in range(carte.LARGEUR):
			var p := Vector2i(x, y)
			var s: String = carte.symbole(p)
			var v: int = Contenu.VIDE
			if Schema.porte_pastille(s):
				v = Contenu.PASTILLE
			elif Schema.porte_super(s):
				v = Contenu.SUPER
			grille[carte.index_de(p)] = v
	return grille


# Total pose : PRODUIT par comptage de ce qui a ete pose, jamais un litteral recopie.
static func total_pose(grille: PackedByteArray) -> int:
	var n: int = 0
	for i in range(grille.size()):
		if grille[i] != Contenu.VIDE:
			n += 1
	return n


static func compter(grille: PackedByteArray, contenu: int) -> int:
	var n: int = 0
	for i in range(grille.size()):
		if grille[i] == contenu:
			n += 1
	return n


static func contenu_de(carte, grille: PackedByteArray, p: Vector2i) -> int:
	if not carte.dans_grille(p):
		return Contenu.VIDE
	return grille[carte.index_de(p)]


# Positions des super-pastilles, dans l'ordre d'index plat (deterministe).
static func positions_super(carte, grille: PackedByteArray) -> Array:
	var sortie: Array = []
	for i in range(grille.size()):
		if grille[i] == Contenu.SUPER:
			sortie.append(carte.case_de(i))
	return sortie


# --- Invariants de carte (ligne pellets.map_invariants) -----------------------------
# Une et une seule super-pastille par quadrant de la grille.
static func quadrant(carte, p: Vector2i) -> int:
	var gauche: bool = p.x < carte.LARGEUR / 2
	var haut: bool = p.y < carte.HAUTEUR / 2
	if haut and gauche:
		return 0
	if haut and not gauche:
		return 1
	if not haut and gauche:
		return 2
	return 3


static func une_super_par_quadrant(carte, grille: PackedByteArray) -> bool:
	var vus: Array = [0, 0, 0, 0]
	for p in positions_super(carte, grille):
		vus[quadrant(carte, p)] += 1
	for n in vus:
		if n != 1:
			return false
	return true


# Coin de grille le plus proche d'une case (mesure unique : maze.distance).
static func coin_le_plus_proche(carte, p: Vector2i) -> Vector2i:
	var coins: Array = [
		Vector2i(0, 0),
		Vector2i(carte.LARGEUR - 1, 0),
		Vector2i(0, carte.HAUTEUR - 1),
		Vector2i(carte.LARGEUR - 1, carte.HAUTEUR - 1),
	]
	var meilleur: Vector2i = coins[0]
	var d: int = Maze.distance(p, meilleur)
	for c in coins:
		var dc: int = Maze.distance(p, c)
		if dc < d:
			d = dc
			meilleur = c
	return meilleur


# Chaque super-pastille est STRICTEMENT plus proche de son coin que de la maison.
static func supers_plus_proches_de_leur_coin(carte, grille: PackedByteArray) -> bool:
	for p in positions_super(carte, grille):
		var d_coin: int = Maze.distance(p, coin_le_plus_proche(carte, p))
		var d_maison: int = Maze.distance(p, carte.MAISON_CENTRE)
		if not (d_coin < d_maison):
			return false
	return true


# Atteignabilite : chaque collectible est atteignable depuis la case de depart, par
# parcours en largeur sur les voisins praticables (bouclage de tunnel compris).
static func cases_atteignables(carte, depart: Vector2i) -> Dictionary:
	var vues := {}
	if not carte.praticable(depart):
		return vues
	var file: Array = [depart]
	vues[depart] = true
	var tete: int = 0
	while tete < file.size():
		var c: Vector2i = file[tete]
		tete += 1
		for v in carte.voisins_praticables(c):
			if not vues.has(v):
				vues[v] = true
				file.append(v)
	return vues


static func tous_atteignables(carte, grille: PackedByteArray, depart: Vector2i) -> bool:
	var vues: Dictionary = cases_atteignables(carte, depart)
	for i in range(grille.size()):
		if grille[i] != Contenu.VIDE and not vues.has(carte.case_de(i)):
			return false
	return true


# --- Consommation (ligne pellets.consume) -------------------------------------------
# Consomme le collectible de la case occupee : efface la case et incremente le
# compteur. Une case deja videe n'est JAMAIS recomptee. Retourne le contenu consomme
# (Contenu.VIDE si rien) et la grille resultante.
static func consommer(carte, grille: PackedByteArray, p: Vector2i, consommees: int) -> Dictionary:
	var c: int = contenu_de(carte, grille, p)
	if c == Contenu.VIDE:
		return {"grille": grille, "consommees": consommees, "contenu": Contenu.VIDE}
	var suite := grille.duplicate()
	suite[carte.index_de(p)] = Contenu.VIDE
	return {"grille": suite, "consommees": consommees + 1, "contenu": c}
