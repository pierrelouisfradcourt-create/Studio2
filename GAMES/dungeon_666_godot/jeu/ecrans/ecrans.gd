extends CanvasLayer
## Les écrans posés par-dessus le jeu : titre, choix (bénédiction, butin, marchand, autel,
## chambre forte, fontaine), mort, victoire, pause, labo et réglages du feel.
## Portage de GAMES/dungeon_666/src/ui/menus.mjs (createUI, show, hide, sync) et de l'armement
## anti-martelage de src/ui/dom.mjs.
##
## Ce nœud choisit QUEL écran montrer d'après l'état (`app.ecran`, `partie.game.mode`,
## `partie.en_pause`), l'installe dans le panneau commun, garde son armement et son focus. Les
## écrans (une scène chacun) n'agissent que par deux signaux, `commande` et `action`, que ce
## nœud transmet à `app` : aucune règle de jeu ici, et rien n'écrit dans `partie.game`.

const Styles = preload("res://jeu/ecrans/styles.gd")
const Couleurs = preload("res://jeu/theme/couleurs.gd")
const Feel = preload("res://jeu/ecrans/feel.gd")
const Doigts = preload("res://jeu/ecrans/doigts.gd")
const SCENES := {
	"titre": preload("res://jeu/ecrans/titre.tscn"),
	"choix": preload("res://jeu/ecrans/choix.tscn"),
	"mort": preload("res://jeu/ecrans/mort.tscn"),
	"victoire": preload("res://jeu/ecrans/victoire.tscn"),
	"pause": preload("res://jeu/ecrans/pause.tscn"),
	"labo": preload("res://jeu/ecrans/labo.tscn"),
	"feel": preload("res://jeu/ecrans/reglages_feel.tscn"),
}
## Un panneau ne répond qu'après ce délai : jamais de choix « à l'aveugle » (ARM_MS du web).
const ARMEMENT_MS := 350.0
## Panneaux de choix : plus long, et chaque appui reçu pendant l'armement le relance. Un dash
## martelé à 3-4 Hz qui ouvre le panneau ne choisit donc rien (ARM_CHOICE_MS).
const ARMEMENT_CHOIX_MS := 600.0
const SANS_DELAI := ["titre", "pause", "labo", "feel"]
const DOUBLE_TIR_MS := 300.0 # un toucher suivi de son clic émulé ne tire qu'une fois (REFIRE_MS)
const OPACITE_DESARME := 0.5
const MARGE := 16.0
const LARGEUR := 760.0
const VOILE := 0.45
const ECHELLE_MAX := 2.0
const DENSITE_ANDROID := 160.0
const IMAGES_DE_POSE := 2 # images laissées à la mise en page avant de montrer un panneau
const NAVIGATION := ["ui_up", "ui_down", "ui_left", "ui_right", "ui_focus_next", "ui_focus_prev", "ui_accept"]

@onready var _racine: Control = %Racine
@onready var _fond_titre: TextureRect = %FondTitre
@onready var _voile: ColorRect = %Voile
@onready var _marge: MarginContainer = %Marge
@onready var _panneau: PanelContainer = %Panneau
@onready var _defilement: ScrollContainer = %Defilement
@onready var _contenu: MarginContainer = %Contenu

var _app: Node
var _partie: Node
var _ecran: Control = null
var _cle := ""
var _nom := ""
var _sous_ecran := "" # « labo » ou « feel », ouverts depuis la pause
var _sans_delai := true
var _delai := ARMEMENT_MS
var _desarme_jusqu := 0.0
var _images := 0
var _feel := Feel.new()
var _doigts := Doigts.new()
var _tir_au_doigt := false
var _dernier_tir := -1e9
var _dernier_tir_au_doigt := false

func _ready() -> void:
	_racine.theme = Styles.theme()
	_voile.color = Color(Couleurs.UI["void"], VOILE)
	_fond_titre.texture = _lueur_du_titre()
	get_viewport().size_changed.connect(_disposer)
	_disposer()

func brancher(app: Node, partie: Node) -> void:
	_app = app
	_partie = partie
	partie.partie_demarree.connect(_sur_partie)
	app.reglages_change.connect(_sur_reglages)
	var entrees = _vue("entrees")
	if entrees != null and entrees.has_signal("pause_demandee"):
		entrees.pause_demandee.connect(basculer_pause)
	if partie.game != null:
		_feel.nouvelle_partie(partie.game.tuning)
	_synchroniser()

