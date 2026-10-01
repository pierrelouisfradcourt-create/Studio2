extends CanvasLayer
## LA VILLE DE DITÉ — l'écran où l'on prépare sa descente, entre deux runs : Portail, Classe,
## Armurerie, Coffre, Grimoire, Sanctuaire, Labo du feel. Portage de GAMES/dungeon_666/src/ui/town.mjs.
##
## Elle ne contient AUCUNE règle : elle lit `app.profil` et `app.contenu`, et chaque bouton passe
## par une action de l'app (`operation_ville`, `demarrer_descente`, `demarrer_entrainement`,
## `regler_labo`, `ouvrir_titre`). Un refus s'affiche sur la carte concernée, sans rien changer.
## Tout ce qui s'achète ou se choisit ici est PERMANENT ; les bénédictions du donjon meurent avec
## le run.
##
## Visible quand `app.ecran == "ville"` ; se redessine sur `app.profil_change`.
## Clavier / manette : flèches ou croix = focus, Entrée / A = appuyer, Page préc. / suiv. ou
## gâchettes hautes = onglet voisin, stick droit = défiler, Échap / B = retour au titre.

const Style = preload("res://jeu/ville/style_ville.gd")
## Les onglets, dans l'ordre des boutons (Onglets) et des pages (Pages) de ville.tscn.
const ONGLETS := ["portail", "classe", "armurerie", "coffre", "grimoire", "sanctuaire", "labo"]
## En portrait, l'écran est mis en page comme s'il faisait cette largeur (sinon tout est minuscule).
const LARGEUR_PORTRAIT := 540.0
const DEFILEMENT_MANETTE := 900.0 # px de référence par seconde, stick droit à fond
const ZONE_MORTE := 0.25

## L'onglet affiché (un identifiant de ONGLETS).
var onglet := "portail"

var _app: Node
var _partie: Node
var _refus: Dictionary = {} # clé de carte -> raison du dernier refus (effacé à l'opération suivante)
var _sale := false

@onready var _racine: Control = $Racine
@onready var _fond: ColorRect = $Racine/Fond
@onready var _ames: Label = $Racine/Marges/Cadre/Colonne/Entete/Bourse/Ames
@onready var _or: Label = $Racine/Marges/Cadre/Colonne/Entete/Bourse/Or
@onready var _classe: Label = $Racine/Marges/Cadre/Colonne/Entete/Bourse/Classe
@onready var _retour: Button = $Racine/Marges/Cadre/Colonne/Entete/Retour
@onready var _onglets: HFlowContainer = $Racine/Marges/Cadre/Colonne/Onglets
@onready var _corps: ScrollContainer = $Racine/Marges/Cadre/Colonne/Corps
@onready var _pages: MarginContainer = $Racine/Marges/Cadre/Colonne/Corps/Pages
@onready var _garde: Control = $Racine/Garde
@onready var _armement: Timer = $Racine/Armement
@onready var _doigt: Node = $Racine/Doigt

func _ready() -> void:
	_racine.theme = Style.theme()
	_fond.color = Style.fond()
	visible = false
	set_process(false)
	for i in ONGLETS.size():
		_onglets.get_child(i).pressed.connect(ouvrir_onglet.bind(ONGLETS[i]))
		_pages.get_child(i).operation_demandee.connect(_sur_operation)
		_pages.get_child(i).dessin_demande.connect(_demander_dessin)
	_retour.pressed.connect(_sur_retour)
	_armement.timeout.connect(_lever_la_garde)
	get_viewport().size_changed.connect(_adapter)
	_adapter()

func brancher(app: Node, partie: Node) -> void:
	_app = app
	_partie = partie
	for page_n in _pages.get_children():
		page_n.brancher(app, partie)
	app.ecran_change.connect(_sur_ecran)
	app.profil_change.connect(_demander_dessin)
	_sur_ecran(app.ecran)

# ---------------------------------------------------------------- onglets

func ouvrir_onglet(id: String) -> void:
	if not (id in ONGLETS):
		return
	onglet = id
	_refus.clear()
	for i in ONGLETS.size():
		_onglets.get_child(i).set_pressed_no_signal(ONGLETS[i] == id)
		_pages.get_child(i).visible = ONGLETS[i] == id
	_corps.scroll_vertical = 0
	_dessiner()

## La page (scène d'onglet) d'identifiant `id`.
func page(id: String) -> Control:
	return _pages.get_child(ONGLETS.find(id))

func bouton_onglet(id: String) -> Button:
	return _onglets.get_child(ONGLETS.find(id))

func _onglet_voisin(pas: int) -> void:
	var i := posmod(ONGLETS.find(onglet) + pas, ONGLETS.size())
	ouvrir_onglet(ONGLETS[i])
	bouton_onglet(onglet).grab_focus()

# ---------------------------------------------------------------- dessin

