# v2_progression_final_state.test.gd — ligne progression.final_state, capacite F107.
# Le catalogue epuise est un CAS NOMME : etat FINAL EXPLICITE, jamais une bascule vers
# une carte inexistante ni un blocage.
extends RefCounted

const Sess = preload("res://05_SYSTEMS/session/session.gd")
const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Progression = preload("res://05_SYSTEMS/level_progression/level_progression.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))
var Alt = MazeClass.depuis_descripteur(ContentV2.descripteur(1))


func run(h) -> void:
	var dernier = State.initial(Alt, 1)
	dernier.niveau = 2
	dernier.consommees = dernier.total_pose

	h.eq(Progression.suite(dernier, 2), Progression.SUITE_CATALOGUE_TERMINE,
		"progression.final: le catalogue epuise est nomme")
	var final_etat = Progression.etat_final(dernier)
	h.eq(final_etat.statut, State.Statut.GAGNE, "progression.final: la partie est gagnee")
	h.eq(final_etat.niveau, 2, "progression.final: le niveau atteint est conserve")
	h.eq(dernier.statut, State.Statut.EN_COURS, "progression.final: l'etat d'entree n'est pas mute")

	# COTE SESSION : l'application passe a l'ecran de fin, et non a une carte inexistante.
	var sess: Dictionary = Sess.initiale()
	sess["partie"] = dernier
	sess["app"] = App.Etat.PARTIE
	var apres: Dictionary = Sess.carte_terminee(sess, null, 0, 2)
	h.eq(int(apres["app"]), App.Etat.FIN, "progression.final: l'application atteint l'ecran de fin")
	h.eq(apres["partie"].statut, State.Statut.GAGNE, "progression.final: le statut final est gagne")
	h.ok(apres["partie"] != null, "progression.final: aucun blocage, un etat est rendu")

	# AVANT le dernier niveau, la meme fonction bascule au lieu de conclure.
	var premier = State.initial(Maze, 1)
	premier.consommees = premier.total_pose
	var sess2: Dictionary = Sess.initiale()
	sess2["partie"] = premier
	sess2["app"] = App.Etat.PARTIE
	var suite: Dictionary = Sess.carte_terminee(sess2, Alt, ContentV2.cadence(1), 2)
	h.eq(int(suite["app"]), App.Etat.PARTIE, "progression.final: avant la fin, la partie continue")
	h.eq(suite["partie"].niveau, 2, "progression.final: elle enchaine sur le niveau suivant")
	h.eq(suite["partie"].statut, State.Statut.EN_COURS, "progression.final: sans statut terminal premature")
