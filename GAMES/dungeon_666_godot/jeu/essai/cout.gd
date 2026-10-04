extends Node
## Banc de COÛT du dessin : le vrai jeu (jeu/principal.tscn, toutes ses vues) dans une salle à
## piliers, la simulation ARRÊTÉE, et une troupe posée autour du héros. Les corps vivent (ils
## respirent, battent des ailes) mais rien ne bouge ni ne meurt : la scène est la même d'une
## mesure à l'autre, et d'une capture à l'autre si l'horloge est fixe (`--fixed-fps 60`).
## OUTIL D'ESSAI : seul ce banc écrit dans l'état, jamais une vue.
##   D666_ENNEMIS = nombre d'ennemis (défaut 10), pris tour à tour parmi les dix archétypes ;
##                  un sur trois est blessé (barre de vie), le quatrième est un champion
##   D666_GARDIEN = gardien | cerbere | minos | colosse : ajoute ce Gardien (défaut : aucun)
##   D666_RAMASSABLES = 1 : pose de l'or et des soins autour du premier pilier (nord, côtés, sud)
##   D666_OBJET = 1 : pose un butin légendaire (colonne de lumière) juste au sud du premier pilier
##   D666_BOND = 1 : le Gardien est posé au coin sud-est du premier pilier, au sommet d'un bond
##   (ces trois cas amènent le héros près du premier pilier)
##   <godot> --position -3000,-3000 --resolution 960x540 --path . --script res://jeu/monde/mesure.gd -- res://jeu/essai/cout.tscn
## Expose `partie`, comme les autres bancs.

const Principal = preload("res://jeu/principal.tscn")
const Profil = preload("res://jeu/profil.gd")
const DONNEES := "user://essais"

const ETAGE := 3.0
const GRAINE := 7.0
const ARCHETYPES := ["imp", "archer", "brute", "charger", "exploder", "pyromancer", "necromancer", "pavois", "stalker", "banner"]
const COLONNES := 7
const PAS := Vector2(92.0, 86.0) # u : écart entre deux ennemis de la troupe
const CHAMPION := 3 # rang de l'ennemi fait champion

var app: Node
var partie: Node

func _ready() -> void:
	# Un essai ne touche jamais au vrai profil ni aux vrais réglages du joueur (jeu/profil.gd), même
	# lancé sans outils/capture.gd (scène ouverte seule, éditeur).
	if OS.get_environment(Profil.ENV_DOSSIER) == "":
		OS.set_environment(Profil.ENV_DOSSIER, DONNEES)
	app = Principal.instantiate()
	add_child(app)
	partie = app.partie
	app.demarrer_descente(ETAGE, false, false, GRAINE)
	# La simulation ne tourne pas : la troupe reste telle qu'elle est posée (les vues, elles, vivent).
	partie.set_process(false)
	var g: Dictionary = partie.game
	for liste in [g.enemies, g.spawns, g.hazards, g.projectiles, g.pickups, g.events]:
		liste.clear()
	g.room.waves = []
	_dresser(g)
	var centre := Vector2(g.room.w, g.room.h) * 0.5
	g.player.x = centre.x
	g.player.y = centre.y + 150.0
	g.player.facing = -PI / 2.0
	_troupe(g, centre, _env("D666_ENNEMIS", "10").to_int())
	var gardien := _env("D666_GARDIEN", "")
	if gardien != "":
		_poser(g, gardien, centre + Vector2(0.0, -150.0), {"boss": true})
	_finitions(g)
	g.events.clear()

static func _env(nom: String, defaut: String) -> String:
	var v := OS.get_environment(nom)
	return defaut if v == "" else v

## Les piliers de la disposition « pillars », par la formule de D6Room.build_room.
func _dresser(g: Dictionary) -> void:
	var room: Dictionary = g.room
	room.layout = "pillars"
	room.obstacles = []
	for rect in D6Data.tables().room.LAYOUTS["pillars"]:
		var c := Vector2(rect[0] * room.w, rect[1] * room.h)
		var demi := Vector2(rect[2], rect[3]) * 0.5
		room.obstacles.append({"x0": c.x - demi.x, "y0": c.y - demi.y, "x1": c.x + demi.x, "y1": c.y + demi.y})
	room.nav = D6Nav.build_nav(room)

func _poser(g: Dictionary, genre: String, p: Vector2, options: Dictionary) -> Dictionary:
	var e: Dictionary = D6Enemies.create_enemy(g, genre, p.x, p.y, options)
	e.spawnT = 0.0
	return e

## `n` ennemis en rangs au nord du héros, les dix archétypes tour à tour.
func _troupe(g: Dictionary, centre: Vector2, n: int) -> void:
	for i in n:
		var rang := i / COLONNES
		var dans_le_rang := mini(COLONNES, n - rang * COLONNES)
		var p := centre + Vector2((i % COLONNES - (dans_le_rang - 1) * 0.5) * PAS.x, 70.0 - rang * PAS.y)
		var e := _poser(g, ARCHETYPES[i % ARCHETYPES.size()], p, {"elite": "blinde"} if i == CHAMPION else {})
		if i % 3 == 0:
			e.hp = e.maxHp * 0.6

## Les cas des finitions de profondeur, autour du premier pilier.
func _finitions(g: Dictionary) -> void:
	var o: Dictionary = g.room.obstacles[0]
	var pres := _env("D666_RAMASSABLES", "") != "" or _env("D666_OBJET", "") != "" or _env("D666_BOND", "") != ""
	if pres:
		g.player.x = o.x1 + 150.0
		g.player.y = o.y1 + 90.0
	if _env("D666_RAMASSABLES", "") != "":
		_ramassables(g, o)
	if _env("D666_OBJET", "") != "":
		var item: Dictionary = D6Loot.generate_item(g, {"rarity": "legendaire"})
		g.room.interact = {"kind": "loot", "x": (o.x0 + o.x1) * 0.5, "y": o.y1 + 34.0, "r": g.tuning.room.rewardRadius, "used": false, "item": item}
	if _env("D666_BOND", "") != "":
		for e in g.enemies:
			if D6Js.truthy(e.boss):
				e.merge({"x": o.x1 + 12.0, "y": o.y1 + 22.0, "airborne": true, "leapK": 0.5}, true)

## De l'or et des soins là où la simulation peut les laisser (jamais dans le pilier) : au nord
## (derrière lui), à l'ouest, à l'est, au sud (devant lui).
func _ramassables(g: Dictionary, o: Dictionary) -> void:
	var milieu := Vector2(o.x0 + o.x1, o.y0 + o.y1) * 0.5
	var lieux := [
		Vector2(o.x0 + 12.0, o.y0 - 9.0), Vector2(milieu.x, o.y0 - 12.0), Vector2(o.x1 - 12.0, o.y0 - 9.0), Vector2(milieu.x + 6.0, o.y0 - 30.0),
		Vector2(o.x0 - 10.0, milieu.y), Vector2(o.x1 + 10.0, milieu.y), Vector2(o.x0 + 14.0, o.y1 + 10.0), Vector2(o.x1 - 14.0, o.y1 + 10.0),
	]
	for i in lieux.size():
		D6Combat.spawn_pickup(g, "heal" if i % 3 == 1 else "gold", lieux[i].x, lieux[i].y, 1.0, {"vx": 0.0, "vy": 0.0})
