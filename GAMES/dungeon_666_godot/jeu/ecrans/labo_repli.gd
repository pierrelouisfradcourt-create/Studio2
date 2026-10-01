extends VBoxContainer
## Panneau de REPLI du labo du feel, quand celui de la Ville manque : les axes de
## D6Data.tables().lab.LAB_AXES (D5, D8, D9), un bouton par variante, le texte de la variante
## choisie dessous (buildLabControls du web). Il ne règle rien lui-même : il émet `choisi`.

signal choisi(axe: String, choix: String)

const Fabrique = preload("res://jeu/ecrans/fabrique.gd")
const ECART := 10

var _app: Node
var _boutons := {} # axe -> {variante -> Button}
var _textes := {} # axe -> Label

func brancher(app: Node, _partie: Node) -> void:
	_app = app
	var axes: Dictionary = D6Data.tables().lab.LAB_AXES
	for axe in axes:
		_poser_axe(axe, axes[axe])
	app.reglages_change.connect(_montrer)
	_montrer()

func _poser_axe(axe: String, definition: Dictionary) -> void:
	add_child(Fabrique.etiquette(String(definition.label), &"TitreSection"))
	var rangee := HFlowContainer.new()
	rangee.add_theme_constant_override("h_separation", ECART)
	rangee.add_theme_constant_override("v_separation", ECART)
	add_child(rangee)
	_boutons[axe] = {}
	for choix in definition.options:
		var b := Fabrique.bouton(String(definition.options[choix].label), &"BoutonPetit")
		b.pressed.connect(func() -> void: choisi.emit(axe, choix))
		rangee.add_child(b)
		_boutons[axe][choix] = b
	_textes[axe] = Fabrique.etiquette("", &"Petit")
	add_child(_textes[axe])

## La variante retenue de chaque axe porte le bouton principal ; son texte est dessous.
func _montrer() -> void:
	var axes: Dictionary = D6Data.tables().lab.LAB_AXES
	for axe in _boutons:
		var retenu = _app.reglages.lab.get(axe)
		for choix in _boutons[axe]:
			_boutons[axe][choix].theme_type_variation = &"BoutonPetitPrincipal" if choix == retenu else &"BoutonPetit"
		var option = axes[axe].options.get(retenu)
		_textes[axe].text = String(option.text) if option is Dictionary else ""
