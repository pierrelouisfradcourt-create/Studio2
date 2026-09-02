# end_victory.test.gd — ligne end.victory, capacite F38.
# Invariant soumis au gate de mutation : un mutant qui remplacerait l'EGALITE par un >=
# doit etre tue par l'assertion « EN COURS a 243 consommes ».
extends RefCounted

const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())

const End = preload("res://05_SYSTEMS/end_conditions/end_conditions.gd")
const Status = preload("res://05_SYSTEMS/game_state/status.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Pellets = preload("res://05_SYSTEMS/pellets/pellets.gd")


func run(h) -> void:
	var total: int = Pellets.total_pose(Pellets.poser(Maze))
	h.eq(total, 244, "end.victory: total pose de reference")

	# EGALITE STRICTE, jamais un >= : 243 -> encore en cours, 244 -> gagne.
	h.eq(End.victoire(243, total), false, "end.victory: pas de victoire a 243 consommes")
	h.eq(End.victoire(244, total), true, "end.victory: victoire EXACTEMENT a 244 consommes")
	h.eq(End.victoire(245, total), false, "end.victory: 245 n'est pas une victoire (egalite stricte)")
	h.eq(End.victoire(0, total), false, "end.victory: pas de victoire a 0 consomme")

	# Issue nommee aux memes bornes.
	h.eq(End.issue(3, 243, total), End.Issue.EN_COURS, "end.victory: EN COURS a total - 1")
	h.eq(End.issue(3, 244, total), End.Issue.GAGNE, "end.victory: GAGNE a total")

	# Traduction en statut de partie.
	h.eq(Status.calculer(3, 243, total), State.Statut.EN_COURS, "end.victory: statut EN COURS a 243")
	h.eq(Status.calculer(3, 244, total), State.Statut.GAGNE, "end.victory: statut GAGNE a 244")
	h.eq(Status.est_terminal(State.Statut.GAGNE), true, "end.victory: GAGNE est terminal")

	# La comparaison porte sur le total POSE, pas sur un litteral : changer le total
	# change le seuil de victoire, sans toucher au code.
	h.eq(End.victoire(10, 10), true, "end.victory: le seuil suit le total pose")
	h.eq(End.victoire(9, 10), false, "end.victory: total - 1 n'est jamais une victoire")

	# Applique a l'etat : a total - 1 la partie est STRICTEMENT encore en cours.
	var s = State.initial(Maze, 1)
	s.consommees = s.total_pose - 1
	h.eq(Status.appliquer(s), State.Statut.EN_COURS, "end.victory: etat a total - 1 -> EN COURS")
	s.consommees = s.total_pose
	h.eq(Status.appliquer(s), State.Statut.GAGNE, "end.victory: etat a total -> GAGNE")
	h.eq(s.statut, State.Statut.GAGNE, "end.victory: l'etat porte le statut GAGNE")
