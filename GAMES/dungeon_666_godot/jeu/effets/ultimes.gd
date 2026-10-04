extends RefCounted
## Effets des trois ULTIMES de classe (combat V3, étape 2), rangés à part de effets.gd qui les
## branche dans sa table. Présentation pure : chaque fonction traduit UN événement de simulation
## en formes, particules, textes, voile d'écran et secousses — avec ce que la vue Effets a déjà.
##   Sentence capitale  ultFreeze (le temps se fige), ultStrike (le fracas), ultBolt (un éclair
##                      par ennemi, marque d'exécution)
##   Forme du Damné     formStart, formEnd, formRush (ruée), formHowl (hurlement), formBurst (embrasement)
##   Meute des Limbes   allySpawn, allyBite, allyHurt, allyDeath, allyGone
## Teintes : la Sentence est d'or (comme la jauge), la forme est de BRAISE (orange, jamais le rouge
## des dangers), la meute a la teinte froide de l'héroïne.

const Couleurs = preload("res://jeu/theme/couleurs.gd")
const PAL: Dictionary = Couleurs.PAL

const BRAISE := Color("#ff8a2a")
const BRAISE_CLAIRE := Color("#ffd9a0")
const OS_CLAIR := Color("#dff6ff") # limiers : os clair et froid
const CIEL := 460.0 # u : hauteur d'où tombe l'éclair de la Sentence
const ONDE_FRACAS := 620.0 # u : onde du fracas autour du Bourreau (la portée réelle est toute la salle)

## Les effets de ce fichier, à ajouter à la table de la vue : type d'événement -> fonction.
static func table(fx: Node) -> Dictionary:
	return {
		"ultFreeze": _gel.bind(fx), "ultStrike": _fracas.bind(fx), "ultBolt": _eclair.bind(fx),
		"formStart": _forme.bind(fx), "formEnd": _fin_forme.bind(fx), "formRush": _ruee.bind(fx),
		"formHowl": _hurlement.bind(fx), "formBurst": _embrasement.bind(fx),
		"allySpawn": _limier_parait.bind(fx), "allyBite": _morsure.bind(fx), "allyHurt": _limier_blesse.bind(fx),
		"allyDeath": _limier_meurt.bind(fx), "allyGone": _limier_part.bind(fx),
	}

# ---------------------------------------------------------------- Sentence capitale

## Le temps se fige : l'écran blanchit d'or, la caméra se resserre.
static func _gel(ev: Dictionary, _g: Dictionary, fx: Node) -> void:
	fx.ecran.voile(1.0, PAL.superBar.lightened(0.5))
	fx.formes.anneau(ev.x, ev.y, 260.0, 30.0, PAL.crit, 5.0, maxf(0.2, ev.get("time", 0.3)))
	fx._zoom(0.08)

## Le fracas : une onde d'or part du Bourreau, la salle tremble.
static func _fracas(ev: Dictionary, _g: Dictionary, fx: Node) -> void:
	fx.formes.ajouter({"type": "nova", "x": ev.x, "y": ev.y, "r": ONDE_FRACAS, "couleur": PAL.superBar, "vie": 0.55})
	fx.formes.anneau(ev.x, ev.y, 30.0, ONDE_FRACAS * 0.6, PAL.crit, 7.0, 0.35)
	fx.particules.gerbe(ev.x, ev.y, 30, 620.0, 0.6, 3.5, PAL.superBar, 0.0, TAU, 4.0, true)
	fx.ecran.voile(0.8, PAL.superBar.lightened(0.3))
	fx._secouer(maxf(0.8, ev.get("shake", 1.0)))
	fx._zoom(0.06)

## Un éclair d'or tombe sur chaque ennemi touché ; un exécuté porte la marque : deux éclairs
## croisés, l'éclat blanc de la mort, le mot.
static func _eclair(ev: Dictionary, _g: Dictionary, fx: Node) -> void:
	var execute: bool = D6Js.truthy(ev.get("executed"))
	fx.formes.ajouter({"type": "eclair", "x0": ev.x + 30.0, "y0": ev.y - CIEL, "x1": ev.x, "y1": ev.y, "graine": randf() * 1000.0, "couleur": PAL.superBar, "vie": 0.3})
	fx.formes.anneau(ev.x, ev.y, 8.0, 54.0 if execute else 38.0, PAL.crit, 4.0, 0.25)
	fx.particules.gerbe(ev.x, ev.y, 10, 300.0, 0.35, 2.5, PAL.superBar, -PI / 2.0, 2.4, 6.0, true)
	if not execute:
		return
	var r: float = ev.get("r", 14.0) + 14.0
	for s: float in [-1.0, 1.0]:
		fx.formes.ajouter({"type": "eclair", "x0": ev.x - r * s, "y0": ev.y - r, "x1": ev.x + r * s, "y1": ev.y + r, "graine": randf() * 1000.0, "couleur": PAL.crit, "vie": 0.45})
	fx.textes.ajouter(ev.x, ev.y - r - 16.0, "EXÉCUTÉ", PAL.crit, 15, 0.9)

# ---------------------------------------------------------------- Forme du Damné

static func _forme(ev: Dictionary, _g: Dictionary, fx: Node) -> void:
	fx.formes.ajouter({"type": "nova", "x": ev.x, "y": ev.y, "r": 150.0, "couleur": BRAISE, "vie": 0.45})
	fx.particules.gerbe(ev.x, ev.y, 34, 340.0, 0.7, 3.5, BRAISE, -PI / 2.0, TAU, 3.0)
	fx.particules.gerbe(ev.x, ev.y, 14, 200.0, 0.9, 2.5, BRAISE_CLAIRE, -PI / 2.0, 1.6, 2.0, true)
	fx.ecran.voile(0.6, BRAISE_CLAIRE)
	fx._secouer(0.45)