# ---------------------------------------------------------------- ce que la vue expose

## Nom de l'écran montré (« titre », « choix », « mort », « victoire », « pause », « labo »,
## « feel »), ou "" si le jeu est à nu.
func ecran_montre() -> String:
	return _nom

## La scène de l'écran montré (null si aucun) : pour les essais.
func ecran() -> Control:
	return _ecran

## Vrai quand le panneau répond (armement écoulé).
func pret() -> bool:
	return _sans_delai or Time.get_ticks_msec() >= _desarme_jusqu

## Pause ↔ jeu ; depuis le labo ou les réglages, revient à la pause.
func basculer_pause() -> void:
	if _app == null or _app.ecran != "jeu" or _partie.game == null:
		return
	if _sous_ecran != "":
		_sous_ecran = ""
	else:
		_app.mettre_en_pause(not _partie.en_pause)
	_synchroniser()

# ---------------------------------------------------------------- quel écran

func _process(_delta: float) -> void:
	if _app == null:
		return
	_synchroniser()
	if _ecran == null:
		return
	_images += 1
	_ajuster()
	_panneau.modulate.a = 1.0 if _images > IMAGES_DE_POSE else 0.0
	_contenu.modulate.a = 1.0 if pret() else OPACITE_DESARME

## La clé de l'écran voulu : quand elle change, l'écran est reconstruit ("" : aucun).
func _cle_voulue() -> String:
	if _app.ecran == "titre":
		return "titre:%s:%s" % [_app.profil.get("bestFloor"), _app.profil.get("checkpoints")]
	var g = _partie.game
	if _app.ecran != "jeu" or g == null:
		return ""
	if _partie.en_pause:
		return _sous_ecran if _sous_ecran != "" else "pause"
	_sous_ecran = ""
	if g.mode == "choice" and g.get("choice") is Dictionary:
		var ch: Dictionary = g.choice
		if ch.kind != "shop":
			return "choix:%s:%s" % [ch.kind, g.tick]
		var vendus: Array = ch.offers.map(func(o): return D6Js.truthy(o.get("sold")))
		return "choix:shop:%s:%s" % [ch.gold, vendus]
	if g.mode == "dead":
		return "mort:%s" % g.tick
	if g.mode == "victory":
		return "victoire"
	return ""

func _synchroniser() -> void:
	var cle := _cle_voulue()
	if cle == _cle:
		return
	if cle == "":
		_cacher()
	else:
		_montrer(cle)

func _montrer(cle: String) -> void:
	var nom := cle.get_slice(":", 0)
	# Le marchand qui se rafraîchit après un achat répond tout de suite et garde son focus.
	var rafraichi := cle.begins_with("choix:shop") and _cle.begins_with("choix:shop")
	var rang := _boutons(true).find(get_viewport().gui_get_focus_owner()) if rafraichi else -1
	_retirer()
	_cle = cle
	_nom = nom
	_ecran = SCENES[nom].instantiate()
	if "etat" in _ecran:
		_ecran.etat = _feel
	_contenu.add_child(_ecran)
	_ecran.commande.connect(_sur_commande)
	_ecran.action.connect(_sur_action)
	_ecran.ouvrir(_app, _partie)
	_racine.visible = true
	_fond_titre.visible = nom == "titre"
	_voile.color.a = 0.0 if nom == "titre" else VOILE
	_panneau.theme_type_variation = &"PanneauNu" if nom == "titre" else &"PanneauEcran"
	_images = 0
	_panneau.modulate.a = 0.0
	_sans_delai = nom in SANS_DELAI or rafraichi
	_delai = ARMEMENT_CHOIX_MS if nom == "choix" else ARMEMENT_MS
	_armer()
	_vider_entrees()
	if not _tactile():
		_focaliser(rang)

func _cacher() -> void:
	_retirer()
	_cle = ""
	_nom = ""
	_racine.visible = false
	_vider_entrees()

func _retirer() -> void:
	_doigts.oublier()
	if _ecran == null:
		return
	_contenu.remove_child(_ecran)
	_ecran.queue_free()
	_ecran = null
	_defilement.scroll_vertical = 0

# ---------------------------------------------------------------- ce que demandent les écrans

