extends CanvasLayer
## Le HUD : tout ce que le joueur lit pendant le combat (vie, étage, or, Âmes, Gardien,
## bannières, bénédictions) et le DESSIN des commandes (tactiles ou rangée du bureau).
## Visible seulement quand `app.ecran == "jeu"` et qu'une partie existe.
##
## Ce nœud ne fait que LIRE `partie.game` et répartir : chaque élément a son script sous
## jeu/interface/. Sa seule action : le bouton pause → `app.mettre_en_pause(true)`.
## Référence : GAMES/dungeon_666/src/render/hud.mjs.

const Couleurs = preload("res://jeu/theme/couleurs.gd")
const ThemeJeu = preload("res://jeu/theme/theme.gd")
const Disposition = preload("res://jeu/interface/disposition.gd")
const Etats = preload("res://jeu/interface/etat_commandes.gd")
const Degrades = preload("res://jeu/interface/degrades.gd")

const BORD := 14 # marge entre le HUD et le bord (en plus de la zone sûre)
const BANDE := 96.0 # hauteur de la bande sombre du haut
const BANDE_UTILE := 6.0 # marge sous le bloc central du haut (flèches hors champ)
const VIE_LARGEUR := Vector2(90.0, 200.0) # mini, maxi
const VIE_PART := 0.26 # part de la largeur d'écran
const VIE_BASSE := 0.3

var app
var partie
## Banc d'essai : présentation tactile sans vue Entrees (disposition de repli).
var forcer_tactile := false

var _marges := Vector4.ZERO # zone sûre : gauche, haut, droite, bas (px du viewport)
var _encoche_forcee := false
var _gras: Font

@onready var racine: Control = $Racine
@onready var bande: TextureRect = $Racine/BandeHaute
@onready var danger: TextureRect = $Racine/Danger
@onready var fleches: Control = $Racine/Fleches
@onready var marges: MarginContainer = $Racine/Marges
@onready var centre: VBoxContainer = $Racine/Marges/Zone/Centre
@onready var vie: Control = %Vie
@onready var vie_nombre: Label = %VieNombre
@onready var benedictions: Control = %Benedictions
@onready var etage: Label = %Etage
@onready var fil: Control = %Fil
@onready var cercle: Label = %Cercle
@onready var gardien: VBoxContainer = %Gardien
@onready var or_montant: Label = %OrMontant
@onready var or_piece: Control = %OrPiece
@onready var ames: HBoxContainer = %Ames
@onready var ames_gemme: Control = %AmesGemme
@onready var ames_montant: Label = %AmesMontant
@onready var pause: Button = %Pause
@onready var banniere: VBoxContainer = %Banniere
@onready var indice: Label = %Indice
@onready var bureau: HBoxContainer = %Bureau
@onready var commandes_bureau: Array = [%CmdAttaque, %CmdDash, %CmdCompetence, %CmdGadget, %CmdSuper]
@onready var tactile: Control = $Racine/Tactile

func _ready() -> void:
	racine.theme = ThemeJeu.theme()
	bande.texture = Degrades.bande()
	_habiller()
	_ignorer_souris(racine)
	pause.pressed.connect(_sur_pause)
	get_viewport().size_changed.connect(_poser_marges)
	_poser_marges()
	visible = false

## Seul point d'entrée de la vue (voir jeu/ARCHITECTURE.md).
func brancher(app_: Node, partie_: Node) -> void:
	app = app_
	partie = partie_
	banniere.brancher(partie)
	danger.brancher(partie)
	partie.partie_demarree.connect(_sur_demarrage)

func _sur_demarrage() -> void:
	vie.reinitialiser()

func _sur_pause() -> void:
	if app != null:
		app.mettre_en_pause(true)

func _process(_delta: float) -> void:
	var game = partie.game if partie != null else null
	visible = game != null and app != null and app.ecran == "jeu" and game.get("info") != null
	if not visible:
		return
	var au_doigt := _tactile()
	_actualiser_vie(game)
	_actualiser_centre(game)
	_actualiser_bourse(game)
	_actualiser_commandes(game, au_doigt)
	_actualiser_reperes(game, au_doigt)

