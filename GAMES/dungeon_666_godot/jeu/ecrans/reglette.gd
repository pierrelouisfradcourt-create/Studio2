extends VBoxContainer
## Une réglette des « Réglages du feel » : le nom du réglage (en or s'il s'écarte du défaut),
## sa valeur, et le curseur. Elle lit et écrit par l'état (jeu/ecrans/feel.gd).

signal reglee(r: Dictionary)

@onready var _nom: Label = %Nom
@onready var _valeur: Label = %Valeur
@onready var _curseur: HSlider = %Curseur

var _r: Dictionary
var _etat: RefCounted
var _muette := false # vrai pendant qu'on pose la valeur lue : ce n'est pas un geste du testeur

func decrire(r: Dictionary, etat: RefCounted) -> void:
	_r = r
	_etat = etat
	_nom.text = r.label
	_curseur.min_value = r.min
	_curseur.max_value = r.max
	_curseur.step = r.step
	_curseur.editable = etat.disponible()
	_curseur.value_changed.connect(_sur_curseur)
	relire()

## Remet le curseur et le texte sur la valeur de la partie (après « Réinitialiser »).
func relire() -> void:
	_muette = true
	_curseur.value = _etat.valeur(_r)
	_muette = false
	_afficher()

func curseur() -> HSlider:
	return _curseur

func _sur_curseur(v: float) -> void:
	if _muette:
		return
	_etat.regler(_r, v)
	_afficher()
	reglee.emit(_r)

func _afficher() -> void:
	_valeur.text = _etat.texte_valeur(_r, _etat.valeur(_r))
	_nom.theme_type_variation = &"ReglageChange" if _etat.a_change(_r) else &"Reglage"