## Refuse un choix fait pendant l'armement, et le doublon d'un même geste (un toucher et son
## clic émulé, dans un ordre ou dans l'autre). Un choix accepté fait entendre le clic de menu.
func _accepter() -> bool:
	if not pret():
		return false
	var t := float(Time.get_ticks_msec())
	if _tir_au_doigt != _dernier_tir_au_doigt and t - _dernier_tir < DOUBLE_TIR_MS:
		return false
	_dernier_tir = t
	_dernier_tir_au_doigt = _tir_au_doigt
	var son = _vue("son")
	if son != null and son.has_method("jouer"):
		son.jouer("clic")
	return true

func _sur_commande(cmd: Dictionary) -> void:
	if not _accepter():
		return
	_app.commande(cmd)
	_synchroniser()

func _sur_action(nom: String, args: Array) -> void:
	if not _accepter():
		return
	match nom:
		"ville": _app.ouvrir_ville()
		"descendre": _app.demarrer_descente(args[0])
		"arene": _app.demarrer_descente(1.0, true)
		"reprendre": _app.mettre_en_pause(false)
		"regler": _app.regler(args[0], args[1])
		"regler_labo": _app.regler_labo(args[0], args[1])
		"abandonner": _app.abandonner()
		"labo", "feel": _sous_ecran = nom
		"retour": _sous_ecran = ""
	_synchroniser()

func _sur_partie() -> void:
	_sous_ecran = ""
	_feel.nouvelle_partie(_partie.game.tuning)

func _sur_reglages() -> void:
	if _ecran != null and _ecran.has_method("rafraichir"):
		_ecran.rafraichir()

# ---------------------------------------------------------------- armement, doigts, focus

func _armer() -> void:
	_desarme_jusqu = Time.get_ticks_msec() + _delai

func _input(ev: InputEvent) -> void:
	if _app == null:
		return
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_ESCAPE and _vue("entrees") == null:
		basculer_pause() # sans la vue Entrees (banc), Échap reste la touche de pause
	if _ecran == null:
		return
	# Anti-martelage : tout appui pendant l'armement le prolonge.
	if _est_appui(ev) and not pret():
		_armer()
	if ev is InputEventScreenTouch and not _souris_emulee(ev.index):
		_sur_doigt(ev)
	elif ev is InputEventScreenDrag and not _souris_emulee(ev.index):
		_doigts.glisser(ev.index, ev.position, ev.relative / _racine.scale.y)
	elif ev is InputEventJoypadButton and ev.pressed and ev.button_index == JOY_BUTTON_B and _partie.en_pause:
		basculer_pause()
	elif _demande_le_focus(ev):
		_focaliser(-1)
		get_viewport().set_input_as_handled()

func _est_appui(ev: InputEvent) -> bool:
	if ev is InputEventMouseButton or ev is InputEventScreenTouch or ev is InputEventJoypadButton:
		return ev.pressed
	return ev is InputEventKey and ev.pressed and not ev.echo

## Le premier doigt est converti en souris par le projet : les Button l'entendent seuls. Les
## doigts suivants (le pouce gauche est resté sur le joystick) passent par jeu/ecrans/doigts.gd.
func _souris_emulee(index: int) -> bool:
	return index == 0 and Input.emulate_mouse_from_touch

func _sur_doigt(ev: InputEventScreenTouch) -> void:
	if ev.pressed:
		_doigts.appuyer(_racine, _defilement, ev.index, ev.position)
		return
	var b := _doigts.relacher(ev.index, ev.position, ev.canceled)
	if b == null:
		return
	_tir_au_doigt = true
	b.pressed.emit()
	_tir_au_doigt = false

## Une touche de navigation alors que rien n'a le focus (écran tactile, clic dans le vide).
func _demande_le_focus(ev: InputEvent) -> bool:
	if not (ev is InputEventKey or ev is InputEventJoypadButton or ev is InputEventJoypadMotion):
		return false
	var tenu: Control = get_viewport().gui_get_focus_owner()
	if tenu != null and _racine.is_ancestor_of(tenu):
		return false
	return NAVIGATION.any(func(a: String) -> bool: return ev.is_action_pressed(a))

## Les boutons de l'écran, dans l'ordre ; `tous` : y compris les grisés.
func _boutons(tous: bool = false) -> Array:
	if _ecran == null:
		return []
	return _ecran.find_children("*", "BaseButton", true, false).filter(func(b: BaseButton) -> bool:
		return b.is_visible_in_tree() and (tous or (not b.disabled and b.focus_mode != Control.FOCUS_NONE)))