# ---------------------------------------------------------------- habillage et marges

## Polices et couleurs des textes : palette par rôle, contour sombre (lisible sur tout fond).
func _habiller() -> void:
	var pal: Dictionary = Couleurs.PAL
	_gras = ThemeJeu.police_corps()
	(_gras as SystemFont).font_weight = 800
	_ecrire(vie_nombre, 12, pal.text)
	vie_nombre.add_theme_constant_override("outline_size", 5)
	_ecrire(etage, 18, pal.text)
	_ecrire(cercle, 13, pal.textDim)
	_ecrire(gardien.nom, 13, pal.bossTrim)
	_ecrire(or_montant, 18, pal.gold)
	_ecrire(ames_montant, 14, pal.lance)
	_ecrire(indice, 15, pal.text)
	# Bannière dans la police du corps, graissée : la police d'apparat a des chiffres qui descendent
	# sous la ligne (« ÉTAGE 7 » se lisait de travers).
	_ecrire(banniere.titre, 30, pal.text)
	_ecrire(banniere.sous, 14, pal.textDim)
	for touche in bureau.find_children("Touche", "Label"):
		_ecrire(touche, 12, pal.textDim)
	or_piece.couleur = pal.gold
	ames_gemme.couleur = pal.lance

func _ecrire(texte: Label, taille: int, couleur: Color, police: Font = null) -> void:
	texte.add_theme_font_override("font", police if police != null else _gras)
	texte.add_theme_font_size_override("font_size", taille)
	texte.add_theme_color_override("font_color", couleur)
	texte.add_theme_color_override("font_outline_color", Color(Couleurs.UI["void"], 0.85))
	texte.add_theme_constant_override("outline_size", maxi(3, taille / 4))

## Le HUD ne prend aucun clic ni toucher (ils vont à la vue Entrees), sauf le bouton pause.
func _ignorer_souris(n: Node) -> void:
	if n is Control and not n is BaseButton:
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for enfant in n.get_children():
		_ignorer_souris(enfant)

## Banc d'essai : impose une encoche (gauche, haut, droite, bas), en pixels du viewport.
func poser_encoche(encoche: Vector4) -> void:
	_encoche_forcee = true
	_marges = encoche
	_appliquer_marges()

func _poser_marges() -> void:
	if not _encoche_forcee:
		_marges = _zone_sure()
	_appliquer_marges()

## Encoche et bords arrondis des téléphones, convertis en pixels du viewport.
func _zone_sure() -> Vector4:
	if not OS.has_feature("mobile"):
		return Vector4.ZERO
	var fenetre := Vector2(DisplayServer.window_get_size())
	var sure := Rect2(DisplayServer.get_display_safe_area())
	if fenetre.x <= 0.0 or fenetre.y <= 0.0 or sure.size.x <= 0.0:
		return Vector4.ZERO
	var k := racine.get_viewport_rect().size / fenetre
	var fin := fenetre - sure.end
	return Vector4(maxf(0.0, sure.position.x) * k.x, maxf(0.0, sure.position.y) * k.y, maxf(0.0, fin.x) * k.x, maxf(0.0, fin.y) * k.y)

func _appliquer_marges() -> void:
	marges.add_theme_constant_override("margin_left", BORD + int(_marges.x))
	marges.add_theme_constant_override("margin_top", BORD + int(_marges.y))
	marges.add_theme_constant_override("margin_right", BORD + int(_marges.z))
	marges.add_theme_constant_override("margin_bottom", BORD + int(_marges.w))
	bande.offset_bottom = BANDE + _marges.y

# ---------------------------------------------------------------- lecture de la partie

