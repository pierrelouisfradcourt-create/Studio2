extends Node2D
## Le Monde : la salle et tout ce qui n'est pas une créature. Un calque par rôle, du sol aux tirs
## (voir monde.tscn) ; les créatures sont dessinées par le calque Entites (jeu/monde/entites.gd).
## Référence de ce qui doit se voir : GAMES/dungeon_666/src/render/render.mjs.
##
## Contrat (jeu/ARCHITECTURE.md) : `camera`, `monde_vers_ecran()`, `ecran_vers_monde()`.

const Couleurs = preload("res://jeu/theme/couleurs.gd")
const FISSURES := 14
const PART_DE_LAVE := 0.35 # part des fissures qui rougeoient
const FLAQUES := 4

var app: Node
var partie: Node
## Horloge d'animation (s), figée pendant la pause : les calques y lisent leurs pulsations.
var temps := 0.0

var _decor := {}
var _salle_du_decor = null

@onready var camera: Camera2D = $Camera
@onready var entites: Node2D = $Entites
@onready var _calques: Array[Node] = [$Sol, $Lueurs, $Portes, $Objets, $ZonesHeros, $Dangers, $Contours, $Tirs]

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
	if visible and not partie.en_pause:
		temps += delta

## Teinte du Cercle en cours (sols, lueurs).
func teinte_du_cercle() -> Color:
	var teintes: Array[Color] = Couleurs.CIRCLE_TINTS
	var info = partie.game.get("info")
	var cercle := int(info.circle) if info is Dictionary else 1
	return teintes[posmod(cercle - 1, teintes.size())]

## Décor procédural de la salle (fissures, flaques de lueur), stable pour une salle donnée :
## {fissures: [{pts: PackedVector2Array, lave: bool, phase: float}], flaques: [{p, r}]}.
## Tirage de présentation seulement : aucune règle n'en dépend.
func decor() -> Dictionary:
	var g: Dictionary = partie.game
	if is_same(g.room, _salle_du_decor):
		return _decor
	_salle_du_decor = g.room
	var alea := RandomNumberGenerator.new()
	alea.seed = int(g.run.floor) * 7919 + int(g.get("seed", 1.0))
	var taille := Vector2(g.room.w, g.room.h)
	var fissures: Array = []
	for i in FISSURES:
		fissures.append(_fissure(alea, taille))
	var flaques: Array = []
	for i in FLAQUES:
		flaques.append({"p": Vector2(alea.randf(), alea.randf()) * taille, "r": 30.0 + alea.randf() * 50.0})
	_decor = {"fissures": fissures, "flaques": flaques}
	return _decor

func _fissure(alea: RandomNumberGenerator, taille: Vector2) -> Dictionary:
	var pts := PackedVector2Array([Vector2(alea.randf(), alea.randf()) * taille])
	var a := alea.randf() * TAU
	for k in 4:
		a += (alea.randf() - 0.5) * 1.4
		pts.append(pts[pts.size() - 1] + Vector2.from_angle(a) * (20.0 + alea.randf() * 40.0))
	return {"pts": pts, "lave": alea.randf() < PART_DE_LAVE, "phase": pts[0].x}
