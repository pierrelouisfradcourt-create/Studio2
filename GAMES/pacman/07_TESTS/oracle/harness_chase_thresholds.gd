# harness_chase_thresholds.gd — ligne harness.chase_thresholds, capacite F57.
# Pour CHACUN des six seuils, l'etat EXPOSE est releve juste avant le seuil, EXACTEMENT
# au seuil et juste apres : les trois valeurs correspondent a la sequence declaree.
extends RefCounted

const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())

const Thresholds = preload("res://06_RUNTIME/adapters/proof_harness/chase_thresholds.gd")
const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")


func run(h) -> void:
	var constats: Array = Thresholds.constats(Maze)
	h.eq(constats.size(), 6, "harness.thresholds: six seuils mesures")

	# Chaque seuil, trois releves, valeurs STRICTES.
	for c in constats:
		h.eq(c["avant_lu"], c["avant_attendu"], "harness.thresholds: seuil %d, juste avant" % c["seuil"])
		h.eq(c["au_lu"], c["au_attendu"], "harness.thresholds: seuil %d, exactement au seuil" % c["seuil"])
		h.eq(c["apres_lu"], c["apres_attendu"], "harness.thresholds: seuil %d, juste apres" % c["seuil"])
		h.ok(c["avant_lu"] != c["au_lu"], "harness.thresholds: seuil %d, le mode CHANGE" % c["seuil"])

	# La mesure porte bien sur les seuils DECLARES par la source unique.
	var seuils_mesures: Array = []
	for c in constats:
		seuils_mesures.append(c["seuil"])
	h.eq(seuils_mesures, Chase.seuils(), "harness.thresholds: les seuils mesures sont ceux declares")

	# La fenetre couvre le dernier seuil et un peu au-dela.
	h.gt(Thresholds.fenetre_requise(), Chase.seuils()[5], "harness.thresholds: la fenetre depasse le dernier seuil")

	# AUCUN RETOUR EN DISPERSION apres le sixieme seuil, mesure sur l'etat expose.
	var trace: Array = Thresholds.releves(Maze)
	h.eq(Thresholds.dispersion_apres_dernier_seuil(trace), 0,
		"harness.thresholds: aucun retour en dispersion apres le sixieme seuil")
	h.eq(trace.size(), Thresholds.fenetre_requise() + 1, "harness.thresholds: un releve par tick")

	# Le protocole d'isolement est TENU : aucune vie perdue pendant la mesure, sinon
	# l'horloge serait revenue a son premier segment au milieu de la fenetre.
	h.eq(trace[trace.size() - 1]["vies"], trace[0]["vies"],
		"harness.thresholds: aucune vie perdue pendant la mesure")
	h.eq(trace[trace.size() - 1]["horloge"], Thresholds.fenetre_requise(),
		"harness.thresholds: l'horloge a avance sans jamais etre remise a zero")
	h.eq(trace[trace.size() - 1]["statut_nom"], "EN COURS", "harness.thresholds: la partie reste en cours")