func _actualiser_vie(game: Dictionary) -> void:
	var p: Dictionary = game.player
	var part: float = p.hp / p.maxHp
	vie.custom_minimum_size.x = clampf(racine.size.x * VIE_PART, VIE_LARGEUR.x, VIE_LARGEUR.y)
	vie.poser(part, Couleurs.PAL.danger if part < VIE_BASSE else Couleurs.PAL.hpBar)
	vie_nombre.text = "%s / %s" % [D6Js.num_str(ceilf(p.hp)), D6Js.num_str(roundf(p.maxHp))]
	benedictions.poser(game.run.boons)

func _actualiser_centre(game: Dictionary) -> void:
	var info: Dictionary = game.info
	if D6Js.truthy(game.get("sandbox")):
		etage.text = "ARÈNE D'ESSAI"
		cercle.text = "%s démons · %s esquives parfaites" % [D6Js.num_str(game.telemetry.kills), D6Js.num_str(game.telemetry.dodges)]
		cercle.visible = true
		fil.visible = false
		gardien.visible = false
		etage.add_theme_color_override("font_color", Couleurs.PAL.text)
		return
	var sur_gardien := D6Js.truthy(info.isBoss)
	etage.text = "ÉTAGE %s / %s" % [D6Js.num_str(info.floor), D6Js.num_str(game.tuning.floors.total)]
	etage.add_theme_color_override("font_color", Couleurs.PAL.danger if sur_gardien else Couleurs.PAL.text)
	var combat: bool = gardien.actualiser(game, racine.size.x)
	fil.visible = not combat
	cercle.visible = not combat
	fil.poser(info.indexInSection, game.tuning.floors.sectionLength)
	cercle.text = String(info.circleName)

func _actualiser_bourse(game: Dictionary) -> void:
	or_montant.text = D6Js.num_str(game.run.gold)
	# Âmes (permanentes) : on les voit monter pendant la descente, pas en arène ni à l'entraînement.
	ames.visible = not D6Js.truthy(game.get("sandbox")) and not D6Js.truthy(game.get("practice"))
	ames_montant.text = D6Js.num_str(game.meta.souls)

func _actualiser_commandes(game: Dictionary, au_doigt: bool) -> void:
	bureau.visible = not au_doigt
	tactile.visible = au_doigt
	if au_doigt:
		tactile.actualiser(game, _interface_tactile())
		return
	for c in commandes_bureau:
		c.montrer(Etats.etat(game, c.id))

func _actualiser_reperes(game: Dictionary, au_doigt: bool) -> void:
	var room: Dictionary = game.room
	var objet = room.get("interact")
	var objet_libre: bool = objet is Dictionary and not D6Js.truthy(objet.get("used"))
	indice.visible = D6Js.truthy(room.get("cleared")) and not objet_libre and _porte_ouverte(room)
	var monde = app.vues.get("monde") if app.vues is Dictionary else null
	var haut := centre.get_global_rect().end.y + BANDE_UTILE
	fleches.actualiser(game, monde, haut, _marges, tactile.coin() if au_doigt else racine.size)

func _porte_ouverte(room: Dictionary) -> bool:
	for porte in room.get("doors", []):
		if D6Js.truthy(porte.get("open")):
			return true
	return false

# ---------------------------------------------------------------- présentation tactile

func _entrees():
	return app.vues.get("entrees") if app != null and app.vues is Dictionary else null

func _tactile() -> bool:
	if forcer_tactile:
		return true
	var entrees = _entrees()
	if entrees != null and entrees.has_method("tactile"):
		return entrees.tactile()
	return entrees == null and OS.has_feature("mobile")

## Disposition donnée par la vue Entrees ; sans elle, celle de repli (identique à input.mjs).
func _interface_tactile() -> Dictionary:
	var entrees = _entrees()
	if entrees != null and entrees.has_method("interface_tactile"):
		var ui = entrees.interface_tactile()
		if ui is Dictionary and ui.get("buttons") is Array and not ui.buttons.is_empty():
			return ui
	return Disposition.calculer(racine.size, _marges)
