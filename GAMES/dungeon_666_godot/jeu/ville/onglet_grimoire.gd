extends "res://jeu/ville/onglet.gd"
## Grimoire : les compétences et les gadgets de la classe équipée (équipé, à choisir, à débloquer),
## et le Super de la classe, rappelé (il ne se choisit pas : il vient avec la classe).

## Le texte nomme ce qui est RÉELLEMENT équipé (lu dans le profil), jamais une compétence en dur.
const NOTE := "%s — compétence équipée : %s ; gadget équipé : %s (charges par section)."

@onready var _note: Label = $Note
@onready var _competences: GridContainer = $Competences
@onready var _gadgets: GridContainer = $Gadgets
@onready var _super: GridContainer = $Super

func _dessiner() -> void:
	var c: Dictionary = app.contenu.classes[app.profil.loadout.classId]
	_note.text = NOTE % [c.name, _nom(app.contenu.skills, app.profil.loadout.skillId), _nom(app.contenu.gadgets, app.profil.loadout.gadgetId)]
	_lister(_competences, "skills", "Compétence", c.skills, app.profil.loadout.skillId, "select_skill")
	_lister(_gadgets, "gadgets", "Gadget", c.gadgets, app.profil.loadout.gadgetId, "select_gadget")
	_vider(_super)
	var s = app.contenu.supers.get(c.super)
	if s is Dictionary:
		_carte(_super, {"surtitre": "Super du %s" % c.name, "titre": s.name, "lignes": [s.get("text", "")], "etat": "equipe", "badge": "Lié à la classe"})

func _lister(grille: GridContainer, genre: String, surtitre: String, ids: Array, equipe, op_choisir: String) -> void:
	_vider(grille)
	for id in ids:
		var entree = app.contenu[genre].get(id)
		if not (entree is Dictionary):
			continue
		var d := {"surtitre": surtitre, "titre": entree.name, "lignes": [entree.get("text", "")]}
		_pied_contenu(d, genre, id, equipe == id)
		_carte(grille, d).action.connect(_sur_contenu.bind(genre, id, op_choisir))
