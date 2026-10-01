extends VBoxContainer
## Un axe du labo du feel (D5, D8 ou D9) : son libellé, et une option par variante — un bouton à
## bascule (la variante de RÉFÉRENCE est signalée) et le texte de la variante dessous.

signal choisi(axe: String, choix: String)

const Style = preload("res://jeu/theme/theme.gd")
const REFERENCE := "%s  ·  référence"

@onready var _titre: Label = $Tete/Titre
@onready var _choix: Label = $Tete/Choix
@onready var _options: GridContainer = $Options

var _axe := ""
var _definition: Dictionary = {}
var _boutons: Dictionary = {} # variante -> Button

## `definition` : une entrée de D6Data.tables().lab.LAB_AXES ({label, reference, options}).
func decrire(axe: String, definition: Dictionary) -> void:
	_axe = axe
	_definition = definition
	_titre.text = definition.label
	for id in definition.options:
		_options.add_child(_option(id, definition.options[id], id == definition.reference))

func _option(id: String, option: Dictionary, reference: bool) -> Control:
	var bloc := VBoxContainer.new()
	bloc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b := Button.new()
	b.text = REFERENCE % option.label if reference else String(option.label)
	b.toggle_mode = true
	b.theme_type_variation = &"Onglet"
	b.custom_minimum_size = Vector2(0.0, Style.CIBLE)
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.set_meta("axe", _axe)
	b.set_meta("choix", id)
	b.pressed.connect(_sur_option.bind(id))
	bloc.add_child(b)
	var texte := Label.new()
	texte.text = option.get("text", "")
	texte.theme_type_variation = &"TexteDoux"
	texte.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bloc.add_child(texte)
	_boutons[id] = b
	return bloc

## Montre la variante en cours (bouton enfoncé, rappel à côté du titre).
func montrer(choix: String) -> void:
	for id in _boutons:
		_boutons[id].set_pressed_no_signal(id == choix)
	var option = _definition.options.get(choix)
	_choix.text = String(option.label) if option is Dictionary else ""

func bouton(choix: String) -> Button:
	return _boutons.get(choix)

func _sur_option(id: String) -> void:
	choisi.emit(_axe, id)
