extends Node
## La partie en cours : fait avancer la simulation (sim/, portée du web) à pas fixe de 1/60 s et
## publie ce qui s'y passe. Aucune règle de jeu ici : ce nœud ne fait qu'appeler D6Game.
##
## Les vues (monde, effets, HUD, son) LISENT `game` et écoutent `evenements` ; elles ne modifient
## jamais la simulation. Les menus agissent par `commande()`.
## Portage de la boucle de GAMES/dungeon_666/src/main.mjs (frame, flushEvents, setSlowmo) et de
## src/render/interp.mjs (interpolation de rendu).

## Événements de simulation de l'image (dictionnaires {type, tick, …}), avant qu'ils soient vidés.
signal evenements(liste: Array)
## La partie vient de démarrer (ou de redémarrer) : les vues se réinitialisent.
signal partie_demarree
## Le mode de la partie a changé : play | choice | dead | victory | town.
signal mode_change(mode: String)
## Un moment où le profil permanent doit être enregistré (checkpoint, butin, mort, retour en Ville).
signal profil_a_enregistrer

const MAX_PAS_PAR_IMAGE := 5
const RALENTI_DELAI := 3.0 # s réelles entre deux ralentis (sauf Gardien et mort)
const RALENTIS := {
	"roomClear": {"scale": 0.3, "dur": 0.45},
	"bossKill": {"scale": 0.2, "dur": 1.1},
	"playerDeath": {"scale": 0.35, "dur": 1.2},
	"dodge": {"scale": 0.55, "dur": 0.1},
}
const A_ENREGISTRER := ["checkpoint", "equip", "stash", "gameOver", "floorEnter", "returnTown"]
const SAUT := 150.0 # u : au-delà (téléportation, changement de salle), pas d'interpolation

## L'état de la simulation (dictionnaire de D6Game.create_game), ou null hors partie.
var game = null
var en_pause := false
## Fournit les entrées d'un pas : Callable() -> InputFrame. Sans elle, le héros ne fait rien.
var entrees := Callable()
## Part du pas en cours déjà écoulée (0..1) : les vues dessinent entre la position d'avant et d'après.
var alpha := 1.0

var _acc := 0.0
var _temps := 0.0
var _ralenti := {"scale": 1.0, "t": 0.0, "last": -99.0}
var _mode := ""
var _avant := {} # id d'entité (0 = héros) -> Vector2 avant le dernier pas

func demarrer(options: Dictionary) -> void:
	game = D6Game.create_game(options)
	en_pause = false
	_acc = 0.0
	_avant.clear()
	_ralenti = {"scale": 1.0, "t": 0.0, "last": -99.0}
	_mode = ""
	partie_demarree.emit()
	_publier()

func arreter() -> void:
	game = null
	en_pause = false

## Commande de menu (choose, equip, stash, salvage, close, respawn, returnToTown, abandon).
func commande(cmd: Dictionary) -> bool:
	if game == null:
		return false
	var ok := D6Js.truthy(D6Game.apply_command(game, cmd))
	_publier()
	return ok

## Position de dessin d'une entité {id?, x, y} : interpolée entre avant et après le dernier pas.
func position_dessin(e: Dictionary, est_heros: bool = false) -> Vector2:
	var ici := Vector2(e.x, e.y)
	var cle = 0 if est_heros else e.get("id", null)
	if cle == null or not _avant.has(cle) or alpha >= 1.0:
		return ici
	var avant: Vector2 = _avant[cle]
	if avant.distance_squared_to(ici) > SAUT * SAUT:
		return ici
	return avant.lerp(ici, alpha)

func _process(delta: float) -> void:
	if game == null:
		return
	var reel := minf(0.1, delta)
	_temps += reel
	if not en_pause and game.mode == "play":
		_avancer(reel)
	else:
		_acc = 0.0
		alpha = 1.0
	_publier()

func _avancer(reel: float) -> void:
	_ralenti.t -= reel
	var echelle: float = _ralenti.scale if _ralenti.t > 0.0 else 1.0
	_acc += reel * echelle
	var pas := 0
	while _acc >= D6Data.DT and pas < MAX_PAS_PAR_IMAGE:
		_noter_avant()
		D6Game.step_game(game, entrees.call() if entrees.is_valid() else D6Game.empty_input())
		_acc -= D6Data.DT
		pas += 1
		if game.mode != "play":
			break
	if pas == MAX_PAS_PAR_IMAGE:
		_acc = 0.0
	alpha = minf(1.0, _acc / D6Data.DT) if game.mode == "play" else 1.0

## Une entité DISPARUE (`hidden` : Traqueur en embuscade, Minos dissous) n'a pas de position
## d'avant : elle resurgit d'un bloc là où elle est, sans glisser depuis l'endroit qu'elle a quitté.
func _noter_avant() -> void:
	_avant.clear()
	_avant[0] = Vector2(game.player.x, game.player.y)
	for liste in [game.enemies, game.projectiles, game.pickups]:
		for e in liste:
			if not D6Js.truthy(e.get("hidden")):
				_avant[e.id] = Vector2(e.x, e.y)

## Publie les événements de l'image, déclenche ralentis et enregistrements, puis vide la liste.
func _publier() -> void:
	if game == null:
		return
	if not game.events.is_empty():
		var liste: Array = game.events.duplicate()
		game.events.clear()
		var enregistrer := false
		for ev in liste:
			_ralentir_pour(ev)
			if ev.type in A_ENREGISTRER:
				enregistrer = true
		evenements.emit(liste)
		if enregistrer:
			profil_a_enregistrer.emit()
	if game.mode != _mode:
		_mode = game.mode
		mode_change.emit(_mode)

func _ralentir_pour(ev: Dictionary) -> void:
	match ev.type:
		"roomClear":
			_ralentir("bossKill" if D6Js.truthy(ev.get("boss")) else "roomClear")
		"playerDeath":
			_ralentir("playerDeath")
		"dodge":
			_ralentir("dodge")

func _ralentir(nom: String) -> void:
	var s: Dictionary = RALENTIS[nom]
	var urgent := nom == "bossKill" or nom == "playerDeath"
	if not urgent and _temps - _ralenti.last < RALENTI_DELAI:
		return
	if s.scale <= _ralenti.scale or _ralenti.t <= 0.0:
		_ralenti.scale = s.scale
		_ralenti.t = s.dur
		_ralenti.last = _temps
