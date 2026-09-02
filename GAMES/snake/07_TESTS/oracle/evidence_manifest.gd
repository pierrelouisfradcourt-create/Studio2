# evidence_manifest.gd — oracle de la ligne proof.evidence_path. SceneTree headless : lit
# la wiremap du jeu et verifie que CHAQUE ligne passee a IMPLEMENTED porte un champ de
# constat `preuve` NON VIDE (le chemin/nom de la sortie d'oracle qui l'appuie). Une ligne
# IMPLEMENTED sans preuve = execution non prouvable = violation. Sortie :
# "FORGE_ORACLE evidence_manifest {json}", exit 0 si vert.
extends SceneTree

func _initialize() -> void:
	var fails: Array = []
	var f := FileAccess.open("res://09_WIREMAP/wiremap.json", FileAccess.READ)
	if f == null:
		print("FORGE_ORACLE evidence_manifest " + JSON.stringify({"ok": false, "fails": ["wiremap illisible"]}))
		quit(1)
		return
	var txt := f.get_as_text()
	f.close()
	var j := JSON.new()
	if j.parse(txt) != OK:
		print("FORGE_ORACLE evidence_manifest " + JSON.stringify({"ok": false, "fails": ["wiremap JSON invalide"]}))
		quit(1)
		return
	var wiremap = j.data
	var lignes: Array = wiremap.get("lines", [])
	var implemented := 0
	var sans_preuve: Array = []
	for l in lignes:
		if typeof(l) != TYPE_DICTIONARY:
			continue
		if l.get("state") == "IMPLEMENTED":
			implemented += 1
			var preuve = l.get("preuve", "")
			if not (preuve is String) or preuve.strip_edges() == "":
				sans_preuve.append(l.get("id", "<sans-id>"))
	for lid in sans_preuve:
		fails.append("IMPLEMENTED sans preuve: " + str(lid))
	print("FORGE_ORACLE evidence_manifest " + JSON.stringify({
		"ok": fails.is_empty(), "fails": fails,
		"lignes_implemented": implemented, "sans_preuve": sans_preuve.size(),
	}))
	quit(0 if fails.is_empty() else 1)
