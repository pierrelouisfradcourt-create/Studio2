extends "res://jeu/ville/onglet.gd"
## Portail : descendre depuis le dernier checkpoint, se téléporter vers un checkpoint ouvert,
## arène d'essai, et entraînement contre un Gardien déjà rencontré.

const NOTE_GARDIENS := "Rejouer un Gardien déjà rencontré, sans récompense ni risque."
const AUCUN_GARDIEN := "Aucun Gardien rencontré : le premier que vous affronterez pourra être défié ici, sans enjeu."

@onready var _checkpoints: GridContainer = $Checkpoints
@onready var _arene: Button = $Essai/Arene
@onready var _note_gardiens: Label = $NoteGardiens
@onready var _gardiens: HFlowContainer = $Gardiens

func _ready() -> void:
	_arene.set_meta("cle", "arene")
	_arene.pressed.connect(_sur_arene)

func _dessiner() -> void:
	_vider(_checkpoints)
	var etages: Array = app.profil.checkpoints.duplicate()
	etages.sort()
	etages.reverse()
	for i in etages.size():
		_carte_checkpoint(etages[i], i == 0)
	_dessiner_gardiens()

func _carte_checkpoint(etage: float, dernier: bool) -> void:
	var info: Dictionary = D6Floors.floor_info(app.contenu, etage)
	var bornes: Dictionary = D6Floors.section_bounds(app.contenu, info.section)
	var gardien := _nom(app.contenu.boss, D6Floors.guardian_for(app.contenu, info.section))
	var carte := _carte(_checkpoints, {
		"surtitre": "Dernier checkpoint" if dernier else "Téléportation",
		"titre": "Étage %s" % D6Js.num_str(etage),
		"sous": "%s · section %s / %s" % [_cercle(info), D6Js.num_str(info.section), D6Js.num_str(info.sectionCount)],
		"lignes": ["Gardien de la section : %s (étage %s)" % [gardien, D6Js.num_str(bornes.guardian)]],
		"accent": Style.accent("") if dernier else Style.accent("verrouille"),
		"boutons": [{
			"nom": "partir", "texte": "Descendre" if dernier else "Se téléporter",
			"genre": "principal" if dernier else "", "cle": "depart:%s" % D6Js.num_str(etage),
		}],
	})
	carte.action.connect(_sur_depart.bind(etage))

func _cercle(info: Dictionary) -> String:
	if info.inFinale:
		return String(info.circleName)
	return "Cercle %s · %s" % [D6Js.num_str(info.circle), info.circleName]

func _dessiner_gardiens() -> void:
	_vider(_gardiens)
	for modele in app.contenu.boss:
		if D6Js.nz(app.profil.guardians.get(modele), 0.0) <= 0.0:
			continue
		var b := Button.new()
		b.text = "Défier %s" % _nom(app.contenu.boss, modele)
		b.custom_minimum_size = Vector2(0.0, Style.CIBLE)
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.set_meta("cle", "gardien:%s" % modele)
		b.pressed.connect(_sur_defi.bind(modele))
		_gardiens.add_child(b)
	var rencontres := _gardiens.get_child_count() > 0
	_gardiens.visible = rencontres
	_note_gardiens.text = NOTE_GARDIENS if rencontres else AUCUN_GARDIEN

func _sur_depart(_nom_action: String, etage: float) -> void:
	app.demarrer_descente(etage)

func _sur_arene() -> void:
	app.demarrer_descente(1.0, true)

func _sur_defi(modele: String) -> void:
	app.demarrer_entrainement(modele)
