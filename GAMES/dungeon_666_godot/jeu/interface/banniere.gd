extends VBoxContainer
## Les bannières : « ÉTAGE n », « SALLE NETTOYÉE », « LE GARDIEN S'ENRAGE », « GARDIEN VAINCU »…
## Elles apparaissent en fondu puis s'effacent. Écoute `partie.evenements` ; portage de
## `setBanner` (src/render/fx.mjs) et de `drawBanner` (src/render/hud.mjs).

const Couleurs = preload("res://jeu/theme/couleurs.gd")
const ENTREE := 0.15 # part de la durée passée à apparaître
const SORTIE := 0.4 # s de fondu final
const COUPE := 0.3 # s restantes quand le combat démarre (bannière d'entrée d'étage)
const OPACITE := 0.95
const ELAN := 0.12 # la bannière arrive un peu plus grande, puis se pose

@onready var titre: Label = $Titre
@onready var sous: Label = $Sous
@onready var filet: Control = $Filet

var _partie
var _vie := 0.0
var _duree := 1.0
var _jusqu_au_combat := false

func _ready() -> void:
	visible = false

func brancher(partie) -> void:
	_partie = partie
	partie.evenements.connect(_sur_evenements)

func afficher(texte: String, detail: String, couleur: Color, duree: float = 2.2, jusqu_au_combat: bool = false) -> void:
	titre.text = texte
	titre.add_theme_color_override("font_color", couleur)
	filet.couleur = couleur
	sous.text = detail
	sous.visible = detail != ""
	_vie = duree
	_duree = duree
	_jusqu_au_combat = jusqu_au_combat

func _sur_evenements(liste: Array) -> void:
	var pal: Dictionary = Couleurs.PAL
	for ev in liste:
		match ev.type:
			"floorEnter":
				var gardien := D6Js.truthy(ev.get("isBoss"))
				var ou := "Gardien de la section" if gardien else "%s · section %s" % [ev.circleName, D6Js.num_str(ev.section)]
				afficher("ÉTAGE %s" % D6Js.num_str(ev.floor), ou, pal.danger if gardien else pal.text, 1.2, true)
			"roomClear":
				var vaincu := D6Js.truthy(ev.get("boss"))
				afficher("GARDIEN VAINCU" if vaincu else "SALLE NETTOYÉE", "Un checkpoint s'éveille" if vaincu else "", pal.gold if vaincu else pal.text, 1.6)
			"bossPhase":
				afficher("LE GARDIEN S'ENRAGE", "", pal.danger, 1.4)
			"checkpoint":
				afficher("GARDIEN VAINCU", _detail_checkpoint(ev), pal.gold, 2.4)

func _detail_checkpoint(ev: Dictionary) -> String:
	if D6Js.truthy(ev.get("practice")):
		return "Entraînement terminé"
	var texte := "Checkpoint : étage %s" % D6Js.num_str(ev.floor)
	if float(ev.get("souls", 0.0)) > 0.0:
		texte += " · + %s Âmes" % D6Js.num_str(ev.souls)
	return texte

func _process(delta: float) -> void:
	var game = _partie.game if _partie != null else null
	if _vie <= 0.0 or game == null:
		_vie = 0.0
		visible = false
		return
	if _jusqu_au_combat and _combat_engage(game):
		_vie = minf(_vie, COUPE)
	_vie -= delta
	var t := 1.0 - _vie / _duree
	var a := t / ENTREE if t < ENTREE else (_vie / SORTIE if _vie < SORTIE else 1.0)
	modulate.a = clampf(a, 0.0, 1.0) * OPACITE
	pivot_offset = size / 2.0
	scale = Vector2.ONE * (1.0 + ELAN * (1.0 - clampf(t / ENTREE, 0.0, 1.0)))
	visible = _vie > 0.0 and game.mode != "choice"

func _combat_engage(game: Dictionary) -> bool:
	for e in game.enemies:
		if not D6Js.truthy(e.get("dead")) and not float(e.get("spawnT", 0.0)) > 0.0:
			return true
	return false
