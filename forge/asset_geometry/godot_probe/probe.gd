# probe.gd — COUCHE RUNTIME de l'Asset Geometry Oracle V1.
#
# Role unique : confirmer l'INTEGRATION d'un .glb dans le moteur consommateur.
# Cette sonde n'est PAS responsable de la mesure geometrique de reference (c'est
# forge/asset_geometry/measure.py, independant du producteur ET du moteur).
# Elle repond a une seule question que l'intake ne peut pas trancher :
#   « ce que Godot instancie correspond-il a ce que le fichier declare ? »
#
# Rappel : --headless ne rend AUCUNE image (driver dummy). Cette sonde ne capture
# rien -- elle lit une scene en memoire, ce qui fonctionne sans GPU.
#
# Usage :
#   <godot> --headless --script forge/asset_geometry/godot_probe/probe.gd -- <a.glb>
# Sortie : une ligne JSON prefixee GODOT_PROBE| (parsable, jamais de prose libre).

extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage: probe.gd -- <asset.glb>")
		quit(3)
		return

	var path: String = args[0]
	var out := {
		"asset_file": path.get_file(),
		"import_ok": false,
		"mesh_instances": 0,
		"node_names": [],
		"aabb_min_y": null,
		"aabb_max_y": null,
		"error": null,
	}

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		out["error"] = "append_from_file a echoue (code %d)" % err
		print("GODOT_PROBE|" + JSON.stringify(out))
		quit(2)
		return

	var scene: Node = doc.generate_scene(state)
	if scene == null:
		out["error"] = "generate_scene a retourne null"
		print("GODOT_PROBE|" + JSON.stringify(out))
		quit(2)
		return

	out["import_ok"] = true

	var names: Array[String] = []
	var min_y := INF
	var max_y := -INF
	var count := 0

	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		# generate_scene() produit des ImporterMeshInstance3D (chemin d'import), pas des
		# MeshInstance3D. On accepte les DEUX : sinon la sonde rapporte 0 mesh sur un
		# fichier parfaitement valide -- un faux negatif silencieux.
		var mesh: Mesh = null
		if node is MeshInstance3D:
			mesh = (node as MeshInstance3D).mesh
		elif node is ImporterMeshInstance3D:
			var im := (node as ImporterMeshInstance3D).mesh
			if im != null:
				mesh = im.get_mesh()

		if mesh != null:
			count += 1
			names.append(node.name)
			var aabb := mesh.get_aabb()
			var xf := _world_of(node as Node3D, scene)
			# 8 coins transformes : AABB monde exacte, pas approchee
			for i in range(8):
				var w := xf * aabb.get_endpoint(i)
				min_y = min(min_y, w.y)
				max_y = max(max_y, w.y)

		for child in node.get_children():
			stack.push_back(child)

	out["mesh_instances"] = count
	names.sort()
	out["node_names"] = names
	if count > 0:
		out["aabb_min_y"] = min_y
		out["aabb_max_y"] = max_y

	print("GODOT_PROBE|" + JSON.stringify(out))
	quit(0)


# Compose la transforme monde en remontant jusqu'a `root` (la scene n'est pas
# ajoutee a l'arbre : global_transform n'est pas disponible).
func _world_of(node: Node3D, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != root.get_parent():
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf
