extends "res://jeu/ville/onglet.gd"
## Armurerie : les types d'arme de la classe équipée ; forger (débloquer) un type, ou prendre au
## coffre l'exemplaire possédé. L'arme portée est rappelée en bas.

const NOTE := "Armes du %s. Débloquer un type d'arme forge un exemplaire commun (rangé au coffre) et l'ajoute au butin du donjon."
const STYLES := {"ranged": "Arme à distance", "melee": "Arme de mêlée"}
const AUCUN_EXEMPLAIRE := "Aucun exemplaire au coffre."

@onready var _note: Label = $Note
@onready var _armes: GridContainer = $Armes
@onready var _titre_portee: Label = $TitrePortee
@onready var _portee: GridContainer = $Portee

func _dessiner() -> void:
	var c: Dictionary = app.contenu.classes[app.profil.loadout.classId]
	_note.text = NOTE % c.name
	_vider(_armes)
	for type in c.weapons:
		if app.contenu.weapons.has(type):
			_carte_arme(type, app.contenu.weapons[type])
	_vider(_portee)
	var portee = app.profil.equipment.get("arme")
	_titre_portee.visible = portee != null
	if portee != null:
		var d := _fiche_objet(portee, _nom(app.contenu.weapons, _type_arme(portee)))
		d.etat = "equipe"
		d.badge = "● Portée"
		_carte(_portee, d)

func _carte_arme(type: String, arme: Dictionary) -> void:
	var cle := "weapons:%s" % type
	var d := {"surtitre": STYLES.get(arme.kind, STYLES.melee), "titre": arme.name, "lignes": [arme.get("text", "")], "refus": _raison(cle)}
	var exemplaire = _meilleur_exemplaire(type)
	if not app.profil.unlocked.weapons.has(type):
		_pied_achat(d, cle, "debloquer", "Forger", D6Profile.unlock_cost(app.contenu, "weapons", type))
		d.etat = "verrouille"
	elif _type_arme(app.profil.equipment.get("arme")) == type:
		d.etat = "equipe"
		d.badge = "● Portée"
		d.boutons = [{"nom": "", "texte": "Portée", "inactif": true, "cle": cle}]
	else:
		d.boutons = [{"nom": "equiper", "texte": "Prendre la meilleure", "genre": "primaire", "inactif": exemplaire == null, "cle": cle}]
		if exemplaire == null:
			d.lignes.append({"texte": AUCUN_EXEMPLAIRE, "genre": "Note"})
	_carte(_armes, d).action.connect(_sur_arme.bind(type, exemplaire))

## L'exemplaire de ce type le mieux noté du coffre (null s'il n'y en a pas).
func _meilleur_exemplaire(type: String):
	var meilleur = null
	for objet in app.profil.stash:
		if objet.get("slot") != "arme" or _type_arme(objet) != type:
			continue
		if meilleur == null or D6Js.nz(objet.get("score"), 0.0) > D6Js.nz(meilleur.get("score"), 0.0):
			meilleur = objet
	return meilleur

func _sur_arme(nom: String, type: String, exemplaire) -> void:
	var cle := "weapons:%s" % type
	if nom == "debloquer":
		operation_demandee.emit(cle, "unlock", ["weapons", type])
	elif nom == "equiper" and exemplaire != null:
		operation_demandee.emit(cle, "equip_from_stash", [exemplaire.get("uid")])
