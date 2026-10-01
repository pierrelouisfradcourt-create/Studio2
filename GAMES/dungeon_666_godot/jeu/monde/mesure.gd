extends SceneTree
## Mesure du coût de rendu : lance une scène (le jeu assemblé, piloté), synchronisation verticale
## coupée, et imprime images par seconde, temps d'image, appels de dessin et primitives du canevas.
##   <godot> --position -3000,-3000 --resolution 960x540 --path . --script res://jeu/monde/mesure.gd -- <scene.tscn> [secondes=8] [echauffement=2]
##   D666_CACHER=Entites,Murs : cache ces nœuds avant de mesurer (ce que coûte un calque = la différence).
## Outil d'essai (comme outils/capture.gd, dont il reprend le pilote) : jamais appelé par le jeu.

var _scene: Node
var _duree := 8.0
var _echauffement := 2.0
var _temps := 0.0
var _images := 0
var _appels := 0
var _appels_max := 0
var _primitives := 0
var _objets := 0
var _pire := 0.0
var _vues := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 1:
		print("usage : mesure.gd -- <scene.tscn> [secondes] [echauffement]")
		quit(2)
		return
	if args.size() > 1:
		_duree = float(args[1])
	if args.size() > 2:
		_echauffement = float(args[2])
	if OS.get_environment("D666_DONNEES") == "":
		OS.set_environment("D666_DONNEES", "user://essais")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_scene = (load(args[0]) as PackedScene).instantiate()
	root.add_child(_scene)

func _process(delta: float) -> bool:
	_vues += 1
	if _vues == 2 and _scene.get("partie") != null:
		_scene.partie.entrees = _piloter
	if _vues == 3:
		_cacher()
	_temps += delta
	if _temps < _echauffement:
		return false
	_images += 1
	_pire = maxf(_pire, delta)
	var vue := root.get_viewport_rid()
	var appels := RenderingServer.viewport_get_render_info(vue, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	_appels += appels
	_appels_max = maxi(_appels_max, appels)
	_primitives += RenderingServer.viewport_get_render_info(vue, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	_objets += RenderingServer.viewport_get_render_info(vue, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)
	if _temps >= _echauffement + _duree:
		_conclure()
		return true
	return false

## D666_CACHER=Entites,Murs : nœuds (par nom) rendus invisibles, pour peser un calque à la fois.
func _cacher() -> void:
	for nom in OS.get_environment("D666_CACHER").split(",", false):
		var noeud := _scene.find_child(nom, true, false)
		if noeud is CanvasItem or noeud is CanvasLayer:
			noeud.visible = false
			if noeud is CanvasItem:
				noeud.set_process(false)

func _conclure() -> void:
	var n := maxf(1.0, float(_images))
	print("MESURE images=%d  ips=%.0f  ms_moyen=%.3f  ms_pire=%.2f  appels_de_dessin=%.1f (max %d)  primitives=%.0f  objets=%.0f" % [
		_images, n / _duree, 1000.0 * _duree / n, 1000.0 * _pire, float(_appels) / n, _appels_max, float(_primitives) / n, float(_objets) / n])

## Même pilote que outils/capture.gd : va vers l'ennemi le plus proche et frappe.
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
