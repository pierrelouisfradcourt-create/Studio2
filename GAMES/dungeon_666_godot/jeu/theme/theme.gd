extends RefCounted
## Le thème d'interface du jeu : un seul Theme Godot, fabriqué par le kit du studio
## (StudioTheme) à partir des couleurs d'interface de jeu/theme/couleurs.gd. Les écrans et le HUD
## le posent sur leur racine ; aucune vue n'écrit de couleur de bouton ou de panneau.
##   const ThemeJeu = preload("res://jeu/theme/theme.gd")   puis   racine.theme = ThemeJeu.theme()

const Couleurs = preload("res://jeu/theme/couleurs.gd")

static var _theme: Theme = null
static var _titre: Font = null

static func theme() -> Theme:
	if _theme == null:
		var ui: Dictionary = Couleurs.UI
		_theme = StudioTheme.construire({
			"fond": ui["void"].to_html(), "carte": ui.panel.to_html(), "bord": Color(0.35, 0.23, 0.27).to_html(),
			"texte": ui.ink.to_html(), "texte_doux": ui.ink_dim.to_html(), "accent": ui.gold.to_html(),
			"bouton": Color(0.26, 0.11, 0.13).to_html(), "bouton_texte": ui.ink.to_html(), "danger": ui.blood.to_html(),
			"rayon": 10, "bord_epaisseur": 1, "police_taille": 16, "titre_taille": 26, "marge": 14,
		})
		_theme.default_font = police_corps()
	return _theme

## Police du corps : celle du système (aucun fichier de police dans le projet).
static func police_corps() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Segoe UI", "Roboto", "Helvetica Neue", "Arial", "sans-serif"])
	return f

## Police d'apparat (titres, « VOUS ÊTES MORT ») : une capitale romaine du système, graissée.
static func police_titre() -> Font:
	if _titre == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Cinzel", "Trajan Pro", "Georgia", "Times New Roman", "serif"])
		f.font_weight = 800
		_titre = f
	return _titre
