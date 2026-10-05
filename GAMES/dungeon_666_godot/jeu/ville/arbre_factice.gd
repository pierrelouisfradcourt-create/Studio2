extends RefCounted
## Un arbre FACTICE, plus chargé que celui des données, pour éprouver la mise en page du Grimoire
## (banc jeu/ville/banc_arbre.tscn, essai jeu/ville/test_ville.gd) : la vue rendue par les règles
## (D6Profile.tree_view), dont chaque étage est complété jusqu'à `par_etage` nœuds par des COPIES de
## ses nœuds (identifiants et noms distincts, états variés). Rien de cela n'existe dans le jeu :
## on ne l'achète pas, on le regarde.

const ETATS := [
	{"rank": 0.0, "canBuy": true, "reason": ""},
	{"rank": 2.0, "canBuy": true, "reason": ""},
	{"rank": 0.0, "canBuy": false, "reason": "aucun point à dépenser"},
]

## `vue` : ce que rend tree_view (elle n'est pas modifiée) ; rend la vue gonflée.
static func gonfler(vue: Dictionary, par_etage: int) -> Dictionary:
	var v: Dictionary = vue.duplicate(true)
	for etage: Dictionary in v.tiers:
		var modeles: Array = etage.nodes.duplicate()
		var k := 0
		while not modeles.is_empty() and etage.nodes.size() < par_etage:
			etage.nodes.append(_copie(modeles[k % modeles.size()], k, etage.open))
			k += 1
		etage.nodes = etage.nodes.slice(0, maxi(par_etage, 1)) if etage.nodes.size() > par_etage else etage.nodes
	return v

static func _copie(modele: Dictionary, rang: int, ouvert: bool) -> Dictionary:
	var n: Dictionary = modele.duplicate(true)
	n.id = "%s_copie%d" % [modele.id, rang]
	n.name = "%s (copie %d)" % [modele.name, rang + 1]
	n.free = false
	var etat: Dictionary = ETATS[rang % ETATS.size()]
	n.rank = minf(etat.rank, n.maxRank - 1.0)
	n.canBuy = etat.canBuy and ouvert
	n.reason = etat.reason if ouvert else modele.reason
	for ch: Dictionary in n.choices:
		ch.taken = false
		ch.canTake = false
	return n
