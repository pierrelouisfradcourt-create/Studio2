# targeting_scatter_corners.test.gd — ligne targeting.scatter_corners, capacite F19.
# Les quatre cibles de dispersion sont quatre coins DEUX A DEUX DIFFERENTS : aucune
# paire de fantomes ne partage sa cible pendant les fenetres de dispersion.
extends RefCounted

const Targeting = preload("res://05_SYSTEMS/ghost_targeting/ghost_targeting.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())


func run(h) -> void:
	var coins: Array = []
	for i in range(4):
		coins.append(Targeting.cible_dispersion(Maze, i))

	# Valeurs EXACTES, coin par coin.
	h.eq(coins[Targeting.ROUGE], Vector2i(Maze.LARGEUR - 1, 0), "targeting.scatter: rouge en haut a droite")
	h.eq(coins[Targeting.ROSE], Vector2i(0, 0), "targeting.scatter: rose en haut a gauche")
	h.eq(coins[Targeting.CYAN], Vector2i(Maze.LARGEUR - 1, Maze.HAUTEUR - 1), "targeting.scatter: cyan en bas a droite")
	h.eq(coins[Targeting.ORANGE], Vector2i(0, Maze.HAUTEUR - 1), "targeting.scatter: orange en bas a gauche")

	# Deux a deux differents — toutes les paires, jamais un echantillon.
	var paires_identiques: int = 0
	for i in range(coins.size()):
		for j in range(i + 1, coins.size()):
			if coins[i] == coins[j]:
				paires_identiques += 1
	h.eq(paires_identiques, 0, "targeting.scatter: aucune paire de cibles identiques")

	# Quatre coins DISTINCTS de la grille : un par angle.
	var vus := {}
	for c in coins:
		vus[c] = true
	h.eq(vus.size(), 4, "targeting.scatter: quatre cibles distinctes")

	# La cible de dispersion NE DEPEND PAS de Pac-Man : c'est ce qui cree les zones sures.
	h.eq(Targeting.cible_dispersion(Maze, Targeting.ROUGE), coins[Targeting.ROUGE],
		"targeting.scatter: cible constante, independante du joueur")
