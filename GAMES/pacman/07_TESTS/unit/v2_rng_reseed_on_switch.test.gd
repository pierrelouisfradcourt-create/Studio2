# v2_rng_reseed_on_switch.test.gd — ligne rng.reseed_on_switch, capacite F106.
# Le generateur est reseede a une valeur DECLAREE lors d'une bascule de niveau : sans
# quoi le niveau suivant ne serait ni rejouable ni comparable.
extends RefCounted

const Rng = preload("res://05_SYSTEMS/rng/rng.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Progression = preload("res://05_SYSTEMS/level_progression/level_progression.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))

var Alt = MazeClass.depuis_descripteur(ContentV2.descripteur(1))


func run(h) -> void:
	# La graine de niveau est DECLAREE et reproductible.
	h.eq(Rng.graine_de_niveau(1, 2), Rng.graine_de_niveau(1, 2), "rng.reseed: valeur reproductible")
	h.ok(Rng.graine_de_niveau(1, 1) != Rng.graine_de_niveau(1, 2),
		"rng.reseed: deux niveaux voisins ne partagent pas leur graine")
	h.ok(Rng.graine_de_niveau(1, 2) != Rng.graine_de_niveau(2, 2),
		"rng.reseed: deux parties voisines ne partagent pas leur graine")
	h.eq(Rng.ECART_GRAINE_NIVEAU, 7919, "rng.reseed: ecart declare")
	h.ok(Rng.graine_de_niveau(0, 1) >= 0, "rng.reseed: la graine reste dans le domaine")

	# A LA BASCULE : l'etat du generateur change, et prend la valeur declaree.
	var jeu = State.initial(Maze, 5)
	jeu.rng_etat = Rng.suivant(jeu.rng_etat)
	var avant: int = jeu.rng_etat
	var suite = Progression.basculer(jeu, Alt, ContentV2.cadence(1), 5)
	h.ok(suite.rng_etat != avant, "rng.reseed: le generateur est reseede a la bascule")
	h.eq(suite.rng_etat, Rng.graine(Rng.graine_de_niveau(5, 2)),
		"rng.reseed: il prend exactement la valeur declaree du niveau")

	# Deux bascules identiques donnent le MEME etat de generateur : le niveau est rejouable.
	var bis = Progression.basculer(jeu, Alt, ContentV2.cadence(1), 5)
	h.eq(bis.rng_etat, suite.rng_etat, "rng.reseed: la bascule est reproductible")

	# Le reseedage direct pose la meme valeur.
	var copie = jeu.clone()
	Rng.reseeder(copie, 5, 2)
	h.eq(copie.rng_etat, suite.rng_etat, "rng.reseed: le reseedage direct pose la meme valeur")

	# L'etat du generateur reste un CHAMP de l'etat de partie : clone et compare.
	h.eq(copie.clone().rng_etat, copie.rng_etat, "rng.reseed: l'etat du generateur se clone")
	var autre = copie.clone()
	autre.rng_etat = copie.rng_etat + 1
	h.eq(copie.egal_profond(autre), false, "rng.reseed: une divergence du generateur est detectee")
