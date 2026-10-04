extends Node
## Banc du TERRAIN À FRANCHIR et des DÉPLACEMENTS DE CLASSE (combat V3, étape 1 bis) : le vrai jeu
## (jeu/principal.tscn, toutes ses vues) dans une salle à rivières ou à obstacles bas, et un cas
## posé par les constructeurs de la simulation. Sert à JUGER À L'ÉCRAN : chaque disposition vue en
## entier, le terrain de près, le saut au-dessus de l'eau, la roulade, un déplacement refusé, des
## ennemis qui contournent, un combat joué. OUTIL D'ESSAI : seul ce banc écrit dans l'état.
##   D666_DISPOSITION = gues (défaut) | douve | fosse | barrieres | torrent (TERRAINS de data/salles.json)
##   D666_CLASSE      = revenant (défaut) | bourreau | chasseresse
##   D666_CERCLE      = 1 (défaut) … 10 : le Cercle (pierre, et ce qui coule dans la rivière)
##   D666_CAS = vue (défaut : la salle entière, figée) | pres (le terrain de près, figé)
##            | geste (le déplacement de la classe au-dessus du terrain, figé en plein vol)
##            | refus (le geste vers une rivière trop large : raccourci, retour visuel)
##            | contournent (des ennemis rejoignent le héros par le gué)
##            | combat (la vraie salle et ses vagues, jouée par le bot habile)
##   D666_INSTANT = image du banc où le geste part (cas geste et refus ; défaut 20)
##   <godot> --position -3000,-3000 --resolution 1600x900 --path . --script res://outils/capture.gd -- res://jeu/essai/terrain.tscn <sortie.png> 60
## Expose `partie`, comme les autres bancs.

const Principal = preload("res://jeu/principal.tscn")
const Profil = preload("res://jeu/profil.gd")
const Bots = preload("res://outils/bots/bots.gd")
const DONNEES := "user://essais"
const ETAGE := 6.0
const GRAINE := 7.0
const MARGE_VUE := 150.0 # u de mur et de vide montrées autour de la salle (cas « vue »)

var app: Node
var partie: Node

var _cas := "vue"
var _images := 0
var _instant := 20
var _dir := Vector2.RIGHT
var _fige := false
var _mem := {}

func _ready() -> void:
	# Un essai ne touche jamais au vrai profil ni aux vrais réglages du joueur (jeu/profil.gd).
	if OS.get_environment(Profil.ENV_DOSSIER) == "":
		OS.set_environment(Profil.ENV_DOSSIER, DONNEES)
	app = Principal.instantiate()
	add_child(app)
	partie = app.partie
	_cas = _env("D666_CAS", "vue")
	_instant = int(_env("D666_INSTANT", "20"))
	app.profil = _profil(_env("D666_CLASSE", "revenant"))
	var cercle := clampi(int(_env("D666_CERCLE", "1")), 1, 10)
	app.demarrer_descente(ETAGE + float(cercle - 1) * app.contenu.floors.circleLength, false, false, GRAINE)
	var g: Dictionary = partie.game
	_dresser(g, _env("D666_DISPOSITION", "gues"), _cas == "combat")
	_poser(g)

static func _env(nom: String, defaut: String) -> String:
	var v := OS.get_environment(nom)
	return defaut if v == "" else v

## Profil d'essai : tout débloqué, la classe demandée, ses deux premières actions équipées.
func _profil(classe: String) -> Dictionary:
	var t: Dictionary = D6Data.create_tuning()
	var m: Dictionary = D6Profile.create_profile(t)
	for k in ["classes", "weapons", "skills", "gadgets"]:
		m.unlocked[k] = t[k].keys()
	var c: Dictionary = t.classes[classe]
	m.loadout = {"classId": classe, "slots": [c.skills[0], c.gadgets[0], null]}
	m.equipment.arme = D6Profile.starter_weapon(t, c.weapons[0])
	return D6Profile.sanitize_profile(m, t)

## La salle de la disposition demandée, par le constructeur de la simulation ; vidée de ses vagues
## sauf pour le combat.
func _dresser(g: Dictionary, disposition: String, combat: bool) -> void:
	var plan: Dictionary = D6Sections.compose_floor(g.tuning, g.seed, g.run.floor, {"reward": "boon"}).duplicate()
	plan.layouts = [{"id": disposition, "weight": 1.0}]
	for liste in [g.enemies, g.spawns, g.hazards, g.projectiles, g.pickups, g.events]:
		liste.clear()
	g.room = D6Room.build_room(g, g.info, plan)
	g.room.plan = plan
	var start: Dictionary = D6Room.player_start(g.room)
	g.player.x = start.x
	g.player.y = start.y
	if combat:
		D6Room.launch_next_wave(g)
	else:
		g.room.waves = []
		g.room.waveIndex = 0.0

