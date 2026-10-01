extends RefCounted
## LE thème d'interface du jeu : un seul Theme Godot pour le HUD, les écrans et la Ville, fabriqué
## par le kit du studio (StudioTheme) à partir des couleurs par rôle (jeu/theme/couleurs.gd), puis
## complété ici de toutes les VARIATIONS dont les vues ont besoin. Une vue pose ce thème sur sa
## racine et ne nomme que des variations (`theme_type_variation`) : jamais une couleur de bouton,
## de panneau ou de texte écrite dans une scène.
##   const ThemeJeu = preload("res://jeu/theme/theme.gd")   puis   racine.theme = ThemeJeu.theme()
##
## Boutons   Button (neutre) · BoutonPrincipal (braise) · BoutonDanger · BoutonDiscret
##           BoutonPetit · BoutonPetitPrincipal · Onglet (bascule dorée) · BoutonCarte · BoutonHud
## Panneaux  Carte · CarteEquipee · CarteVerrouillee · CarteVide · PanneauEcran · PanneauNu
##           Cadre (plein écran) · Bandeau (liseré d'accent, teinté par self_modulate)
## Titres    Logo · TitreMort · TitreEcran · TitreSection · TitreCarte   (police d'apparat)
## Textes    SurTitre · SurTitreDoux · SurTitreEcran · Texte · TexteDoux · Petit · Affixe · Pouvoir
##           Or · Ames · Prix · PrixCher · Refus · Badge · BadgeDoux · Reglage · ReglageChange · Valeur
## HUD       HudFort · HudDoux · HudVie · HudOr · HudAmes · HudGardien · HudIndice · HudBanniere
##           HudBanniereSous · Touche (libellé de touche ou de bouton de manette)
## État grisé : `OPACITE_GRISE` (boutons désactivés, cartes qu'on ne peut pas prendre).

const Couleurs = preload("res://jeu/theme/couleurs.gd")

## Hauteur minimale d'une cible (doigt), en px de la résolution de référence ; la grande pour
## les boutons d'un panneau, la petite pour une rangée dense.
const CIBLE := 44.0
const CIBLE_GRANDE := 48.0
const RAYON := 6
const RAYON_PANNEAU := 8
const MARGE_BOUTON := 16
const OMBRE_PANNEAU := 24
const CONTOUR_FOCUS := 2
const ECART_FOCUS := 3
const ESPACEMENT_SURTITRE := 2 # px entre les lettres d'un sur-titre (capitales espacées)
const GRAISSE := 700
const GRAISSE_HUD := 800
const OPACITE_GRISE := 0.4
const ECHELLE_MAX := 2.0
const DENSITE_ANDROID := 160.0 # points par pouce d'un px de référence sur Android
## Opacités du blanc posé sur le panneau : carte au repos, survolée, enfoncée, grisée.
const VOILE_CARTE := [0.04, 0.08, 0.12, 0.02]
const TAILLES := {
	"logo": 84, "mort": 56, "titre": 24, "carte": 18, "section": 16, "corps": 16, "bouton": 15,
	"texte": 14, "doux": 13, "petit": 12, "surtitre": 11,
}

static var _theme: Theme = null
static var _titre: Font = null
static var _grasse: Font = null
static var _hud: Font = null
static var _espacee := {}

static func theme() -> Theme:
	if _theme == null:
		var ui: Dictionary = Couleurs.UI
		_theme = StudioTheme.construire({
			"fond": ui["void"].to_html(), "carte": ui.panel.to_html(), "bord": Color(0.35, 0.23, 0.27).to_html(),
			"texte": ui.ink.to_html(), "texte_doux": ui.ink_dim.to_html(), "accent": ui.gold.to_html(),
			"bouton": Color(0.26, 0.11, 0.13).to_html(), "bouton_texte": ui.ink.to_html(), "danger": ui.blood.to_html(),
			"rayon": RAYON, "bord_epaisseur": 1, "police_taille": TAILLES.corps, "titre_taille": TAILLES.titre, "marge": MARGE_BOUTON,
		})
		_theme.default_font = police_corps()
		_boutons(_theme)
		_cartes(_theme)
		_panneaux(_theme)
		_titres(_theme)
		_textes(_theme)
		_sommes(_theme)
		_hud_textes(_theme)
	return _theme

