extends Node2D
## Banc de la vue Effets : une vraie Partie, le héros et les ennemis en disques, les télégraphes
## en rouge (pour vérifier qu'aucun effet ne les cache), la vue Effets, et une caméra d'essai.
## Il tient le rôle d'`app` (reglages, vues) et celui du Monde (propriété `camera`).
##   D666_ETAGE=7      étage de départ            D666_GRAINE=7   graine de la partie
##   D666_PLANCHE=hit,kill   à l'image 20, donne à la vue les événements d'exemple de ces types
##                     (« tout » : tous), en grille autour du héros ; D666_PLANCHE_IMAGE=20
##   D666_FIGER=kill:3:2   met la partie en pause 3 images après le 2e événement « kill » :
##                     la capture finale montre le coup en plein vol
##   D666_CHARGE=1     tient le réservoir de particules plein et affiche le coût par image
##                     (D666_CHARGE=0 : la même mesure sur une partie ordinaire)

const Partie = preload("res://jeu/partie.gd")
const Couleurs = preload("res://jeu/theme/couleurs.gd")
const Echantillons = preload("res://jeu/effets/echantillons.gd")
const PAL: Dictionary = Couleurs.PAL
const GENRES := {"imp": "imp", "archer": "archer", "brute": "brute", "charger": "charger", "exploder": "exploder"}

var partie: Node
var vues := {}
var reglages := {"sound": false, "haptics": false, "shake": 1.0}

@onready var camera: Camera2D = $Camera
@onready var effets: Node2D = $Effets

var _images := 0
var _planche := PackedStringArray()
var _planche_image := -1
var _charge := false
var _maj_cumul := 0
var _particules_cumul := 0
var _figer_type := ""
var _figer_rang := 1
var _figer_dans := -1

func _ready() -> void:
	partie = Partie.new()
	partie.name = "Partie"
	add_child(partie)
	move_child(partie, 0)
	vues = {"monde": self}
	camera.brancher(self, partie)
	effets.brancher(self, partie)
	var planche := OS.get_environment("D666_PLANCHE")
	if planche != "":
		_planche_image = int(_env("D666_PLANCHE_IMAGE", "20"))
		if planche != "tout":
			_planche = planche.split(",")
	_charge = OS.get_environment("D666_CHARGE") != ""
	if _charge:
		effets.set_process(false)
	var figer := OS.get_environment("D666_FIGER").split(":", false)
	if figer.size() >= 2:
		_figer_type = figer[0]
		_figer_dans = -1 - int(figer[1])
		_figer_rang = int(figer[2]) if figer.size() > 2 else 1
		partie.evenements.connect(_guetter)
	partie.demarrer({"seed": float(_env("D666_GRAINE", "7")), "startFloor": float(_env("D666_ETAGE", "1"))})

## Compte les événements du type guetté ; au bon rang, arme le compte à rebours de la pause.
func _guetter(liste: Array) -> void:
	for ev in liste:
		if ev.get("type") == _figer_type and _figer_dans < 0:
			_figer_rang -= 1
			if _figer_rang == 0:
				_figer_dans = -1 - _figer_dans

static func _env(nom: String, defaut: String) -> String:
	var v := OS.get_environment(nom)
	return v if v != "" else defaut

func _process(delta: float) -> void:
	_images += 1
	queue_redraw()
	if partie.game == null:
		return
	var p: Vector2 = partie.position_dessin(partie.game.player, true)
	if _images == _planche_image:
		partie.evenements.emit(Echantillons.poses(p, _planche))
	if _charge:
		_charger(p, delta)
	if _figer_dans >= 0 and _figer_rang == 0:
		_figer_dans -= 1
		if _figer_dans < 0:
			partie.en_pause = true
			_figer_rang = -1

## Tient le réservoir plein (pire cas) et mesure, par image, le coût de la mise à jour de la vue
## (appelée d'ici, chronométrée) et le nombre d'appels de dessin de l'image.
## D666_CHARGE=0 : même mesure sans remplir (le coût d'une partie ordinaire).
func _charger(p: Vector2, delta: float) -> void:
	var reservoir: Node2D = effets.particules
	if OS.get_environment("D666_CHARGE") != "0":
		reservoir.gerbe(p.x, p.y, reservoir.PLAFOND - reservoir.n, 400.0, 0.6, 3.0, PAL.slash, 0.0, TAU, 4.0, _images % 2 == 0)
	var debut := Time.get_ticks_usec()
	effets._process(delta)
	_maj_cumul += Time.get_ticks_usec() - debut
	_particules_cumul += reservoir.n
	if _images % 120 == 0:
		print("charge : %d particules en moyenne ; mise à jour de la vue %.0f µs par image ; %d appels de dessin pour toute l'image" % [_particules_cumul / 120, _maj_cumul / 120.0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
		_maj_cumul = 0
		_particules_cumul = 0

func _draw() -> void:
	var g = partie.game
	if g == null:
		return
	var salle: Dictionary = g.room
	draw_rect(Rect2(0, 0, salle.w, salle.h), PAL.wall)
	draw_rect(Rect2(salle.pad, salle.pad, salle.w - 2 * salle.pad, salle.h - 2 * salle.pad), PAL.floorA)
	for o in salle.obstacles:
		draw_rect(Rect2(o.x0, o.y0, o.x1 - o.x0, o.y1 - o.y0), PAL.pillarTop)
	for h in g.hazards:
		_telegraphe(h)
	for k in g.pickups:
		draw_circle(partie.position_dessin(k), k.r, PAL.gold if k.kind == "gold" else PAL.heal)
	for e in g.enemies:
		if D6Js.truthy(e.get("dead")):
			continue
		var c: Color = PAL.boss if D6Js.truthy(e.get("boss")) else PAL[GENRES.get(e.kind, "imp")]
		var pos: Vector2 = partie.position_dessin(e)
		draw_circle(pos, e.r + 2.0, PAL.enemyOutline)
		draw_circle(pos, e.r, PAL.enemyFlash if e.flash > 0.0 else c)
	for pr in g.projectiles:
		draw_circle(partie.position_dessin(pr), pr.r, PAL.lance if pr.owner == "player" else PAL.arrow)
	var p: Vector2 = partie.position_dessin(g.player, true)
	draw_circle(p, g.player.r, PAL.hero)
	draw_line(p, p + Vector2.from_angle(g.player.facing) * (g.player.r + 10.0), PAL.heroCape, 3.0)

func _telegraphe(h: Dictionary) -> void:
	if D6Js.truthy(h.get("done")):
		return
	if h.shape == "line":
		draw_set_transform(Vector2(h.x, h.y), h.angle)
		draw_rect(Rect2(0.0, -h.width * 0.5, h.length, h.width), PAL.dangerFill)
		draw_rect(Rect2(0.0, -h.width * 0.5, h.length, h.width), PAL.danger, false, 2.0)
		draw_set_transform(Vector2.ZERO)
	else:
		draw_circle(Vector2(h.x, h.y), h.r, PAL.dangerFill)
		draw_arc(Vector2(h.x, h.y), h.r, 0.0, TAU, 48, PAL.danger, 2.0)
