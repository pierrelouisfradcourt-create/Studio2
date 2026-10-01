extends Node2D
## Les CRÉATURES du Monde : le héros, les ennemis, les Gardiens, et ce qu'ils portent (statuts,
## jauges, marques d'élite). Tout est dessiné, rien n'est importé ; tout est LU dans la partie.
##
## Quatre calques, du sol vers le haut (un script par famille, sous jeu/monde/creatures/) :
##   Sol      ombres douces, halos, fils de protection, traînée de dash, aura d'élan
##   Ennemis  les 10 archétypes et les 4 Gardiens : un nœud par corps, trié du fond vers l'avant
##   Heros    arc du coup, cape, corps, arme
##   Statuts  barres de vie, étourdissement, garde, froid, brûlure, vulnérabilité, élites, protégés
## Les télégraphes au sol, les tirs, le sol et la caméra sont dessinés par le Monde.

const Sol = preload("res://jeu/monde/creatures/sol.gd")
const Ennemis = preload("res://jeu/monde/creatures/ennemis.gd")
const Heros = preload("res://jeu/monde/creatures/heros.gd")
const Statuts = preload("res://jeu/monde/creatures/statuts.gd")

const TRAINEE_VIE := 0.24 # s : durée d'un point de la traînée du dash
const GARDES_CADENCE := 0.1 # s entre deux relevés de « qui protège qui »

var app: Node
var partie: Node
## Horloge du dessin (flammes, tirets qui tournent, respiration) : elle ne règle rien dans la partie.
var temps := 0.0
## Traînée du dash : [{pos: Vector2, vie: float}], du plus ancien au plus récent (lue par Sol).
var trainee: Array = []
## Qui protège qui : id d'un ennemi couvert -> son porte-étendard (D6FoeDefense.ward_of).
var gardes := {}

var _calques: Array = []
var _heros: Node2D
var _gardes_t := 0.0

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
	gardes.clear()

func _sur_evenements(liste: Array) -> void:
	if _heros != null:
		_heros.sur_evenements(liste)

func _process(delta: float) -> void:
	temps += delta
	_suivre_trainee(delta)
	_suivre_gardes(delta)
	for calque in _calques:
		calque.actualiser(delta)

func _suivre_trainee(delta: float) -> void:
	for f in trainee:
		f.vie -= delta
	while not trainee.is_empty() and trainee[0].vie <= 0.0:
		trainee.pop_front()
	if partie == null or partie.game == null or partie.en_pause:
		return
	var h: Dictionary = partie.game.player
	if h.state == "dash":
		trainee.append({"pos": partie.position_dessin(h, true), "vie": TRAINEE_VIE})

## Relève, dix fois par seconde, les ennemis couverts par un porte-étendard debout. Sans porteur
## dans la salle (le cas courant), rien n'est parcouru.
func _suivre_gardes(delta: float) -> void:
	_gardes_t -= delta
	if _gardes_t > 0.0:
		return
	_gardes_t = GARDES_CADENCE
	gardes.clear()
	if partie == null or partie.game == null:
		return
	var g: Dictionary = partie.game
	if not _porteur_present(g):
		return
	for e in g.enemies:
		if D6Js.truthy(e.get("dead")) or D6Js.truthy(e.get("hidden")) or e.spawnT > 0.0:
			continue
		var porteur = D6FoeDefense.ward_of(g, e)
		if porteur != null:
			gardes[e.id] = porteur

static func _porteur_present(g: Dictionary) -> bool:
	var defs: Dictionary = g.tuning.enemies
	for e in g.enemies:
		var def = defs.get(e.kind)
		if def != null and D6Js.nz(def.get("auraRadius"), 0.0) > 0.0 and not D6Js.truthy(e.get("dead")):
			return true
	return false
