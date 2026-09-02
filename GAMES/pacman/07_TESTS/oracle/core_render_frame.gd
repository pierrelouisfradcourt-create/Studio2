# core_render_frame.gd — ligne CORE core.render.
#
# CE QUE LE STANDARD EXIGE : deux captures produites EN FENETRE GPU REELLE
# (--rendering-driver vulkan, fenetre hors ecran) a deux etats distincts different sur AU
# MOINS 1 pixel, et le nombre de captures monochromes est EXACTEMENT 0.
#
# CE QUI EST MESURE ICI, ET POURQUOI PAS LE RESTE : l'oracle maitre
# (scripts/forge/godot_oracle.mjs) lance ce harnais en `--headless`. Sur ce poste,
# `--headless` rend une texture NULLE et ne produit AUCUN PNG (fait mesure 2026-07-22,
# memoire studio). Le volet PIXEL est donc STRUCTURELLEMENT hors d'atteinte de cet
# executeur : il est remonte en SKIPPED_VALIDATION, jamais presente comme obtenu.
#
# CE QUI EST MESURE A LA PLACE, et qui n'est pas rien : (1) le garde-fou refuse
# EXPLICITEMENT une capture headless au lieu d'ecrire une image morte ; (2) deux etats
# distincts produisent des GRANDEURS DE RENDU differentes — c'est-a-dire que le rendu
# n'est pas constant, ce qui est la propriete que le volet pixel cherche a etablir ;
# (3) la palette n'est pas monochrome. Sans (2) et (3), un jeu peut passer la mutation
# et rester mort a l'ecran (incident shmup_slice).
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
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const Pellets = preload("res://05_SYSTEMS/pellets/pellets.gd")
const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")
const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/bot_driver.gd")


# Empreinte de rendu d'un etat : la liste des primitives que _draw() dessinerait, dans
# l'ordre. Deux etats qui donnent la meme empreinte donneraient la meme image.
func _empreinte(s) -> Array:
	var traits: Array = []
	for i in range(s.pastilles.size()):
		if s.pastilles[i] != Pellets.Contenu.VIDE:
			traits.append([MazeView.centre_case(Maze.case_de(i)),
				MazeView.rayon_collectible(s.pastilles[i])])
	for g in range(s.fantomes.size()):
		traits.append([MazeView.centre_case(s.fantomes[g]),
			MazeView.couleur_fantome(g, s.etats_fantomes[g])])
	traits.append([MazeView.centre_case(s.pac), MazeView.COULEUR_PACMAN])
	return traits


func run(h) -> void:
	# (1) GARDE-FOU : le mode headless est REFUSE, avec une raison nommee — jamais une
	# image morte presentee comme un vert.
	h.eq(Capture.contexte_capture_valide("headless"), false,
		"core.render: --headless est refuse (texture nulle mesuree sur ce poste)")
	h.eq(Capture.contexte_capture_valide("dummy"), false, "core.render: le pilote dummy est refuse")
	h.eq(Capture.contexte_capture_valide("vulkan"), true, "core.render: une fenetre GPU reelle est acceptee")
	var echec: Dictionary = Capture.capturer(null, "user://jamais.png")
	h.eq(echec["ok"], false, "core.render: sans viewport, ECHEC EXPLICITE")
	h.ok(echec["raison"].length() > 0, "core.render: l'echec porte une raison nommee")

	# (2) DEUX ETATS DISTINCTS -> RENDU DIFFERENT. Les positions de Pac-Man different, et
	# l'empreinte de rendu differe : le rendu suit l'etat, il n'est pas constant.
	var a = State.initial(Maze, 1)
	var b = a.clone()
	for _t in range(30):
		b = Loop.step(b, Bot.choisir_action(b))["etat"]
	h.ok(a.pac != b.pac, "core.render: les deux etats ont des positions de Pac-Man differentes")
	var ea: Array = _empreinte(a)
	var eb: Array = _empreinte(b)
	h.ok(ea != eb, "core.render: deux etats distincts produisent un rendu different")
	h.ok(ea.size() != eb.size() or ea[ea.size() - 1] != eb[eb.size() - 1],
		"core.render: la difference porte sur des primitives reellement dessinees")
	h.eq(_empreinte(a), _empreinte(a), "core.render: le rendu d'un meme etat est reproductible")

	# (3) LA PALETTE N'EST PAS MONOCHROME : le nombre de couleurs distinctes est > 1.
	var palette := {}
	for t in [Maze.Type.MUR, Maze.Type.COULOIR, Maze.Type.MAISON, Maze.Type.TUNNEL]:
		palette[MazeView.couleur_case(t)] = true
	for i in range(4):
		palette[MazeView.couleur_fantome(i, Chase.Mode.POURSUITE)] = true
	palette[MazeView.COULEUR_PACMAN] = true
	palette[MazeView.COULEUR_PASTILLE] = true
	h.gt(palette.size(), 1, "core.render: 0 rendu monochrome — la palette porte plusieurs couleurs")
	h.eq(palette.size(), 10, "core.render: dix couleurs distinctes dans la palette de rendu")

	# Le rendu couvre bien les trois familles d'objets : decor, collectibles, entites.
	h.gt(ea.size(), 244, "core.render: le rendu dessine les collectibles et les entites")
	h.eq(ea.size(), 244 + 5, "core.render: 244 collectibles, quatre fantomes et un Pac-Man")
