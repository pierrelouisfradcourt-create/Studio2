# harness_asset_inventory.gd — ligne harness.asset_inventory, capacite F62.
# Inventaire des fichiers du jeu : AUCUN fichier d'image, de police ni de son importe n'y
# figure. L'exigence hors_scope du charter devient un FAIT MESURE, pas une intention.
extends RefCounted

const Inventory = preload("res://06_RUNTIME/adapters/proof_harness/asset_inventory.gd")


func run(h) -> void:
	var mesure: Dictionary = Inventory.mesurer()

	# L'inventaire a REELLEMENT parcouru le projet : un inventaire vide ne prouve rien.
	h.gt(mesure["fichiers"], 50, "harness.inventory: l'inventaire a parcouru le projet")

	# AUCUN asset importe.
	h.eq(mesure["assets_importes"], 0, "harness.inventory: aucun asset importe dans le projet")
	h.eq(mesure["fautifs"], [], "harness.inventory: la liste des fichiers fautifs est vide")

	# Le parcours est RECURSIF et DETERMINISTE : deux inventaires donnent la meme liste.
	var a: Array = Inventory.fichiers()
	var b: Array = Inventory.fichiers()
	h.eq(a, b, "harness.inventory: inventaire reproductible et trie")
	h.eq(a.size(), mesure["fichiers"], "harness.inventory: la mesure porte sur la liste complete")

	# Les fichiers attendus du projet sont bien vus — sinon le parcours serait aveugle.
	h.ok(a.has("res://project.godot"), "harness.inventory: project.godot est inventorie")
	h.ok(a.has("res://main.tscn"), "harness.inventory: main.tscn est inventorie")
	h.ok(a.has("res://solvability.gd"), "harness.inventory: solvability.gd est inventorie")
	h.ok(a.has("res://tests/run_tests.gd"), "harness.inventory: tests/run_tests.gd est inventorie")
	h.ok(a.has("res://05_SYSTEMS/maze/maze.gd"), "harness.inventory: les systemes sont inventories")
	h.ok(a.has("res://06_RUNTIME/adapters/presentation/hud.gd"), "harness.inventory: les adaptateurs aussi")

	# La liste des extensions refusees couvre image, police ET son.
	for ext in ["png", "jpg", "ttf", "otf", "wav", "ogg", "mp3"]:
		h.ok(Inventory.EXTENSIONS_INTERDITES.has(ext),
			"harness.inventory: l'extension %s est refusee" % ext)

	# CONTRE-EPREUVE : le detecteur trouve bien un asset la ou il y en a un. Sans elle,
	# une liste vide pourrait venir d'un detecteur qui ne regarde rien.
	var faux_positifs: int = 0
	for f in a:
		if Inventory.EXTENSIONS_INTERDITES.has(f.get_extension().to_lower()):
			faux_positifs += 1
	h.eq(faux_positifs, mesure["assets_importes"], "harness.inventory: le detecteur et la mesure concordent")
	var dossier_inexistant: Array = Inventory.fichiers("res://dossier_qui_n_existe_pas")
	h.eq(dossier_inexistant, [], "harness.inventory: un dossier absent rend une liste vide, sans exception")
