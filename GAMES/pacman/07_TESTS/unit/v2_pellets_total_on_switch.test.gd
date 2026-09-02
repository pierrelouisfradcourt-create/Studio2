# v2_pellets_total_on_switch.test.gd — ligne pellets.total_on_switch, capacite F106.
# A la bascule, les collectibles sont reposes au total de la CARTE SUIVANTE : les
# pastilles restantes valent exactement ce nouveau total, JAMAIS le reliquat de la
# carte precedente.
extends RefCounted

const Pellets = preload("res://05_SYSTEMS/pellets/pellets.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Progression = preload("res://05_SYSTEMS/level_progression/level_progression.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))
var Alt = MazeClass.depuis_descripteur(ContentV2.descripteur(1))


func run(h) -> void:
	# Partie sur la carte nominale, plusieurs collectibles consommes.
	var jeu = State.initial(Maze, 7)
	for _t in range(20):
		jeu = Loop.step(jeu, Maze.DEPART_DIRECTION)["etat"]
	h.gt(jeu.consommees, 0, "pellets.switch: des collectibles ont ete consommes avant la bascule")
	var restantes_avant: int = jeu.total_pose - jeu.consommees

	# BASCULE vers la seconde carte.
	var suite = Progression.basculer(jeu, Alt, ContentV2.cadence(1), 7)
	var total_alt: int = Pellets.total_pose(Pellets.poser(Alt))
	h.eq(suite.total_pose, total_alt, "pellets.switch: le total est celui de la carte suivante")
	h.eq(suite.consommees, 0, "pellets.switch: aucun collectible n'est deja consomme")
	h.eq(suite.total_pose - suite.consommees, total_alt, "pellets.switch: restantes = total de la nouvelle carte")
	h.ok(suite.total_pose - suite.consommees != restantes_avant,
		"pellets.switch: le reliquat de la carte precedente ne survit pas")
	h.ok(suite.total_pose != jeu.total_pose, "pellets.switch: le total change avec la carte")
	h.eq(suite.pastilles.size(), Alt.nb_cases(), "pellets.switch: la grille suit les dimensions de la carte")

	# EGALITE STRICTE de part et d'autre : ce qui repart repart entierement.
	h.eq(Pellets.total_pose(suite.pastilles), suite.total_pose,
		"pellets.switch: la grille posee et le total declare concordent")
	h.eq(suite.carte.meme_carte(Alt), true, "pellets.switch: l'etat porte bien la carte suivante")
	h.eq(suite.carte.meme_carte(Maze), false, "pellets.switch: il ne porte plus la precedente")
