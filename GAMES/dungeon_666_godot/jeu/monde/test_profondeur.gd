extends SceneTree
## Essai headless de la PROFONDEUR et de ce qui disparaît, sur le banc du Monde (jeu/monde/banc.tscn).
##   <godot> --headless --path . --script res://jeu/monde/test_profondeur.gd      (sortie 0 = vert)
## 1. piliers : un nœud par obstacle, au pied de sa face avant, dans le groupe trié des créatures ;
##    un ennemi au nord passe derrière, un ennemi au sud devant ; le sol des créatures reste
##    dessous, leurs statuts dessus ;
## 2. héros : derrière le pilier dont il est au nord, devant sinon, devant tout ennemi, au-dessus
##    de tout en plein Bond ;
## 3. Traqueur disparu : pas de flèche hors écran tant qu'il est caché, et il resurgit d'un bloc
##    (aucune position interpolée depuis l'endroit qu'il a quitté) ;
## 4. élan : sa durée pleine est lue dans les procs du héros.
## Ce qu'il ne prouve pas : que cela se LIT (voir jeu/essai/profondeur.tscn et ses captures).

const Fleches = preload("res://jeu/interface/fleches.gd")

const PILIER := {"x0": 400.0, "y0": 300.0, "x1": 470.0, "y1": 370.0}
const ECRAN := Vector2(960.0, 540.0)

var _banc: Node
var _monde: Node2D
var _g: Dictionary
var _verifs := 0
var _rouges := 0

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
	# Une salle NEUVE (les calques statiques la reconnaissent à son identité), avec un seul pilier.
	_g.room = _g.room.duplicate()
	_g.room.obstacles = [PILIER.duplicate()]
	await _piliers()
	await _heros()
	await _traqueur_cache()
	_traqueur_revenu()
	_elan()
	print("PROFONDEUR : %d vérifications, %d rouge(s)" % [_verifs, _rouges])
	print("PROFONDEUR : OK" if _rouges == 0 else "PROFONDEUR : ECHEC")
	quit(0 if _rouges == 0 else 1)

func _placer_heros(p: Vector2) -> void:
	_g.player.x = p.x
	_g.player.y = p.y

func _ennemi(genre: String, p: Vector2) -> Dictionary:
	var e: Dictionary = D6Enemies.create_enemy(_g, genre, p.x, p.y, {})
	e.spawnT = 0.0
	return e

## Le nœud (corps.gd) d'un ennemi dans le calque des ennemis.
func _corps(e: Dictionary) -> Node2D:
	for n in _monde.get_node("Entites/Debout/Ennemis").get_children():
		if n.e.id == e.id:
			return n
	return null

func _piliers() -> void:
	print("-- piliers")
	_placer_heros(Vector2(900.0, 600.0))
	var nord := _ennemi("brute", Vector2(435.0, PILIER.y0 - 40.0))
	var sud := _ennemi("brute", Vector2(435.0, PILIER.y1 + 40.0))
	await _images()
	var entites: Node2D = _monde.get_node("Entites")
	var debout: Node2D = entites.get_node("Debout")
	var piliers: Node2D = debout.get_node("Piliers")
	_ok(debout.y_sort_enabled and piliers.y_sort_enabled and debout.get_node("Ennemis").y_sort_enabled, "le groupe Debout, ses piliers et ses ennemis sont triés en y")
	_ok(piliers.get_child_count() == 1, "un nœud par pilier")
	var pilier: Node2D = piliers.get_child(0)
	_ok(pilier.position == Vector2(PILIER.x0, PILIER.y1), "le pilier est posé au pied de sa face avant")
	_ok(_corps(nord).position.y < pilier.position.y, "un ennemi au nord du pilier passe derrière lui")
	_ok(_corps(sud).position.y > pilier.position.y, "un ennemi au sud du pilier passe devant lui")
	_ok(entites.get_node("Sol").get_index() < debout.get_index(), "le sol des créatures (ombres, halos) reste sous les piliers")
	_ok(entites.get_node("Statuts").get_index() > debout.get_index(), "les statuts (barres de vie) restent au-dessus des piliers")
	_ok(_monde.get_node("Contours").get_index() > entites.get_index(), "les contours des dangers restent au-dessus des piliers")