## Échelle d'une vue d'interface. L'étirement du projet rétrécit tout quand la fenêtre est plus
## petite que la référence (téléphone en paysage : 844 × 390) : la vue agrandit alors sa racine
## d'autant, pour que ses panneaux gardent leur taille (texte lisible, cibles d'au moins 44 px).
## `vue` : taille du viewport ; `fenetre` : sa fenêtre. Jamais moins de 1.
static func echelle(vue: Vector2, fenetre: Window) -> float:
	var largeur := fenetre.size.x
	if largeur <= 0:
		return 1.0
	var densite := DisplayServer.screen_get_scale()
	if OS.has_feature("android"):
		densite = DisplayServer.screen_get_dpi() / DENSITE_ANDROID
	return clampf(vue.x / float(largeur) * maxf(1.0, densite), 1.0, ECHELLE_MAX)

## Texte NET malgré l'agrandissement d'une vue (`k` : son échelle) : les polices de la fenêtre
## sont tramées à l'échelle réelle de l'écran, au lieu d'être agrandies après coup (flou).
## Sans agrandissement, le tramage revient à l'automatique. Chaque vue agrandie l'appelle quand
## la fenêtre change de taille ; toutes demandent la même chose.
static func nettete(fenetre: Viewport, k: float) -> void:
	var voulu := 0.0 # 0 = automatique
	if k > 1.0:
		voulu = fenetre.get_stretch_transform().get_scale().x * k
	if not is_equal_approx(fenetre.oversampling_override, voulu):
		fenetre.oversampling_override = voulu # (renvoie size_changed : d'où la comparaison)

# ---------------------------------------------------------------- polices, couleurs d'état

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
		f.font_weight = GRAISSE_HUD
		_titre = f
	return _titre

## Corps gras (boutons, sommes).
static func police_grasse() -> Font:
	if _grasse == null:
		_grasse = _graissee(GRAISSE)
	return _grasse

## Corps très gras du HUD : lisible en petit, par-dessus le jeu.
static func police_hud() -> Font:
	if _hud == null:
		_hud = _graissee(GRAISSE_HUD)
	return _hud

## Corps gras aux lettres espacées de `espace` px (sur-titres, badges).
static func police_espacee(espace: int = ESPACEMENT_SURTITRE) -> Font:
	if not _espacee.has(espace):
		var f := FontVariation.new()
		f.base_font = police_grasse()
		f.spacing_glyph = espace
		_espacee[espace] = f
	return _espacee[espace]

static func _graissee(graisse: int) -> Font:
	var f: SystemFont = police_corps()
	f.font_weight = graisse
	return f

## Couleur d'accent d'une carte selon son état (« equipe », « verrouille », « vide », « »).
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

## Le fond d'un écran plein (Ville, titre).
static func fond() -> Color:
	return Couleurs.UI["void"]

# ---------------------------------------------------------------- boutons

static func _boite(fond_c: Color, bord: Color, epaisseur: int = 1, rayon: int = RAYON) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fond_c
	sb.border_color = bord
	sb.set_border_width_all(epaisseur)
	sb.set_corner_radius_all(rayon)
	sb.content_margin_left = MARGE_BOUTON
	sb.content_margin_right = MARGE_BOUTON
	sb.content_margin_top = MARGE_BOUTON / 2.0
	sb.content_margin_bottom = MARGE_BOUTON / 2.0
	return sb

