# v2_harness_keyboard_gamepad_parity.gd — ligne harness.keyboard_gamepad_parity, F77.
# Pour CHAQUE intention de jeu, deux executions comparees tick par tick sur une fenetre
# declaree — l'une pilotee par les entrees clavier, l'autre par les entrees manette :
# les traces d'etat sont STRICTEMENT EGALES.
extends RefCounted

const Parity = preload("res://06_RUNTIME/adapters/proof_harness/harness_input_parity.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))


func run(h) -> void:
	var m: Dictionary = Parity.mesurer(Maze)
	h.eq(m["intentions"], 6, "harness.parite: six intentions de jeu comparees")
	h.eq(m["intentions_divergentes"], 0, "harness.parite: 0 intention divergente")
	h.eq(m["intentions_non_atteignables"], 0, "harness.parite: 0 intention injouable sur un des deux")
	h.eq(m["fenetre"], Parity.FENETRE, "harness.parite: la fenetre de comparaison est declaree")
	h.gt(m["fenetre"], 0, "harness.parite: elle est non nulle")

	# CONTRE-EPREUVE : le comparateur DETECTE une difference quand elle existe — sans
	# quoi « 0 divergence » ne prouverait rien.
	h.gt(m["divergences_de_controle"], 0, "harness.parite: le comparateur detecte une difference reelle")

	# LE DETAIL, intention par intention.
	for c in m["constats"]:
		h.eq(c["par_touche"], c["par_bouton"], "harness.parite: meme intention par les deux peripheriques")
		h.eq(c["divergences"], 0, "harness.parite: traces strictement egales pour %s" % c["nom"])
		h.eq(c["atteignable"], true, "harness.parite: %s est atteignable sur les deux" % c["nom"])
