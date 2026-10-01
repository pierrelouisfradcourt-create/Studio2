extends "res://jeu/monde/creatures/calque.gd"
## Calque du SOL : ce qui est posé sous les corps. Une ombre douce sous chaque créature (celle
## d'un bond reste au sol, plus petite et plus pâle, pendant que le corps monte), halos des élites
## et des Gardiens, lueur du possédé qui va exploser, fils violets qui relient un porte-étendard
## à ceux qu'il protège, traînée de cape du dash, aura chaude de l'élan.
## Tout est ici en rectangles texturés et en traits simples : le moteur les regroupe.

const ELAN := Color("#ffb02e") # l'aura de l'élan : or chaud, jamais le rouge du danger
const ELAN_FONDU := 0.4 # s : l'aura s'éteint sur la fin de l'élan

func _draw() -> void:
	var g = jeu()
	if g == null:
		return
	for e in g.enemies:
		if D6Js.truthy(e.get("dead")) or (D6Js.truthy(e.get("hidden")) and not D6Js.truthy(e.boss)):
			continue
		_sol_ennemi(e, g)
	_sol_heros(g)
	p.alpha = 1.0

## Ombre : une tache aux bords fondus, un peu en dessous du corps (la lumière vient du haut).
func _ombre(pos: Vector2, r: float, haut: float, force: float = 1.0) -> void:
	var k := 1.0 - 0.35 * haut
	p.ombre(pos + Vector2(0.0, r * 0.42), r * 1.3 * k, r * 0.78 * k, force * (1.0 - 0.45 * haut))

func _sol_ennemi(e: Dictionary, g: Dictionary) -> void:
	var pos := lieu(e)
	var r: float = e.r
	p.alpha = _presence(e, g)
	_ombre(pos, r, envol(e), 1.15 if D6Js.truthy(e.boss) else 1.0)
	if D6Js.truthy(e.eliteMod):
		p.lueur(pos, r * 2.6, Couleurs.ELITE_COLORS[e.eliteMod], 0.42)
	if D6Js.truthy(e.boss):
		p.lueur(pos, r * 2.5, _teinte_phase(e), 0.5 + 0.15 * sin(temps() * 5.0))
	if e.kind == "exploder" and e.state == "windup":
		p.lueur(pos, r * 4.5, PAL.exploder, 0.45 + 0.35 * sin(e.stateTime * 40.0))
	var porteur = entites.gardes.get(e.id)
	if porteur != null:
		_fil(pos, lieu(porteur), e.id)

## Ce que le sol montre d'un ennemi : il paraît à l'apparition, s'efface avec le Traqueur qui se dissout.
func _presence(e: Dictionary, g: Dictionary) -> float:
	if D6Js.truthy(e.get("hidden")):
		return 0.3
	if e.spawnT > 0.0:
		return 0.5 + 0.5 * (1.0 - clampf(e.spawnT / 0.25, 0.0, 1.0))
	if e.kind == "stalker" and e.state == "fade":
		return 1.0 - clampf(e.stateTime / maxf(1e-3, g.tuning.enemies.stalker.fade), 0.0, 1.0)
	return 1.0

## Fil de protection : un trait violet ténu de l'étendard vers le protégé, et une perle qui le
## parcourt dans ce sens — on lit QUI protège QUI.
func _fil(protege: Vector2, porteur: Vector2, graine: float) -> void:
	draw_line(porteur, protege, Color(PAL.summon, 0.3 * p.alpha), 1.5)
	var k := fposmod(temps() * 0.9 + graine * 0.37, 1.0)
	var perle := porteur.lerp(protege, k)
	draw_rect(Rect2(perle - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), Color(PAL.summon, 0.8 * sin(PI * k) * p.alpha))

## Le halo d'un Gardien dit sa phase : sombre, puis rouge, puis braise.
func _teinte_phase(e: Dictionary) -> Color:
	if e.phase >= 3.0:
		return Color("#ff6a1a")
	return Color("#ff3a1a") if e.phase >= 2.0 else Color("#a01f48")

func _sol_heros(g: Dictionary) -> void:
	var h: Dictionary = g.player
	var pr: float = h.r * HEROS_VISUEL
	var pos := lieu_heros(g)
	p.alpha = 1.0
	_trainee(pos, pr, h.state == "dash")
	var haut := envol_heros(g)
	p.alpha = alpha_heros(h)
	_ombre(pos, pr, haut)
	p.lueur(pos, 62.0, PAL.heroGlow, 0.9)
	if h.state == "super":
		p.lueur(pos, 150.0, PAL.superBar, 0.4 + 0.2 * sin(temps() * 18.0))
	var elan: float = nombre(h, "surge")
	if elan > 0.0 and h.state != "dead":
		p.lueur(pos, 84.0 + 8.0 * sin(temps() * 11.0), ELAN, 0.75 * minf(1.0, elan / ELAN_FONDU))

## Traînée du dash : un ruban de la couleur de la cape, plein près du héros, effilé et transparent
## vers le point de départ (les points viennent de entites.trainee, le dernier est le héros).
func _trainee(pos: Vector2, pr: float, en_dash: bool) -> void:
	var pts: Array = entites.trainee
	var n := pts.size()
	if n < 2:
		return
	var a: Vector2 = pts[0].pos
	var ka := 0.0
	for i in range(1, n + 1):
		var b: Vector2 = pos if i == n else pts[i].pos
		if i == n and not en_dash:
			break
		var kb: float = (1.0 if i == n else pts[i].vie / entites.TRAINEE_VIE) * float(i) / n
		var cote := (b - a).orthogonal().normalized() * pr
		draw_primitive(PackedVector2Array([a + cote * (0.25 + 0.6 * ka), b + cote * (0.25 + 0.6 * kb), b - cote * (0.25 + 0.6 * kb), a - cote * (0.25 + 0.6 * ka)]),
			PackedColorArray([Color(PAL.heroCape, 0.55 * ka), Color(PAL.heroCape, 0.55 * kb), Color(PAL.heroCape, 0.55 * kb), Color(PAL.heroCape, 0.55 * ka)]), PackedVector2Array())
		a = b
		ka = kb
