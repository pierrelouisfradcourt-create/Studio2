extends Node2D
## Banc d'essai du HUD : un fond sombre, des disques pour le héros et les ennemis, le HUD, une
## Partie démarrée à l'étage `D666_ETAGE`, et un faux `app`. Sert à se capturer seul :
##   <godot> --path . --script res://outils/capture.gd -- res://jeu/interface/banc.tscn <sortie.png> 240 pilote
##
## Variables d'environnement (toutes facultatives) :
##   D666_ETAGE=18        étage de départ (18 = Gardien)
##   D666_TACTILE=1       présentation tactile, avec une fausse vue Entrees (joystick tenu, dash
##                        appuyé, compétence visée) ; =2 : sans vue Entrees (disposition de repli)
##   D666_CLASSE=bourreau classe du héros (revenant | bourreau | chasseresse)
##   D666_PV=0.25         à la 90e image, la vie du héros tombe à cette part (on voit la barre réagir)
##   D666_GARDIEN_PV=0.6  à la 90e image, la vie du Gardien tombe à cette part (phase suivante)
##   D666_SUPER=1         Super chargé         D666_BENEDICTIONS=6  nombre de bénédictions
##   D666_OR=1234         bourse               D666_ENCOCHE=44,0,44,21  zone sûre simulée
##   D666_PAUSE=1         à la 90e image, un doigt touche le bouton pause (le résultat est imprimé)
## Le banc est un outil d'essai : il est le SEUL ici à modifier l'état de la partie.

const Partie = preload("res://jeu/partie.gd")
const Couleurs = preload("res://jeu/theme/couleurs.gd")
const Disposition = preload("res://jeu/interface/disposition.gd")
const ZOOM := 0.8
const DELAI := 90 # images avant les événements du banc (compté en images : captures reproductibles)

## Faux `app` : ce que le HUD lit de Principal (jeu/principal.gd), et rien d'autre.
class FauxApp extends Node:
	signal ecran_change(ecran: String)
	var ecran := "jeu"
	var profil := {}
	var reglages := {"sound": false, "haptics": false, "shake": 1.0, "lab": {}}
	var vues := {}
	var partie: Node
	func mettre_en_pause(pause: bool) -> void:
		partie.en_pause = pause
		print("banc : mettre_en_pause(", pause, ") reçu")

## Fausse vue Entrees : la disposition de repli, avec un joystick tenu et des boutons actifs.
class FaussesEntrees extends Node:
	var encoche := Vector4.ZERO
	func tactile() -> bool:
		return true
	func interface_tactile() -> Dictionary:
		var taille := get_viewport().get_visible_rect().size
		var ui: Dictionary = Disposition.calculer(taille, encoche)
		var base := Vector2(taille.x * 0.17, taille.y * 0.7)
		ui.stick = {"active": true, "baseX": base.x, "baseY": base.y, "knobX": base.x + 38.0, "knobY": base.y - 22.0}
		for b in ui.buttons:
			if b.id == "dash":
				b.pressed = true
			elif b.id == "skill":
				b.pressed = true
				b.dragging = true
				b.dx = -40.0
				b.dy = -30.0
		return ui

var partie: Node
var app: FauxApp
var hud: CanvasLayer
var _images := 0

func _ready() -> void:
	partie = Partie.new()
	add_child(partie)
	app = FauxApp.new()
	app.partie = partie
	add_child(app)
	app.vues["monde"] = self
	hud = (load("res://jeu/interface/hud.tscn") as PackedScene).instantiate()
	add_child(hud)
	_preparer_tactile()
	hud.brancher(app, partie)
	var tuning: Dictionary = D6Data.create_tuning()
	app.profil = _profil(tuning)
	partie.demarrer({"seed": 7.0, "startFloor": float(_env("D666_ETAGE", "1")), "meta": app.profil})
	_preparer_partie()

func _env(nom: String, defaut: String = "") -> String:
	var v := OS.get_environment(nom)
	return v if v != "" else defaut

func _preparer_tactile() -> void:
	var encoche := Vector4.ZERO
	var e := _env("D666_ENCOCHE").split_floats(",")
	if e.size() == 4:
		encoche = Vector4(e[0], e[1], e[2], e[3])
		hud.poser_encoche(encoche)
	match _env("D666_TACTILE"):
		"1":
			var entrees := FaussesEntrees.new()
			entrees.encoche = encoche
			add_child(entrees)
			app.vues["entrees"] = entrees
		"2":
			hud.forcer_tactile = true

