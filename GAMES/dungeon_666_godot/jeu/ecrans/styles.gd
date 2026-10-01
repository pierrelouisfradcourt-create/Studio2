extends RefCounted
## Les variations de thème des écrans : le thème du jeu (jeu/theme/theme.gd) complété des rôles
## dont les panneaux ont besoin (bouton principal, bouton discret, carte, logo, sur-titre…).
## Toutes les couleurs viennent de la palette par rôle (jeu/theme/couleurs.gd) : les scènes des
## écrans ne nomment que des VARIATIONS (`theme_type_variation`), jamais une couleur.
## Ces variations ont vocation à rejoindre jeu/theme/theme.gd (HUD et Ville en ont l'usage).
##   const Styles = preload("res://jeu/ecrans/styles.gd")   puis   racine.theme = Styles.theme()

const ThemeJeu = preload("res://jeu/theme/theme.gd")
const Couleurs = preload("res://jeu/theme/couleurs.gd")

const RAYON := 6
const RAYON_PANNEAU := 8
const MARGE_BOUTON := 18
const OMBRE_PANNEAU := 24
const CONTOUR_FOCUS := 2
const ECART_FOCUS := 3
const ESPACEMENT_SURTITRE := 2 # px entre les lettres des sur-titres (letter-spacing du web)
const GRAISSE := 700
## Opacités du blanc posé sur le panneau : carte au repos, survolée, enfoncée, grisée.
const VOILE_CARTE := [0.04, 0.08, 0.12, 0.02]
const TAILLES := {"logo": 84, "mort": 56, "titre": 24, "carte": 18, "texte": 14, "petit": 12, "surtitre": 11, "reglage": 13}

static var _theme: Theme = null
static var _grasse: Font = null
static var _espacee: Font = null

static func theme() -> Theme:
	if _theme == null:
		_theme = ThemeJeu.theme().duplicate()
		_boutons(_theme)
		_cartes(_theme)
		_panneaux(_theme)
		_titres(_theme)
		_textes(_theme)
	return _theme

## Corps gras (boutons, sommes) : la police du système, graissée.
static func police_grasse() -> Font:
	if _grasse == null:
		var f: SystemFont = ThemeJeu.police_corps()
		f.font_weight = GRAISSE
		_grasse = f
	return _grasse

## Sur-titres : capitales espacées.
static func police_espacee() -> Font:
	if _espacee == null:
		var f := FontVariation.new()
		f.base_font = ThemeJeu.police_corps()
		f.spacing_glyph = ESPACEMENT_SURTITRE
		_espacee = f
	return _espacee

static func _boite(fond: Color, bord: Color, epaisseur: int = 1, rayon: int = RAYON) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fond
	sb.border_color = bord
	sb.set_border_width_all(epaisseur)
	sb.set_corner_radius_all(rayon)
	sb.content_margin_left = MARGE_BOUTON
	sb.content_margin_right = MARGE_BOUTON
	sb.content_margin_top = MARGE_BOUTON / 2.0
	sb.content_margin_bottom = MARGE_BOUTON / 2.0
	return sb

## Contour de focus (clavier, manette) : un liseré d'or, détaché du bouton.
static func _focus() -> StyleBoxFlat:
	var sb := _boite(Color.TRANSPARENT, Couleurs.UI.gold, CONTOUR_FOCUS)
	sb.set_expand_margin_all(ECART_FOCUS)
	return sb

static func _etats(th: Theme, type: String, fond: Color, bord: Color, texte: Color) -> void:
	th.set_stylebox("normal", type, _boite(fond, bord))
	th.set_stylebox("hover", type, _boite(fond.lightened(0.1), bord))
	th.set_stylebox("pressed", type, _boite(fond.darkened(0.15), bord))
	th.set_stylebox("disabled", type, _boite(Color(fond, fond.a * 0.4), Color(bord, bord.a * 0.4)))
	th.set_stylebox("focus", type, _focus())
	for etat in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		th.set_color(etat, type, texte)
	th.set_color("font_disabled_color", type, Color(texte, 0.4))
	th.set_font("font", type, police_grasse())

