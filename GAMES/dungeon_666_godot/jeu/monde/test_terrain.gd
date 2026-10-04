extends SceneTree
## Essai headless du TERRAIN À FRANCHIR à l'affichage, sur le banc du Monde (jeu/monde/banc.tscn).
##   <godot> --headless --path . --script res://jeu/monde/test_terrain.gd      (sortie 0 = vert)
## 1. obstacles bas : un nœud par palissade, au pied de sa face avant, dans le groupe trié des
##    créatures ; un ennemi au nord passe derrière, au sud devant ; le héros de même ;
## 2. rivières : le calque du sol les lit dans room.low, rognées à l'intérieur des murs ; ce qui
##    coule change avec le Cercle ;
## 3. coût : le terrain n'est redessiné que lorsque la salle change ;
## 4. déplacements : le Bourreau en plein saut est en l'air (et passe devant tout) ; ni le dash ni
##    la roulade ne décollent.
## Ce qu'il ne prouve pas : que cela se LIT (voir jeu/essai/terrain.tscn et ses captures).

const Terrain = preload("res://jeu/monde/terrain.gd")

const RIVIERE := {"x0": 0.0, "y0": 500.0, "x1": 600.0, "y1": 564.0, "kind": "river"}
const PALISSADE := {"x0": 400.0, "y0": 300.0, "x1": 640.0, "y1": 332.0, "kind": "barrier"}

var _banc: Node
var _monde: Node2D
var _g: Dictionary
var _verifs := 0
var _rouges := 0
var _dessins := 0

func _initialize() -> void:
	OS.set_environment("D666_DONNEES", "user://essais") # AVANT d'instancier quoi que ce soit
	_derouler()

func _ok(vrai: bool, quoi: String) -> void:
	_verifs += 1
	if vrai:
		print("  ok    — ", quoi)
	else:
		_rouges += 1
		print("  ROUGE — ", quoi)

func _images(n: int = 3) -> void:
	for i in n:
		await process_frame

func _derouler() -> void:
	_banc = (load("res://jeu/monde/banc.tscn") as PackedScene).instantiate()
	root.add_child(_banc)
	await _images()
	_monde = _banc.vues.monde
	_g = _banc.partie.game
	_banc.partie.en_pause = true
	for liste in [_g.enemies, _g.spawns, _g.hazards]:
		liste.clear()
	_monde.get_node("Terrain").draw.connect(func() -> void: _dessins += 1)
	_nouvelle_salle([RIVIERE.duplicate(), PALISSADE.duplicate()])
	await _images()
	await _palissades()
	_rivieres()
	await _cout()
	await _gestes()
	print("TERRAIN : %d vérifications, %d rouge(s)" % [_verifs, _rouges])
	print("TERRAIN : OK" if _rouges == 0 else "TERRAIN : ECHEC")
	quit(0 if _rouges == 0 else 1)

## Une salle NEUVE (les calques statiques la reconnaissent à son identité), sans pilier.
func _nouvelle_salle(low: Array) -> void:
	_g.room = _g.room.duplicate()
	_g.room.obstacles = []
	_g.room.low = low

func _heros_en(p: Vector2) -> void:
	_g.player.x = p.x
	_g.player.y = p.y

func _palissades() -> void:
	print("-- obstacles bas")
	var calque: Node2D = _monde.get_node("Entites/Debout/Barrieres")
	_ok(calque.get_child_count() == 1, "un nœud par obstacle bas (la rivière n'en a pas) : %d" % calque.get_child_count())
	if calque.get_child_count() == 0:
		return
	var n: Node2D = calque.get_child(0)
	_ok(n.position == Vector2(PALISSADE.x0, PALISSADE.y1), "posé au pied de sa face avant : %s" % n.position)
	_ok(calque.get_parent().y_sort_enabled and calque.y_sort_enabled, "dans le groupe trié en profondeur")
	_ok(_monde.get_node("Entites/Debout/Piliers").get_child_count() == 0, "ce n'est pas un pilier")
	var heros: Node2D = _monde.get_node("Entites/Debout/Heros")
	_heros_en(Vector2(520.0, PALISSADE.y0 - 20.0))
	await _images()
	_ok(heros.position.y < n.position.y, "le héros au nord passe derrière la palissade (rang %s < %s)" % [heros.position.y, n.position.y])
	_heros_en(Vector2(520.0, PALISSADE.y1 + 20.0))
	await _images()
	_ok(heros.position.y > n.position.y, "le héros au sud passe devant")

