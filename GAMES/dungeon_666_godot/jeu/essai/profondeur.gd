extends Node
## Banc de PROFONDEUR et d'ÉTATS : le vrai jeu (jeu/principal.tscn, toutes ses vues) dans une
## salle à piliers, la simulation ARRÊTÉE, et un cas posé par les constructeurs de la simulation.
## Sert à juger à l'écran ce qui passe devant et derrière un pilier, l'élan de « Représailles »,
## et le Traqueur qui disparaît. OUTIL D'ESSAI : seul ce banc écrit dans l'état, jamais une vue.
##   D666_CAS = heros_nord (défaut) | heros_sud | ennemi_nord | ennemi_sud | bond
##            | represailles | traqueur_visible | traqueur_dissolution | traqueur_disparu
##   D666_DISPOSITION = pillars (défaut) | lanes | scatter… (LAYOUTS de data/salles.json)
##   D666_ELAN = part de la durée de l'élan déjà écoulée (défaut 0.5), pour le cas represailles
##   <godot> --position -3000,-3000 --resolution 1600x900 --path . --script res://outils/capture.gd -- res://jeu/essai/profondeur.tscn <sortie.png> 90
## Expose `partie`, comme les autres bancs.

const Principal = preload("res://jeu/principal.tscn")

const ETAGE := 3.0
const GRAINE := 7.0
const PRES := Vector2(50.0, -110.0) # u : à côté du héros, à l'écran
const LOIN := Vector2(900.0, 380.0) # u : assez loin du héros pour sortir de l'écran

var app: Node
var partie: Node

func _ready() -> void:
	app = Principal.instantiate()
	add_child(app)
	partie = app.partie
	app.demarrer_descente(ETAGE, false, false, GRAINE)
	# La simulation ne tourne pas : le cas reste tel qu'il est posé (les vues, elles, vivent).
	partie.set_process(false)
	var g: Dictionary = partie.game
	_vider(g)
	_dresser(g, _env("D666_DISPOSITION", "pillars"))
	_poser(g, _env("D666_CAS", "heros_nord"), g.room.obstacles[0])

static func _env(nom: String, defaut: String) -> String:
	var v := OS.get_environment(nom)
	return defaut if v == "" else v

func _vider(g: Dictionary) -> void:
	for liste in [g.enemies, g.spawns, g.hazards, g.projectiles, g.pickups, g.events]:
		liste.clear()
	g.room.waves = []

## Les piliers d'une disposition, par la même formule que D6Room.build_room (la première salle
## d'une descente est toujours dégagée).
func _dresser(g: Dictionary, disposition: String) -> void:
	var room: Dictionary = g.room
	room.layout = disposition
	room.obstacles = []
	for rect in D6Data.tables().room.LAYOUTS[disposition]:
		var c := Vector2(rect[0] * room.w, rect[1] * room.h)
		var demi := Vector2(rect[2], rect[3]) * 0.5
		room.obstacles.append({"x0": c.x - demi.x, "y0": c.y - demi.y, "x1": c.x + demi.x, "y1": c.y + demi.y})
	room.nav = D6Nav.build_nav(room)

func _poser(g: Dictionary, cas: String, o: Dictionary) -> void:
	var h: Dictionary = g.player
	var milieu: float = (o.x0 + o.x1) * 0.5
	var ouest := Vector2(o.x0 - 110.0, (o.y0 + o.y1) * 0.5)
	match cas:
		"heros_nord":
			_heros(h, Vector2(milieu - 10.0, o.y0 - h.r - 1.0), 0.0)
		"heros_sud":
			_heros(h, Vector2(milieu - 10.0, o.y1 + h.r + 1.0), 0.0)
		"ennemi_nord":
			_heros(h, ouest, 0.0)
			_ennemis_au_bord(g, o, -1.0)
		"ennemi_sud":
			_heros(h, ouest, 0.0)
			_ennemis_au_bord(g, o, 1.0)
		"bond":
			_heros(h, Vector2(milieu, (o.y0 + o.y1) * 0.5), 0.0)
			_bond(g)
		"represailles":
			_heros(h, ouest, 0.0)
			_ennemi(g, "imp", ouest + Vector2(120.0, -70.0), {})
			_represailles(g)
		_:
			_heros(h, ouest, 0.0)
			_traqueurs(g, cas, ouest)

func _heros(h: Dictionary, p: Vector2, regard: float) -> void:
	h.x = p.x
	h.y = p.y
	h.facing = regard

func _ennemi(g: Dictionary, genre: String, p: Vector2, etat: Dictionary) -> Dictionary:
	var e: Dictionary = D6Enemies.create_enemy(g, genre, p.x, p.y, {})
	e.spawnT = 0.0
	e.merge(etat, true)
	if etat.has("hp"):
		e.hp = e.maxHp * float(etat.hp)
	return e

## Une brute blessée qui arme son coup (barre de vie et télégraphe) et un diablotin, collés au
## bord nord (`cote` = -1) ou sud (+1) du pilier.
func _ennemis_au_bord(g: Dictionary, o: Dictionary, cote: float) -> void:
	var def: Dictionary = g.tuning.enemies
	var bord: float = o.y0 if cote < 0.0 else o.y1
	var brute := _ennemi(g, "brute", Vector2(o.x0 + 22.0, bord + cote * (def.brute.radius + 1.0)), {"hp": 0.6, "state": "windup", "stateTime": 0.4})
	brute.tele = {"shape": "circle", "r": 80.0, "progress": 0.8}
	_ennemi(g, "imp", Vector2(o.x1 - 12.0, bord + cote * (def.imp.radius + 1.0)), {"hp": 0.5})
	g.events.clear()

## Le héros en plein Bond, au-dessus du pilier (sommet de la cloche).
func _bond(g: Dictionary) -> void:
	var h: Dictionary = g.player
	g.tuning.skill["leapTime"] = 0.4
	h.state = "cast"
	h.cast = {"kind": "bond"}
	h.castT = 0.2

## L'élan par le VRAI chemin : la bénédiction est accordée, ses procs recalculés, et l'esquive
## parfaite déclenchée ; puis une part de sa durée est écoulée.
func _represailles(g: Dictionary) -> void:
	D6Boons.add_boon(g.run, {"id": "represailles", "rarity": "common", "level": 1.0})
	D6Stats.recompute_stats(g)
	D6Combat.fire_procs(g, "dodge")
	g.player.surge *= 1.0 - clampf(_env("D666_ELAN", "0.5").to_float(), 0.0, 1.0)
	g.events.clear()

## Deux Traqueurs blessés dans le même état : l'un à côté du héros, l'autre hors de l'écran (sa
## flèche au bord). `cas` : traqueur_visible | traqueur_dissolution | traqueur_disparu.
func _traqueurs(g: Dictionary, cas: String, pres: Vector2) -> void:
	var def: Dictionary = g.tuning.enemies.stalker
	var etat := {"hp": 0.6}
	match cas:
		"traqueur_dissolution":
			etat.merge({"state": "fade", "stateTime": def.fade * 0.5})
		"traqueur_disparu":
			etat.merge({"state": "ambush", "hidden": true, "spawnT": def.hiddenTime * 0.5})
	_ennemi(g, "stalker", pres + PRES, etat)
	_ennemi(g, "stalker", pres + LOIN, etat)
	g.events.clear()