## Profil d'essai (jamais le vrai) : la classe demandée, débloquée avec son kit de départ.
func _profil(tuning: Dictionary) -> Dictionary:
	var p: Dictionary = D6Profile.new_profile(tuning)
	var classe := _env("D666_CLASSE")
	if tuning.classes.has(classe):
		var c: Dictionary = tuning.classes[classe]
		p.unlocked.classes.append(classe)
		D6Profile.grant_class_starters(p, tuning, classe)
		p.loadout = {"classId": classe, "skillId": c.skills[0], "gadgetId": c.gadgets[0]}
	p.souls = 145.0
	p.gold = float(_env("D666_OR", "37"))
	return p

func _preparer_partie() -> void:
	var g: Dictionary = partie.game
	if _env("D666_SUPER") == "1":
		g.player.superCharge = 1.0
	var voulues := int(_env("D666_BENEDICTIONS", "0"))
	var table: Dictionary = D6Data.tables().boons
	for def in table.BOONS + table.DUOS:
		if g.run.boons.size() >= voulues:
			break
		if def.slot == "passive" or g.run.boons.size() < 2:
			D6Boons.add_boon(g.run, {"id": def.id, "rarity": "commun"})

func _evenements_du_banc() -> void:
	var g = partie.game
	if g == null:
		return
	if _env("D666_PV") != "":
		g.player.hp = maxf(1.0, g.player.maxHp * float(_env("D666_PV")))
		g.events.append({"type": "playerHurt", "tick": g.get("tick", 0.0), "x": g.player.x, "y": g.player.y})
	if _env("D666_GARDIEN_PV") != "":
		for e in g.enemies:
			if D6Js.truthy(e.get("boss")):
				e.hp = e.maxHp * float(_env("D666_GARDIEN_PV"))
	if _env("D666_PAUSE") == "1":
		_toucher_pause()

## Un doigt se pose sur le bouton pause : il doit appeler app.mettre_en_pause(true).
func _toucher_pause() -> void:
	var bouton: Button = hud.pause
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.pressed = true
	ev.position = bouton.get_global_rect().get_center() * get_viewport().get_screen_transform().get_scale()
	Input.parse_input_event(ev)
	await get_tree().create_timer(0.2).timeout
	var fin := InputEventScreenTouch.new()
	fin.index = 0
	fin.pressed = false
	fin.position = ev.position
	Input.parse_input_event(fin)
	await get_tree().create_timer(0.2).timeout
	print("banc : partie.en_pause = ", partie.en_pause)

# ---------------------------------------------------------------- faux monde

func monde_vers_ecran(p: Vector2) -> Vector2:
	var g = partie.game
	var heros: Vector2 = partie.position_dessin(g.player, true) if g != null else Vector2.ZERO
	return get_viewport_rect().size / 2.0 + (p - heros) * ZOOM

func _process(_delta: float) -> void:
	_images += 1
	if _images == DELAI:
		_evenements_du_banc()
	queue_redraw()

func _draw() -> void:
	var g = partie.game
	if g == null:
		return
	var pal: Dictionary = Couleurs.PAL
	var room: Dictionary = g.room
	var p: Vector2 = partie.position_dessin(g.player, true)
	draw_set_transform(get_viewport_rect().size / 2.0 - p * ZOOM, 0.0, Vector2(ZOOM, ZOOM))
	draw_rect(Rect2(0, 0, room.w, room.h), pal.wall)
	draw_rect(Rect2(room.pad, room.pad, room.w - 2 * room.pad, room.h - 2 * room.pad), pal.floorB)
	for o in room.obstacles:
		draw_rect(Rect2(o.x0, o.y0, o.x1 - o.x0, o.y1 - o.y0), pal.pillarTop)
	for e in g.enemies:
		if not D6Js.truthy(e.get("dead")):
			draw_circle(partie.position_dessin(e), e.r, pal.boss if D6Js.truthy(e.get("boss")) else pal.imp)
	draw_circle(p, g.player.r, pal.hero)
	draw_arc(p, g.player.r, 0.0, TAU, 32, pal.heroCape, 4.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