func _poser(g: Dictionary) -> void:
	var h: Dictionary = g.player
	var low: Dictionary = _terrain_large(g) if _cas == "refus" else g.room.low[0]
	# Le bord du terrain le plus proche de l'entrée, et la direction pour le franchir.
	var horizontal: bool = low.x1 - low.x0 >= low.y1 - low.y0
	_dir = Vector2.UP if horizontal else Vector2.RIGHT
	var bord := Vector2((low.x0 + low.x1) * 0.5, low.y1 + h.r + 3.0) if horizontal else Vector2(low.x0 - h.r - 3.0, (low.y0 + low.y1) * 0.5)
	match _cas:
		"vue":
			partie.set_process(false)
		"pres":
			h.x = bord.x - _dir.x * 70.0 + 40.0
			h.y = bord.y - _dir.y * 70.0
			_ennemi(g, "imp", Vector2(h.x, h.y) + _dir * 190.0 + Vector2(-50.0, 0.0))
			_ennemi(g, "archer", Vector2(h.x, h.y) + _dir * 210.0 + Vector2(70.0, 0.0))
			partie.set_process(false)
		"geste", "refus":
			h.x = bord.x - _dir.x * (30.0 if _cas == "refus" else 0.0)
			h.y = bord.y - _dir.y * (30.0 if _cas == "refus" else 0.0)
			h.facing = _dir.angle()
			partie.entrees = _lire_geste
		"contournent":
			g.godMode = true
			for k in 5:
				_ennemi(g, ["imp", "brute", "imp", "exploder", "imp"][k], Vector2(g.room.w * (0.34 + 0.08 * k), g.room.pad + 70.0 + 26.0 * (k % 2)))
			partie.entrees = D6Game.empty_input
		"combat":
			partie.entrees = _lire_bot

## Pour le cas « refus » : la rivière la plus LARGE de la salle prise dans son grand axe — on
## saute en long, l'arrivée tombe dans l'eau.
func _terrain_large(g: Dictionary) -> Dictionary:
	var mieux: Dictionary = g.room.low[0]
	for o in g.room.low:
		if maxf(o.x1 - o.x0, o.y1 - o.y0) > maxf(mieux.x1 - mieux.x0, mieux.y1 - mieux.y0):
			mieux = o
	# On la vise par son petit bout : le geste part dans le sens de sa longueur.
	var long_x: bool = mieux.x1 - mieux.x0 >= mieux.y1 - mieux.y0
	if long_x:
		return {"x0": maxf(mieux.x0, g.room.pad + 60.0), "y0": mieux.y0 - 400.0, "x1": mieux.x1, "y1": mieux.y1 + 400.0}
	return {"x0": mieux.x0 - 400.0, "y0": mieux.y0, "x1": mieux.x1 + 400.0, "y1": minf(mieux.y1, g.room.h - g.room.pad - 60.0)}

func _ennemi(g: Dictionary, genre: String, p: Vector2) -> Dictionary:
	var e: Dictionary = D6Enemies.create_enemy(g, genre, p.x, p.y, {})
	e.spawnT = 0.0
	return e

## Le geste part à l'image D666_INSTANT, dans la direction qui franchit.
func _lire_geste() -> Dictionary:
	var input: Dictionary = D6Game.empty_input()
	if _images >= _instant and partie.game.telemetry.dashes == 0.0:
		input.moveX = _dir.x
		input.moveY = _dir.y
		input.dashPressed = true
	return input

func _lire_bot() -> Dictionary:
	var g: Dictionary = partie.game
	if g.mode == "choice":
		Bots.resolve_choice(g, "skilled")
	return Bots.play("skilled", g, _mem)

func _process(_delta: float) -> void:
	_images += 1
	var g = partie.game
	if g == null:
		return
	if _cas == "vue" or _cas == "contournent":
		_cadrer_la_salle(g)
	# Le geste est figé en plein vol : au sommet du saut, ou au milieu du dash et de la roulade.
	if _cas == "geste" and not _fige and g.player.state == "dash":
		var part: float = 1.0 - g.player.dashT / maxf(1e-3, g.player.dashDur)
		if part >= 0.45:
			_fige = true
			partie.set_process(false)

## Cas « vue » et « contournent » : la caméra ne suit plus le héros, elle montre la salle entière.
func _cadrer_la_salle(g: Dictionary) -> void:
	var camera: Camera2D = app.vues.monde.camera
	camera.set_process(false)
	var ecran := get_viewport().get_visible_rect().size
	var e := minf(ecran.x / (g.room.w + 2.0 * MARGE_VUE), ecran.y / (g.room.h + 2.0 * MARGE_VUE))
	camera.position = Vector2(g.room.w, g.room.h) * 0.5
	camera.rotation = 0.0
	camera.zoom = Vector2.ONE * e