## Focus (clavier, manette) : un liseré d'or DÉCOLLÉ du bouton, visible même sur un onglet actif.
static func _focus() -> StyleBoxFlat:
	var sb := _boite(Color.TRANSPARENT, Couleurs.UI.gold, CONTOUR_FOCUS, RAYON + ECART_FOCUS)
	sb.draw_center = false
	sb.set_expand_margin_all(ECART_FOCUS)
	return sb

static func _etats(th: Theme, type: String, fond_c: Color, bord: Color, texte: Color) -> void:
	if type != "Button":
		th.set_type_variation(type, "Button")
	th.set_stylebox("normal", type, _boite(fond_c, bord))
	th.set_stylebox("hover", type, _boite(fond_c.lightened(0.1), bord))
	th.set_stylebox("pressed", type, _boite(fond_c.darkened(0.15), bord))
	th.set_stylebox("disabled", type, _boite(Color(fond_c, fond_c.a * OPACITE_GRISE), Color(bord, bord.a * OPACITE_GRISE)))
	th.set_stylebox("focus", type, _focus())
	for etat in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		th.set_color(etat, type, texte)
	th.set_color("font_disabled_color", type, Color(texte, OPACITE_GRISE))
	th.set_font("font", type, police_grasse())
	th.set_font_size("font_size", type, TAILLES.bouton)

static func _boutons(th: Theme) -> void:
	var ui: Dictionary = Couleurs.UI
	var braise: Color = ui.ember.darkened(0.22)
	_etats(th, "Button", Color(ui.ink, 0.06), ui.line, ui.ink)
	_etats(th, "BoutonPrincipal", braise, ui.ember.lightened(0.3), Color.WHITE)
	_etats(th, "BoutonDanger", ui.blood, ui.blood.lightened(0.35), Color.WHITE)
	_etats(th, "BoutonDiscret", Color.TRANSPARENT, ui.line, ui.ink_dim)
	_etats(th, "BoutonPetit", Color(ui.ink, 0.06), ui.line, ui.ink)
	_etats(th, "BoutonPetitPrincipal", braise, ui.ember.lightened(0.3), Color.WHITE)
	for petit in ["BoutonPetit", "BoutonPetitPrincipal"]:
		th.set_font_size("font_size", petit, TAILLES.texte)
	# Onglet et option à bascule : l'état « choisi » se lit au liseré et au texte dorés.
	_etats(th, "Onglet", Color(ui.ink, 0.05), ui.line, ui.ink)
	var choisi := _boite(Color(ui.gold, 0.1), ui.gold)
	th.set_stylebox("pressed", "Onglet", choisi)
	th.set_stylebox("hover_pressed", "Onglet", choisi)
	for etat in ["font_pressed_color", "font_hover_pressed_color"]:
		th.set_color(etat, "Onglet", ui.gold)
	# Bouton posé sur le jeu (pause) : fond sombre, lisible sur un sol clair comme sur un sol noir.
	_etats(th, "BoutonHud", Color(ui.panel, 0.72), Color(ui.ink, 0.35), ui.ink)

# ---------------------------------------------------------------- cartes et panneaux

static func _carte(fond_c: Color, bord: Color) -> StyleBoxFlat:
	var sb := _boite(fond_c, bord)
	sb.set_content_margin_all(0.0)
	return sb

