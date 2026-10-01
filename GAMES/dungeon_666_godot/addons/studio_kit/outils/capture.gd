extends SceneTree

## Capture d'écran d'une scène, pour juger À L'ÉCRAN (pas aux métriques) — commun à tous les jeux.
## Généralise les capture_*.gd de Kitten Factory. Demande un rendu : PAS de --headless.
##   godot --path <jeu> --script res://addons/studio_kit/outils/capture.gd -- <scene.tscn> <sortie.png> [images=30] [LxH]
## Exemple : … -- res://ui/jeu.tscn user://captures/jeu.png 60 1600x900

const IMAGES_DEFAUT := 30


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 2:
		printerr("usage : capture.gd -- <scene.tscn> <sortie.png> [images] [LxH]")
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		printerr("capture impossible en --headless : relancer sans ce drapeau")
		quit(2)
		return
	if a.size() >= 4 and "x" in a[3]:
		var t := a[3].split("x")
		DisplayServer.window_set_size(Vector2i(int(t[0]), int(t[1])))
		root.size = Vector2i(int(t[0]), int(t[1]))
	var paquet := load(a[0]) as PackedScene
	if paquet == null:
		printerr("scène introuvable : " + a[0])
		quit(2)
		return
	root.add_child(paquet.instantiate())
	_capturer(a[1], int(a[2]) if a.size() >= 3 else IMAGES_DEFAUT)


func _capturer(sortie: String, images: int) -> void:
	for i in images:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(sortie.get_base_dir()))
	var err := img.save_png(sortie)
	print("capture %s : %s (%dx%d)" % ["OK" if err == OK else "ÉCHEC", ProjectSettings.globalize_path(sortie), img.get_width(), img.get_height()])
	quit(0 if err == OK else 1)
