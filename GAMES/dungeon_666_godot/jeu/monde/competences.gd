extends "res://jeu/monde/calque.gd"
## Ce que les COMPÉTENCES NEUVES (combat V3, étape 4) posent SUR les créatures, au-dessus d'elles et
## sous les tirs : les MARQUES des ennemis (Stigmate du Revenant, Marque de la proie de la
## Chasseresse) et ce que le héros porte un instant (garde de la Contre-taille, bouclier de la Garde
## de fer, arc bandé du Trait de Nemrod, pas de braise du Sillage). Aucune règle ici : tout est LU
## (e.stigmate, e.proie, player.parry, player.guard, player.sillage, D6Loadout.slot_state).
## Teintes du héros, froides : le Stigmate est de braise CLAIRE (presque blanche), la proie est
## cyan ; jamais le rouge des dangers.

const BRAISE_CLAIRE := Color("#ffd9a0")
const ECUME := Color("#e8fbff")
const NUIT := Color("#0d2a36")
const PORTEE_VISEE := 300.0 # u : longueur dessinée de la ligne de visée du Trait (une direction, pas sa portée)

func _draw() -> void:
	var g = etat()
	if g == null:
		return
	for e in g.enemies:
		if D6Js.truthy(e.get("dead")) or float(e.get("spawnT", 0.0)) > 0.0 or D6Js.truthy(e.get("hidden")):
			continue
		var stigmate = e.get("stigmate")
		if stigmate is Dictionary:
			_stigmate(partie.position_dessin(e), float(e.r), stigmate)
		var proie = e.get("proie")
		if proie is Dictionary:
			_proie(partie.position_dessin(e), float(e.r), proie)
	var h: Dictionary = g.player
	if h.state == "dead":
		return
	var p: Vector2 = partie.position_dessin(h, true)
	var parade = h.get("parry")
	if parade is Dictionary:
		_parade(p, float(h.r), parade)
	var garde = h.get("guard")
	if garde is Dictionary:
		_garde(p, float(h.r), float(h.facing), garde)
	var sillage = h.get("sillage")
	if sillage is Dictionary:
		_sillage(p, float(h.r), sillage)
	for i in D6Loadout.SLOTS:
		var etat_i: Dictionary = D6Loadout.slot_state(g, i)
		if etat_i.charging:
			_arc_bande(p, float(h.r), Vector2(h.castDirX, h.castDirY), etat_i.chargeFrac)

## STIGMATE : un fer rouge refroidi au-dessus de l'ennemi — un anneau de braise claire à trois
## dents qui tourne, et l'arc du temps qui lui reste. « Celui-là explose s'il meurt. »
func _stigmate(p: Vector2, r: float, m: Dictionary) -> void:
	var reste := clampf(m.t / maxf(1e-3, m.max), 0.0, 1.0)
	var rayon := r + 9.0
	var tour := temps() * 1.6
	draw_arc(p, rayon, 0.0, TAU, 32, Trace.voile(NUIT, 0.6), 4.5, true)
	draw_arc(p, rayon, -PI / 2.0, -PI / 2.0 + TAU * reste, 32, BRAISE_CLAIRE, 2.5, true)
	for i in 3:
		var a := tour + float(i) / 3.0 * TAU
		var d := Vector2.from_angle(a)
		Trace.triangle(self, p + d * (rayon + 9.0), p + d.rotated(0.22) * (rayon - 1.0), p + d.rotated(-0.22) * (rayon - 1.0), BRAISE_CLAIRE, BRAISE_CLAIRE, Color.WHITE)
	Trace.halo(self, p, rayon * 1.3, BRAISE_CLAIRE, 0.25)

## MARQUE DE LA PROIE : un réticule cyan — quatre crochets qui se resserrent et s'écartent, une
## pointe de flèche au-dessus de la tête, l'arc du temps qui reste.
func _proie(p: Vector2, r: float, m: Dictionary) -> void:
	var reste := clampf(m.t / maxf(1e-3, m.max), 0.0, 1.0)
	var rayon := r + 13.0 + 2.5 * sin(temps() * 6.0)
	var teinte: Color = PAL.heroCape
	for i in 4:
		var a := PI / 4.0 + float(i) * PI / 2.0
		draw_arc(p, rayon, a - 0.42, a + 0.42, 8, Trace.voile(NUIT, 0.6), 5.0, true)
		draw_arc(p, rayon, a - 0.4, a + 0.4, 8, teinte, 2.5, true)
	draw_arc(p, rayon + 6.0, -PI / 2.0, -PI / 2.0 + TAU * reste, 32, Trace.voile(ECUME, 0.55), 1.5, true)
	var haut := p + Vector2(0.0, -r - 30.0 + 2.0 * sin(temps() * 6.0))
	Trace.triangle(self, haut + Vector2(0, 10), haut + Vector2(-7, -3), haut + Vector2(7, -3), teinte, ECUME, ECUME)