static func _fin_forme(ev: Dictionary, _g: Dictionary, fx: Node) -> void:
	if ev.get("reason") == "etage":
		return # nouvelle salle : tout est effacé de toute façon
	fx.formes.anneau(ev.x, ev.y, 70.0, 12.0, BRAISE, 4.0, 0.35)
	fx.particules.gerbe(ev.x, ev.y, 16, 120.0, 0.9, 3.0, fx.TEINTES.cendre, -PI / 2.0, TAU, 2.0)

## Ruée spectrale : un trait de braise du départ à l'arrivée, des cendres le long du passage.
static func _ruee(ev: Dictionary, _g: Dictionary, fx: Node) -> void:
	var a := Vector2(ev.x0, ev.y0)
	var b := Vector2(ev.x, ev.y)
	for i in 2:
		fx.formes.ajouter({"type": "eclair", "x0": a.x, "y0": a.y, "x1": b.x, "y1": b.y, "graine": randf() * 1000.0, "couleur": BRAISE if i == 0 else BRAISE_CLAIRE, "vie": 0.28})
	var n := maxi(2, int(a.distance_to(b) / 40.0))
	for i in n:
		var p := a.lerp(b, (i + 0.5) / n)
		fx.particules.gerbe(p.x, p.y, 3, 110.0, 0.5, 3.0, BRAISE, 0.0, TAU, 4.0)
	fx.formes.anneau(b.x, b.y, 8.0, 44.0, BRAISE_CLAIRE, 3.0, 0.2)
	fx._recul((b - a).normalized() if a != b else Vector2.RIGHT, 6.0)

static func _hurlement(ev: Dictionary, _g: Dictionary, fx: Node) -> void:
	fx.formes.anneau(ev.x, ev.y, 20.0, ev.r, BRAISE, 6.0, 0.35)
	fx.formes.anneau(ev.x, ev.y, 10.0, ev.r * 0.7, BRAISE_CLAIRE, 3.0, 0.25)
	fx._secouer(0.4)
	fx._zoom(0.02)

## Embrasement : la forme finit en explosion, d'autant plus grosse qu'il restait du temps.
static func _embrasement(ev: Dictionary, _g: Dictionary, fx: Node) -> void:
	var part: float = clampf(ev.get("frac", 0.5), 0.0, 1.0)
	fx.formes.ajouter({"type": "choc", "x": ev.x, "y": ev.y, "r": ev.r, "couleur": BRAISE, "bord": BRAISE_CLAIRE, "vie": 0.4})
	fx.formes.ajouter({"type": "nova", "x": ev.x, "y": ev.y, "r": ev.r * 1.25, "couleur": BRAISE, "vie": 0.5})
	fx.particules.gerbe(ev.x, ev.y, roundi(lerpf(18.0, 46.0, part)), ev.r * 3.6, 0.6, 4.0, BRAISE, 0.0, TAU, 4.0)
	fx.particules.gerbe(ev.x, ev.y, 14, ev.r * 2.2, 0.8, 3.0, fx.TEINTES.cendre, 0.0, TAU, 3.0)
	fx.ecran.voile(lerpf(0.4, 0.9, part), BRAISE_CLAIRE)
	fx._secouer(lerpf(0.5, 1.0, part))
	fx._zoom(lerpf(0.03, 0.08, part))

# ---------------------------------------------------------------- Meute des Limbes

static func _limier_parait(ev: Dictionary, _g: Dictionary, fx: Node) -> void:
	fx.formes.anneau(ev.x, ev.y, 40.0, 10.0, PAL.heroCape, 3.0, 0.3)
	fx.particules.gerbe(ev.x, ev.y, 10, 150.0, 0.5, 3.0, OS_CLAIR, -PI / 2.0, 1.8, 4.0)

static func _morsure(ev: Dictionary, _g: Dictionary, fx: Node) -> void:
	fx.particules.gerbe(ev.tx, ev.ty, 4, 220.0, 0.2, 2.0, OS_CLAIR, ev.angle + PI, 1.4, 7.0, true)

## Un limier encaisse : un chiffre discret, froid (jamais le rouge du héros blessé).
static func _limier_blesse(ev: Dictionary, _g: Dictionary, fx: Node) -> void:
	fx.textes.ajouter(ev.x, ev.y - 22.0, "-" + D6Js.num_str(ev.amount), PAL.heroCape, 11, 0.5)
	fx.particules.gerbe(ev.x, ev.y, 5, 160.0, 0.3, 2.5, OS_CLAIR, 0.0, TAU, 5.0)

static func _limier_meurt(ev: Dictionary, _g: Dictionary, fx: Node) -> void:
	fx.formes.ajouter({"type": "mort", "x": ev.x, "y": ev.y, "r": 12.0, "couleur": PAL.heroCape, "vie": 0.25})
	fx.particules.gerbe(ev.x, ev.y, 14, 240.0, 0.6, 3.0, OS_CLAIR, 0.0, TAU, 4.0)

## Fin de la durée : il se défait en poussière d'os qui monte.
static func _limier_part(ev: Dictionary, _g: Dictionary, fx: Node) -> void:
	if ev.get("reason") == "etage":
		return
	fx.formes.anneau(ev.x, ev.y, 10.0, 36.0, PAL.heroCape, 2.0, 0.3)
	fx.particules.gerbe(ev.x, ev.y, 9, 90.0, 0.8, 2.5, OS_CLAIR, -PI / 2.0, 1.2, 2.0)
