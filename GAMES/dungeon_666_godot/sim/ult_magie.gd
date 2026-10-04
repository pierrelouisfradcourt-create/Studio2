extends RefCounted
## ULTIME « GROSSE MAGIE » — Sentence capitale (Bourreau). Chargé par D6KitSupers (pas de class_name).
## Données : tuning.supers.sentence_capitale (data/classes.json).
##
## Un seul geste, joué dans l'état 'super' du héros (invulnérable, immobile : speedMult 0) :
##   1. lame levée pendant `strikeAt` s (télégraphe) ;
##   2. le temps se fige `freeze` s (gel imposé de la sim : D6Combat.force_hitstop) ;
##   3. le FRACAS : tout ennemi présent dans la salle (apparu, non dissous ; ni visée ni ligne de
##      vue : la foudre tombe d'en haut, un pavois ne l'arrête pas) prend `damage` et est étourdi
##      `stun` s. Un ennemi qui n'est PAS un Gardien et dont la vie est à `executeBelow` ou moins de
##      son maximum est EXÉCUTÉ (champions compris ; une bulle d'immunité le protège). Un Gardien
##      n'est jamais exécuté et ne perd pas plus de `bossCap` de sa vie maximale. Les projectiles
##      ennemis en vol sont effacés.
## Source des dégâts : 'super' (ne recharge pas la jauge, « Gloire charnelle » s'y applique, les
## procs « au toucher » de source 'super' jouent). Pas de critique : le nombre affiché est le nombre.

## Un pas de l'état 'super' (player.superClock est déjà avancé par D6KitSupers).
static func tick(game: Dictionary, s: Dictionary) -> void:
	var p: Dictionary = game.player
	if p.superStep == 0.0 and p.superClock >= s.strikeAt:
		p.superStep = 1.0
		D6State.emit(game, "ultFreeze", {"x": p.x, "y": p.y, "time": s.freeze})
		D6Combat.force_hitstop(game, s.freeze)
		return
	if p.superStep == 1.0:
		p.superStep = 2.0
		_strike(game, s)

## Le fracas : chaque ennemi présent est jugé, puis les tirs ennemis disparaissent.
static func _strike(game: Dictionary, s: Dictionary) -> void:
	var p: Dictionary = game.player
	var hits := 0.0
	var executed := 0.0
	var enemies: Array = game.enemies
	var i := 0
	while i < enemies.size():
		var e: Dictionary = enemies[i]
		i += 1
		if e.dead or e.spawnT > 0.0:
			continue
		var reach: float = s.radius + e.r
		if D6Geo.dist2(p.x, p.y, e.x, e.y) >= reach * reach:
			continue
		hits += 1.0
		if _judge(game, e, s):
			executed += 1.0
	for pr in game.projectiles:
		if pr.get("owner") == "enemy" and not D6Js.truthy(pr.get("dead")):
			pr.dead = true
			D6State.emit(game, "deflect", {"x": pr.x, "y": pr.y})
	D6State.emit(game, "ultStrike", {"x": p.x, "y": p.y, "r": s.radius, "hits": hits, "executed": executed, "shake": D6Js.nz(s.get("shake"), 0.0)})

## Vrai si l'ennemi est exécutable : pas un Gardien, pas sous une bulle d'immunité, vie au seuil ou dessous.
static func executable(e: Dictionary, s: Dictionary) -> bool:
	if D6Js.truthy(e.get("boss")) or D6Js.nz(e.get("invuln"), 0.0) > 0.0:
		return false
	return e.hp / e.maxHp <= s.executeBelow

## Un ennemi sous le fracas : exécuté (rend true), ou blessé et étourdi. Gardien : dégâts plafonnés.
static func _judge(game: Dictionary, e: Dictionary, s: Dictionary) -> bool:
	if executable(e, s):
		D6State.emit(game, "ultBolt", {"id": e.id, "x": e.x, "y": e.y, "r": e.r, "executed": true})
		D6Combat.kill_enemy(game, e, {"kind": "super"})
		return true
	var src := {"kind": "super", "amount": s.damage, "stun": D6Js.nz(s.get("stun"), 0.0), "canCrit": false}
	if D6Js.truthy(e.get("boss")):
		src.cap = maxf(1.0, D6Js.jround(e.maxHp * s.bossCap))
	D6State.emit(game, "ultBolt", {"id": e.id, "x": e.x, "y": e.y, "r": e.r, "executed": false})
	D6Combat.damage_enemy(game, e, src)
	return false
