extends RefCounted
## Petites fabriques des écrans : un bouton à la taille du doigt, une étiquette qui passe à la
## ligne. Le style vient du thème (variations de jeu/ecrans/styles.gd), jamais d'ici.

## Hauteur minimale d'une cible tactile (px de la résolution de référence).
const CIBLE := 48.0
const CIBLE_PETITE := 44.0

static func bouton(texte: String, variation: StringName = &"", desactive: bool = false) -> Button:
	var b := Button.new()
	b.text = texte
	b.disabled = desactive
	if variation != &"":
		b.theme_type_variation = variation
	var petit := String(variation).begins_with("BoutonPetit")
	b.custom_minimum_size = Vector2(0.0, CIBLE_PETITE if petit else CIBLE)
	b.focus_mode = Control.FOCUS_NONE if desactive else Control.FOCUS_ALL
	return b

## Bouton d'une colonne étroite : un libellé long passe à la ligne au lieu d'élargir le panneau.
static func bouton_long(texte: String, variation: StringName = &"", desactive: bool = false) -> Button:
	var b := bouton(texte, variation, desactive)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return b

static func etiquette(texte: String, variation: StringName = &"", centre: bool = false) -> Label:
	var l := Label.new()
	l.text = texte
	if variation != &"":
		l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if centre:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

## Couleur d'une donnée de la simulation (« #ff5a3c ») ; `defaut` si elle manque.
static func couleur(valeur, defaut: Color) -> Color:
	return Color(String(valeur)) if valeur is String and valeur != "" else defaut
