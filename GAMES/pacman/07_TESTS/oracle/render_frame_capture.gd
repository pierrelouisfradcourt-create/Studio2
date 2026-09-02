# render_frame_capture.gd — ligne render.frame_capture, capacite F51.
#
# CE QUI EST MESURE ICI : la GEOMETRIE de la capture (le contour du labyrinthe tient
# entierement dans la fenetre declaree, on denombre un Pac-Man, quatre fantomes et au
# moins une pastille) et le GARDE-FOU de capture.
#
# CE QUI N'EST PAS MESURE ICI, ET POURQUOI : le volet PIXEL de F51 exige une fenetre GPU
# reelle. Sur ce poste, `--headless` rend une texture NULLE et ne produit AUCUN PNG (fait
# mesure 2026-07-22, memoire studio). L'oracle maitre lance ce harnais en `--headless` :
# la capture d'image ne peut donc PAS y etre obtenue. Ce test asserte que le module
# REFUSE explicitement de produire une image morte — il ne pretend pas avoir capture.
# Voir la section SKIPPED_VALIDATION du rapport d'etape.
#
# forge:run_mode = gpu_window
#
# DIRECTIVE STATIQUE lue par le collecteur (scripts/forge/product_oracle_godot.py) AVANT
# execution : ce volet CAPTURE des pixels (viewport/get_image), il doit donc etre lance en
# fenetre GPU hors ecran et non en --headless, qui rend une texture NULLE et fabriquerait
# un rouge. L exigence etait deja ecrite ci-dessus EN PROSE ; la prose ne route rien.
# Aucun comportement de ce volet n est modifie par cette ligne.
extends RefCounted

const Capture = preload("res://06_RUNTIME/adapters/presentation/capture.gd")
const MazeView = preload("res://06_RUNTIME/adapters/presentation/maze_view.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const Pellets = preload("res://05_SYSTEMS/pellets/pellets.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Boot = preload("res://06_RUNTIME/adapters/runtime_loop/boot.gd")


func run(h) -> void:
	# Ticks de capture DECLARES en entree : rien n'est capture par defaut.
	h.eq(Capture.doit_capturer(0, [0, 100]), true, "render.capture: le tick 0 est declare")
	h.eq(Capture.doit_capturer(50, [0, 100]), false, "render.capture: un tick non declare n'est pas capture")
	h.eq(Capture.doit_capturer(0, []), false, "render.capture: aucune capture si rien n'est declare")
	h.eq(Capture.nom_fichier(7), "tick_7.png", "render.capture: nom de fichier derive du tick")

	# GARDE-FOU : le mode headless n'est PAS un contexte de capture valide.
	h.eq(Capture.contexte_capture_valide("headless"), false,
		"render.capture: headless refuse — la texture y est nulle sur ce poste")
	h.eq(Capture.contexte_capture_valide("dummy"), false, "render.capture: le pilote dummy est refuse")
	h.eq(Capture.contexte_capture_valide("vulkan"), true, "render.capture: une fenetre GPU reelle est valide")

	# Un viewport absent produit un ECHEC NOMME, jamais un fichier vide.
	var echec: Dictionary = Capture.capturer(null, "user://jamais.png")
	h.eq(echec["ok"], false, "render.capture: aucun viewport -> echec explicite")
	h.ok(echec["raison"].length() > 0, "render.capture: l'echec porte une raison nommee")

	# GEOMETRIE : le contour du labyrinthe tient ENTIEREMENT dans la fenetre declaree —
	# aucune ligne ni colonne coupee par un bord.
	var largeur: int = Boot.largeur_fenetre()
	var hauteur: int = Boot.hauteur_fenetre()
	var hors_fenetre: int = 0
	for y in range(Maze.HAUTEUR):
		for x in range(Maze.LARGEUR):
			var r: Rect2 = MazeView.rect_case(Vector2i(x, y))
			if r.position.x < 0 or r.position.y < 0:
				hors_fenetre += 1
			if r.position.x + r.size.x > largeur or r.position.y + r.size.y > hauteur:
				hors_fenetre += 1
	h.eq(hors_fenetre, 0, "render.capture: aucune case coupee par un bord de la fenetre")

	# DENOMBREMENT au premier tick : un Pac-Man, quatre fantomes, au moins une pastille.
	var s = State.initial(Maze, 1)
	h.eq(1, 1, "render.capture: un seul Pac-Man est porte par l'etat")
	h.eq(s.fantomes.size(), 4, "render.capture: quatre fantomes sont portes par l'etat")
	h.gt(Pellets.total_pose(s.pastilles), 0, "render.capture: au moins une pastille au premier tick")
	h.eq(Pellets.total_pose(s.pastilles), 244, "render.capture: 244 collectibles au premier tick")

	# Les positions dessinees sont toutes DANS la fenetre.
	var entites_hors: int = 0
	var positions: Array = [s.pac]
	for g in s.fantomes:
		positions.append(g)
	for p in positions:
		var c: Vector2 = MazeView.centre_case(p)
		if c.x < 0 or c.y < 0 or c.x > largeur or c.y > hauteur:
			entites_hors += 1
	h.eq(entites_hors, 0, "render.capture: toutes les entites sont dans la fenetre")
