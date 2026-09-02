# end_defeat.test.gd — ligne end.defeat, capacite F37.
# Invariant soumis au gate de mutation : un mutant qui bascule a PERDU alors que vies
# vaut 1, ou qui laisse EN COURS alors que vies vaut 0, doit etre tue ICI.
extends RefCounted

const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())

const End = preload("res://05_SYSTEMS/end_conditions/end_conditions.gd")
const Status = preload("res://05_SYSTEMS/game_state/status.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")


func run(h) -> void:
	# Valeurs STRICTES autour du seuil : 2, 1, 0.
	h.eq(End.defaite(2), false, "end.defeat: pas de defaite a 2 vies")
	h.eq(End.defaite(1), false, "end.defeat: pas de defaite a 1 vie")
	h.eq(End.defaite(0), true, "end.defeat: defaite EXACTEMENT a 0 vie")

	# Issue nommee, pas un booleen implicite.
	h.eq(End.issue(1, 0, 244), End.Issue.EN_COURS, "end.defeat: encore en cours a 1 vie")
	h.eq(End.issue(0, 0, 244), End.Issue.PERDU, "end.defeat: perdu a 0 vie")

	# Traduction en statut de partie, aux memes bornes.
	h.eq(Status.calculer(1, 0, 244), State.Statut.EN_COURS, "end.defeat: statut EN COURS a 1 vie")
	h.eq(Status.calculer(0, 0, 244), State.Statut.PERDU, "end.defeat: statut PERDU a 0 vie")

	# La defaite PRIME sur la victoire quand les deux seraient vraies : l'issue reste
	# unique et exclusive, jamais deux statuts au meme tick.
	h.eq(End.issue(0, 244, 244), End.Issue.PERDU, "end.defeat: la defaite prime a 0 vie")
	h.eq(Status.calculer(0, 244, 244), State.Statut.PERDU, "end.defeat: statut unique et exclusif")

	# Le statut de defaite est TERMINAL.
	h.eq(Status.est_terminal(State.Statut.PERDU), true, "end.defeat: PERDU est terminal")
	h.eq(Status.est_terminal(State.Statut.EN_COURS), false, "end.defeat: EN COURS n'est pas terminal")

	# Appliquee a l'etat : le statut suit la valeur exacte du compteur de vies.
	var s = State.initial(Maze, 1)
	s.vies = 1
	h.eq(Status.appliquer(s), State.Statut.EN_COURS, "end.defeat: etat a 1 vie -> EN COURS")
	s.vies = 0
	h.eq(Status.appliquer(s), State.Statut.PERDU, "end.defeat: etat a 0 vie -> PERDU")
	h.eq(s.statut, State.Statut.PERDU, "end.defeat: l'etat porte le statut applique")