## La carte : un PanelContainer quand elle n'est qu'à lire ; quand elle est à CHOISIR, un Button
## nu (BoutonCarte) lui sert de fond cliquable (survol, appui, focus, grisé).
static func _cartes(th: Theme) -> void:
	var ui: Dictionary = Couleurs.UI
	var etats := ["normal", "hover", "pressed", "disabled"]
	th.set_type_variation("BoutonCarte", "Button")
	for i in etats.size():
		th.set_stylebox(etats[i], "BoutonCarte", _carte(Color(Color.WHITE, VOILE_CARTE[i]), ui.line))
	th.set_stylebox("focus", "BoutonCarte", _focus())
	for nom in ["Carte", "CarteEquipee", "CarteVerrouillee", "CarteVide"]:
		th.set_type_variation(nom, "PanelContainer")
	th.set_stylebox("panel", "Carte", _carte(Color(Color.WHITE, VOILE_CARTE[0]), ui.line))
	th.set_stylebox("panel", "CarteEquipee", _carte(Color(ui.gold, 0.07), Color(ui.gold, 0.75)))
	th.set_stylebox("panel", "CarteVerrouillee", _carte(Color(Color.WHITE, VOILE_CARTE[3]), ui.line))
	th.set_stylebox("panel", "CarteVide", _carte(Color(Color.WHITE, VOILE_CARTE[3] / 2.0), Color(ui.line, 0.1)))
	# Bandeau d'accent : blanc, teinté par self_modulate (une couleur par carte, un seul style).
	var bandeau := StyleBoxFlat.new()
	bandeau.bg_color = Color.WHITE
	bandeau.corner_radius_top_left = RAYON
	bandeau.corner_radius_top_right = RAYON
	th.set_type_variation("Bandeau", "Panel")
	th.set_stylebox("panel", "Bandeau", bandeau)

static func _panneaux(th: Theme) -> void:
	var ui: Dictionary = Couleurs.UI
	# Le panneau d'un écran posé sur le jeu : sombre, liseré clair, ombre portée.
	var ecran := _boite(ui.panel, ui.line, 1, RAYON_PANNEAU)
	ecran.set_content_margin_all(0.0)
	ecran.shadow_color = Color(0, 0, 0, 0.6)
	ecran.shadow_size = OMBRE_PANNEAU
	th.set_type_variation("PanneauEcran", "PanelContainer")
	th.set_stylebox("panel", "PanneauEcran", ecran)
	th.set_type_variation("PanneauNu", "PanelContainer")
	th.set_stylebox("panel", "PanneauNu", StyleBoxEmpty.new())
	# Le cadre d'un écran plein (la Ville) : le même panneau, sans ombre, avec ses marges.
	var cadre := _boite(ui.panel, ui.line, 1, RAYON_PANNEAU)
	cadre.content_margin_left = 14
	cadre.content_margin_right = 14
	cadre.content_margin_top = 8
	cadre.content_margin_bottom = 8
	th.set_type_variation("Cadre", "PanelContainer")
	th.set_stylebox("panel", "Cadre", cadre)

# ---------------------------------------------------------------- textes

static func _etiquette(th: Theme, type: String, taille: int, couleur: Color, police: Font = null) -> void:
	th.set_type_variation(type, "Label")
	th.set_font_size("font_size", type, taille)
	th.set_color("font_color", type, couleur)
	if police != null:
		th.set_font("font", type, police)

static func _titres(th: Theme) -> void:
	var ui: Dictionary = Couleurs.UI
	var apparat: Font = police_titre()
	_etiquette(th, "Logo", TAILLES.logo, ui.ink, apparat)
	_etiquette(th, "TitreMort", TAILLES.mort, Couleurs.PAL.heroHurt, apparat)
	# Relief des grands titres : un liseré sombre, et une ombre de braise décalée vers le bas.
	for type in ["Logo", "TitreMort"]:
		th.set_color("font_outline_color", type, ui.ember.darkened(0.84))
		th.set_constant("outline_size", type, 5)
		th.set_color("font_shadow_color", type, ui.ember.darkened(0.6))
		th.set_constant("shadow_outline_size", type, 5)
		th.set_constant("shadow_offset_x", type, 0)
		th.set_constant("shadow_offset_y", type, 6)
	_etiquette(th, "TitreEcran", TAILLES.titre, ui.ink, apparat)
	_etiquette(th, "TitreSection", TAILLES.section, ui.ink, apparat)
	_etiquette(th, "TitreCarte", TAILLES.carte, ui.ink, apparat)
	_etiquette(th, "SurTitre", TAILLES.surtitre, ui.ember, police_espacee())
	_etiquette(th, "SurTitreDoux", TAILLES.surtitre, ui.ink_dim, police_espacee())
	_etiquette(th, "SurTitreEcran", TAILLES.petit, ui.ember, police_espacee(4))

