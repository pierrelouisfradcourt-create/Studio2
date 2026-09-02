# v2_core_end_condition.gd — ligne core.end_condition, capacite F107.
# La partie peut se terminer, et la condition de fin est definie par les regles. En V2
# s'ajoute l'etat FINAL EXPLICITE quand la derniere carte du catalogue est terminee : le
# catalogue epuise est un CAS NOMME, jamais une bascule vers une carte inexistante.
extends RefCounted

const End = preload("res://05_SYSTEMS/end_conditions/end_conditions.gd")
const Progression = preload("res://05_SYSTEMS/level_progression/level_progression.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Sess = preload("res://05_SYSTEMS/session/session.gd")
const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Shell = preload("res://06_RUNTIME/adapters/app_shell/app_shell.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))
var Alt = MazeClass.depuis_descripteur(ContentV2.descripteur(1))


func run(h) -> void:
	# LES REGLES DE FIN, en egalite STRICTE.
	h.eq(End.defaite(0), true, "core.end: defaite a zero vie")
	h.eq(End.defaite(1), false, "core.end: pas de defaite a une vie")
	h.eq(End.victoire(244, 244), true, "core.end: victoire a l'egalite stricte")
	h.eq(End.victoire(243, 244), false, "core.end: pas de victoire a total - 1")
	h.eq(End.issue(3, 243, 244), End.Issue.EN_COURS, "core.end: sinon la partie continue")

	# CATALOGUE NON EPUISE : bascule, et non fin de partie.
	var premier = State.initial(Maze, 1)
	premier.consommees = premier.total_pose
	h.eq(Progression.suite(premier, 2), Progression.SUITE_NIVEAU_SUIVANT, "core.end: niveau suivant")
	var sess: Dictionary = Sess.initiale()
	sess["partie"] = premier
	sess["app"] = App.Etat.PARTIE
	var suite: Dictionary = Sess.carte_terminee(sess, Alt, ContentV2.cadence(1), 2)
	h.eq(int(suite["app"]), App.Etat.PARTIE, "core.end: la partie continue au niveau suivant")
	h.eq(suite["partie"].statut, State.Statut.EN_COURS, "core.end: sans statut terminal premature")

	# CATALOGUE EPUISE : etat FINAL EXPLICITE.
	var dernier = suite["partie"]
	dernier.consommees = dernier.total_pose
	var sess2: Dictionary = suite.duplicate()
	sess2["partie"] = dernier
	var fin: Dictionary = Sess.carte_terminee(sess2, null, 0, 2)
	h.eq(int(fin["app"]), App.Etat.FIN, "core.end: l'application atteint l'ecran de fin")
	h.eq(fin["partie"].statut, State.Statut.GAGNE, "core.end: le statut final est GAGNE")
	h.ok(fin["partie"] != null, "core.end: aucun blocage, un etat final est rendu")
	h.eq(Progression.suite(dernier, 2), Progression.SUITE_CATALOGUE_TERMINE, "core.end: cas nomme")
