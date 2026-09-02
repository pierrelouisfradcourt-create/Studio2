# v2_progression_level_switch.test.gd — ligne progression.level_switch, capacite F104.
# La bascule est une TRANSFORMATION D'ETAT dans la MEME execution : jamais une relance
# de l'application, jamais un retour force au titre.
extends RefCounted

const Sess = preload("res://05_SYSTEMS/session/session.gd")
const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Progression = preload("res://05_SYSTEMS/level_progression/level_progression.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))
var Alt = MazeClass.depuis_descripteur(ContentV2.descripteur(1))


func run(h) -> void:
	# CARTE VIDEE : egalite STRICTE, jamais un >=.
	var jeu = State.initial(Maze, 1)
	h.eq(Progression.carte_videe(jeu), false, "progression.switch: une carte pleine n'est pas videe")
	jeu.consommees = jeu.total_pose - 1
	h.eq(Progression.carte_videe(jeu), false, "progression.switch: a total - 1, la carte n'est pas videe")
	jeu.consommees = jeu.total_pose
	h.eq(Progression.carte_videe(jeu), true, "progression.switch: a total exactement, elle l'est")

	# SUITE : niveau suivant, ou catalogue termine. Un cas NOMME dans les deux sens.
	h.eq(Progression.suite(jeu, 2), Progression.SUITE_NIVEAU_SUIVANT, "progression.switch: niveau suivant")
	h.eq(Progression.suite(jeu, 1), Progression.SUITE_CATALOGUE_TERMINE, "progression.switch: catalogue termine")
	h.eq(Progression.dernier_niveau(2, 2), true, "progression.switch: le second de deux est le dernier")
	h.eq(Progression.dernier_niveau(1, 2), false, "progression.switch: le premier ne l'est pas")

	# BASCULE : nouvel etat, MEME execution, aucun retour au titre.
	var suite = Progression.basculer(jeu, Alt, ContentV2.cadence(1), 1)
	h.eq(suite.niveau, 2, "progression.switch: le niveau est incremente")
	h.eq(suite.carte.meme_carte(Alt), true, "progression.switch: la carte suivante est en place")
	h.eq(suite.statut, State.Statut.EN_COURS, "progression.switch: la partie continue")
	h.eq(suite.ticks, 0, "progression.switch: le compteur de ticks du niveau repart")
	h.eq(suite.cadence_fantome, ContentV2.cadence(1), "progression.switch: la cadence du niveau suivant")

	# L'etat d'entree n'est JAMAIS mute par la bascule.
	h.eq(jeu.niveau, 1, "progression.switch: l'etat d'entree reste au premier niveau")
	h.eq(jeu.carte.meme_carte(Maze), true, "progression.switch: il porte encore sa carte")

	# COTE SESSION : l'application reste en PARTIE, aucune relance.
	var sess: Dictionary = Sess.initiale()
	sess["partie"] = jeu
	sess["app"] = App.Etat.PARTIE
	var apres: Dictionary = Sess.carte_terminee(sess, Alt, ContentV2.cadence(1), 2)
	h.eq(int(apres["app"]), App.Etat.PARTIE, "progression.switch: l'application reste en partie")
	h.eq(apres["partie"].niveau, 2, "progression.switch: la session porte le niveau suivant")
