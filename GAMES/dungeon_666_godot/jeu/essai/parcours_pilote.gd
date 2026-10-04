extends RefCounted
## Le PILOTE du test de parcours (jeu/essai/test_parcours.gd) : il tient la manette du vrai jeu.
## Il ne réécrit pas un joueur : il donne la main au bot « skilled » de outils/bots/ (une entrée
## par pas, ce qu'un joueur VOIT), et répond aux menus par `app.commande`, la porte des écrans.
## Il compte ce qui s'est réellement passé (événements de la simulation), pour que le test puisse
## refuser un parcours qui n'a rien joué.
##
## Ce qu'il ajoute au bot :
##   - il préfère la porte qui mène à une sorte de menu pas encore traversée (mem.wantRewards) ;
##   - butin : il équipe si le bot le ferait, sinon il RANGE au coffre (le bot recyclerait) ;
##   - marchand : il achète la première offre à sa portée, une fois, puis s'en va ;
##   - chambre forte : il prend l'objet ; fontaine : il médite s'il a une bénédiction, sinon il boit ;
##   - `vers_la_ville` : il prend le portail de la Ville quand un Gardien vaincu l'ouvre ;
##   - `inerte` : il lâche les commandes dès qu'un combat est en cours (il se laisse tuer).

const Bots = preload("res://outils/bots/bots.gd")

const POLITIQUE := "skilled"
## Les sortes de menu que le parcours doit traverser (porte = sorte du menu).
const SORTES_VOULUES := ["boon", "loot", "shop", "event", "treasure", "rest"]
## Menus des salles calmes : l'option préférée, puis les autres dans l'ordre du panneau.
const OPTIONS_PREFEREES := {"treasure": "objet", "rest": "mediter"}

var app: Node
var inerte := false
var vers_la_ville := false
## Les sortes que CETTE descente cherche (une halte n'en offre qu'une sur deux : le test répartit).
var voulues: Array = SORTES_VOULUES
## salles nettoyées, Gardiens vaincus, étages entrés, étage le plus profond, morts, pas joués, menus
## ouverts par sorte, commandes de menu acceptées par type, événements de simulation par type.
var compte := {"salles": 0, "gardiens": 0, "etages": 0, "etage_max": 0.0, "morts": 0, "pas": 0, "choix": {}, "commandes": {}, "evenements": {}}

## Le dernier événement « checkpoint » publié (étage ouvert, Gardien, Âmes de sa prime).
var dernier_checkpoint := {}

var _mem := {}

func _init(p_app: Node) -> void:
	app = p_app
	app.partie.entrees = entree
	app.partie.partie_demarree.connect(_sur_partie)
	app.partie.evenements.connect(_sur_evenements)

## L'entrée d'un pas de simulation (branchée sur `partie.entrees`, à la place du joueur).
func entree() -> Dictionary:
	var g: Dictionary = app.partie.game
	compte.pas += 1
	var vue = app.vues.get("entrees")
	if vue != null:
		vue.lire() # la vraie lecture tourne à chaque pas ; sa trame (vide, personne ne touche) est écartée
	if inerte and not D6Js.truthy(g.room.get("cleared")):
		return D6Game.empty_input()
	_mem.wantRewards = sortes_manquantes()
	_mem.wantTown = vers_la_ville
	return Bots.play(POLITIQUE, g, _mem)

## Les sortes voulues par cette descente que le pilote n'a pas encore traversées.
func sortes_manquantes() -> Array:
	return voulues.filter(func(s: String) -> bool: return not compte.choix.has(s))

## Nombre d'événements de simulation de ce type vus depuis le début.
func vus(type: String) -> int:
	return compte.evenements.get(type, 0)

## Répond au menu ouvert par `app.commande` : essaie les commandes dans l'ordre, la première
## acceptée gagne. Rend {sorte, type, option, ok} (`option` : l'identifiant de l'option choisie
## dans une salle calme, "" ailleurs).
func repondre_au_menu() -> Dictionary:
	var sorte: String = app.partie.game.choice.kind
	var options: Array = app.partie.game.choice.get("options", [])
	for cmd in _commandes_du_menu():
		if app.commande(cmd):
			compte.commandes[cmd.type] = compte.commandes.get(cmd.type, 0) + 1
			var option: String = options[int(cmd.index)].get("id", "") if OPTIONS_PREFEREES.has(sorte) else ""
			return {"sorte": sorte, "type": cmd.type, "option": option, "ok": true}
	return {"sorte": sorte, "type": "", "option": "", "ok": false}

func _commandes_du_menu() -> Array:
	var g: Dictionary = app.partie.game
	var du_bot: Array = Bots.choice_commands(g, POLITIQUE)
	match g.choice.kind:
		"loot":
			return [{"type": "equip"}, {"type": "stash"}] if du_bot[0].type == "equip" else [{"type": "stash"}]
		"shop":
			return _commandes_du_marchand(g.choice) + du_bot
		"treasure", "rest":
			return _commandes_de_la_salle_calme(g.choice)
	return du_bot

## Chambre forte, fontaine : l'option préférée d'abord ; une option grisée est refusée par la
## simulation, la suivante est alors essayée.
func _commandes_de_la_salle_calme(ch: Dictionary) -> Array:
	var premieres: Array = []
	var autres: Array = []
	for i in ch.options.size():
		var cmd := {"type": "choose", "index": float(i)}
		if ch.options[i].id == OPTIONS_PREFEREES[ch.kind]:
			premieres.append(cmd)
		else:
			autres.append(cmd)
	return premieres + autres

## Un achat par visite : la première offre encore en vente que la bourse permet, puis on ferme.
func _commandes_du_marchand(ch: Dictionary) -> Array:
	var offres: Array = ch.offers
	if offres.any(func(o: Dictionary) -> bool: return D6Js.truthy(o.get("sold"))):
		return [{"type": "close"}]
	for i in offres.size():
		if offres[i].price <= ch.gold:
			return [{"type": "choose", "index": float(i)}, {"type": "close"}]
	return [{"type": "close"}]

## Partie neuve : le bot repart d'une mémoire vide (elle est dérivée de la graine de la partie).
func _sur_partie() -> void:
	_mem = {}
	inerte = false
	vers_la_ville = false

func _sur_evenements(liste: Array) -> void:
	for ev in liste:
		compte.evenements[ev.type] = compte.evenements.get(ev.type, 0) + 1
		match ev.type:
			"roomClear":
				compte.salles += 1
				compte.gardiens += 1 if D6Js.truthy(ev.get("boss")) else 0
			"floorEnter":
				compte.etages += 1
				compte.etage_max = maxf(compte.etage_max, ev.floor)
			"checkpoint":
				dernier_checkpoint = ev
			"choiceOpen":
				compte.choix[ev.kind] = compte.choix.get(ev.kind, 0) + 1
			"gameOver":
				compte.morts += 1
