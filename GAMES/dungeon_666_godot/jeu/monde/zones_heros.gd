extends "res://jeu/monde/calque.gd"
## Les zones posées par le héros (game.room.kitFx.zones) : cible d'un pot ou d'une bombe en vol,
## Brasier d'âmes, Bombe de soufre, Piège à mâchoires, Totem de givre ; et le souffle de ses
## explosions. Ce sont SES outils : teintes froides (cyan, blanc), jamais de rouge.
## Les objets lancés, tant qu'ils volent, sont dessinés par tirs.gd (au-dessus des créatures).

const FEU_D_AMES := Color("#3fb8ff")
const GIVRE := Color("#bff8ff")
const ACIER := Color("#7a8c96")
const POUDRE := Color("#1d2a33")

func _draw() -> void:
	var g = etat()
	if g == null:
		return
	for h in g.hazards:
		if not D6Js.truthy(h.get("hitsPlayer")) and not D6Js.truthy(h.get("done")) and h.shape == "circle":
			_souffle(h)
	var reserve = g.room.get("kitFx")
	if not (reserve is Dictionary):
		return
	for z in reserve.zones:
		if D6Js.truthy(z.get("dead")):
			continue
		match z.kind:
			"pot":
				_cible(Vector2(z.tx, z.ty), z.r, PAL.lance, 0.5)
			"brasier":
				_brasier(z)
			"bombe":
				_bombe(z)
			"piege":
				_piege(z)
			"totem":
				_totem(z)

## Anneau en pointillé qui tourne : « ceci est à moi ».
func _cible(p: Vector2, r: float, couleur: Color, alpha: float) -> void:
	Trace.cercle_pointille(self, p, r, Trace.voile(couleur, alpha), 2.0, 8.0, 7.0, temps() * 30.0)

## Explosion d'une bénédiction en préparation : elle ne menace que les ennemis.
func _souffle(h: Dictionary) -> void:
	var k: float = D6Projectiles.hazard_progress(h)
	var p := Vector2(h.x, h.y)
	draw_circle(p, h.r * k, Trace.voile(FEU_D_AMES, 0.1 + 0.12 * k), true, -1.0, true)
	_cible(p, h.r, PAL.lance, 0.6)

func _brasier(z: Dictionary) -> void:
	var t := temps()
	var fondu := clampf((z.duration - z.t) / 0.4, 0.0, 1.0)
	var p := Vector2(z.x, z.y)
	draw_circle(p, z.r, Trace.voile(FEU_D_AMES, 0.2 * fondu), true, -1.0, true)
	Trace.halo(self, p, z.r * 1.1, PAL.heroGlow, 0.8 * fondu)
	# Langues de feu d'âmes (bleues) qui dansent dans la zone.
	for i in 12:
		var a := float(i) / 12.0 * TAU + t * 0.6
		var d: float = z.r * (0.45 + 0.45 * float((i * 7) % 5) / 5.0)
		var h := 7.0 + 5.0 * sin(t * 9.0 + float(i) * 1.7)
		var pied := p + Vector2.from_angle(a) * d
		var feu := Trace.voile(PAL.lance, 0.7 * fondu)
		Trace.triangle(self, pied + Vector2(-4, 0), pied + Vector2(4, 0), pied + Vector2(0, -h * 1.25), feu, feu, Trace.voile(Color.WHITE, 0.15 * fondu))
	_cible(p, z.r, PAL.lance, 0.6 * fondu)

func _bombe(z: Dictionary) -> void:
	if z.get("phase") == "flight":
		_cible(Vector2(z.tx, z.ty), z.r, PAL.lance, 0.5)
		return
	# Mèche : le disque du souffle se remplit jusqu'à l'explosion.
	var t := temps()
	var k := clampf(z.t / maxf(1e-3, z.fuse), 0.0, 1.0)
	var p := Vector2(z.x, z.y)
	draw_circle(p, z.r * k, Trace.voile(FEU_D_AMES, 0.14 + 0.2 * k), true, -1.0, true)
	_cible(p, z.r, PAL.lance, 0.85)
	Trace.disque(self, p, 10.0, POUDRE, PAL.lance, 2.0)
	draw_line(p + Vector2(3, -9), p + Vector2(6, -13), ACIER, 2.0, true)
	Trace.halo(self, p + Vector2(6, -13), 12.0, Color.WHITE, 0.5 + 0.5 * sin(t * 40.0))

func _piege(z: Dictionary) -> void:
	var arme: bool = z.t >= z.armTime
	var alpha := 0.95 if arme else 0.45
	var p := Vector2(z.x, z.y)
	var r: float = z.r * 0.55
	draw_circle(p, r, Trace.voile(Trace.CERNE, alpha * 0.8), false, 5.5, true)
	draw_circle(p, r, Trace.voile(ACIER, alpha), false, 3.0, true)
	for i in 8:
		var a := float(i) / 8.0 * TAU
		var pied := p + Vector2.from_angle(a) * r
		var acier := Trace.voile(PAL.lance, alpha)
		Trace.triangle(self, pied + Vector2.from_angle(a + 1.3) * 4.0, pied - Vector2.from_angle(a) * 8.0, pied + Vector2.from_angle(a - 1.3) * 4.0, acier, acier, acier)
	if arme:
		_cible(p, z.r, PAL.heroCape, 0.35 + 0.15 * sin(temps() * 5.0))

func _totem(z: Dictionary) -> void:
	var fondu := clampf((z.life - z.t) / 0.4, 0.0, 1.0)
	var p := Vector2(z.x, z.y)
	draw_circle(p, z.r, Trace.voile(GIVRE, 0.07 * fondu), true, -1.0, true)
	_cible(p, z.r, GIVRE, 0.4 * fondu)
	Trace.halo_ovale(self, p + Vector2(0, 5.5), 16.0, 8.0, Color.BLACK, 0.75 * fondu)
	Trace.halo(self, p + Vector2(0, -18.0), 34.0, PAL.heroGlow, 0.9 * fondu)
	var cristal := PackedVector2Array([p + Vector2(0, -40), p + Vector2(9, -18), p + Vector2(6, 4), p + Vector2(-6, 4), p + Vector2(-9, -18)])
	Trace.forme(self, cristal, Trace.voile(GIVRE, fondu), Trace.voile(PAL.heroCape, fondu), 2.0)
	draw_line(p + Vector2(0, -40), p + Vector2(0, 4), Trace.voile(Color.WHITE, 0.5 * fondu), 1.5, true)
