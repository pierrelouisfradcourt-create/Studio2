# targeting_chase_targets.test.gd — ligne targeting.chase_targets, capacites F15..F18.
# Les quatre formules de case-cible en poursuite, chacune assertee a la valeur EXACTE.
extends RefCounted

const Targeting = preload("res://05_SYSTEMS/ghost_targeting/ghost_targeting.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())


func run(h) -> void:
	var pac := Vector2i(10, 20)
	var dir: Vector2i = Maze.DROITE
	var rouge := Vector2i(4, 20)
	var fantomes: Array = [rouge, Vector2i(2, 2), Vector2i(3, 3), Vector2i(25, 30)]

	# F15 — rouge : la case de Pac-Man, exactement.
	h.eq(Targeting.cible_poursuite(Maze, Targeting.ROUGE, pac, dir, fantomes), pac,
		"targeting.chase: le rouge vise la case de Pac-Man")

	# F16 — rose : quatre cases devant, dans la direction courante.
	h.eq(Targeting.cible_poursuite(Maze, Targeting.ROSE, pac, Maze.DROITE, fantomes), Vector2i(14, 20),
		"targeting.chase: le rose vise 4 cases devant (droite)")
	h.eq(Targeting.cible_poursuite(Maze, Targeting.ROSE, pac, Maze.HAUT, fantomes), Vector2i(10, 16),
		"targeting.chase: le rose vise 4 cases devant (haut)")
	h.eq(Targeting.cible_poursuite(Maze, Targeting.ROSE, pac, Maze.GAUCHE, fantomes), Vector2i(6, 20),
		"targeting.chase: le rose vise 4 cases devant (gauche)")

	# F17 — cyan : prolongement du segment rouge -> deux cases devant Pac-Man.
	# pivot = (12, 20) ; cible = 2 * pivot - rouge = (20, 20).
	h.eq(Targeting.cible_poursuite(Maze, Targeting.CYAN, pac, Maze.DROITE, fantomes), Vector2i(20, 20),
		"targeting.chase: le cyan prolonge le segment rouge -> pivot")
	# Le cyan DEPEND de la position du rouge : deplacer le rouge deplace la cible.
	var autres: Array = [Vector2i(6, 20), Vector2i(2, 2), Vector2i(3, 3), Vector2i(25, 30)]
	h.eq(Targeting.cible_poursuite(Maze, Targeting.CYAN, pac, Maze.DROITE, autres), Vector2i(18, 20),
		"targeting.chase: la cible cyan bouge avec le rouge")

	# F18 — orange : bascule EXACTEMENT au seuil, assertee a 9, 8 et 7.
	var pac_o := Vector2i(13, 20)
	var f9: Array = [rouge, Vector2i(2, 2), Vector2i(3, 3), Vector2i(13, 11)]
	h.eq(Targeting.distance(f9[3], pac_o), 9, "targeting.chase: fixture orange a 9")
	h.eq(Targeting.cible_poursuite(Maze, Targeting.ORANGE, pac_o, Maze.GAUCHE, f9), pac_o,
		"targeting.chase: a 9 l'orange vise Pac-Man")
	var f8: Array = [rouge, Vector2i(2, 2), Vector2i(3, 3), Vector2i(13, 12)]
	h.eq(Targeting.cible_poursuite(Maze, Targeting.ORANGE, pac_o, Maze.GAUCHE, f8),
		Targeting.cible_dispersion(Maze, Targeting.ORANGE), "targeting.chase: a 8 l'orange vise son coin")
	var f7: Array = [rouge, Vector2i(2, 2), Vector2i(3, 3), Vector2i(13, 13)]
	h.eq(Targeting.cible_poursuite(Maze, Targeting.ORANGE, pac_o, Maze.GAUCHE, f7),
		Targeting.cible_dispersion(Maze, Targeting.ORANGE), "targeting.chase: a 7 l'orange vise son coin")

	# VARIANCE : depuis un MEME etat, les quatre cibles ne sont pas toutes confondues.
	# Une regle de ciblage a variance nulle validerait le moteur sans rien poursuivre.
	var cibles: Array = []
	for i in range(4):
		cibles.append(Targeting.cible_poursuite(Maze, i, pac, dir, fantomes))
	var distinctes := {}
	for c in cibles:
		distinctes[c] = true
	h.gt(distinctes.size(), 1, "targeting.chase: les quatre cibles ne sont pas confondues")
	# Fixture ou l'orange est SOUS son seuil (distance 4) : il vise alors son coin, et
	# les quatre cibles sont deux a deux differentes. Au-dessus du seuil, rouge et orange
	# visent legitimement la MEME case — c'est la regle, pas un defaut de variance.
	var proches: Array = [rouge, Vector2i(2, 2), Vector2i(3, 3), Vector2i(12, 18)]
	h.eq(Targeting.distance(proches[3], pac), 4, "targeting.chase: fixture orange sous le seuil")
	var cibles_proches := {}
	for i in range(4):
		cibles_proches[Targeting.cible_poursuite(Maze, i, pac, dir, proches)] = true
	h.eq(cibles_proches.size(), 4, "targeting.chase: quatre cibles distinctes sous le seuil orange")
	h.eq(distinctes.size(), 3, "targeting.chase: au-dela du seuil, rouge et orange partagent la cible")

	# Purete : la meme entree rend la meme cible, toujours.
	h.eq(Targeting.cible_poursuite(Maze, Targeting.CYAN, pac, dir, fantomes),
		Targeting.cible_poursuite(Maze, Targeting.CYAN, pac, dir, fantomes),
		"targeting.chase: formule pure et deterministe")
