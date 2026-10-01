extends "res://jeu/monde/creatures/calque.gd"
## Calque du SOL : ce qui est posé sous les corps. Ombres (celle d'un Gardien qui bondit reste
## au sol), halos des élites et des Gardiens, lueur du possédé qui va exploser, traînée de dash.

const TRAINEE_VIE := 0.18

func _draw() -> void:
	var g = jeu()
	if g == null:
		return
	for e in vivants(g):
		_sol_ennemi(e)
	_sol_heros(g)
	p.alpha = 1.0

func _ombre(pos: Vector2, r: float, force: float = 1.0) -> void:
	p.ellipse(pos + Vector2(0.0, r * 0.55), r * 1.05, r * 0.5, Color(PAL.shadow, PAL.shadow.a * force), Pinceau.SANS)

func _sol_ennemi(e: Dictionary) -> void:
	var pos := lieu(e)
	var r: float = e.r
	var haut := envol(e)
	p.alpha = 0.3 if D6Js.truthy(e.get("hidden")) else (0.5 + 0.5 * (1.0 - clampf(e.spawnT / 0.25, 0.0, 1.0)))
	_ombre(pos, r * (1.0 - 0.3 * haut), 1.0 - 0.35 * haut)
	if D6Js.truthy(e.eliteMod):
		p.lueur(pos, r * 2.6, Couleurs.ELITE_COLORS[e.eliteMod], 0.42)
	if D6Js.truthy(e.boss):
		p.lueur(pos, r * 2.5, _teinte_phase(e), 0.5 + 0.15 * sin(temps() * 5.0))
	if e.kind == "exploder" and e.state == "windup":
		p.lueur(pos, r * 4.5, PAL.exploder, 0.45 + 0.35 * sin(e.stateTime * 40.0))

## Le halo d'un Gardien dit sa phase : sombre, puis rouge, puis braise.
func _teinte_phase(e: Dictionary) -> Color:
	if e.phase >= 3.0:
		return Color("#ff6a1a")
	return Color("#ff3a1a") if e.phase >= 2.0 else Color("#a01f48")

func _sol_heros(g: Dictionary) -> void:
	var h: Dictionary = g.player
	var pr: float = h.r * HEROS_VISUEL
	p.alpha = 1.0
	for f in entites.trainee:
		var k: float = f.vie / TRAINEE_VIE
		p.disque(f.pos, pr * (0.55 + 0.4 * k), Color(PAL.heroCape, 0.4 * k), Pinceau.SANS)
	var pos := lieu_heros(g)
	var haut := envol_heros(g)
	p.alpha = alpha_heros(h)
	_ombre(pos, pr * (1.0 - 0.3 * haut), 1.0 - 0.35 * haut)
	p.lueur(pos, 62.0, PAL.heroGlow, 0.9)
	if h.state == "super":
		p.lueur(pos, 150.0, PAL.superBar, 0.4 + 0.2 * sin(temps() * 18.0))
