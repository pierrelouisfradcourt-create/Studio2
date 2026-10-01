extends VBoxContainer
## Le labo du feel ouvert depuis la pause (buildLabPanel du web) : il accueille le panneau de la
## Ville (`jeu/ville/panneau_labo.tscn`, le même que dans l'onglet Labo) ; si la Ville n'est pas
## là, un panneau de repli offre les mêmes axes.

signal commande(cmd: Dictionary)
signal action(nom: String, args: Array)

const PANNEAU_VILLE := "res://jeu/ville/panneau_labo.tscn"
const Repli = preload("res://jeu/ecrans/labo_repli.tscn")
const LARGEUR := 620.0

@onready var _hote: VBoxContainer = %Hote
@onready var _retour: Button = %Retour

func ouvrir(app: Node, partie: Node) -> void:
	var panneau: Node
	if ResourceLoader.exists(PANNEAU_VILLE):
		panneau = (load(PANNEAU_VILLE) as PackedScene).instantiate()
	else:
		panneau = Repli.instantiate()
		panneau.choisi.connect(func(axe: String, choix: String) -> void: action.emit("regler_labo", [axe, choix]))
	_hote.add_child(panneau)
	panneau.brancher(app, partie)
	_retour.pressed.connect(func() -> void: action.emit("retour", []))

func largeur() -> float:
	return LARGEUR

func premier_focus() -> Control:
	return _retour
