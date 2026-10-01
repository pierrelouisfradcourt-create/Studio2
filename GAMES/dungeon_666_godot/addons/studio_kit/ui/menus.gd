class_name StudioMenus
extends CanvasLayer

## Écran titre, pause et options, communs à tous les jeux.
## Construits avec des CONTENEURS (VBox, Center, Margin) : aucune coordonnée en dur, ils
## tiennent en 1600x900 comme sur un téléphone. Le style vient du Theme (StudioTheme).
##
## Aucune logique de jeu : il émet des signaux, le jeu décide.

signal continuer
signal nouvelle_partie
signal reprendre
signal menu_principal
signal quitter

enum Ecran { AUCUN, TITRE, PAUSE, OPTIONS }

const COUCHE := 90
const LARGEUR_BOITE := 520
const ESPACE := 14
const VOILE := Color(0, 0, 0, 0.55)
const PAS_VOLUME := 0.05

var reglages: StudioReglages
var ecran: Ecran = Ecran.AUCUN
var _precedent: Ecran = Ecran.AUCUN
var _racine: Control
var _boite: VBoxContainer
var _titre_jeu := ""
var _partie_existe := false


func _init(reglages_jeu: StudioReglages = null, theme_jeu: Theme = null) -> void:
	reglages = reglages_jeu if reglages_jeu != null else StudioReglages.new()
	layer = COUCHE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_racine = Control.new()
	_racine.set_anchors_preset(Control.PRESET_FULL_RECT)
	_racine.theme = theme_jeu
	_racine.visible = false
	add_child(_racine)


func est_ouvert() -> bool:
	return ecran != Ecran.AUCUN


func ouvrir_titre(titre: String, partie_existe: bool) -> void:
	_titre_jeu = titre
	_partie_existe = partie_existe
	var b := _nouvel_ecran(Ecran.TITRE, titre, "Titre")
	if partie_existe:
		_bouton(b, "Continuer", "Continuer", continuer.emit)
	_bouton(b, "NouvellePartie", "Nouvelle partie", nouvelle_partie.emit)
	_bouton(b, "Options", "Options", ouvrir_options)
	if not OS.has_feature("web") and not OS.has_feature("mobile"):
		_bouton(b, "Quitter", "Quitter", quitter.emit)


func ouvrir_pause() -> void:
	var b := _nouvel_ecran(Ecran.PAUSE, "Pause", "Titre")
	_bouton(b, "Reprendre", "Reprendre", _sur_reprendre)
	_bouton(b, "Options", "Options", ouvrir_options)
	_bouton(b, "MenuPrincipal", "Menu principal", menu_principal.emit)
	if is_inside_tree():
		get_tree().paused = true
	else:
		push_warning("StudioMenus.ouvrir_pause : menu hors de l'arbre, le jeu n'est pas gelé")


func ouvrir_options() -> void:
	_precedent = ecran if ecran != Ecran.OPTIONS else _precedent
	var b := _nouvel_ecran(Ecran.OPTIONS, "Options", "Titre")
	_ligne_son(b, "Musique", "musique_on", "musique_vol")
	_ligne_son(b, "Effets", "effets_on", "effets_vol")
	if not OS.has_feature("mobile"):
		_case(b, "PleinEcran", "Plein écran", "plein_ecran")
	_bouton(b, "Retour", "Retour", _sur_retour_options)


func fermer() -> void:
	ecran = Ecran.AUCUN
	_racine.visible = false
	if is_inside_tree():
		get_tree().paused = false


func _sur_reprendre() -> void:
	fermer()
	reprendre.emit()


func _sur_retour_options() -> void:
	reglages.enregistrer()
	match _precedent:
		Ecran.PAUSE:
			ouvrir_pause()
		Ecran.TITRE:
			ouvrir_titre(_titre_jeu, _partie_existe)
		_:
			fermer()


func _nouvel_ecran(quel: Ecran, titre: String, variation: String) -> VBoxContainer:
	for enfant in _racine.get_children():
		_racine.remove_child(enfant)  # tout de suite : les noms des boutons restent uniques
		enfant.queue_free()
	ecran = quel
	_racine.visible = true
	var voile := ColorRect.new()
	voile.color = VOILE
	voile.set_anchors_preset(Control.PRESET_FULL_RECT)
	_racine.add_child(voile)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	_racine.add_child(centre)
	var cadre := PanelContainer.new()
	cadre.custom_minimum_size.x = LARGEUR_BOITE
	centre.add_child(cadre)
	_boite = VBoxContainer.new()
	_boite.add_theme_constant_override("separation", ESPACE)
	cadre.add_child(_boite)
	var l := Label.new()
	l.name = "TitreEcran"
	l.text = titre
	l.theme_type_variation = variation
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boite.add_child(l)
	return _boite


func _bouton(parent: Control, nom: String, texte: String, action: Callable) -> Button:
	var b := Button.new()
	b.name = nom
	b.text = texte
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _ligne_son(parent: Control, texte: String, cle_on: String, cle_vol: String) -> void:
	var ligne := HBoxContainer.new()
	ligne.add_theme_constant_override("separation", ESPACE)
	parent.add_child(ligne)
	var c := CheckButton.new()
	c.name = texte + "Actif"
	c.text = texte
	c.button_pressed = bool(reglages.lire(cle_on))
	c.toggled.connect(func(v: bool) -> void: reglages.regler(cle_on, v); reglages.appliquer())
	ligne.add_child(c)
	var s := HSlider.new()
	s.name = texte + "Volume"
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = PAS_VOLUME
	s.value = float(reglages.lire(cle_vol))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(v: float) -> void: reglages.regler(cle_vol, v); reglages.appliquer())
	ligne.add_child(s)


func _case(parent: Control, nom: String, texte: String, cle: String) -> void:
	var c := CheckButton.new()
	c.name = nom
	c.text = texte
	c.button_pressed = bool(reglages.lire(cle))
	c.toggled.connect(func(v: bool) -> void: reglages.regler(cle, v); reglages.appliquer())
	parent.add_child(c)
