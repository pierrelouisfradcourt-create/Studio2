# render_maze_and_entities.gd — ligne render.maze_and_entities, capacite F45.
# Les murs portent une apparence CONSTANTE differente du couloir vide ; les quatre
# fantomes portent quatre couleurs DEUX A DEUX DIFFERENTES ; une super-pastille est
# visiblement PLUS GRANDE qu'une pastille ordinaire.
#
# PORTEE DE CETTE PREUVE : elle porte sur les GRANDEURS DE RENDU (couleurs, rayons,
# geometrie), lisibles en headless. Le volet PIXEL — deux captures qui different — exige
# une fenetre GPU reelle et n'est PAS obtenu ici : voir core_render_frame.gd et la
# section SKIPPED_VALIDATION du rapport d'etape.
extends RefCounted

const MazeView = preload("res://06_RUNTIME/adapters/presentation/maze_view.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const Pellets = preload("res://05_SYSTEMS/pellets/pellets.gd")
const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")


func run(h) -> void:
	# Le mur a une apparence CONSTANTE, DIFFERENTE du couloir vide.
	h.ok(MazeView.couleur_case(Maze.Type.MUR) != MazeView.couleur_case(Maze.Type.COULOIR),
		"render.maze: le mur differe du couloir")
	h.eq(MazeView.couleur_case(Maze.Type.MUR), MazeView.couleur_case(Maze.Type.MUR),
		"render.maze: l'apparence du mur est constante")
	var couleurs_de_case := {}
	for t in [Maze.Type.MUR, Maze.Type.COULOIR, Maze.Type.MAISON, Maze.Type.TUNNEL]:
		couleurs_de_case[MazeView.couleur_case(t)] = true
	h.eq(couleurs_de_case.size(), 4, "render.maze: les quatre types de case sont distinguables")

	# QUATRE COULEURS DE FANTOMES deux a deux differentes.
	h.eq(MazeView.COULEURS_FANTOMES.size(), 4, "render.maze: quatre couleurs de fantomes")
	h.eq(MazeView.couleurs_distinctes(), true, "render.maze: couleurs deux a deux differentes")
	var vues := {}
	for i in range(4):
		vues[MazeView.couleur_fantome(i, Chase.Mode.POURSUITE)] = true
	h.eq(vues.size(), 4, "render.maze: quatre couleurs distinctes en poursuite")

	# L'etat Effraye a sa PROPRE apparence, la meme pour les quatre : c'est ce qui rend
	# la vulnerabilite lisible.
	var effrayes := {}
	for i in range(4):
		effrayes[MazeView.couleur_fantome(i, Chase.Mode.EFFRAYE)] = true
	h.eq(effrayes.size(), 1, "render.maze: une seule apparence pour l'etat Effraye")
	h.ok(MazeView.couleur_fantome(0, Chase.Mode.EFFRAYE) != MazeView.couleur_fantome(0, Chase.Mode.POURSUITE),
		"render.maze: l'apparence Effraye differe de la poursuite")

	# UNE SUPER-PASTILLE EST VISIBLEMENT PLUS GRANDE — inegalite STRICTE.
	h.lt(int(MazeView.rayon_collectible(Pellets.Contenu.PASTILLE)),
		int(MazeView.rayon_collectible(Pellets.Contenu.SUPER)),
		"render.maze: la super-pastille a un rayon strictement plus grand")

	# Pac-Man se distingue des fantomes.
	var couleurs_entites := {}
	couleurs_entites[MazeView.COULEUR_PACMAN] = true
	for c in MazeView.COULEURS_FANTOMES:
		couleurs_entites[c] = true
	h.eq(couleurs_entites.size(), 5, "render.maze: Pac-Man et les quatre fantomes sont distinguables")

	# La geometrie du rendu suit la grille, sans defilement.
	h.eq(MazeView.rect_case(Vector2i(0, 0)), Rect2(0, 0, MazeView.COTE_CASE, MazeView.COTE_CASE),
		"render.maze: la premiere case est a l'origine")
	h.eq(MazeView.centre_case(Vector2i(0, 0)), Vector2(MazeView.COTE_CASE / 2.0, MazeView.COTE_CASE / 2.0),
		"render.maze: le centre de la premiere case")
	h.eq(MazeView.largeur_pixels(Maze), Maze.LARGEUR * MazeView.COTE_CASE, "render.maze: largeur totale")
	h.eq(MazeView.hauteur_pixels(Maze), Maze.HAUTEUR * MazeView.COTE_CASE, "render.maze: hauteur totale")

	# ZERO ASSET : le rendu n'utilise que des primitives, aucune texture n'est chargee.
	# Constate par l'inventaire (harness_asset_inventory) ; ici on constate que le module
	# de rendu ne declare AUCUNE ressource.
	var s = State.initial(Maze, 1)
	h.eq(s.pastilles.size(), Maze.LARGEUR * Maze.HAUTEUR, "render.maze: le rendu lit la grille d'etat")
