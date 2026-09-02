# v2_targeting_corners_from_state_map.test.gd — ligne targeting.corners_from_state_map, capacite F100.
# Les COINS DE DISPERSION viennent de la carte PORTEE PAR L'ETAT et non d'une constante
# globale : une carte de dimensions differentes a ses propres coins sans qu'aucune
# formule de ciblage ne change.
extends RefCounted

const Targeting = preload("res://05_SYSTEMS/ghost_targeting/ghost_targeting.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))
var Alt = MazeClass.depuis_descripteur(ContentV2.descripteur(1))


func run(h) -> void:
	# Quatre coins DEUX A DEUX DIFFERENTS sur chaque carte.
	for carte in [Maze, Alt]:
		var vus: Array = []
		var doublons: int = 0
		for i in range(4):
			var c: Vector2i = Targeting.cible_dispersion(carte, i)
			if vus.has(c):
				doublons += 1
			vus.append(c)
		h.eq(doublons, 0, "targeting.corners: quatre coins deux a deux differents")

	# Les coins SUIVENT les dimensions de la carte.
	h.eq(Targeting.cible_dispersion(Maze, 0), Vector2i(27, 0), "targeting.corners: coin rouge nominal")
	h.eq(Targeting.cible_dispersion(Maze, 1), Vector2i(0, 0), "targeting.corners: coin rose nominal")
	h.eq(Targeting.cible_dispersion(Maze, 2), Vector2i(27, 35), "targeting.corners: coin cyan nominal")
	h.eq(Targeting.cible_dispersion(Maze, 3), Vector2i(0, 35), "targeting.corners: coin orange nominal")
	h.eq(Targeting.cible_dispersion(Alt, 0), Vector2i(20, 0), "targeting.corners: coin rouge alternatif")
	h.eq(Targeting.cible_dispersion(Alt, 2), Vector2i(20, 23), "targeting.corners: coin cyan alternatif")
	h.ok(Targeting.cible_dispersion(Maze, 0) != Targeting.cible_dispersion(Alt, 0),
		"targeting.corners: le coin change avec la carte")

	# LE MODULE ne porte aucune constante de coin : la valeur vient de l'argument.
	var f := FileAccess.open("res://05_SYSTEMS/ghost_targeting/ghost_targeting.gd", FileAccess.READ)
	var texte: String = f.get_as_text() if f != null else ""
	h.eq(texte.contains("const COINS"), false, "targeting.corners: aucune constante de coins")
	h.eq(texte.contains("Vector2i(27"), false, "targeting.corners: aucune coordonnee de carte")

	# La FORMULE de poursuite est inchangee et s'applique aux deux cartes.
	var fantomes: Array = [Vector2i(5, 5), Vector2i(6, 6), Vector2i(7, 7), Vector2i(8, 8)]
	h.eq(Targeting.cible_poursuite(Maze, Targeting.ROUGE, Vector2i(3, 3), MazeClass.DROITE, fantomes),
		Vector2i(3, 3), "targeting.corners: le rouge vise Pac-Man, quelle que soit la carte")
	h.eq(Targeting.cible_poursuite(Alt, Targeting.ROUGE, Vector2i(3, 3), MazeClass.DROITE, fantomes),
		Vector2i(3, 3), "targeting.corners: idem sur la seconde carte")
	# L'orange bascule sur SON coin, donc sur celui de SA carte.
	var proche: Array = [Vector2i(5, 5), Vector2i(6, 6), Vector2i(7, 7), Vector2i(3, 4)]
	h.eq(Targeting.cible_poursuite(Alt, Targeting.ORANGE, Vector2i(3, 3), MazeClass.DROITE, proche),
		Targeting.cible_dispersion(Alt, Targeting.ORANGE), "targeting.corners: l'orange vise le coin de sa carte")
