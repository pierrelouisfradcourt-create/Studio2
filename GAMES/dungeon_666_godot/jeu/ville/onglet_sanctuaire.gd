extends "res://jeu/ville/onglet.gd"
## Sanctuaire : les améliorations permanentes (niveau actuel / maximum, effet par niveau, effet
## CUMULÉ au niveau actuel, prix du niveau suivant). Le prix vient de D6Profile.upgrade_cost ;
## null = niveau maximal atteint.

const ACQUIS := "◆"
const A_VENIR := "◇"
const ACTUEL := "Actuel : %s"
const SANS_EFFET := "Actuel : aucun effet"
const PAR_NIVEAU := " par niveau"
const POURCENT := 100.0

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
		"lignes": [{"texte": ACQUIS.repeat(int(niveau)) + A_VENIR.repeat(int(a.max - niveau)), "genre": "Ames"}, a.text, _ligne_actuelle(a, niveau)],
		"refus": _raison(cle),
	}
	if prix == null:
		d.etat = "equipe"
		d.badge = "Maximum"
		d.boutons = [{"nom": "", "texte": "Maximum", "inactif": true, "cle": cle}]
	else:
		_pied_achat(d, cle, "ameliorer", "Améliorer", prix)
	_carte(_ameliorations, d).action.connect(_sur_amelioration.bind(id))

## La ligne « Actuel : +20 PV max » : ce que l'amélioration donne DÉJÀ, au niveau du profil.
func _ligne_actuelle(a: Dictionary, niveau: float) -> Dictionary:
	if niveau <= 0.0:
		return {"texte": SANS_EFFET, "genre": "TexteDoux"}
	return {"texte": ACTUEL % _effet_cumule(a, niveau), "genre": "Valeur"}

## L'effet cumulé (`perLevel` × niveau), écrit dans la forme du texte de l'amélioration :
## « +10 PV max par niveau. » au niveau 2 donne « +20 PV max » ; une part (0,06) se lit en %.
## De l'affichage seulement : la règle, elle, est dans sim/stats.gd.
func _effet_cumule(a: Dictionary, niveau: float) -> String:
	var par_niveau: float = absf(a.perLevel)
	var total := par_niveau * niveau
	var nombre: String = D6Js.num_str(snappedf(total * POURCENT, 0.1) if par_niveau < 1.0 else total)
	var texte := String(a.text)
	var trouve := RegEx.create_from_string("[0-9]+(?:[.,][0-9]+)?").search(texte)
	if trouve == null:
		return nombre
	texte = texte.substr(0, trouve.get_start()) + nombre + texte.substr(trouve.get_end())
	return texte.replace(PAR_NIVEAU, "").trim_suffix(".")

func _sur_amelioration(nom: String, id: String) -> void:
	if nom == "ameliorer":
		operation_demandee.emit("upgrades:%s" % id, "buy_upgrade", [id])
