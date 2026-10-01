extends "res://jeu/ville/onglet.gd"
## Coffre : l'équipement porté (arme, armure, talisman) et les objets rangés. Chaque objet montre
## sa rareté (couleur du bandeau et du nom), son niveau et ses affixes ; on l'équipe (il échange
## sa place avec l'objet porté) ou on le recycle en Âmes — en deux appuis, car c'est sans retour.

const TITRE_COFFRE := "Coffre (%s / %s)"
const AUTRE_CLASSE := "Arme réservée à une autre classe (%s)."

@onready var _porte: GridContainer = $Porte
@onready var _titre_coffre: Label = $TitreCoffre
@onready var _vide: Label = $Vide
@onready var _objets: GridContainer = $Objets

## Identifiant de l'objet dont le recyclage attend sa confirmation ("" : aucun).
var _a_confirmer := ""

func _ready() -> void:
	visibility_changed.connect(_oublier_confirmation)

func _dessiner() -> void:
	var tables: Dictionary = D6Data.tables()
	_vider(_porte)
	for emplacement in tables.profile.EQUIP_SLOTS:
		var d := _fiche_objet(app.profil.equipment.get(emplacement), tables.loot.SLOT_NAMES.get(emplacement, emplacement))
		if d.get("etat", "") == "":
			d.etat = "equipe"
			d.badge = "● Porté"
		_carte(_porte, d)
	var rang: Array = app.profil.stash.duplicate()
	rang.sort_custom(func(a, b): return D6Js.nz(a.get("score"), 0.0) > D6Js.nz(b.get("score"), 0.0))
	_titre_coffre.text = TITRE_COFFRE % [rang.size(), D6Js.num_str(tables.profile.STASH_MAX)]
	_vide.visible = rang.is_empty()
	_vider(_objets)
	for objet in rang:
		_carte_objet(objet)

func _carte_objet(objet: Dictionary) -> void:
	var uid := String(objet.get("uid", ""))
	var cle := "objet:%s" % uid
	var arme: bool = objet.slot == "arme"
	var genre: String = D6Data.tables().loot.SLOT_NAMES.get(objet.slot, objet.slot)
	var d := _fiche_objet(objet, "%s · %s" % [genre, _nom(app.contenu.weapons, _type_arme(objet))] if arme else genre)
	d.refus = _raison(cle)
	var maniable: bool = not arme or app.contenu.classes[app.profil.loadout.classId].weapons.has(_type_arme(objet))
	if not maniable:
		d.lignes.append({"texte": AUTRE_CLASSE % _classe_de(_type_arme(objet)), "genre": "TexteDoux"})
	var gain := _ames(D6Profile.salvage_souls(app.contenu, objet))
	var confirme := _a_confirmer == uid
	d.boutons = [
		{"nom": "equiper", "texte": "Équiper" if maniable else "Autre classe", "genre": "principal" if maniable else "", "inactif": not maniable, "cle": cle},
		{"nom": "recycler", "texte": ("Confirmer · %s" if confirme else "Recycler · %s") % gain, "genre": "danger" if confirme else "", "cle": cle + ":recycler"},
	]
	_carte(_objets, d).action.connect(_sur_objet.bind(uid))

## Nom de la classe qui manie ce type d'arme.
func _classe_de(type: String) -> String:
	for id in app.contenu.classes:
		if app.contenu.classes[id].weapons.has(type):
			return app.contenu.classes[id].name
	return "?"

func _sur_objet(nom: String, uid: String) -> void:
	var cle := "objet:%s" % uid
	if nom == "recycler" and _a_confirmer != uid:
		_a_confirmer = uid
		dessin_demande.emit()
		return
	_a_confirmer = ""
	if nom == "equiper":
		operation_demandee.emit(cle, "equip_from_stash", [uid])
	elif nom == "recycler":
		operation_demandee.emit(cle, "salvage_from_stash", [uid])

func _oublier_confirmation() -> void:
	_a_confirmer = ""