static func _textes(th: Theme) -> void:
	var ui: Dictionary = Couleurs.UI
	_etiquette(th, "Texte", TAILLES.texte, ui.ink)
	_etiquette(th, "TexteDoux", TAILLES.doux, ui.ink_dim)
	_etiquette(th, "Petit", TAILLES.petit, ui.ink_dim)
	_etiquette(th, "Refus", TAILLES.doux, Couleurs.PAL.heroHurt)
	_etiquette(th, "Badge", TAILLES.surtitre, ui.gold, police_espacee(1))
	_etiquette(th, "BadgeDoux", TAILLES.surtitre, ui.ink_dim, police_espacee(1))
	# Lignes d'un objet : ses affixes (bleu de l'objet magique, éclairci), son pouvoir (orange légendaire).
	var raretes: Array = D6Data.tables().loot.ITEM_RARITIES
	_etiquette(th, "Affixe", TAILLES.texte, Color(String(raretes[1].color)).lightened(0.45))
	_etiquette(th, "Pouvoir", TAILLES.texte, Color(String(raretes[raretes.size() - 1].color)))
	_etiquette(th, "Reglage", TAILLES.doux, ui.ink)
	_etiquette(th, "ReglageChange", TAILLES.doux, ui.gold)
	_etiquette(th, "Valeur", TAILLES.doux, ui.gold, police_grasse())

## Sommes : l'or est doré, les Âmes ont le bleu clair du héros ; un prix trop cher vire au rouge.
static func _sommes(th: Theme) -> void:
	var pal: Dictionary = Couleurs.PAL
	var gras: Font = police_grasse()
	_etiquette(th, "Or", TAILLES.corps, Couleurs.UI.gold, gras)
	_etiquette(th, "Ames", TAILLES.corps, pal.lance, gras)
	_etiquette(th, "Prix", TAILLES.bouton, pal.lance, gras)
	_etiquette(th, "PrixCher", TAILLES.bouton, pal.heroHurt, gras)

# ---------------------------------------------------------------- HUD

## Texte du HUD : très gras et cerné de sombre, lisible sur n'importe quel sol.
static func _hud_texte(th: Theme, type: String, taille: int, couleur: Color, contour: int = 0) -> void:
	_etiquette(th, type, taille, couleur, police_hud())
	th.set_color("font_outline_color", type, Color(Couleurs.UI["void"], 0.85))
	th.set_constant("outline_size", type, contour if contour > 0 else maxi(3, taille / 4))

static func _hud_textes(th: Theme) -> void:
	var pal: Dictionary = Couleurs.PAL
	_hud_texte(th, "HudFort", 18, pal.text)
	_hud_texte(th, "HudDoux", 13, pal.textDim)
	_hud_texte(th, "HudVie", 12, pal.text, 5)
	_hud_texte(th, "HudOr", 18, pal.gold)
	_hud_texte(th, "HudAmes", 14, pal.lance)
	_hud_texte(th, "HudGardien", 14, pal.bossTrim)
	_hud_texte(th, "HudIndice", 15, pal.text)
	_hud_texte(th, "HudBanniere", 30, pal.text)
	_hud_texte(th, "HudBanniereSous", 14, pal.textDim)
	# Libellé d'une touche (ou d'un bouton de manette) : une petite capsule sombre.
	_hud_texte(th, "Touche", 11, pal.text, 0)
	th.set_constant("outline_size", "Touche", 0)
	var capsule := _boite(Color(Couleurs.UI.panel, 0.78), Color(pal.text, 0.28), 1, 4)
	capsule.content_margin_left = 6
	capsule.content_margin_right = 6
	capsule.content_margin_top = 1
	capsule.content_margin_bottom = 2
	th.set_stylebox("normal", "Touche", capsule)
