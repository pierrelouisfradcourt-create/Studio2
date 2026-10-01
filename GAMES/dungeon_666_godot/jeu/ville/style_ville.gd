extends RefCounted
## Le style de la Ville : le thème du jeu (jeu/theme/theme.gd) COMPLÉTÉ par les variations dont
## la Ville a besoin (carte, bandeau d'accent, onglet, bouton primaire, sur-titre, prix…).
## Toutes les couleurs sortent de la palette par rôle (jeu/theme/couleurs.gd) et des raretés des
## tables : aucune scène ni aucun script de la Ville n'écrit une couleur de bouton ou de panneau.
## Mêmes partis que jeu/ecrans/styles.gd (rayon, voile des cartes, bouton neutre, bouton de
## braise, liseré de focus) pour que la Ville et les écrans se ressemblent, sans dépendance
## croisée ; ces variations ont vocation à rejoindre jeu/theme/theme.gd.
##   const Style = preload("res://jeu/ville/style_ville.gd")   puis   racine.theme = Style.theme()

const ThemeJeu = preload("res://jeu/theme/theme.gd")
const Couleurs = preload("res://jeu/theme/couleurs.gd")

## Hauteur minimale d'une cible (doigt) : 44 px de la résolution de référence.
const CIBLE := 44.0
const RAYON := 6
const RAYON_CADRE := 8
const MARGE_BOUTON := 16
const VOILE_CARTE := 0.04 # blanc posé sur le panneau
const GRAS := 700
const ESPACE_SURTITRE := 2 # px entre les lettres d'un sur-titre (capitales espacées)
const OPACITE_INACTIF := 0.4

static var _theme: Theme = null

static func theme() -> Theme:
	if _theme == null:
		var base: Theme = ThemeJeu.theme()
		_theme = Theme.new()
		_theme.merge_with(base)
		_theme.default_font = base.default_font
		_theme.default_font_size = base.default_font_size
		_textes(_theme)
		_boutons(_theme)
		_panneaux(_theme)
	return _theme

## Couleur du bandeau d'une carte selon son état (« equipe », « verrouille », « vide », « »).
static func accent(etat: String) -> Color:
	var ui: Dictionary = Couleurs.UI
	match etat:
		"equipe":
			return ui.gold
		"verrouille":
			return Color(ui.ink_dim, 0.7)
		"vide":
			return ui.line
	return ui.ember

static func fond() -> Color:
	return Couleurs.UI["void"]

# ---------------------------------------------------------------- textes

static func _police(graisse: int, espace: int = 0) -> Font:
	var f := SystemFont.new()
	f.font_names = (ThemeJeu.police_corps() as SystemFont).font_names
	f.font_weight = graisse
	if espace == 0:
		return f
	var v := FontVariation.new()
	v.base_font = f
	v.spacing_glyph = espace
	return v

static func _label(th: Theme, nom: String, taille: int, couleur: Color, police: Font = null) -> void:
	th.set_type_variation(nom, "Label")
	th.set_font_size("font_size", nom, taille)
	th.set_color("font_color", nom, couleur)
	if police != null:
		th.set_font("font", nom, police)

static func _textes(th: Theme) -> void:
	var ui: Dictionary = Couleurs.UI
	var pal: Dictionary = Couleurs.PAL
	var titre: Font = ThemeJeu.police_titre()
	var gras := _police(GRAS)
	_label(th, "TitreVille", 22, ui.ink, titre)
	_label(th, "TitreCarte", 18, ui.ink, titre)
	_label(th, "TitreSection", 16, ui.ink, titre)
	_label(th, "Surtitre", 11, ui.ember, _police(GRAS, ESPACE_SURTITRE))
	_label(th, "Badge", 11, ui.gold, _police(GRAS, 1))
	_label(th, "BadgeDoux", 11, ui.ink_dim, _police(GRAS, 1))
	_label(th, "Sous", 12, ui.ink_dim)
	_label(th, "Texte", 14, ui.ink)
	_label(th, "Note", 13, ui.ink_dim)
	# Lignes d'un objet : ses affixes (bleu de l'objet magique, éclairci), son pouvoir (orange légendaire).
	var raretes: Array = D6Data.tables().loot.ITEM_RARITIES
	_label(th, "Affixe", 14, Color(String(raretes[1].color)).lightened(0.45))
	_label(th, "Pouvoir", 14, Color(String(raretes[raretes.size() - 1].color)))
	_label(th, "Ames", 16, pal.lance, gras)
	_label(th, "Or", 16, ui.gold, gras)
	_label(th, "Prix", 15, pal.lance, gras)
	_label(th, "PrixCher", 15, pal.heroHurt, gras)
	_label(th, "Refus", 13, pal.heroHurt)

