extends Node2D
## Le Monde : la salle et tout ce qui n'est pas une créature. Un calque par rôle, du sol aux tirs
## (voir monde.tscn) ; les créatures sont dessinées par le calque Entites (jeu/monde/entites.gd).
## Référence de ce qui doit se voir : GAMES/dungeon_666/src/render/render.mjs.
##
## Contrat (jeu/ARCHITECTURE.md) : `camera`, `monde_vers_ecran()`, `ecran_vers_monde()`.

const Couleurs = preload("res://jeu/theme/couleurs.gd")
const Ambiance = preload("res://jeu/monde/ambiance.gd")
const Calque = preload("res://jeu/monde/calque.gd")
## Flambeaux : part de la largeur (mur du fond) et de la hauteur (murs de côté) où ils sont scellés.
const FLAMBEAUX_FOND := [0.1, 0.24, 0.76, 0.9]
const FLAMBEAUX_COTE := [0.3, 0.7]

var app: Node
var partie: Node
## Horloge d'animation (s), figée pendant la pause : les calques y lisent leurs pulsations.
var temps := 0.0

var _ambiance := {}
var _cercle := -1
var _flambeaux: Array = []
var _salle_des_flambeaux = null

@onready var camera: Camera2D = $Camera
@onready var entites: Node2D = $Entites
@onready var voile: CanvasLayer = $Voile
@onready var _calques: Array[Node] = [$Sol, $Murs, $Lueurs, $Portes, $Objets, $ZonesHeros, $Dangers, $Contours, $Tirs, $Braises]

func brancher(p_app: Node, p_partie: Node) -> void:
	app = p_app
	partie = p_partie
	camera.brancher(app, partie)
	for calque in _calques:
		calque.relier(self, partie)
	if entites.has_method("brancher"):
		entites.brancher(app, partie)

func monde_vers_ecran(p: Vector2) -> Vector2:
	return camera.vers_ecran(p)

func ecran_vers_monde(p: Vector2) -> Vector2:
	return camera.vers_monde(p)

func _process(delta: float) -> void:
	visible = partie != null and partie.game != null
	voile.visible = visible
	if visible and not partie.en_pause:
		temps += delta

## Numéro du Cercle en cours (1..10).
func cercle() -> int:
	var info = partie.game.get("info")
	return int(info.circle) if info is Dictionary else 1

## Teinte du Cercle en cours (lueurs, flammes, braises).
func teinte_du_cercle() -> Color:
	return ambiance().teinte

## Matière et lumière du Cercle en cours (voir ambiance.gd).
func ambiance() -> Dictionary:
	var c := cercle()
	if c != _cercle:
		_cercle = c
		_ambiance = Ambiance.du_cercle(c)
	return _ambiance

## Les flambeaux de la salle : [{p: la flamme, sol: le centre de sa flaque de lumière}].
## Trois murs en portent ; celui de devant reste dans l'ombre.
func flambeaux() -> Array:
	var room: Dictionary = partie.game.room
	if is_same(room, _salle_des_flambeaux):
		return _flambeaux
	_salle_des_flambeaux = room
	_flambeaux = []
	var d: Rect2 = Calque.dedans(room)
	for k in FLAMBEAUX_FOND:
		var x: float = room.w * k
		_flambeaux.append({"p": Vector2(x, d.position.y - Calque.FACE_NORD * 0.6), "sol": Vector2(x, d.position.y + 44.0)})
	for k in FLAMBEAUX_COTE:
		var y: float = room.h * k
		_flambeaux.append({"p": Vector2(d.position.x - Calque.FACE_COTE * 0.55, y - 14.0), "sol": Vector2(d.position.x + 44.0, y)})
		_flambeaux.append({"p": Vector2(d.end.x + Calque.FACE_COTE * 0.55, y - 14.0), "sol": Vector2(d.end.x - 44.0, y)})
	return _flambeaux