static func _boutons(th: Theme) -> void:
	var ui: Dictionary = Couleurs.UI
	var braise: Color = ui.ember.darkened(0.22)
	_etats(th, "Button", Color(ui.ink, 0.06), ui.line, ui.ink)
	th.set_type_variation("BoutonPrincipal", "Button")
	_etats(th, "BoutonPrincipal", braise, ui.ember.lightened(0.3), Color.WHITE)
	th.set_type_variation("BoutonDiscret", "Button")
	_etats(th, "BoutonDiscret", Color.TRANSPARENT, ui.line, ui.ink_dim)
	th.set_type_variation("BoutonPetit", "Button")
	th.set_font_size("font_size", "BoutonPetit", TAILLES.texte)
	th.set_type_variation("BoutonPetitPrincipal", "BoutonPrincipal")
	th.set_font_size("font_size", "BoutonPetitPrincipal", TAILLES.texte)

## La carte : un Button nu sert de fond cliquable (survol, appui, focus), un PanelContainer de
## fond quand elle n'est qu'à lire.
static func _cartes(th: Theme) -> void:
	var ui: Dictionary = Couleurs.UI
	var etats := ["normal", "hover", "pressed", "disabled"]
	th.set_type_variation("BoutonCarte", "Button")
	for i in etats.size():
		var sb := _boite(Color(Color.WHITE, VOILE_CARTE[i]), ui.line)
		sb.set_content_margin_all(0.0)
		th.set_stylebox(etats[i], "BoutonCarte", sb)
	th.set_stylebox("focus", "BoutonCarte", _focus())
	th.set_type_variation("Carte", "PanelContainer")
	var fond := _boite(Color(Color.WHITE, VOILE_CARTE[0]), ui.line)
	fond.set_content_margin_all(0.0)
	th.set_stylebox("panel", "Carte", fond)

static func _panneaux(th: Theme) -> void:
	var ui: Dictionary = Couleurs.UI
	var sb := _boite(ui.panel, ui.line, 1, RAYON_PANNEAU)
	sb.set_content_margin_all(0.0)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = OMBRE_PANNEAU
	th.set_type_variation("PanneauEcran", "PanelContainer")
	th.set_stylebox("panel", "PanneauEcran", sb)
	th.set_type_variation("PanneauNu", "PanelContainer")
	th.set_stylebox("panel", "PanneauNu", StyleBoxEmpty.new())

static func _etiquette(th: Theme, type: String, taille: int, couleur: Color, police: Font = null) -> void:
	th.set_type_variation(type, "Label")
	th.set_font_size("font_size", type, taille)
	th.set_color("font_color", type, couleur)
	if police != null:
		th.set_font("font", type, police)

static func _titres(th: Theme) -> void:
	var ui: Dictionary = Couleurs.UI
	var apparat: Font = ThemeJeu.police_titre()
	_etiquette(th, "Logo", TAILLES.logo, ui.ink, apparat)
	_etiquette(th, "TitreMort", TAILLES.mort, Couleurs.PAL.heroHurt, apparat)
	for type in ["Logo", "TitreMort"]:
		th.set_color("font_shadow_color", type, Color(ui.ember.darkened(0.7), 0.9))
		th.set_constant("shadow_outline_size", type, 4)
		th.set_constant("shadow_offset_x", type, 0)
		th.set_constant("shadow_offset_y", type, 3)
	_etiquette(th, "TitreEcran", TAILLES.titre, ui.ink, apparat)
	_etiquette(th, "TitreSection", TAILLES.carte, ui.ink, apparat)
	_etiquette(th, "TitreCarte", TAILLES.carte, ui.ink, apparat)
	_etiquette(th, "SurTitreEcran", TAILLES.petit, ui.ember, police_espacee())
	_etiquette(th, "SurTitre", TAILLES.surtitre, ui.ink_dim, police_espacee())

static func _textes(th: Theme) -> void:
	var ui: Dictionary = Couleurs.UI
	_etiquette(th, "TexteCarte", TAILLES.texte, ui.ink)
	_etiquette(th, "Aide", TAILLES.texte, ui.ink_dim)
	_etiquette(th, "Petit", TAILLES.petit, ui.ink_dim)
	_etiquette(th, "Or", th.default_font_size, ui.gold, police_grasse())
	# Lignes d'un objet : ses affixes (bleu de l'objet magique), son pouvoir légendaire (orange).
	var raretes: Array = D6Data.tables().loot.ITEM_RARITIES
	_etiquette(th, "Affixe", TAILLES.texte, Color(String(raretes[1].color)).lightened(0.45))
	_etiquette(th, "Pouvoir", TAILLES.texte, Color(String(raretes[raretes.size() - 1].color)))
	_etiquette(th, "Reglage", TAILLES.reglage, ui.ink)
	_etiquette(th, "ReglageChange", TAILLES.reglage, ui.gold)
	_etiquette(th, "Valeur", TAILLES.reglage, ui.gold, police_grasse())
