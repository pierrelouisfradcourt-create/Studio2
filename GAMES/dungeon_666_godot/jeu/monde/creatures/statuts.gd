extends "res://jeu/monde/creatures/calque.gd"
## Calque des STATUTS : ce qui se lit PAR-DESSUS les corps, une fonction par signe.
##   froid          anneau bleu glace et cristaux
##   brûlure        lueur et flammèches sur le dos
##   vulnérabilité  quatre repères dorés qui visent le corps
##   étourdissement trois étoiles qui tournent au-dessus de la tête
##   garde          petit écu au bout de la barre de vie (il ne peut pas être ré-étourdi à l'arme)
##   barre de vie   seulement si l'ennemi est blessé ou d'élite (celle d'un Gardien est au HUD)
##   élites         étiquette, bulle d'immunité annoncée puis active, canalisation, rayon de drain
##   protégé        chevron violet au-dessus de l'ennemi qu'un porte-étendard couvre

const GARDE_FONDU := 0.3 # s : l'écu s'efface sur la fin de la garde
const BULLE := Color(1.0, 0.914, 0.659, 0.16)
const GLACE := Color("#8fd8ff")
const ECU := Color("#c9c9d6")
const NOIR := Color(0.0, 0.0, 0.0, 0.85)

func _draw() -> void:
	var g = jeu()
	if g == null:
		return
	var heros := lieu_heros(g)
	for e in vivants(g):
		if D6Js.truthy(e.get("hidden")):
			continue
		var pos := lieu(e)
		p.poser(Transform2D(0.0, pos))
		_afflictions(e)
		_pouvoirs_elite(e, g, heros - pos)
		_jauges(e)
	p.alpha = 1.0
	p.lever()

func _afflictions(e: Dictionary) -> void:
	var r: float = e.r
	if e.chill > 0.0:
		_froid(r)
	if e.burn > 0.0:
		_brulure(e, r)
	if e.vuln > 0.0 and nombre(e, "exposed") <= 0.0:
		_vulnerable(r)
	if D6Js.truthy(e.boss) and nombre(e, "invuln") > 0.0 and not D6Js.truthy(e.get("shielded")):
		p.pointille(Vector2.ZERO, r * 1.22, Color(PAL.eliteBouclier, 0.85), 3.0, 20.0, temps() * 1.5)

func _froid(r: float) -> void:
	p.anneau(Vector2.ZERO, r + 3.0, GLACE, 2.0)
	for i in 6:
		var d := Vector2.from_angle(i * TAU / 6.0 + 0.5)
		p.pic(d * (r + 2.0) + d.orthogonal() * 2.5, d * (r + 2.0) - d.orthogonal() * 2.5, d * (r + 9.0), Color("#dff6ff"), GLACE, 1.0)

func _brulure(e: Dictionary, r: float) -> void:
	var t0: float = temps() * 20.0 + e.id
	p.lueur(Vector2(0.0, -r * 0.5), r * 1.7, PAL.lava, 0.5 + 0.2 * sin(t0))
	for i in 3:
		var x := (i - 1) * r * 0.5
		var h := r * (0.55 + 0.2 * sin(t0 * 0.7 + i * 2.1))
		var pied := Vector2(x, -r * 0.55)
		p.forme(PackedVector2Array([pied + Vector2(-r * 0.2, 0.0), pied + Vector2(sin(t0 * 0.5 + i) * 2.0, -h), pied + Vector2(r * 0.2, 0.0)]), PAL.lava, Pinceau.SANS)
		p.disque(pied + Vector2(0.0, -h * 0.25), r * 0.1, PAL.crit, Pinceau.SANS)

## Vulnérable (il subit plus de dégâts) : quatre repères dorés pointés vers lui, qui battent.
func _vulnerable(r: float) -> void:
	var bat := 2.0 * sin(temps() * 8.0)
	for i in 4:
		var d := Vector2.from_angle(PI * 0.25 + i * PI * 0.5)
		var pointe := d * (r + 4.0 + bat)
		p.pic(pointe + d * 9.0 + d.orthogonal() * 4.5, pointe + d * 9.0 - d.orthogonal() * 4.5, pointe, PAL.crit, NOIR, 1.2)

## Jauges empilées au-dessus de la tête : barre de vie (et écu de garde), étoiles, étiquette d'élite.
func _jauges(e: Dictionary) -> void:
	var r: float = e.r
	var y := -r - 8.0
	var boss: bool = D6Js.truthy(e.boss)
	var elite: bool = D6Js.truthy(e.eliteMod)
	if not boss and (e.hp < e.maxHp or elite):
		var largeur := maxf(28.0, r * 2.2)
		_barre_vie(e, y, largeur)
		if e.stun <= 0.0 and e.guard > 0.0:
			_ecu(Vector2(largeur * 0.5 + 9.0, y - 2.0), minf(1.0, e.guard / GARDE_FONDU))
		y -= 10.0
	elif not boss and e.stun <= 0.0 and e.guard > 0.0:
		_ecu(Vector2(0.0, y - 4.0), minf(1.0, e.guard / GARDE_FONDU))
	if e.stun > 0.0:
		_etoiles(Vector2(0.0, y - 5.0), maxf(12.0, r * 0.6))
		y -= 12.0
	if elite:
		p.texte(Vector2(0.0, y - 3.0), String(Couleurs.ELITE_NAMES[e.eliteMod]).to_upper(), 11, Couleurs.ELITE_COLORS[e.eliteMod])
		y -= 17.0
	if entites.gardes.has(e.id):
		_chevron(Vector2(0.0, y - 3.0))

