extends PanelContainer
## La carte des écrans de choix : bandeau de la couleur d'accent, sur-titre, titre, sous-titre,
## texte, lignes (affixes d'un objet), et un pied libre (un bouton « Acheter »).
## Deux usages : carte À CHOISIR (toute la carte est un bouton : survol, appui, focus, grisé) ou
## carte À LIRE (objet porté, récapitulatif). Elle n'affiche que ce qu'on lui donne.

signal choisie

const OPACITE_GRISEE := 0.45
const PUCE := "•  "
const ETOILE := "★  "

@onready var _fond: Button = %Fond
@onready var _colonne: VBoxContainer = %Colonne
@onready var _bandeau: ColorRect = %Bandeau
@onready var _sur_titre: Label = %SurTitre
@onready var _titre: Label = %Titre
@onready var _sous_titre: Label = %SousTitre
@onready var _texte: Label = %Texte
@onready var _lignes: VBoxContainer = %Lignes
@onready var _ressort: Control = %Ressort
@onready var _pied: VBoxContainer = %Pied

func _ready() -> void:
	_fond.pressed.connect(func() -> void: choisie.emit())

## `d` : {accent: Color, sur_titre, sur_titre_neutre: bool, titre, couleur_titre: Color,
## sous_titre, texte, lignes: Array[String], pouvoir, a_choisir: bool, grisee: bool}.
## Toute clé est facultative ; un champ vide ne prend pas de place.
func remplir(d: Dictionary) -> void:
	var accent: Color = d.get("accent", _sur_titre.get_theme_color("font_color"))
	_bandeau.color = accent
	_ecrire(_sur_titre, String(d.get("sur_titre", "")).to_upper())
	if not d.get("sur_titre_neutre", false):
		_sur_titre.add_theme_color_override("font_color", accent)
	_ecrire(_titre, String(d.get("titre", "")))
	if d.has("couleur_titre"):
		_titre.add_theme_color_override("font_color", d.couleur_titre)
	_ecrire(_sous_titre, String(d.get("sous_titre", "")))
	_ecrire(_texte, String(d.get("texte", "")))
	for ligne in d.get("lignes", []):
		_ajouter_ligne(PUCE + String(ligne), &"Affixe")
	if String(d.get("pouvoir", "")) != "":
		_ajouter_ligne(ETOILE + String(d.pouvoir), &"Pouvoir")
	_fond.visible = d.get("a_choisir", false)
	theme_type_variation = &"PanneauNu" if _fond.visible else &"Carte" # le bouton fait alors le fond
	griser(d.get("grisee", false))

## Carte grisée : lisible, mais on ne peut pas la choisir.
func griser(grisee: bool) -> void:
	_fond.disabled = grisee
	_fond.focus_mode = Control.FOCUS_NONE if grisee else Control.FOCUS_ALL
	_colonne.modulate.a = OPACITE_GRISEE if grisee else 1.0
	_bandeau.modulate.a = OPACITE_GRISEE if grisee else 1.0

## Le bouton de la carte (focus, essais) : celui de son fond si elle est à choisir.
func bouton() -> Button:
	return _fond

## Ajoute un nœud au pied de la carte (bouton d'achat), calé en bas.
func ajouter_au_pied(n: Control) -> void:
	_ressort.visible = true
	_pied.visible = true
	_pied.add_child(n)

func _ecrire(etiquette: Label, texte: String) -> void:
	etiquette.text = texte
	etiquette.visible = texte != ""

func _ajouter_ligne(texte: String, variation: StringName) -> void:
	var l := Label.new()
	l.text = texte
	l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lignes.add_child(l)
	_lignes.visible = true
