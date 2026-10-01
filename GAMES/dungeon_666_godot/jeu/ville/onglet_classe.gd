extends "res://jeu/ville/onglet.gd"
## Classe : les classes du jeu (texte, passif chiffré, armes, Super) ; équipée, à choisir, ou à
## débloquer en Âmes.

@onready var _classes: GridContainer = $Classes

func _dessiner() -> void:
	_vider(_classes)
	for id in app.contenu.classes:
		_carte_classe(id, app.contenu.classes[id])

func _carte_classe(id: String, c: Dictionary) -> void:
	var lignes: Array = [c.text]
	var passif = c.get("passive")
	if passif is Dictionary:
		lignes.append("Passif · %s : %s" % [passif.name, passif.text])
	var armes: Array = c.weapons.map(func(w): return _nom(app.contenu.weapons, w))
	lignes.append({"texte": "Armes : %s" % ", ".join(PackedStringArray(armes)), "genre": "TexteDoux"})
	var d := {"surtitre": "Super : %s" % _nom(app.contenu.supers, c.super), "titre": c.name, "lignes": lignes}
	_pied_contenu(d, "classes", id, app.profil.loadout.classId == id)
	_carte(_classes, d).action.connect(_sur_contenu.bind("classes", id, "select_class"))
