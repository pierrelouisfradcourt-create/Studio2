extends VBoxContainer
## La pause : reprendre, son, vibrations, tremblement d'écran, labo et réglages du feel,
## abandonner la descente — avec confirmation (buildPause du web, qui abandonnait d'un seul tap).
## Les réglages se lisent dans `app.reglages` ; l'écran se remet à jour sur `reglages_change`.

signal commande(cmd: Dictionary)
signal action(nom: String, args: Array)

const LARGEUR := 480.0
const POURCENT := 100.0
## Le tremblement d'écran tourne sur trois crans : plein, moitié, coupé.
const CRANS_TREMBLEMENT := [1.0, 0.5, 0.0]
const COUT_DESCENTE := "Abandonner compte comme une mort : Charon prélève sa part de l'or et les bénédictions sont perdues. Équipement, Âmes et checkpoints restent acquis."
const COUT_ESSAI := "Retour à la Ville. Rien n'est en jeu ici : ni or, ni Âmes."

@onready var _menu: VBoxContainer = %Menu
@onready var _confirmation: VBoxContainer = %Confirmation
@onready var _reprendre: Button = %Reprendre
@onready var _son: Button = %Son
@onready var _vibrations: Button = %Vibrations
@onready var _tremblement: Button = %Tremblement
@onready var _labo: Button = %Labo
@onready var _feel: Button = %Feel
@onready var _abandonner: Button = %Abandonner
@onready var _cout: Label = %Cout
@onready var _rester: Button = %Rester
@onready var _confirmer: Button = %Confirmer

var _app: Node

func ouvrir(app: Node, partie: Node) -> void:
	_app = app
	var g: Dictionary = partie.game
	var essai: bool = D6Js.truthy(g.get("sandbox")) or D6Js.truthy(g.get("practice"))
	_cout.text = COUT_ESSAI if essai else COUT_DESCENTE
	_reprendre.pressed.connect(func() -> void: action.emit("reprendre", []))
	_son.pressed.connect(func() -> void: action.emit("regler", ["sound", not _app.reglages.sound]))
	_vibrations.pressed.connect(func() -> void: action.emit("regler", ["haptics", not _app.reglages.haptics]))
	_tremblement.pressed.connect(func() -> void: action.emit("regler", ["shake", _cran_suivant(_app.reglages.shake)]))
	_labo.pressed.connect(func() -> void: action.emit("labo", []))
	_feel.pressed.connect(func() -> void: action.emit("feel", []))
	_abandonner.pressed.connect(_demander.bind(true))
	_rester.pressed.connect(_demander.bind(false))
	_confirmer.pressed.connect(func() -> void: action.emit("abandonner", []))
	rafraichir()

func largeur() -> float:
	return LARGEUR

func premier_focus() -> Control:
	return _reprendre

## Appelé quand un réglage change : les libellés suivent, le focus ne bouge pas.
func rafraichir() -> void:
	var r: Dictionary = _app.reglages
	_son.text = "Son : " + _oui_non(r.sound)
	_vibrations.text = "Vibrations : " + _oui_non(r.haptics)
	_tremblement.text = "Tremblement : %s %%" % D6Js.num_str(roundf(r.shake * POURCENT))

## Montre (ou referme) la confirmation d'abandon.
func _demander(ouverte: bool) -> void:
	_menu.visible = not ouverte
	_confirmation.visible = ouverte
	(_rester if ouverte else _abandonner).grab_focus()

static func _oui_non(v: bool) -> String:
	return "oui" if v else "non"

static func _cran_suivant(v: float) -> float:
	for i in CRANS_TREMBLEMENT.size():
		if v >= CRANS_TREMBLEMENT[i]:
			return CRANS_TREMBLEMENT[(i + 1) % CRANS_TREMBLEMENT.size()]
	return CRANS_TREMBLEMENT[0]