func _sur_ecran(ecran: String) -> void:
	visible = ecran == "ville"
	set_process(visible)
	_doigt.actif = visible
	_adapter()
	if not visible:
		return
	_refus.clear()
	# Armement : l'écran ne répond qu'après un court délai (jamais d'appui « à l'aveugle » quand
	# on arrive de l'écran de mort en martelant).
	_garde.visible = true
	_armement.start()
	ouvrir_onglet(onglet)

func _lever_la_garde() -> void:
	_garde.visible = false

## Redessin demandé (profil changé, confirmation en attente) : une seule fois par image.
func _demander_dessin() -> void:
	if _sale or not visible:
		return
	_sale = true
	_dessiner.call_deferred()

func _dessiner() -> void:
	_sale = false
	if _app == null or not visible:
		return
	var cle := _cle_du_focus()
	var profil: Dictionary = _app.profil
	var classe = _app.contenu.classes.get(profil.loadout.classId)
	_ames.text = "◆ %s Âmes" % D6Js.num_str(profil.souls)
	_or.text = "● %s or" % D6Js.num_str(profil.gold)
	_classe.text = "%s · record étage %s" % [classe.name if classe is Dictionary else "?", D6Js.num_str(profil.bestFloor)]
	page(onglet).dessiner(_refus)
	_rendre_focus(cle)

## Clé de la carte qui tient le focus dans la page ("" : le focus n'est pas dans la page).
func _cle_du_focus() -> String:
	var tenu := get_viewport().gui_get_focus_owner()
	if tenu == null or not page(onglet).is_ancestor_of(tenu):
		return ""
	return String(tenu.get_meta("cle", "?"))

## Après un redessin (les cartes sont refaites), rend le focus au bouton de la même carte.
func _rendre_focus(cle: String) -> void:
	if cle == "":
		return
	var repli: Button = null
	for b in page(onglet).find_children("*", "Button", true, false):
		if String(b.get_meta("cle", "")) != cle:
			continue
		if not b.disabled:
			b.grab_focus()
			return
		repli = b
	(repli if repli != null else bouton_onglet(onglet)).grab_focus()

# ---------------------------------------------------------------- actions

func _sur_operation(cle: String, nom: String, args: Array) -> void:
	var res: Dictionary = _app.operation_ville(nom, args)
	_refus.clear()
	if not D6Js.truthy(res.get("ok")):
		_refus[cle] = String(D6Js.nz(res.get("reason"), "refusé"))
	_demander_dessin()

func _sur_retour() -> void:
	_app.ouvrir_titre()

# ---------------------------------------------------------------- clavier, manette, écran

func _input(ev: InputEvent) -> void:
	# Première touche ou premier bouton de manette : le focus apparaît (sur l'onglet actif).
	if not visible or get_viewport().gui_get_focus_owner() != null:
		return
	if (ev is InputEventKey or ev is InputEventJoypadButton) and ev.is_pressed():
		bouton_onglet(onglet).grab_focus()

func _unhandled_input(ev: InputEvent) -> void:
	if not visible:
		return
	if ev.is_action_pressed("ui_page_down") or _epaule(ev, JOY_BUTTON_RIGHT_SHOULDER):
		_onglet_voisin(1)
	elif ev.is_action_pressed("ui_page_up") or _epaule(ev, JOY_BUTTON_LEFT_SHOULDER):
		_onglet_voisin(-1)
	elif ev.is_action_pressed("ui_cancel"):
		_sur_retour()
	else:
		return
	get_viewport().set_input_as_handled()

func _epaule(ev: InputEvent, bouton_manette: JoyButton) -> bool:
	return ev is InputEventJoypadButton and ev.pressed and ev.button_index == bouton_manette

func _process(delta: float) -> void:
	var axe := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(axe) > ZONE_MORTE:
		_corps.scroll_vertical += int(axe * DEFILEMENT_MANETTE * delta)

## Paysage : la mise en page occupe l'écran tel quel. Portrait : la vue de référence (960 de
## large) rendrait tout minuscule ; on met en page sur LARGEUR_PORTRAIT et on agrandit d'autant.
func _adapter() -> void:
	var vue: Vector2 = _racine.get_viewport_rect().size
	var echelle := 1.0
	if vue.x < vue.y:
		echelle = maxf(1.0, vue.x / LARGEUR_PORTRAIT)
	_racine.scale = Vector2(echelle, echelle)
	_racine.position = Vector2.ZERO
	_racine.size = vue / echelle
	_nettete(echelle)

## Texte net malgré l'agrandissement du portrait : tant que la Ville est affichée et agrandie,
## les polices de la fenêtre sont tramées à l'échelle réelle. Rendu à l'automatique sinon.
func _nettete(echelle: float) -> void:
	var fenetre := get_viewport()
	var voulu := 0.0 # 0 = automatique
	if visible and echelle > 1.0:
		voulu = fenetre.get_stretch_transform().get_scale().x * echelle
	if not is_equal_approx(fenetre.oversampling_override, voulu):
		fenetre.oversampling_override = voulu # (renvoie size_changed : d'où la comparaison)
