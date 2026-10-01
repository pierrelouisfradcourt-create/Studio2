extends SceneTree
## Lance une scène, la laisse vivre, et enregistre une ou plusieurs images de la fenêtre.
##   <godot> --position -3000,-3000 --path . --script res://outils/capture.gd -- <scene.tscn> <sortie.png> [images=180] [pilote]
## SANS --headless (il faut un vrai rendu). `pilote` : la scène est jouée par un pilote simple
## (va vers l'ennemi le plus proche et frappe) si elle expose un nœud `partie` (jeu/partie.gd).
## Une image est aussi enregistrée à mi-parcours : <sortie>_mi.png.

var _scene: Node
var _sortie := ""
var _images := 180
var _vues := 0
var _pilote := false

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage : capture.gd -- <scene.tscn> <sortie.png> [images] [pilote]")
		quit(2)
		return
	_sortie = args[1]
	if args.size() > 2:
		_images = int(args[2])
	_pilote = args.size() > 3 and args[3] == "pilote"
	# Un essai ne touche jamais au vrai profil du joueur (jeu/profil.gd).
	if OS.get_environment("D666_DONNEES") == "":
		OS.set_environment("D666_DONNEES", "user://essais")
	_scene = (load(args[0]) as PackedScene).instantiate()
	root.add_child(_scene)
	process_frame.connect(_image)

func _piloter() -> Dictionary:
	var g = _scene.partie.game
	var input: Dictionary = D6Game.empty_input()
	var cible = null
	var d_min := INF
	for e in g.enemies:
		if D6Js.truthy(e.get("dead")) or e.spawnT > 0.0:
			continue
		var d: float = D6Geo.dist2(g.player.x, g.player.y, e.x, e.y)
		if d < d_min:
			d_min = d
			cible = e
	if cible == null:
		return input
	var v := Vector2(cible.x - g.player.x, cible.y - g.player.y)
	if v.length() > 70.0:
		v = v.normalized()
		input.moveX = v.x
		input.moveY = v.y
	input.attack = true
	return input

func _image() -> void:
	_vues += 1
	if _vues == 2 and _pilote and _scene.get("partie") != null:
		_scene.partie.entrees = _piloter
	if _vues == _images / 2:
		_enregistrer(_sortie.replace(".png", "_mi.png"))
	if _vues >= _images:
		_enregistrer(_sortie)
		quit(0)

func _enregistrer(chemin: String) -> void:
	var image := root.get_texture().get_image()
	image.save_png(chemin)
	print("capture : ", chemin, " (", image.get_width(), "x", image.get_height(), ")")