func _rivieres() -> void:
	print("-- rivières")
	var calque: Node2D = _monde.get_node("Terrain")
	var vues: Array = calque._rivieres(_g.room)
	_ok(vues.size() == 1, "une rivière lue dans room.low : %d" % vues.size())
	if vues.size() == 1:
		var r: Rect2 = vues[0]
		_ok(r.position.x == _g.room.pad and r.end.x == RIVIERE.x1, "rognée au pied du mur : %s" % r)
	var fluides := {}
	for cercle in range(1, 11):
		fluides[Terrain.FLUIDE_DU_CERCLE[cercle - 1]] = true
		_ok(Terrain.FLUIDES.has(Terrain.FLUIDE_DU_CERCLE[cercle - 1]), "Cercle %d : ce qui coule est décrit" % cercle)
	_ok(fluides.size() >= 3, "au moins trois fluides selon le Cercle : %s" % str(fluides.keys()))

func _cout() -> void:
	print("-- coût")
	await _images(2)
	var avant := _dessins
	var pieux: Node2D = _monde.get_node("Entites/Debout/Barrieres").get_child(0)
	await _images(30)
	_ok(_dessins == avant, "30 images dans la même salle : le terrain n'est pas redessiné (%d dessins)" % (_dessins - avant))
	_ok(is_instance_valid(pieux) and pieux.get_parent() != null, "… et la palissade n'est pas refaite")
	_nouvelle_salle([RIVIERE.duplicate()])
	await _images(4)
	_ok(_dessins == avant + 1, "salle changée : redessiné une fois (%d)" % (_dessins - avant))
	_ok(_monde.get_node("Entites/Debout/Barrieres").get_child_count() == 0, "les palissades de l'ancienne salle sont parties")

## Le héros de la classe `classe` en plein déplacement : la hauteur que lit le calque des créatures.
func _hauteur(classe: String) -> float:
	var t: Dictionary = D6Data.create_tuning()
	var m: Dictionary = D6Profile.create_profile(t)
	for k in ["classes", "weapons", "skills", "gadgets"]:
		m.unlocked[k] = t[k].keys()
	var c: Dictionary = t.classes[classe]
	m.loadout = {"classId": classe, "slots": [c.skills[0], c.gadgets[0], null]}
	m.equipment.arme = D6Profile.starter_weapon(t, c.weapons[0])
	_banc.partie.demarrer({"seed": 7.0, "startFloor": 1.0, "meta": m})
	_g = _banc.partie.game
	_banc.partie.en_pause = true
	_g.spawns.clear()
	var entree: Dictionary = D6Game.empty_input()
	entree.moveX = 1.0
	entree.dashPressed = true
	D6Game.step_game(_g, entree)
	var haut := 0.0
	var calque: Node2D = _monde.get_node("Entites/Debout/Heros")
	while _g.player.state == "dash":
		haut = maxf(haut, calque.envol_heros(_g))
		D6Game.step_game(_g, D6Game.empty_input())
	await _images()
	return haut

func _gestes() -> void:
	print("-- déplacements")
	var saut := await _hauteur("bourreau")
	_ok(saut > 0.9, "le Bourreau en plein saut est dessiné en l'air (hauteur %.2f)" % saut)
	_ok(await _hauteur("revenant") == 0.0, "le dash du Revenant reste au sol")
	_ok(await _hauteur("chasseresse") == 0.0, "la roulade de la Chasseresse reste au sol")
