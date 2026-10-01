extends Node2D
## Les CRÉATURES du Monde : le héros, les ennemis, les Gardiens, et ce qu'ils portent (statuts,
## jauges, marques d'élite). Tout est dessiné, rien n'est importé ; tout est LU dans la partie.
##
## Quatre calques, du sol vers le haut (un script par famille, sous jeu/monde/creatures/) :
##   Sol      ombres, halos, traînée de dash
##   Ennemis  les 7 archétypes et les 4 Gardiens, triés du fond vers l'avant
##   Heros    arc du coup, cape, corps, arme
##   Statuts  barres de vie, étourdissement, garde, froid, brûlure, vulnérabilité, élites
## Les télégraphes au sol, les tirs, le sol et la caméra sont dessinés par le Monde.

const Sol = preload("res://jeu/monde/creatures/sol.gd")
const Ennemis = preload("res://jeu/monde/creatures/ennemis.gd")
const Heros = preload("res://jeu/monde/creatures/heros.gd")
const Statuts = preload("res://jeu/monde/creatures/statuts.gd")

const TRAINEE_VIE := 0.18 # s : durée d'une image fantôme du dash

var app: Node
var partie: Node
## Horloge du dessin (flammes, tirets qui tournent) : elle ne règle rien dans la partie.
var temps := 0.0
## Images fantômes du dash : [{pos: Vector2, vie: float}], lues par le calque Sol.
var trainee: Array = []

var _calques: Array = []
var _heros: Node2D

func _ready() -> void:
	for famille in [["Sol", Sol], ["Ennemis", Ennemis], ["Heros", Heros], ["Statuts", Statuts]]:
		var calque: Node2D = famille[1].new()
		calque.name = famille[0]
		calque.entites = self
		add_child(calque)
		_calques.append(calque)
	_heros = _calques[2]

func brancher(p_app: Node, p_partie: Node) -> void:
	app = p_app
	partie = p_partie
	if not partie.evenements.is_connected(_sur_evenements):
		partie.evenements.connect(_sur_evenements)
		partie.partie_demarree.connect(_sur_partie_demarree)

func _sur_partie_demarree() -> void:
	trainee.clear()

func _sur_evenements(liste: Array) -> void:
	if _heros != null:
		_heros.sur_evenements(liste)

func _process(delta: float) -> void:
	temps += delta
	_suivre_trainee(delta)
	for calque in _calques:
		calque.queue_redraw()

func _suivre_trainee(delta: float) -> void:
	for f in trainee:
		f.vie -= delta
	trainee = trainee.filter(func(f): return f.vie > 0.0)
	if partie == null or partie.game == null or partie.en_pause:
		return
	var h: Dictionary = partie.game.player
	if h.state == "dash":
		trainee.append({"pos": partie.position_dessin(h, true), "vie": TRAINEE_VIE})