func _heros() -> void:
	print("-- héros")
	var heros: Node2D = _monde.get_node("Entites/Debout/Heros")
	var pilier: Node2D = _monde.get_node("Entites/Debout/Piliers").get_child(0)
	var r: float = _g.player.r
	var gros := _ennemi("brute", Vector2(445.0, PILIER.y0 - r - 30.0))
	_placer_heros(Vector2(435.0, PILIER.y0 - r - 1.0))
	await _images()
	_ok(heros.position.y < pilier.position.y, "héros au nord du pilier : derrière lui")
	_ok(heros.position.y > _corps(gros).position.y, "… et toujours devant l'ennemi qui le chevauche")
	_placer_heros(Vector2(435.0, PILIER.y1 + r + 1.0))
	await _images()
	_ok(heros.position.y > pilier.position.y, "héros au sud du pilier : devant lui")
	_placer_heros(Vector2(PILIER.x0 - 200.0, PILIER.y0 - 60.0))
	var bas := _ennemi("brute", Vector2(PILIER.x0 - 200.0, PILIER.y0 - 40.0))
	await _images()
	_ok(heros.position.y > _corps(bas).position.y, "loin de tout pilier : devant un ennemi placé plus bas que lui")
	_placer_heros(Vector2(435.0, PILIER.y0 - r - 1.0))
	_g.tuning.skill["leapTime"] = 0.4
	_g.player.state = "cast"
	_g.player.cast = {"kind": "bond"}
	_g.player.castT = 0.2
	await _images()
	_ok(heros.position.y > pilier.position.y, "en plein Bond : au-dessus du pilier")
	_g.player.state = "free"
	_g.player.cast = null

## Flèches hors écran : le Traqueur visible en a une, le Traqueur disparu n'en a pas.
func _traqueur_cache() -> void:
	print("-- Traqueur disparu")
	_g.enemies.clear()
	_placer_heros(Vector2(300.0, 300.0))
	_monde.camera.recaler()
	await _images()
	var fleches: Control = Fleches.new()
	fleches.size = ECRAN
	root.add_child(fleches)
	var traqueur := _ennemi("stalker", Vector2(1300.0, 800.0))
	fleches.actualiser(_g, _monde, 0.0, Vector4.ZERO, ECRAN)
	_ok(fleches._pointes.size() == 1, "Traqueur visible hors écran : une flèche")
	traqueur.state = "fade"
	fleches.actualiser(_g, _monde, 0.0, Vector4.ZERO, ECRAN)
	_ok(fleches._pointes.size() == 1, "Traqueur qui se dissout (encore vulnérable) : la flèche reste")
	traqueur.state = "ambush"
	traqueur.hidden = true
	traqueur.spawnT = 0.3
	fleches.actualiser(_g, _monde, 0.0, Vector4.ZERO, ECRAN)
	_ok(fleches._pointes.is_empty(), "Traqueur disparu : aucune flèche")
	await _images()
	_ok(not _corps(traqueur).visible, "Traqueur disparu : son corps est caché")
	fleches.queue_free()

## Le Traqueur resurgit à moins d'un « saut » de l'endroit qu'il a quitté : la position dessinée
## est la sienne dès la première image, quelle que soit la part du pas écoulée.
func _traqueur_revenu() -> void:
	var partie: Node = _banc.partie
	var h: Dictionary = _g.player
	_g.enemies.clear()
	_placer_heros(Vector2(700.0, 440.0))
	h.facing = -PI / 2.0
	var depart := Vector2(700.0, 560.0)
	var traqueur := _ennemi("stalker", depart)
	traqueur.merge({"state": "ambush", "hidden": true, "spawnT": 0.001}, true)
	partie.en_pause = false
	partie._process(D6Data.DT + 0.001)
	partie.en_pause = true
	var ici := Vector2(traqueur.x, traqueur.y)
	_ok(not D6Js.truthy(traqueur.get("hidden")) and ici != depart and ici.distance_to(depart) < partie.SAUT, "le Traqueur a resurgi tout près (%.0f u)" % ici.distance_to(depart))
	partie.alpha = 0.25
	_ok(partie.position_dessin(traqueur).is_equal_approx(ici), "il resurgit d'un bloc : aucune position intermédiaire")
	partie.alpha = 1.0

func _elan() -> void:
	print("-- élan")
	var heros: Node2D = _monde.get_node("Entites/Debout/Heros")
	D6Boons.add_boon(_g.run, {"id": "represailles", "rarity": "common", "level": 1.0})
	D6Stats.recompute_stats(_g)
	D6Combat.fire_procs(_g, "dodge")
	var h: Dictionary = _g.player
	_ok(h.surge > 0.0, "Représailles pose l'élan (%.1f s)" % h.surge)
	var plein: float = heros._elan_plein(h)
	h.surge *= 0.5
	_ok(is_equal_approx(heros._elan_plein(h), plein) and is_equal_approx(h.surge / plein, 0.5), "à mi-durée, l'anneau de l'élan est à moitié plein")
