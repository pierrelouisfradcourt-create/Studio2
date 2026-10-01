extends SceneTree
## Essai « salle nettoyée, portes ouvertes » : joue le jeu assemblé jusqu'à vider la salle, va
## prendre la récompense, choisit la première proposition, s'approche des portes ouvertes et
## enregistre une image. Sert à juger les portes dans le vrai jeu (pas dans la vitrine).
##   <godot> --position -3000,-3000 --resolution 960x540 --path . --script res://jeu/monde/essai_portes.gd -- res://jeu/essai/assemblage.tscn <sortie.png> [images_apres=90]
## Outil d'essai (comme outils/capture.gd, dont il reprend le pilote) : jamais appelé par le jeu.

const IMAGES_MAX := 5400
const RECUL := 150.0 # u : le héros s'arrête à cette distance du mur du fond

var _scene: Node
var _sortie := ""
var _apres := 90
var _vues := 0
var _ouvertes_depuis := -1

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage : essai_portes.gd -- <scene.tscn> <sortie.png> [images_apres]")
		quit(2)
		return
	_sortie = args[1]
	if args.size() > 2:
		_apres = int(args[2])
	if OS.get_environment("D666_DONNEES") == "":
		OS.set_environment("D666_DONNEES", "user://essais")
	_scene = (load(args[0]) as PackedScene).instantiate()
	root.add_child(_scene)
	process_frame.connect(_image)

func _image() -> void:
	_vues += 1
	if _vues == 2:
		_scene.partie.entrees = _piloter
	var g = _scene.partie.game
	if g == null:
		return
	if g.mode == "choice":
		_scene.app.commande({"type": "choose", "index": 0.0})
		if g.mode == "choice":
			_scene.app.commande({"type": "close"})
	if _ouvertes_depuis < 0 and _porte_ouverte(g) != null:
		_ouvertes_depuis = _vues
	if (_ouvertes_depuis >= 0 and _vues - _ouvertes_depuis >= _apres) or _vues >= IMAGES_MAX:
		root.get_texture().get_image().save_png(_sortie)
		print("capture : ", _sortie, " (portes ouvertes : ", _ouvertes_depuis >= 0, ", image ", _vues, ")")
		quit(0)

func _porte_ouverte(g: Dictionary):
	for d in g.room.doors:
		if D6Js.truthy(d.get("open")):
			return d
	return null

## Où aller quand la salle est vide : la récompense, puis devant les portes ; sinon null.
func _but(g: Dictionary):
	var objet = g.room.get("interact")
	if objet is Dictionary and not D6Js.truthy(objet.get("used")):
		return Vector2(objet.x, objet.y)
	if _porte_ouverte(g) != null:
		return Vector2(g.room.w / 2.0, g.room.pad + RECUL)
	return null

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
	var seuil := 70.0
	var v := Vector2.ZERO
	if cible != null:
		v = Vector2(cible.x - g.player.x, cible.y - g.player.y)
		input.attack = true
	else:
		var but = _but(g)
		if but == null:
			return input
		v = but - Vector2(g.player.x, g.player.y)
		seuil = 10.0
	if v.length() > seuil:
		v = v.normalized()
		input.moveX = v.x
		input.moveY = v.y
	return input
