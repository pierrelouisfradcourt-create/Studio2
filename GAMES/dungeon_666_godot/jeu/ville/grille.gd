extends GridContainer
## Grille qui SE REPLIE : autant de colonnes que la largeur en accepte (au moins une), chaque
## colonne faisant au moins `largeur_mini`. 3 cartes de front en paysage, 1 ou 2 en portrait.

@export var largeur_mini := 240.0
@export var colonnes_max := 4

func _ready() -> void:
	resized.connect(_replier)
	_replier()

func _replier() -> void:
	var ecart := float(get_theme_constant("h_separation"))
	var n := int((size.x + ecart) / (largeur_mini + ecart))
	var voulu := clampi(n, 1, colonnes_max)
	if columns != voulu:
		columns = voulu
