extends "res://jeu/ville/onglet.gd"
## Sanctuaire : les améliorations permanentes (niveau actuel / maximum, effet par niveau, prix du
## niveau suivant). Le prix vient de D6Profile.upgrade_cost ; null = niveau maximal atteint.

const ACQUIS := "◆"
const A_VENIR := "◇"

@onready var _ameliorations: GridContainer = $Ameliorations

func _dessiner() -> void:
	_vider(_ameliorations)
	var liste: Dictionary = app.contenu.town.upgrades
	for id in liste:
		_carte_amelioration(id, liste[id])

func _carte_amelioration(id: String, a: Dictionary) -> void:
	var cle := "upgrades:%s" % id
	var niveau: float = D6Js.nz(app.profil.upgrades.get(id), 0.0)
	var prix = D6Profile.upgrade_cost(app.contenu, id, niveau)
	var d := {
		"surtitre": "Niveau %s / %s" % [D6Js.num_str(niveau), D6Js.num_str(a.max)],
		"titre": a.name,
		"sous": ACQUIS.repeat(int(niveau)) + A_VENIR.repeat(int(a.max - niveau)),
		"lignes": [a.text],
		"refus": _raison(cle),
	}
	if prix == null:
		d.etat = "equipe"
		d.badge = "Maximum"
		d.boutons = [{"nom": "", "texte": "Maximum", "inactif": true, "cle": cle}]
	else:
		_pied_achat(d, cle, "ameliorer", "Améliorer", prix)
	_carte(_ameliorations, d).action.connect(_sur_amelioration.bind(id))

func _sur_amelioration(nom: String, id: String) -> void:
	if nom == "ameliorer":
		operation_demandee.emit("upgrades:%s" % id, "buy_upgrade", [id])
