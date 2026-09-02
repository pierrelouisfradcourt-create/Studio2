# mutation_invariants.gd — oracle de la ligne proof.mutation_gate. SceneTree headless :
# declare et VERIFIE le PERIMETRE du gate de mutation — EXCLUSIVEMENT 05_SYSTEMS/ (la seule
# zone que la mutation sait juger, mesure Pong : 95 % de mutants tues sur les systemes purs,
# 0 % sur les adaptateurs de presentation). L'invariant qui rend un systeme mutable : il est
# PUR (RefCounted, jamais Node). Le gate lui-meme est execute par forge.mutation.run_mutation_test
# (Python) ; cet oracle en fixe et prouve le perimetre. Sortie : "FORGE_ORACLE mutation_invariants {json}".
extends SceneTree

func _lister_gd(racine: String, sortie: Array) -> void:
	var da := DirAccess.open(racine)
	if da == null:
		return
	da.list_dir_begin()
	var nom := da.get_next()
	while nom != "":
		if nom == "." or nom == "..":
			nom = da.get_next()
			continue
		var chemin := racine + "/" + nom
		if da.current_is_dir():
			_lister_gd(chemin, sortie)
		elif nom.ends_with(".gd"):
			sortie.append(chemin)
		nom = da.get_next()
	da.list_dir_end()

func _initialize() -> void:
	var fails: Array = []
	var perimetre: Array = []
	_lister_gd("res://05_SYSTEMS", perimetre)
	perimetre.sort()
	if perimetre.is_empty():
		fails.append("perimetre de mutation vide (aucun systeme pur)")
	# Invariant : chaque fichier du perimetre est PUR (extends RefCounted, jamais Node).
	for chemin in perimetre:
		var f := FileAccess.open(chemin, FileAccess.READ)
		if f == null:
			fails.append("illisible: " + chemin)
			continue
		var txt := f.get_as_text()
		f.close()
		if "extends Node" in txt:
			fails.append("systeme non pur (extends Node): " + chemin)
	print("FORGE_ORACLE mutation_invariants " + JSON.stringify({
		"ok": fails.is_empty(), "fails": fails,
		"perimetre_racine": "05_SYSTEMS/",
		"fichiers_perimetre": perimetre.size(),
		"perimetre": perimetre,
	}))
	quit(0 if fails.is_empty() else 1)
