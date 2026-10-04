extends Node2D
## Banc des CRÉATURES : le calque `Entites` seul, sur fond uni, devant une vraie Partie.
##   D666_ETAGE, D666_GRAINE      étage et graine de la partie (18, 36, 54, 72 : un Gardien)
##   D666_CLASSE, D666_ARME       kit du héros (revenant | bourreau | chasseresse ; lame, dagues, hache…)
##   D666_ZOOM                    zoom de la caméra (défaut 1,5 en combat, 1 sur une planche)
##   D666_DECALAGE="dx,dy"        décale la caméra (unités de monde) : regarder un rang de près
##   D666_DIEU=1                  le héros ne prend aucun dégât (pour tenir devant un Gardien)
##   D666_PLANCHE=1               planche : les 10 archétypes, les 6 élites, les 4 Gardiens, immobiles
##   D666_PLANCHE=2               planche des ÉTATS : statuts, attaques armées, pouvoirs d'élite, Gardiens
##   D666_PLANCHE=3               planche des trois nouveaux : pavois, traqueur, étendard et ses protégés
##   D666_PLANCHE=4 D666_POSE=…   une pose du héros (coup:active:0.5:2, frappe, dash, touche, elan, lancer,
##                                colere, sentence, nuee : voir banc_planches.gd), avec D666_CLASSE / D666_ARME
##   D666_PLANCHE=9               foule de 40 ennemis, pour jeu/monde/mesure.gd
## Capture : outils/capture.gd -- res://jeu/monde/creatures/banc.tscn <sortie.png> [images] [pilote]

const Partie = preload("res://jeu/partie.gd")
const Planches = preload("res://jeu/monde/creatures/banc_planches.gd")
const Pinceau = preload("res://jeu/monde/creatures/pinceau.gd")
const Couleurs = preload("res://jeu/theme/couleurs.gd")

## La Partie du banc (lue par outils/capture.gd pour le pilote).
var partie: Node
## Vues voisines, au sens de `app.vues` : aucune ici.
var vues := {}

var _legendes: Array = [] # [{pos: Vector2, texte: String}]
var _pinceau: Pinceau

@onready var entites: Node2D = $Entites
@onready var camera: Camera2D = $Camera

func _ready() -> void:
	_pinceau = Pinceau.new(self)
	partie = Partie.new()
	partie.name = "Partie"
	add_child(partie)
	move_child(partie, 0)
	var planche := _env("D666_PLANCHE", "0").to_int()
	partie.demarrer(_options())
	entites.brancher(self, partie)
	if planche > 0:
		partie.en_pause = true
		_legendes = Planches.composer(partie.game, planche)
	var zoom := _env("D666_ZOOM", ("0.8" if planche <= 3 else "1.0") if planche > 0 else "1.5").to_float()
	camera.zoom = Vector2(zoom, zoom)
	_cadrer(planche > 0)

static func _env(nom: String, defaut: String) -> String:
	var v := OS.get_environment(nom)
	return defaut if v == "" else v

func _options() -> Dictionary:
	var options := {
		"seed": _env("D666_GRAINE", "7").to_float(),
		"startFloor": _env("D666_ETAGE", "1").to_float(),
		"godMode": _env("D666_DIEU", "0") == "1",
	}
	var classe := _env("D666_CLASSE", "")
	if classe != "":
		options["meta"] = _profil_kit(D6Data.create_tuning(null), classe, _env("D666_ARME", ""))
	return options

## Profil permanent d'un kit : tout débloqué, la classe et l'arme demandées (kitProfile de tools/classes.mjs).
static func _profil_kit(tuning: Dictionary, classe: String, arme: String) -> Dictionary:
	var m: Dictionary = D6Profile.create_profile(tuning)
	for k in ["classes", "weapons", "skills", "gadgets"]:
		m.unlocked[k] = tuning[k].keys()
	var c: Dictionary = tuning.classes[classe]
	m.loadout = {"classId": classe, "slots": [c.skills[0], c.gadgets[0], null]}
	m.equipment.arme = D6Profile.starter_weapon(tuning, c.weapons[0] if arme == "" else arme)
	m.equipment.arme.uid = "i9000"
	return m

func _process(_delta: float) -> void:
	var g = partie.game
	if g == null:
		return
	if g.mode == "choice":
		for cmd in [{"type": "choose", "index": 0.0}, {"type": "equip"}, {"type": "close"}]:
			if partie.commande(cmd):
				break
	elif g.mode == "dead":
		partie.commande({"type": "respawn", "floor": D6Run.last_checkpoint(g)})
	_cadrer(partie.en_pause)
	queue_redraw()

func _cadrer(planche: bool) -> void:
	var g = partie.game
	if g == null:
		return
	var decalage := _env("D666_DECALAGE", "0,0").split_floats(",")
	var centre: Vector2 = Vector2(g.room.w, g.room.h) * 0.5 if planche else partie.position_dessin(g.player, true)
	camera.position = centre + Vector2(decalage[0], decalage[1])

## Repères du banc : le bord de la salle, ses obstacles, et les légendes d'une planche.
func _draw() -> void:
	var g = partie.game
	if g == null:
		return
	var room: Dictionary = g.room
	if _legendes.is_empty():
		draw_rect(Rect2(room.pad, room.pad, room.w - 2.0 * room.pad, room.h - 2.0 * room.pad), Color("#3b252d"), false, 2.0)
		for o in room.obstacles:
			draw_rect(Rect2(o.x0, o.y0, o.x1 - o.x0, o.y1 - o.y0), Color("#2a1a20"))
	for l in _legendes:
		_pinceau.texte(l.pos, l.texte, 10, Couleurs.PAL.textDim)