# ---------------------------------------------------------------- boutons

static func _boite(fond_c: Color, bord: Color, epaisseur: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fond_c
	sb.set_corner_radius_all(RAYON)
	sb.border_color = bord
	sb.set_border_width_all(epaisseur)
	sb.content_margin_left = MARGE_BOUTON
	sb.content_margin_right = MARGE_BOUTON
	sb.content_margin_top = MARGE_BOUTON / 2.0
	sb.content_margin_bottom = MARGE_BOUTON / 2.0
	return sb

static func _bouton(th: Theme, nom: String, fond_c: Color, bord: Color, texte: Color) -> void:
	if nom != "Button":
		th.set_type_variation(nom, "Button")
	th.set_stylebox("normal", nom, _boite(fond_c, bord))
	th.set_stylebox("hover", nom, _boite(fond_c.lightened(0.12), bord))
	th.set_stylebox("pressed", nom, _boite(fond_c.darkened(0.15), bord))
	th.set_stylebox("disabled", nom, _boite(Color(fond_c, fond_c.a * OPACITE_INACTIF), Color(bord, bord.a * OPACITE_INACTIF)))
	for etat in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		th.set_color(etat, nom, texte)
	th.set_color("font_disabled_color", nom, Color(texte, OPACITE_INACTIF))

static func _boutons(th: Theme) -> void:
	var ui: Dictionary = Couleurs.UI
	# Focus (clavier, manette) : un liseré doré DÉCOLLÉ du bouton, visible même sur un onglet actif.
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = ui.gold
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(RAYON + 3)
	focus.set_expand_margin_all(3)
	th.set_stylebox("focus", "Button", focus)
	th.set_font("font", "Button", _police(GRAS))
	th.set_font_size("font_size", "Button", 15)
	_bouton(th, "Button", Color(ui.ink, 0.06), ui.line, ui.ink) # le bouton neutre du web
	var braise: Color = ui.ember.darkened(0.22)
	_bouton(th, "BoutonPrimaire", braise, ui.ember.lightened(0.3), Color.WHITE)
	_bouton(th, "BoutonDanger", ui.blood, ui.blood.lightened(0.35), Color.WHITE)
	_bouton(th, "BoutonDiscret", Color.TRANSPARENT, ui.line, ui.ink_dim)
	# Onglet et option à bascule : l'état « choisi » se lit au liseré et au texte dorés.
	_bouton(th, "Onglet", Color(ui.ink, 0.05), ui.line, ui.ink)
	var choisi := _boite(Color(ui.gold, 0.1), ui.gold)
	th.set_stylebox("pressed", "Onglet", choisi)
	th.set_stylebox("hover_pressed", "Onglet", choisi)
	for etat in ["font_pressed_color", "font_hover_pressed_color"]:
		th.set_color(etat, "Onglet", ui.gold)

# ---------------------------------------------------------------- panneaux

static func _carte(fond_c: Color, bord: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fond_c
	sb.border_color = bord
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(RAYON)
	sb.set_content_margin_all(0)
	return sb

static func _panneaux(th: Theme) -> void:
	var ui: Dictionary = Couleurs.UI
	for nom in ["Carte", "CarteEquipee", "CarteVerrouillee", "CarteVide"]:
		th.set_type_variation(nom, "PanelContainer")
	th.set_stylebox("panel", "Carte", _carte(Color(Color.WHITE, VOILE_CARTE), ui.line))
	th.set_stylebox("panel", "CarteEquipee", _carte(Color(ui.gold, 0.07), Color(ui.gold, 0.75)))
	th.set_stylebox("panel", "CarteVerrouillee", _carte(Color(Color.WHITE, VOILE_CARTE / 2.0), ui.line))
	th.set_stylebox("panel", "CarteVide", _carte(Color(Color.WHITE, VOILE_CARTE / 4.0), Color(ui.line, 0.1)))
	# Le cadre de l'écran : le panneau du web (fond sombre, liseré clair).
	var cadre := _carte(ui.panel, ui.line)
	cadre.set_corner_radius_all(RAYON_CADRE)
	cadre.content_margin_left = 14
	cadre.content_margin_right = 14
	cadre.content_margin_top = 8
	cadre.content_margin_bottom = 8
	th.set_type_variation("Cadre", "PanelContainer")
	th.set_stylebox("panel", "Cadre", cadre)
	# Bandeau d'accent : blanc, teinté par self_modulate (une couleur par carte, un seul style).
	var bandeau := StyleBoxFlat.new()
	bandeau.bg_color = Color.WHITE
	bandeau.corner_radius_top_left = RAYON
	bandeau.corner_radius_top_right = RAYON
	th.set_type_variation("Bandeau", "Panel")
	th.set_stylebox("panel", "Bandeau", bandeau)
