# harness_frightened_slowdown.gd — ligne harness.frightened_slowdown, capacite F61.
# Sur une fenetre DECLAREE en etat Effraye : le nombre de cases parcourues par CHAQUE
# fantome est STRICTEMENT INFERIEUR a celui parcouru par Pac-Man.
extends RefCounted

const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())

const Slowdown = preload("res://06_RUNTIME/adapters/proof_harness/frightened_slowdown.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")


func run(h) -> void:
	var mesure: Dictionary = Slowdown.mesurer(Maze)

	# Le protocole est TENU : les quatre fantomes sont restes Effrayes toute la fenetre.
	h.eq(mesure["tous_effrayes"], true, "harness.slowdown: les quatre restent Effrayes sur la fenetre")
	h.eq(mesure["fenetre"], P.FENETRE_MESURE_ECART_TICKS, "harness.slowdown: fenetre declaree")

	# Pac-Man a parcouru une case par tick.
	h.eq(mesure["pas_joueur"], mesure["fenetre"], "harness.slowdown: Pac-Man avance a chaque tick")

	# CHAQUE fantome a parcouru STRICTEMENT moins de cases que Pac-Man.
	h.eq(mesure["pas_fantomes"].size(), 4, "harness.slowdown: quatre fantomes mesures")
	h.eq(Slowdown.fantomes_non_ralentis(mesure), 0,
		"harness.slowdown: 0 fantome n'atteint le nombre de cases de Pac-Man")
	for i in range(4):
		h.lt(mesure["pas_fantomes"][i], mesure["pas_joueur"],
			"harness.slowdown: le fantome %d parcourt strictement moins de cases" % i)
		h.gt(mesure["pas_fantomes"][i], 0, "harness.slowdown: le fantome %d s'est reellement deplace" % i)

	# La cadence Effraye est celle DECLAREE : un tick sur deux.
	var attendu: int = mesure["fenetre"] / P.CADENCE_EFFRAYE_PERIODE
	for i in range(4):
		h.eq(mesure["pas_fantomes"][i], attendu, "harness.slowdown: cadence Effraye tenue par le fantome %d" % i)

	# CONTRE-EPREUVE du detecteur : un fantome aussi rapide que Pac-Man est REFUSE.
	var faux: Dictionary = {"pas_joueur": 24, "pas_fantomes": [12, 12, 24, 12]}
	h.eq(Slowdown.fantomes_non_ralentis(faux), 1, "harness.slowdown: un fantome non ralenti est detecte")
	var faux2: Dictionary = {"pas_joueur": 24, "pas_fantomes": [25, 25, 25, 25]}
	h.eq(Slowdown.fantomes_non_ralentis(faux2), 4, "harness.slowdown: quatre fantomes trop rapides detectes")
	var vrai: Dictionary = {"pas_joueur": 24, "pas_fantomes": [12, 12, 12, 12]}
	h.eq(Slowdown.fantomes_non_ralentis(vrai), 0, "harness.slowdown: un vrai ralentissement passe")
