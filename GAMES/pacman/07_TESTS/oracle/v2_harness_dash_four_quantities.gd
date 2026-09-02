# v2_harness_dash_four_quantities.gd — ligne harness.dash_four_quantities, capacite F85.
# Les QUATRE grandeurs sont relevees DANS LES DEUX CONDITIONS ; le nombre de grandeurs
# sans releve vaut exactement 0.
extends RefCounted

const Mesure = preload("res://06_RUNTIME/adapters/proof_harness/harness_dash_measurement.gd")
const Dash = preload("res://05_SYSTEMS/dash/dash.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))
var Alt = MazeClass.depuis_descripteur(ContentV2.descripteur(1))


func run(h) -> void:
	var m: Dictionary = Mesure.mesurer(Maze)
	h.eq(m["grandeurs_sans_releve"], 0, "harness.dash: 0 grandeur sans releve")
	h.eq(m["releves"].size(), 4, "harness.dash: quatre grandeurs relevees")
	for g in Dash.GRANDEURS:
		h.eq(m["releves"].has(g), true, "harness.dash: la grandeur %s est relevee" % g)
		h.eq(m["releves"][g].has("avec"), true, "harness.dash: %s relevee avec dash" % g)
		h.eq(m["releves"][g].has("sans"), true, "harness.dash: %s relevee sans dash" % g)

	# LE COULOIR DE MESURE est DERIVE de la carte, pas ecrit en dur : la mesure vaut
	# donc aussi sur la seconde carte.
	var couloir: Dictionary = Mesure.couloir_le_plus_long(Maze)
	h.gt(couloir["longueur"], Mesure.FENETRE, "harness.dash: le couloir est plus long que la fenetre")
	var couloir_alt: Dictionary = Mesure.couloir_le_plus_long(Alt)
	h.gt(couloir_alt["longueur"], 0, "harness.dash: la seconde carte a aussi un couloir")
	var m2: Dictionary = Mesure.mesurer(Alt)
	h.eq(m2["grandeurs_sans_releve"], 0, "harness.dash: 0 grandeur sans releve sur la seconde carte")
	h.eq(m2["ecarts_a_la_declaration"].size(), 0, "harness.dash: 0 ecart sur la seconde carte")

	# LA CONFRONTATION a la declaration : aucune grandeur requalifiee.
	h.eq(m["ecarts_a_la_declaration"].size(), 0, "harness.dash: 0 ecart a la declaration")
	h.gt(m["releves"]["vitesse_joueur"]["avec"], m["releves"]["vitesse_joueur"]["sans"],
		"harness.dash: le dash fait strictement avancer plus")
