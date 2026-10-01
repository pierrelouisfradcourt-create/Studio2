extends VBoxContainer
## Les « Réglages du feel » (portage de buildTuningPanel, src/ui/tuning.mjs) : une réglette par
## réglage de jeu/ecrans/feel.gd, sa valeur, « Réinitialiser », « Copier les réglages » (les
## écarts au défaut, en JSON, dans le presse-papiers). L'écriture dans `game.tuning` passe par
## `etat` (feel.gd), le seul à y avoir droit.

signal commande(cmd: Dictionary)
signal action(nom: String, args: Array)

const Ligne = preload("res://jeu/ecrans/reglette.tscn")
const LARGEUR := 760.0
const COPIER := "Copier les réglages"
const COPIE := "Copié"
const RIEN_A_COPIER := "Aucun changement"

@onready var _fermer: Button = %Fermer
@onready var _copier: Button = %Copier
@onready var _reinitialiser: Button = %Reinitialiser
@onready var _liste: GridContainer = %Liste

## L'état des réglages (jeu/ecrans/feel.gd), posé par Ecrans avant `ouvrir`.
var etat: RefCounted

func ouvrir(_app: Node, _partie: Node) -> void:
	for r in etat.REGLAGES:
		var ligne := Ligne.instantiate()
		_liste.add_child(ligne)
		ligne.decrire(r, etat)
		ligne.reglee.connect(_sur_reglee)
	_fermer.pressed.connect(func() -> void: action.emit("retour", []))
	_copier.pressed.connect(_copier_ecarts)
	_reinitialiser.pressed.connect(_tout_remettre)

func largeur() -> float:
	return LARGEUR

func premier_focus() -> Control:
	return _fermer

func _sur_reglee(_r: Dictionary) -> void:
	_copier.text = COPIER

func _copier_ecarts() -> void:
	DisplayServer.clipboard_set(etat.texte_ecarts())
	_copier.text = RIEN_A_COPIER if etat.ecarts.is_empty() else COPIE

func _tout_remettre() -> void:
	etat.reinitialiser()
	for ligne in _liste.get_children():
		ligne.relire()
	_copier.text = COPIER
