# harness_ghost_trajectory_divergence.gd — ligne harness.ghost_trajectory_divergence,
# capacite F58. A partir d'un etat initial identique et sur un horizon DECLARE, les
# QUATRE sequences de positions de fantomes sont DEUX A DEUX DIFFERENTES.
#
# La grandeur comparee est la SEQUENCE sur l'horizon, paire a paire — pas les positions a
# un instant donne : deux fantomes peuvent se croiser sans suivre la meme trajectoire.
extends RefCounted

const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())

const Divergence = preload("res://06_RUNTIME/adapters/proof_harness/trajectory_divergence.gd")


func run(h) -> void:
	var mesure: Dictionary = Divergence.mesurer(Maze)

	h.eq(mesure["longueur"], Divergence.HORIZON_FIN - Divergence.HORIZON_DEBUT,
		"harness.divergence: l'horizon declare a bien ete parcouru")
	h.gt(mesure["longueur"], 0, "harness.divergence: l'horizon n'est pas vide")
	h.eq(mesure["paires_identiques"], 0,
		"harness.divergence: les quatre trajectoires sont DEUX A DEUX differentes")

	# L'horizon commence APRES la sortie du dernier fantome : mesurer avant reviendrait a
	# constater des places de maison distinctes, pas des trajectoires distinctes.
	h.gt(Divergence.HORIZON_DEBUT, 90, "harness.divergence: l'horizon debute apres le dernier delai de sortie")

	# CONTRE-EPREUVE du comparateur : il DETECTE deux sequences identiques. Sans elle, un
	# comparateur qui rendrait toujours 0 passerait pour une preuve de variance.
	var jumelles: Array = [[1, 2], [1, 2], [3, 4], [5, 6]]
	h.eq(Divergence.paires_identiques(jumelles), 1, "harness.divergence: une paire jumelle est detectee")
	var toutes_jumelles: Array = [[1], [1], [1], [1]]
	h.eq(Divergence.paires_identiques(toutes_jumelles), 6,
		"harness.divergence: quatre sequences identiques donnent six paires")
	var toutes_distinctes: Array = [[1], [2], [3], [4]]
	h.eq(Divergence.paires_identiques(toutes_distinctes), 0,
		"harness.divergence: quatre sequences distinctes ne donnent aucune paire")

	# Les quatre sequences existent reellement et ont la meme longueur.
	var suites: Array = Divergence.sequences(Maze)
	h.eq(suites.size(), 4, "harness.divergence: quatre sequences relevees")
	var longueurs_differentes: int = 0
	for s in suites:
		if s.size() != suites[0].size():
			longueurs_differentes += 1
	h.eq(longueurs_differentes, 0, "harness.divergence: les quatre sequences couvrent le meme horizon")

	# Chaque fantome a REELLEMENT bouge sur l'horizon : une sequence constante serait une
	# trajectoire degeneree, distincte des autres sans rien poursuivre.
	var immobiles: int = 0
	for s in suites:
		var distinctes := {}
		for p in s:
			distinctes[str(p)] = true
		if distinctes.size() < 2:
			immobiles += 1
	h.eq(immobiles, 0, "harness.divergence: aucun fantome n'est immobile sur l'horizon")