## Protégé par un porte-étendard (il ne prend qu'une part des dégâts) : chevron violet, la couleur
## de l'aura de l'étendard et du fil qui l'y relie.
func _chevron(pointe: Vector2) -> void:
	var bat := 1.5 * sin(temps() * 5.0)
	var pts := PackedVector2Array([pointe + Vector2(-7.0, 1.0 + bat), pointe + Vector2(0.0, -6.0 + bat), pointe + Vector2(7.0, 1.0 + bat)])
	p.filet(pts, NOIR, 6.0)
	p.filet(pts, PAL.summon, 3.0)

func _barre_vie(e: Dictionary, y: float, largeur: float) -> void:
	var x := -largeur * 0.5
	draw_rect(Rect2(x - 1.5, y - 6.5, largeur + 3.0, 8.0), Pinceau.ENCRE)
	draw_rect(Rect2(x, y - 5.0, largeur, 5.0), PAL.hpBack)
	var plein: float = largeur * clampf(e.hp / e.maxHp, 0.0, 1.0)
	var teinte: Color = Couleurs.ELITE_COLORS[e.eliteMod] if D6Js.truthy(e.eliteMod) else PAL.hpBar
	draw_rect(Rect2(x, y - 5.0, plein, 5.0), teinte)
	draw_rect(Rect2(x, y - 5.0, plein, 1.5), teinte.lightened(0.35))

func _etoiles(centre: Vector2, rayon: float) -> void:
	for i in 3:
		var a := temps() * 6.0 + i * TAU / 3.0
		p.etoile(centre + Vector2(cos(a) * rayon, sin(a) * 4.0), 5.0, PAL.crit, a * 0.6)

func _ecu(centre: Vector2, force: float) -> void:
	var pts := PackedVector2Array()
	for v: Vector2 in [Vector2(-6, -6), Vector2(6, -6), Vector2(6, 0), Vector2(4.2, 4.6), Vector2(0, 8), Vector2(-4.2, 4.6), Vector2(-6, 0)]:
		pts.append(centre + v)
	p.forme(pts, Color(ECU, force), Color(NOIR, 0.85 * force), 2.0)
	p.ligne(centre + Vector2(0.0, -4.0), centre + Vector2(0.0, 5.0), Color(0.35, 0.35, 0.42, force), 1.5)

# ------------------------------------------------------------------ champions

func _pouvoirs_elite(e: Dictionary, g: Dictionary, vers_heros: Vector2) -> void:
	var mods: Dictionary = g.tuning.elite.mods
	if nombre(e, "leechFlash") > 0.0 and mods.has("vampirique"):
		_drain(e, vers_heros, minf(1.0, e.leechFlash / mods.vampirique.flash))
	var phase = e.get("modPhase")
	var duree := nombre(e, "modDur")
	if phase == "warn" and duree > 0.0:
		_annonce_bulle(e.r, minf(1.0, 1.0 - e.modT / duree))
	if nombre(e, "invuln") > 0.0 and not D6Js.truthy(e.boss):
		_bulle(e.r + 12.0)
	if phase == "channel" and duree > 0.0 and mods.has("invocateur"):
		_canalisation(mods.invocateur.channelRadius, minf(1.0, 1.0 - e.modT / duree))

## Vampirique : le sang coule du héros vers l'élite, en tirets.
func _drain(e: Dictionary, vers_heros: Vector2, k: float) -> void:
	var teinte := Color(PAL.eliteVampirique, 0.9 * k)
	var longueur := vers_heros.length()
	var dir := vers_heros / maxf(1.0, longueur)
	var d := longueur - fmod(temps() * 120.0, 16.0)
	while d > 10.0:
		draw_line(dir * d, dir * (d - 10.0), teinte, 2.0 + 4.0 * k, true)
		d -= 16.0
	p.lueur(Vector2.ZERO, e.r * 2.4, PAL.eliteVampirique, 0.55 * k)

## Bouclier, annonce : un anneau doré en tirets se resserre ; il ne blesse pas.
func _annonce_bulle(r: float, k: float) -> void:
	p.pointille(Vector2.ZERO, r + 22.0 - 10.0 * k, Color(PAL.eliteBouclier, 0.4 + 0.5 * k), 2.5, 10.0, temps() * 2.0, 0.5)

## Bouclier, actif : bulle d'immunité (rien ne le blesse), avec son reflet.
func _bulle(rayon: float) -> void:
	p.disque(Vector2.ZERO, rayon, BULLE, PAL.eliteBouclier, 3.0)
	var balance := sin(temps() * 3.0) * 0.2
	p.arc(Vector2.ZERO, rayon - 5.0, -2.4 + balance, -1.4 + balance, Color(1.0, 1.0, 1.0, 0.6), 2.0)

## Invocateur : cercle violet inoffensif qui se remplit ; à son terme, des renforts arrivent.
func _canalisation(rayon: float, k: float) -> void:
	p.disque(Vector2.ZERO, rayon, Color(PAL.summon, 0.08 + 0.1 * k), Pinceau.SANS)
	p.pointille(Vector2.ZERO, rayon, Color(PAL.summon, 0.7), 2.0, 12.0, -temps() * 1.5, 0.5)
	p.arc(Vector2.ZERO, rayon + 5.0, -PI * 0.5, -PI * 0.5 + TAU * k, PAL.summon, 3.0)