## GARDE DE LA CONTRE-TAILLE : un cercle clair et fin, tendu autour de lui, qui se vide — « le
## prochain coup est paré ». Bref : il doit se lire d'un coup d'œil.
func _parade(p: Vector2, r: float, st: Dictionary) -> void:
	var reste := clampf(st.t / maxf(1e-3, st.def.window), 0.0, 1.0)
	var rayon := r + 14.0
	draw_arc(p, rayon, 0.0, TAU, 32, Trace.voile(ECUME, 0.25), 6.0, true)
	draw_arc(p, rayon, -PI / 2.0, -PI / 2.0 + TAU * reste, 32, Color.WHITE, 3.0, true)
	for i in 4:
		var d := Vector2.from_angle(temps() * 5.0 + float(i) * PI / 2.0)
		draw_line(p + d * (rayon - 5.0), p + d * (rayon + 7.0), ECUME, 2.0, true)

## GARDE DE FER : le bouclier — un arc épais DEVANT lui, de l'ouverture que disent les données, et
## dessous l'arc fin du temps qui reste. Le dos reste nu : on voit d'où il est vulnérable.
func _garde(p: Vector2, r: float, face: float, st: Dictionary) -> void:
	var reste := clampf(st.t / maxf(1e-3, st.max), 0.0, 1.0)
	var demi: float = st.def.arc * D6Data.DEG * 0.5
	var rayon := r + 18.0
	draw_arc(p, rayon, face - demi, face + demi, 24, Trace.voile(NUIT, 0.7), 10.0, true)
	draw_arc(p, rayon, face - demi, face + demi, 24, PAL.heroCape, 6.0, true)
	draw_arc(p, rayon + 2.0, face - demi, face + demi, 24, Trace.voile(Color.WHITE, 0.7), 1.5, true)
	draw_arc(p, rayon - 8.0, face - demi * reste, face + demi * reste, 24, Trace.voile(ECUME, 0.8), 2.0, true)

## SILLAGE DE BRAISE en cours : deux flammèches à ses talons et l'arc du temps qui reste, à ses pieds.
func _sillage(p: Vector2, r: float, st: Dictionary) -> void:
	var reste := clampf(st.t / maxf(1e-3, st.def.duration), 0.0, 1.0)
	var pied := p + Vector2(0.0, r * 0.5)
	draw_arc(pied, r + 6.0, -PI / 2.0, -PI / 2.0 + TAU * reste, 28, Trace.voile(PAL.lance, 0.85), 2.0, true)
	for cote: float in [-1.0, 1.0]:
		var base := pied + Vector2(cote * r * 0.5, 0.0)
		var h := 9.0 + 4.0 * sin(temps() * 12.0 + cote)
		Trace.triangle(self, base + Vector2(-3, 0), base + Vector2(3, 0), base + Vector2(0, -h), PAL.lance, PAL.lance, Color.WHITE)

## TRAIT DE NEMROD qui se bande : la ligne de visée s'allonge et s'épaissit avec la charge, la
## corde (un arc derrière elle) se tend ; pleine, tout blanchit.
func _arc_bande(p: Vector2, r: float, dir: Vector2, charge: float) -> void:
	if dir.length_squared() < 1e-6:
		return
	dir = dir.normalized()
	var plein := charge >= 0.98
	var teinte: Color = Color.WHITE if plein else PAL.heroCape
	var bout := p + dir * (r + 20.0 + (PORTEE_VISEE - 20.0) * charge)
	Trace.ligne_pointillee(self, p + dir * (r + 6.0), bout, Trace.voile(teinte, 0.35 + 0.5 * charge), 1.5 + 3.0 * charge, 12.0, 7.0, -temps() * 80.0)
	Trace.triangle(self, bout + dir * 12.0, bout + dir.orthogonal() * 7.0, bout - dir.orthogonal() * 7.0, teinte, teinte, ECUME)
	var a := dir.angle() + PI
	draw_arc(p, r + 10.0 + 8.0 * charge, a - 0.9, a + 0.9, 16, Trace.voile(teinte, 0.9), 2.5, true)
	draw_arc(p, r + 22.0, a - 0.9 * charge, a + 0.9 * charge, 16, Trace.voile(ECUME, 0.6), 1.5, true)
