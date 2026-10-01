extends RefCounted
## Les mises en scène du banc et du test des écrans : amener une partie devant un menu précis.
## Ce fichier a le droit de manipuler `game` (c'est un banc, comme `window.__d666` du web) ;
## les écrans, eux, n'y touchent jamais.

## Porte à prendre pour arriver dans la salle de chaque menu (D6Run.enter_floor).
const PORTES := {"benediction": "boon", "butin": "loot", "marchand": "shop", "evenement": "event", "coffre": "treasure", "fontaine": "rest"}
const ETAGE_DES_MENUS := 3.0
const ETAGE_FINAL := 666.0

## Entre dans une salle dont l'objet d'interaction ouvrira le menu `sorte`.
static func entrer(game: Dictionary, sorte: String) -> void:
	D6Run.enter_floor(game, ETAGE_DES_MENUS, {"reward": PORTES[sorte]})

## Salle vaincue d'office (killAll du web) : dernière vague, plus personne.
static func vider_salle(game: Dictionary) -> void:
	var room: Dictionary = game.room
	if room.get("waves") is Array:
		room.waveIndex = float(room.waves.size() - 1)
	game.spawns.clear()
	for e in game.enemies:
		e.dead = true

## Pose le héros sur l'objet d'interaction de la salle, s'il y en a un : le menu s'ouvre au
## prochain pas de simulation. Rend vrai si le héros a été posé.
static func toucher_l_objet(game: Dictionary) -> bool:
	var it = game.room.get("interact")
	if not (it is Dictionary) or D6Js.truthy(it.get("used")):
		return false
	game.player.x = it.x
	game.player.y = it.y
	return true

## Un pas de la mise en scène, à appeler à chaque image tant que le menu n'est pas ouvert.
static func avancer_vers_le_menu(game: Dictionary) -> void:
	if game.mode != "play":
		return
	if not game.room.cleared:
		vider_salle(game)
	toucher_l_objet(game)

## Défaite forcée (hurt du web) : l'écran de mort suit l'agonie.
static func tuer_le_heros(game: Dictionary) -> void:
	var p: Dictionary = game.player
	p.iframes = 0.0
	p.hp = 0.0
	p.state = "dead"
	p.stateTime = 0.0

## Donne `n` bénédictions de la famille (pour un récapitulatif de mort, une fontaine à méditer).
static func benir(game: Dictionary, n: int, famille: String = "colere") -> void:
	for i in n:
		var offres: Array = D6Boons.roll_boon_offer(game, famille)
		if not offres.is_empty():
			D6Boons.add_boon(game.run, offres[i % offres.size()])
	D6Stats.recompute_stats(game)

static func donner_or(game: Dictionary, somme: float) -> void:
	game.run.gold = somme
	D6Run.sync_purse(game)
