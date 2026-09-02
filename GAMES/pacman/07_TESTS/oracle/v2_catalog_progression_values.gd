# v2_catalog_progression_values.gd — ligne catalog.progression_values, capacite F108.
# Releve du parametre de progression sur TOUS les niveaux embarques : la distribution
# porte AU MOINS DEUX VALEURS DISTINCTES. Une distribution a valeur unique serait une
# progression de facade — c'est ce que cette ligne fait MESURER, pas seulement declarer.
extends RefCounted

const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const Progression = preload("res://05_SYSTEMS/level_progression/level_progression.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")


func run(h) -> void:
	var valeurs: Array = ContentV2.cadences_declarees()
	h.eq(valeurs.size(), ContentV2.nb_niveaux(), "catalog.progression: une valeur par niveau")
	h.gt(valeurs.size(), 1, "catalog.progression: la distribution porte plus d'un releve")

	# PREUVE DE VARIANCE : au moins deux valeurs DISTINCTES, non triviales.
	h.gt(ContentV2.valeurs_distinctes(valeurs), 1,
		"catalog.progression: au moins deux valeurs distinctes")
	var triviales: int = 0
	for v in valeurs:
		if int(v) <= 1:
			triviales += 1
	h.eq(triviales, 0, "catalog.progression: aucune valeur triviale")

	# CONTRE-EPREUVE : le compteur de valeurs distinctes DETECTE bien l'uniformite.
	h.eq(ContentV2.valeurs_distinctes([20, 20, 20]), 1,
		"catalog.progression: une distribution uniforme est reconnue comme telle")
	h.eq(ContentV2.valeurs_distinctes([20, 24]), 2,
		"catalog.progression: deux valeurs distinctes sont reconnues")

	# Les VALEURS vivent dans le catalogue, la REGLE de lecture dans level_progression.
	h.eq(ContentV2.cadence(0), 20, "catalog.progression: valeur du premier niveau")
	h.eq(ContentV2.cadence(1), 24, "catalog.progression: valeur du second niveau")
	h.eq(Progression.cadence_de_repli(), P.CADENCE_FANTOME_PERIODE,
		"catalog.progression: le repli est declare dans le bloc de parametres")
	h.eq(ContentV2.cadence(99), 0, "catalog.progression: hors bornes rend 0, pas une valeur inventee")
