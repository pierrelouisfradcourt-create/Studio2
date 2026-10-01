extends VBoxContainer
## Le panneau du labo du feel, RÉUTILISABLE (onglet de la Ville, écran de pause) : les axes D5,
## D8 et D9 de D6Data.tables().lab.LAB_AXES, une option par variante. Chaque option appelle
## `app.regler_labo(axe, choix)` ; le panneau se met à jour sur `app.reglages_change`.
##
##   var panneau := preload("res://jeu/ville/panneau_labo.tscn").instantiate()
##   conteneur.add_child(panneau)      # il porte son thème : rien d'autre à poser
##   panneau.brancher(app, partie)
##
## Racine : un VBoxContainer (donc un Control) ; sa hauteur minimale suit son contenu, à placer
## dans un conteneur ou un ScrollContainer. Aucune règle ici : la table décrit, l'app applique.

const Axe = preload("res://jeu/ville/axe_labo.tscn")
const Style = preload("res://jeu/ville/style_ville.gd")

var _app: Node
var _axes: Dictionary = {} # axe -> nœud AxeLabo

func _ready() -> void:
	theme = Style.theme()

func brancher(app: Node, _partie: Node) -> void:
	if _app != null:
		return
	_app = app
	var table: Dictionary = D6Data.tables().lab.LAB_AXES
	for axe in table:
		var n := Axe.instantiate()
		add_child(n)
		n.decrire(axe, table[axe])
		n.choisi.connect(_sur_choix)
		_axes[axe] = n
	app.reglages_change.connect(_actualiser)
	_actualiser()

## Le bouton de la variante `choix` de l'axe `axe` (null si inconnu) : pour le focus et les essais.
func bouton(axe: String, choix: String) -> Button:
	return _axes[axe].bouton(choix) if _axes.has(axe) else null

func _actualiser() -> void:
	for axe in _axes:
		_axes[axe].montrer(String(_app.reglages.lab.get(axe, "")))

func _sur_choix(axe: String, choix: String) -> void:
	_app.regler_labo(axe, choix)
	_actualiser()
