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
##   - `inerte` : il lâche les commandes dès qu'un combat est en cours (il se laisse tuer).

const Bots = preload("res://outils/bots/bots.gd")

const POLITIQUE := "skilled"
## Les sortes de menu que la première descente doit traverser (porte = sorte du menu).
const SORTES_VOULUES := ["boon", "loot", "shop", "event"]

var app: Node
var inerte := false
## salles nettoyées, étages entrés, étage le plus profond, morts, pas joués, menus ouverts par
## sorte, commandes de menu acceptées par type, événements de simulation par type.
var compte := {"salles": 0, "etages": 0, "etage_max": 0.0, "morts": 0, "pas": 0, "choix": {}, "commandes": {}, "evenements": {}}

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
	return Bots.play(POLITIQUE, g, _mem)

## Les sortes voulues que le parcours n'a pas encore traversées.
func sortes_manquantes() -> Array:
	return SORTES_VOULUES.filter(func(s: String) -> bool: return not compte.choix.has(s))

## Nombre d'événements de simulation de ce type vus depuis le début.
func vus(type: String) -> int:
	return compte.evenements.get(type, 0)

## Répond au menu ouvert par `app.commande` : essaie les commandes dans l'ordre, la première
## acceptée gagne. Rend {sorte, type, ok}.
func repondre_au_menu() -> Dictionary:
	var sorte: String = app.partie.game.choice.kind
	for cmd in _commandes_du_menu():
		if app.commande(cmd):
			compte.commandes[cmd.type] = compte.commandes.get(cmd.type, 0) + 1
			return {"sorte": sorte, "type": cmd.type, "ok": true}
	return {"sorte": sorte, "type": "", "ok": false}

func _commandes_du_menu() -> Array:
	var g: Dictionary = app.partie.game
	var du_bot: Array = Bots.choice_commands(g, POLITIQUE)
	match g.choice.kind:
		"loot":
			return [{"type": "equip"}, {"type": "stash"}] if du_bot[0].type == "equip" else [{"type": "stash"}]
		"shop":
			return _commandes_du_marchand(g.choice) + du_bot
	return du_bot

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

func _sur_evenements(liste: Array) -> void:
	for ev in liste:
		compte.evenements[ev.type] = compte.evenements.get(ev.type, 0) + 1
		match ev.type:
			"roomClear":
				compte.salles += 1
			"floorEnter":
				compte.etages += 1
				compte.etage_max = maxf(compte.etage_max, ev.floor)
			"choiceOpen":
				compte.choix[ev.kind] = compte.choix.get(ev.kind, 0) + 1
			"gameOver":
				compte.morts += 1
