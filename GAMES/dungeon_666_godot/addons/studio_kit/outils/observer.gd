extends SceneTree

## Observation d'un écran de jeu : charge une scène, la prépare, attend, photographie.
## Utilisé par le contrôle quotidien (verifier_tout.py --observer). Demande un rendu : PAS de --headless.
##   godot --fixed-fps 60 --position -3000,-3000 --path <jeu> --script res://addons/studio_kit/outils/observer.gd -- <config.json>
## config : {"scene", "sortie", "images" (30), "taille" ("LxH"),
##           "proprietes" {nom: valeur} posées AVANT l'entrée dans l'arbre (ex. un chemin de sauvegarde de test),
##           "appel" [méthode, arg…] appelé sur la racine de la scène après sa première image}
## Sortie 0 = photo écrite.

const IMAGES_DEFAUT := 30


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var conf: Variant = JSON.parse_string(FileAccess.get_file_as_string(a[0])) if a.size() > 0 else null
	if not (conf is Dictionary) or DisplayServer.get_name() == "headless":
		printerr("usage : observer.gd -- <config.json> (sans --headless)")
		quit(2)
		return
	var c: Dictionary = conf
	if String(c.get("taille", "")).contains("x"):
		var t := String(c["taille"]).split("x")
		DisplayServer.window_set_size(Vector2i(int(t[0]), int(t[1])))
		root.size = Vector2i(int(t[0]), int(t[1]))
	var paquet := load(String(c.get("scene", ""))) as PackedScene
	if paquet == null:
		printerr("scène introuvable : %s" % c.get("scene", ""))
		quit(2)
		return
	var n := paquet.instantiate()
	for p in c.get("proprietes", {}):
		n.set(p, c["proprietes"][p])
	root.add_child(n)
	_observer(n, c)


func _observer(n: Node, c: Dictionary) -> void:
	await process_frame
	var appel: Array = c.get("appel", [])
	if not appel.is_empty():
		n.callv(String(appel[0]), appel.slice(1))
	for i in int(c.get("images", IMAGES_DEFAUT)):
		await process_frame
	await RenderingServer.frame_post_draw
	var sortie := String(c["sortie"])
	DirAccess.make_dir_recursive_absolute(sortie.get_base_dir())
	var err := root.get_texture().get_image().save_png(sortie)
	print("observation %s : %s" % ["OK" if err == OK else "ÉCHEC", sortie])
	quit(0 if err == OK else 1)
