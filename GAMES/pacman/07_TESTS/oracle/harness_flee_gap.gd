# harness_flee_gap.gd — ligne harness.flee_gap, capacite F60.
# Sur un couloir droit DECLARE, Pac-Man fuyant en s'eloignant : la distance Pac-Man /
# poursuivant est STRICTEMENT plus grande a la fin de la fenetre qu'a son debut.
#
# L'exigence porte sur le SIGNE de l'inegalite observable, pas sur la valeur 95 %.
# CORRECTION M3 : la fenetre vaut P.FENETRE_MESURE_ECART_TICKS — a 19/20 sur grille
# discrete, l'ecart ne se creuse que d'UNE case par periode ; une fenetre plus courte
# rendrait l'assertion fausse ou tautologique.
extends RefCounted

const FleeGap = preload("res://06_RUNTIME/adapters/proof_harness/flee_gap.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const P = preload("res://05_SYSTEMS/params/params.gd")


func run(h) -> void:
	# Le couloir DECLARE est bien droit et assez long pour la fenetre.
	var libres: int = 0
	for x in range(1, Maze.LARGEUR - 1):
		if Maze.praticable(Vector2i(x, FleeGap.LIGNE_COULOIR)):
			libres += 1
	h.eq(libres, 26, "harness.flee: le couloir declare fait 26 cases praticables")
	h.gt(libres, FleeGap.FENETRE, "harness.flee: le couloir est plus long que la fenetre de mesure")

	var mesure: Dictionary = FleeGap.mesurer(Maze)
	h.eq(mesure["fenetre"], P.FENETRE_MESURE_ECART_TICKS, "harness.flee: fenetre declaree par les parametres")
	h.gt(mesure["fenetre"], P.CADENCE_FANTOME_PERIODE,
		"harness.flee: la fenetre couvre au moins une periode de cadence")

	# Pac-Man a REELLEMENT fui : un pas par tick, sur toute la fenetre.
	h.eq(mesure["pas_joueur"], FleeGap.FENETRE, "harness.flee: Pac-Man avance a chaque tick")

	# Le poursuivant a REELLEMENT suivi, mais STRICTEMENT moins vite.
	h.gt(mesure["pas_fantome"], 0, "harness.flee: le poursuivant s'est deplace")
	h.lt(mesure["pas_fantome"], mesure["pas_joueur"],
		"harness.flee: le poursuivant a fait STRICTEMENT moins de pas que Pac-Man")

	# L'ECART S'EST CREUSE : inegalite STRICTE sur la distance.
	h.gt(mesure["distance_fin"], mesure["distance_debut"],
		"harness.flee: la distance finale est STRICTEMENT plus grande qu'au debut")
	h.eq(mesure["distance_fin"] - mesure["distance_debut"],
		mesure["pas_joueur"] - mesure["pas_fantome"],
		"harness.flee: l'ecart creuse egale exactement la difference de pas")

	# La contrainte dure est tenue : le poursuivant ne peut jamais depasser le joueur.
	h.lt(mesure["pas_fantome"], mesure["fenetre"],
		"harness.flee: un fantome ne fait jamais un pas par tick en poursuite")
