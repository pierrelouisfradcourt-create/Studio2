class_name StudioTheme
extends RefCounted

## Fabrique un Theme Godot (.tres) à partir des JETONS d'un jeu (fichier JSON de palette).
## Remplace les palettes recopiées dans chaque vue (Kitten Factory : ui_theme.gd + menu_view.gd
## avaient chacun leurs constantes). Un jeu = un fichier de jetons = un thème ; les vues
## n'écrivent plus aucune couleur.
##
## Jetons reconnus (tous optionnels, défauts = interface sombre lisible) :
##   fond, carte, bord, texte, texte_doux, accent, bouton, bouton_texte, danger,
##   rayon (int), bord_epaisseur (int), police_taille (int), titre_taille (int), marge (int),
##   police (chemin res:// d'une police .ttf/.otf).

const DEFAUTS := {
	"fond": "#10151B", "carte": "#1A222CEE", "bord": "#43586E",
	"texte": "#F2EFE8", "texte_doux": "#B9C6D2", "accent": "#FFD23F",
	"bouton": "#2D4A6D", "bouton_texte": "#F2EFE8", "danger": "#B8473A",
	"rayon": 12, "bord_epaisseur": 2, "police_taille": 22, "titre_taille": 40, "marge": 16,
	"police": "",
}
const ECLAIRCI_SURVOL := 0.12
const ASSOMBRI_APPUI := 0.15
const OPACITE_DESACTIVE := 0.45
const CONTRASTE_MIN := 4.5


## Lit un fichier de jetons JSON ; retourne les défauts complétés.
static func jetons_depuis(chemin: String) -> Dictionary:
	var j := DEFAUTS.duplicate()
	if FileAccess.file_exists(chemin):
		var brut: Variant = JSON.parse_string(FileAccess.get_file_as_string(chemin))
		if brut is Dictionary:
			j.merge(brut, true)
	return j


static func construire(jetons: Dictionary) -> Theme:
	var j := DEFAUTS.duplicate()
	j.merge(jetons, true)
	var th := Theme.new()
	th.default_font_size = int(j["police_taille"])
	if String(j["police"]) != "" and ResourceLoader.exists(String(j["police"])):
		th.default_font = load(String(j["police"]))
	_boutons(th, j)
	_panneaux(th, j)
	_textes(th, j)
	_reglettes(th, j)
	return th


static func enregistrer(th: Theme, chemin: String) -> Error:
	return ResourceSaver.save(th, chemin)


## Contraste WCAG entre deux couleurs (1..21). Sert d'oracle : texte sur carte >= 4,5.
static func contraste(a: Color, b: Color) -> float:
	# luminance RELATIVE (WCAG) : sur les composantes linéaires, pas sur le sRGB brut
	var la := a.srgb_to_linear().get_luminance() + 0.05
	var lb := b.srgb_to_linear().get_luminance() + 0.05
	return maxf(la, lb) / minf(la, lb)


## Liste des paires illisibles (texte, texte_doux, bouton_texte) — vide si tout passe.
static func verifier_contrastes(jetons: Dictionary) -> Array[String]:
	var j := DEFAUTS.duplicate()
	j.merge(jetons, true)
	var fautes: Array[String] = []
	var paires := [["texte", "carte"], ["texte_doux", "carte"], ["bouton_texte", "bouton"], ["texte", "fond"]]
	for p in paires:
		var c := contraste(Color(String(j[p[0]])), Color(String(j[p[1]])))
		if c < CONTRASTE_MIN:
			fautes.append("%s sur %s : %.1f:1 (minimum %.1f)" % [p[0], p[1], c, CONTRASTE_MIN])
	return fautes


static func boite(fond: Color, j: Dictionary, bord: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fond
	sb.set_corner_radius_all(int(j["rayon"]))
	if bord.a > 0.0:
		sb.border_color = bord
		sb.set_border_width_all(int(j["bord_epaisseur"]))
	var m := int(j["marge"])
	sb.content_margin_left = m
	sb.content_margin_right = m
	sb.content_margin_top = m * 0.5
	sb.content_margin_bottom = m * 0.5
	return sb


static func _boutons(th: Theme, j: Dictionary) -> void:
	var fond := Color(String(j["bouton"]))
	var bord := Color(String(j["bord"]))
	var focus := boite(Color.TRANSPARENT, j, Color(String(j["accent"])))
	th.set_stylebox("normal", "Button", boite(fond, j, bord))
	th.set_stylebox("hover", "Button", boite(fond.lightened(ECLAIRCI_SURVOL), j, bord))
	th.set_stylebox("pressed", "Button", boite(fond.darkened(ASSOMBRI_APPUI), j, bord))
	th.set_stylebox("disabled", "Button", boite(Color(fond, OPACITE_DESACTIVE), j, bord))
	th.set_stylebox("focus", "Button", focus)
	var texte := Color(String(j["bouton_texte"]))
	for etat in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		th.set_color(etat, "Button", texte)
	th.set_color("font_disabled_color", "Button", Color(texte, OPACITE_DESACTIVE))


static func _panneaux(th: Theme, j: Dictionary) -> void:
	var carte := boite(Color(String(j["carte"])), j, Color(String(j["bord"])))
	th.set_stylebox("panel", "Panel", carte)
	th.set_stylebox("panel", "PanelContainer", carte)


static func _textes(th: Theme, j: Dictionary) -> void:
	th.set_color("font_color", "Label", Color(String(j["texte"])))
	th.set_type_variation("Titre", "Label")
	th.set_font_size("font_size", "Titre", int(j["titre_taille"]))
	th.set_color("font_color", "Titre", Color(String(j["accent"])))
	th.set_type_variation("TexteDoux", "Label")
	th.set_color("font_color", "TexteDoux", Color(String(j["texte_doux"])))
	th.set_type_variation("BoutonDanger", "Button")
	th.set_stylebox("normal", "BoutonDanger", boite(Color(String(j["danger"])), j, Color(String(j["bord"]))))


static func _reglettes(th: Theme, j: Dictionary) -> void:
	var rail := StyleBoxFlat.new()
	rail.bg_color = Color(String(j["bord"]))
	rail.set_corner_radius_all(4)
	rail.content_margin_top = 3
	rail.content_margin_bottom = 3
	var plein := rail.duplicate() as StyleBoxFlat
	plein.bg_color = Color(String(j["accent"]))
	th.set_stylebox("slider", "HSlider", rail)
	th.set_stylebox("grabber_area", "HSlider", plein)
	th.set_stylebox("grabber_area_highlight", "HSlider", plein)
	th.set_color("font_color", "CheckButton", Color(String(j["texte"])))
