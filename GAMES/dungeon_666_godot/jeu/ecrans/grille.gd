extends GridContainer
## Une rangée de cartes qui passe en COLONNE quand la largeur manque (portrait, petit écran) :
## toutes côte à côte si elles tiennent à `largeur_min` chacune, sinon l'une sous l'autre.
## Avec `colonnes_max`, une longue liste se range sur ce nombre de colonnes (réglettes).

## Largeur en deçà de laquelle une carte ne se lit plus.
@export var largeur_min := 190.0
## 0 : autant de colonnes que de cartes.
@export var colonnes_max := 0

func _ready() -> void:
	resized.connect(_ranger)
	child_entered_tree.connect(func(_n: Node) -> void: _ranger.call_deferred())
	_ranger()

func _ranger() -> void:
	var n := 0
	for c in get_children():
		if c is Control and c.visible:
			n += 1
	var voulues: int = maxi(1, n if colonnes_max <= 0 else mini(n, colonnes_max))
	var ecart: float = get_theme_constant("h_separation")
	var besoin := voulues * largeur_min + (voulues - 1) * ecart
	var nouvelles := voulues if size.x >= besoin else 1
	if columns != nouvelles:
		columns = nouvelles