## Focus sur le bouton de rang `rang` (parmi tous) s'il est actif ; sinon sur celui que l'écran
## désigne, sinon sur le premier bouton actif.
func _focaliser(rang: int) -> void:
	var actifs := _boutons()
	var tous := _boutons(true)
	var cible: Control = null
	if rang >= 0 and rang < tous.size() and tous[rang] in actifs:
		cible = tous[rang]
	elif rang >= 0 and not actifs.is_empty():
		cible = actifs[actifs.size() - 1]
	elif _ecran != null and _ecran.has_method("premier_focus"):
		cible = _ecran.premier_focus()
	if cible == null and not actifs.is_empty():
		cible = actifs[0]
	if cible != null:
		cible.grab_focus()

func _tactile() -> bool:
	var entrees = _vue("entrees")
	if entrees != null and entrees.has_method("tactile"):
		return entrees.tactile()
	return DisplayServer.is_touchscreen_available()

func _vue(nom: String):
	var vues = _app.get("vues") if _app != null else null
	return vues.get(nom) if vues is Dictionary else null

func _vider_entrees() -> void:
	var entrees = _vue("entrees")
	if entrees != null and entrees.has_method("vider"):
		entrees.vider()

# ---------------------------------------------------------------- mise en page

## Le panneau prend la largeur de son écran (bornée par la place) et la hauteur de son contenu ;
## au-delà de la place, il défile.
func _ajuster() -> void:
	var place := _racine.size
	place.x -= _marge.get_theme_constant("margin_left") + _marge.get_theme_constant("margin_right")
	place.y -= _marge.get_theme_constant("margin_top") + _marge.get_theme_constant("margin_bottom")
	var largeur: float = _ecran.largeur() if _ecran.has_method("largeur") else LARGEUR
	_panneau.custom_minimum_size.x = minf(largeur, place.x)
	_defilement.custom_minimum_size.y = minf(_contenu.get_combined_minimum_size().y, place.y)

## Les panneaux gardent la taille du web (px CSS) : sur un écran étroit ou dense, la racine est
## agrandie plutôt que de laisser l'étirement du projet rétrécir les textes.
func _disposer() -> void:
	var vue := get_viewport().get_visible_rect().size
	var k := _echelle(vue)
	_racine.scale = Vector2(k, k)
	_racine.position = Vector2.ZERO
	_racine.size = vue / k
	var sures := _marges_sures(vue)
	for cote in sures:
		_marge.add_theme_constant_override("margin_" + cote, int(maxf(MARGE, sures[cote] / k)))

func _echelle(vue: Vector2) -> float:
	var fenetre := get_window().size
	if fenetre.x <= 0:
		return 1.0
	var densite := DisplayServer.screen_get_scale()
	if OS.has_feature("android"):
		densite = DisplayServer.screen_get_dpi() / DENSITE_ANDROID
	return clampf(vue.x / float(fenetre.x) * maxf(1.0, densite), 1.0, ECHELLE_MAX)

## Marges de la zone sûre (encoche, barre de gestes) en unités d'écran ; nulles hors téléphone.
func _marges_sures(vue: Vector2) -> Dictionary:
	var marges := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	var fenetre := get_window().size
	if not OS.has_feature("mobile") or fenetre.x <= 0:
		return marges
	var sure := DisplayServer.get_display_safe_area()
	var k := vue.x / float(fenetre.x)
	marges.left = maxf(0.0, sure.position.x) * k
	marges.top = maxf(0.0, sure.position.y) * k
	marges.right = maxf(0.0, fenetre.x - sure.end.x) * k
	marges.bottom = maxf(0.0, fenetre.y - sure.end.y) * k
	return marges

## Le fond de l'écran titre : une lueur de braise qui monte du bas (dessinée, aucun fichier).
func _lueur_du_titre() -> GradientTexture2D:
	var ui: Dictionary = Couleurs.UI
	var degrade := Gradient.new()
	degrade.set_color(0, ui.ember.darkened(0.7))
	degrade.set_color(1, ui["void"])
	var texture := GradientTexture2D.new()
	texture.gradient = degrade
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 1.15)
	texture.fill_to = Vector2(0.5, 0.1)
	return texture
