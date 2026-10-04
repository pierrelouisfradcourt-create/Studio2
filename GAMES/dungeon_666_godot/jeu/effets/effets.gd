extends Node2D
## La vue des EFFETS : tout ce qui fait qu'un coup « se sent » (pilier n°3 de la charte).
## Elle écoute `partie.evenements` et traduit chaque événement de simulation en particules,
## chiffres flottants, anneaux, ondes, éclairs, flashs d'écran, et en secousses demandées à la
## caméra du Monde. Présentation pure : elle ne modifie jamais la partie.
## Portage de la table HANDLERS de GAMES/dungeon_666/src/render/fx.mjs : une fonction par type
## d'événement, rangées dans `_table`. Les bannières de haut d'écran sont au HUD, le son à Son.
##
## Repère : celui du MONDE (cette vue est montée au-dessus du Monde et suit sa caméra) ; seul
## le nœud Ecran (CanvasLayer) couvre l'écran entier.

const Couleurs = preload("res://jeu/theme/couleurs.gd")
const Accords = preload("res://jeu/theme/accords.gd")
const Formes = preload("res://jeu/effets/formes.gd")
const Particules = preload("res://jeu/effets/particules.gd")
const Textes = preload("res://jeu/effets/textes.gd")
const Ecran = preload("res://jeu/effets/ecran.gd")
const PAL: Dictionary = Couleurs.PAL

## Teintes absentes de la palette par rôle : poussières et cendres (neutres), nuances des kits.
const TEINTES := {
	"poussiere": Color("#5a4a52"), "cendre": Color("#8a7a80"), "fumee": Color("#3a2a2e"),
	"gravats": Color("#4a3036"), "ombre": Color("#3a1c2c"), "ardoise": Color("#4a5a64"),
	"brulure": Color("#ff9a5a"), "braise": Color("#ffb36a"), "choc": Color("#ff6a3a"),
	"dash_nova": Color("#ff8a4a"), "harpon": Color("#cfe9f5"), "givre": Color("#bff8ff"),
	"ecume": Color("#e8fbff"), "brasier": Color("#3fb8ff"),
}
const COULEUR_ENNEMI := {"imp": "imp", "archer": "archer", "brute": "brute", "charger": "charger", "exploder": "exploder", "gardien": "boss"}
## Explosions du héros (bombe, piège, Bond, Brasier) : teintes FROIDES, jamais le rouge des dangers.
const SOUFFLE_HEROS := {
	"bombe": {"couleur": "lance", "secousse": 0.45, "zoom": 0.03},
	"piege": {"couleur": "heroCape", "secousse": 0.2, "zoom": 0.0},
	"bond": {"couleur": "lance", "secousse": 0.55, "zoom": 0.04},
	"brasier": {"couleur": "", "secousse": 0.15, "zoom": 0.0},
}
## Événements que fx.mjs ne traduit qu'en BANNIÈRE : ils sont au HUD, rien ici.
const AU_HUD: Array[String] = ["roomClear", "checkpoint"]

const ONDE_SUPER := 140.0 # u : onde de départ d'un Super à longue portée (Nuée)
const SOINS_DELAI := 0.4 # s entre deux chiffres de soin (les soins s'additionnent entre-temps)
# Éclats du fil de la lame au départ d'un coup de mêlée (la taillade est au calque du héros).
const ECLATS := 3
const ECLATS_FRAPPE := 6
const ECLATS_PORTEE := 0.7 # part de la portée où naissent les éclats
const BRAISES := 0.2 # probabilité par image d'une braise ambiante (0,35 sur le web)
# Secousse des ZONES qui frappent : pleine près du héros, faible loin ; un lot d'événements ne
# secoue pas plus qu'une zone ; au-delà de quelques zones par lot, leurs particules s'allègent.
const ZONE_SECOUSSE := 0.28
const ZONE_SECOUSSE_LOT := 0.28
const ZONE_PRES := 90.0
const ZONE_LOIN := 480.0
const ZONE_LOIN_PART := 0.2
const ZONE_SECOUSSE_PAR_GENRE := {"sinBlast": 0.06, "colosseEmber": 0.0}
const ZONE_PARTICULES_PAR_GENRE := {"colosseEmber": 0.25}
const ZONES_PLEINES_PAR_LOT := 3
const ZONE_PART_ALLEGEE := 0.3

@onready var formes: Formes = $Formes
@onready var particules: Particules = $Particules
@onready var textes: Textes = $Textes
@onready var ecran: Ecran = $Ecran/Flash

var app: Node
var partie: Node
## Braises ambiantes qui montent du bas de la salle (coupées par un réglage de qualité).
var braises := true

var _table := {}
var _soins := 0.0
var _soins_t := 0.0
var _zones_secousse := 0.0
var _zones_lot := 0

func _ready() -> void:
	_table = {
		"swing": _sur_swing, "dashEnd": _sur_fin_dash, "hit": _sur_coup, "kill": _sur_mort_ennemi,
		"dash": _sur_dash, "dodge": _sur_esquive, "playerHurt": _sur_heros_touche,
		"playerDeath": _sur_mort_heros, "hazardFire": _sur_zone, "explode": _sur_explosion,
		"hook": _sur_harpon, "kitPulse": _sur_pulsation, "deflect": _sur_parade,
		"skill": _sur_competence, "gadget": _sur_gadget, "super": _sur_super,
		"superTick": _sur_super_coup, "dashNova": _sur_dash_nova, "chain": _sur_chaine,
		"pickup": _sur_ramassage, "gold": _sur_or, "heal": _sur_soin, "souls": _sur_ames,
		"wallSlam": _sur_mur, "chargerWall": _sur_chargeur_mur, "spawn": _sur_apparition,
		"floorEnter": _sur_etage, "bossPhase": _sur_phase, "boonGain": _sur_benediction,
		"immune": _sur_invulnerable, "moveShort": _sur_geste_court, "moveLand": _sur_atterrissage,
	}

func brancher(p_app: Node, p_partie: Node) -> void:
	app = p_app
	partie = p_partie
	partie.evenements.connect(_sur_evenements)
	partie.partie_demarree.connect(effacer)

## Les types d'événements qui ont un effet ici (pour la vérification).
func types() -> Array:
	return _table.keys()

## Tout effacer : entrée dans un étage, nouvelle partie.
func effacer() -> void:
	particules.vider()
	formes.vider()
	textes.vider()
	ecran.vider()
	_soins = 0.0
	_soins_t = 0.0

func _sur_evenements(liste: Array) -> void:
	var g = partie.game
	if g == null:
		return
	_zones_secousse = 0.0
	_zones_lot = 0
	for ev in liste:
		var effet = _table.get(ev.get("type"))
		if effet != null:
			effet.call(ev, g)

func _process(delta: float) -> void:
	if partie == null or partie.game == null:
		return
	var g: Dictionary = partie.game
	if partie.en_pause or not (g.mode == "play" or g.mode == "dead"):
		return
	var dt := minf(0.1, delta)
	var p: Vector2 = partie.position_dessin(g.player, true)
	formes.heros = p
	formes.rayon_heros = g.player.r
	particules.avancer(dt)
	formes.avancer(dt)
	textes.avancer(dt)
	ecran.avancer(dt)
	_montrer_soins(dt, p)
	if braises and randf() < BRAISES and particules.n < particules.PLAFOND / 2:
		var salle: Dictionary = g.room
		particules.emettre(randf() * salle.w, salle.h + 10.0, (randf() - 0.5) * 20.0, -30.0 - randf() * 50.0, 4.0 + randf() * 3.0, 1.5 + randf() * 1.5, PAL.lava if randf() < 0.5 else TEINTES.braise, 0.05)

## Soins regroupés : un seul chiffre vert au lieu d'une pluie de « +1 ».
func _montrer_soins(dt: float, p: Vector2) -> void:
	_soins_t -= dt
	if _soins >= 1.0 and _soins_t <= 0.0:
		textes.ajouter(p.x, p.y - 30.0, "+" + D6Js.num_str(roundf(_soins)), PAL.heal, 14, 0.7)
		particules.gerbe(p.x, p.y, 5, 70.0, 0.5, 2.5, PAL.heal, -PI / 2.0, 1.6, 3.0, false, formes.rayon_heros)
		_soins = 0.0
		_soins_t = SOINS_DELAI

# ---------------------------------------------------------------- caméra du Monde

func _camera() -> Object:
	if app == null:
		return null
	var vues = app.get("vues")
	if not (vues is Dictionary) or not vues.has("monde") or not is_instance_valid(vues.monde):
		return null
	var cam = vues.monde.get("camera")
	return cam if cam is Object and is_instance_valid(cam) else null

func _secouer(force: float, du_heros: bool = false) -> void:
	var cam := _camera()
	if cam != null and cam.has_method("secouer"):
		cam.secouer(force, du_heros)

func _recul(dir: Vector2, force: float) -> void:
	var cam := _camera()
	if cam != null and cam.has_method("recul"):
		cam.recul(dir, force)

func _zoom(force: float) -> void:
	var cam := _camera()
	if cam != null and cam.has_method("coup_de_zoom"):
		cam.coup_de_zoom(force)

func _couleur_ennemi(genre) -> Color:
	return PAL[COULEUR_ENNEMI.get(genre, "imp")]

# ---------------------------------------------------------------- le héros frappe

func _sur_swing(ev: Dictionary, _g: Dictionary) -> void:
	var dir := Vector2.from_angle(ev.angle)
	if D6Js.truthy(ev.get("ranged")):
		# Arme à distance : éclat de départ du trait, pas de taillade.
		var lourd: bool = D6Js.truthy(ev.get("strike")) or ev.index > 0.0
		particules.gerbe(ev.x + dir.x * 20.0, ev.y + dir.y * 20.0, 7 if lourd else 4, 260.0, 0.18, 2.0, PAL.lance, ev.angle, 0.6, 8.0, true)
		_recul(-dir, 1.0)
		return
	# La taillade elle-même est dessinée par le calque du héros (jeu/monde/creatures/heros.gd) : elle
	# y suit la portée et l'ouverture RÉELLES du coup. Ici, seulement les éclats du fil de la lame.
	# (De même, la traînée du dash est celle de jeu/monde/entites.gd : une seule de chaque.)
	var frappe := D6Js.truthy(ev.get("strike"))
	var bout: Vector2 = Vector2(ev.x, ev.y) + dir * (ev.range * ECLATS_PORTEE)
	particules.gerbe(bout.x, bout.y, ECLATS_FRAPPE if frappe else ECLATS, 240.0, 0.16, 1.8, PAL.slashStrike if frappe else PAL.slash, ev.angle, minf(ev.arc, PI), 9.0, true)
	_recul(dir, 1.5)

func _sur_coup(ev: Dictionary, _g: Dictionary) -> void:
	var critique := D6Js.truthy(ev.get("crit"))
	var lourd: bool = ev.amount >= 20.0 or critique
	if ev.kind == "burn":
		particules.gerbe(ev.x, ev.y, 2, 60.0, 0.4, 2.5, PAL.lava, 0.0, TAU, 2.0)
		textes.ajouter_degats(ev.id, ev.x, ev.y - 18.0, ev.amount, TEINTES.brulure, 11, 0.5)
		return
	var dir := atan2(ev.dirY, ev.dirX)
	particules.gerbe(ev.x, ev.y, 12 if lourd else 7, 520.0 if lourd else 380.0, 0.28, 2.2, PAL.slash, dir, 1.4, 7.0, true)
	particules.gerbe(ev.x, ev.y, 9 if lourd else 5, 220.0, 0.45, 3.2, _couleur_ennemi(ev.get("enemy")), dir, 2.2, 4.0)
	formes.anneau(ev.x, ev.y, 6.0, 46.0 if lourd else 30.0, PAL.impactRing, 4.0 if lourd else 2.5, 0.14)
	if critique:
		textes.ajouter(ev.x, ev.y - 18.0, D6Js.num_str(ev.amount) + "!", PAL.crit, 21, 0.85)
	else:
		textes.ajouter_degats(ev.id, ev.x, ev.y - 18.0, ev.amount, PAL.text, 17 if lourd else 14, 0.6)
	_secousse_du_coup(ev, critique, lourd)

func _secousse_du_coup(ev: Dictionary, critique: bool, lourd: bool) -> void:
	var melee: bool = ev.kind == "melee" or ev.kind == "strike"
	var force: float = ev.get("shake", 0.0)
	if force <= 0.0:
		force = {"skill": 0.14, "gadget": 0.05, "super": 0.04}.get(ev.kind, 0.08)
	_secouer(force + 0.08 if critique else force, true)
	var dir := Vector2(ev.dirX, ev.dirY)
	if melee:
		_recul(dir, 5.0 if lourd else 3.0)
	elif ev.kind == "skill":
		_recul(dir, 4.0)
	if lourd and melee:
		_zoom(0.025)

func _sur_mort_ennemi(ev: Dictionary, _g: Dictionary) -> void:
	var couleur := _couleur_ennemi(ev.get("enemy"))
	var boss := D6Js.truthy(ev.get("boss"))
	var elite := D6Js.truthy(ev.get("elite"))
	var gros := 3.0 if boss else (1.8 if elite else 1.0)
	particules.gerbe(ev.x, ev.y, roundi(18.0 * gros), 360.0 * gros, 0.6, 3.5, couleur, 0.0, TAU, 3.5)
	particules.gerbe(ev.x, ev.y, roundi(10.0 * gros), 140.0, 1.1, 5.0, TEINTES.fumee, 0.0, TAU, 2.0)
	particules.gerbe(ev.x, ev.y, roundi(6.0 * gros), 260.0, 0.5, 2.0, PAL.lava, 0.0, TAU, 3.0, true)
	formes.anneau(ev.x, ev.y, 10.0, 70.0 * gros, couleur, 5.0, 0.25)
	formes.ajouter({"type": "mort", "x": ev.x, "y": ev.y, "r": ev.get("r", 14.0), "couleur": couleur, "vie": 0.22 * gros})
	_secouer(1.0 if boss else (0.5 if elite else 0.1), not boss and not elite)
	if boss:
		_zoom(0.12)
	elif elite:
		_zoom(0.04)

func _sur_chaine(ev: Dictionary, _g: Dictionary) -> void:
	formes.ajouter({"type": "eclair", "x0": ev.x0, "y0": ev.y0, "x1": ev.x1, "y1": ev.y1, "graine": randf() * 1000.0, "couleur": TEINTES.givre, "vie": 0.16})

func _sur_invulnerable(ev: Dictionary, _g: Dictionary) -> void:
	if not textes.affiche("INVULNÉRABLE", 0.4):
		textes.ajouter(ev.x, ev.y - 50.0, "INVULNÉRABLE", PAL.eliteBlinde, 13, 0.6)

# ---------------------------------------------------------------- le héros bouge

func _sur_dash(ev: Dictionary, _g: Dictionary) -> void:
	particules.gerbe(ev.x, ev.y, 8, 160.0, 0.35, 4.0, TEINTES.poussiere, atan2(-ev.dirY, -ev.dirX), 1.6, 5.0)
	formes.anneau(ev.x, ev.y, 8.0, 34.0, PAL.heroCape, 2.0, 0.16)

## Atterrissage du dash : un souffle de poussière au sol (sur le web, le héros s'écrase un instant).
func _sur_fin_dash(ev: Dictionary, _g: Dictionary) -> void:
	particules.gerbe(ev.x, ev.y, 4, 90.0, 0.25, 3.0, TEINTES.poussiere, 0.0, TAU, 6.0)

## Déplacement de classe RACCOURCI (l'arrivée tombait dans une rivière) ou fait sur place : on
## le VOIT — croix rouge sur l'arrivée refusée, barre au bord où le héros s'arrête, un mot bref.
func _sur_geste_court(ev: Dictionary, g: Dictionary) -> void:
	var bord := Vector2(ev.x + ev.dirX * ev.done, ev.y + ev.dirY * ev.done)
	var cible := Vector2(ev.x + ev.dirX * ev.reach, ev.y + ev.dirY * ev.reach)
	formes.ajouter({"type": "refus", "x": bord.x, "y": bord.y, "x1": cible.x, "y1": cible.y, "rayon": g.player.r, "vie": 0.55})
	textes.ajouter(bord.x, bord.y - g.player.r - 18.0, "TROP LOIN" if ev.done <= 1.0 else "AU BORD", PAL.danger, 14, 0.7)
	particules.gerbe(cible.x, cible.y, 6, 120.0, 0.3, 3.0, PAL.danger, 0.0, TAU, 6.0)

## Atterrissage du SAUT du Bourreau : une onde froide qui repousse (aucun dégât : pas de rouge),
## de la poussière, une petite secousse.
func _sur_atterrissage(ev: Dictionary, _g: Dictionary) -> void:
	formes.ajouter({"type": "choc", "x": ev.x, "y": ev.y, "r": ev.r, "couleur": PAL.heroCape, "bord": TEINTES.ecume, "vie": 0.26})
	particules.gerbe(ev.x, ev.y, 14, ev.r * 3.0, 0.4, 3.5, TEINTES.poussiere, 0.0, TAU, 5.0)
	particules.gerbe(ev.x, ev.y, 6, ev.r * 2.0, 0.5, 3.0, TEINTES.ardoise, 0.0, TAU, 4.0)
	_secouer(0.3)

func _sur_dash_nova(ev: Dictionary, _g: Dictionary) -> void:
	formes.anneau(ev.x, ev.y, 10.0, ev.r, TEINTES.dash_nova, 4.0, 0.22)

func _sur_esquive(ev: Dictionary, g: Dictionary) -> void:
	textes.ajouter(ev.x, ev.y - 30.0, "ESQUIVE", PAL.heroCape, 15, 0.7)
	particules.gerbe(ev.x, ev.y, 10, 200.0, 0.4, 2.0, PAL.heroCape, 0.0, TAU, 6.0, true, g.player.r)

func _sur_parade(ev: Dictionary, _g: Dictionary) -> void:
	particules.gerbe(ev.x, ev.y, 6, 260.0, 0.25, 2.0, Color.WHITE, 0.0, TAU, 8.0, true)
	formes.anneau(ev.x, ev.y, 4.0, 22.0, Color.WHITE, 2.0, 0.12)

# ---------------------------------------------------------------- le héros encaisse

func _sur_heros_touche(ev: Dictionary, g: Dictionary) -> void:
	textes.ajouter(ev.x, ev.y - g.player.r - 12.0, "-" + D6Js.num_str(ev.amount), PAL.heroHurt, 19, 0.8)
	particules.gerbe(ev.x, ev.y, 12, 260.0, 0.45, 3.0, PAL.heroHurt, 0.0, TAU, 4.0, false, g.player.r)
	ecran.blessure()
	_secouer(0.6)
	var d := Vector2(ev.x - ev.get("srcX", ev.x), ev.y - ev.get("srcY", ev.y))
	if d.length_squared() > 0.0:
		_recul(d.normalized(), 7.0)

func _sur_mort_heros(ev: Dictionary, _g: Dictionary) -> void:
	particules.gerbe(ev.x, ev.y, 40, 380.0, 1.2, 4.0, PAL.heroCape, 0.0, TAU, 2.0)
	formes.anneau(ev.x, ev.y, 10.0, 120.0, PAL.heroCape, 5.0, 0.4)
	ecran.blessure(true)
	_secouer(1.0)
	_zoom(0.12)

# ---------------------------------------------------------------- dangers

func _sur_zone(ev: Dictionary, g: Dictionary) -> void:
	_zones_lot += 1
	if ev.shape == "line":
		formes.ajouter({"type": "bande", "x": ev.x, "y": ev.y, "angle": ev.angle, "longueur": ev.length, "largeur": ev.width, "vie": 0.25})
	else:
		formes.ajouter({"type": "choc", "x": ev.x, "y": ev.y, "r": ev.r, "couleur": Couleurs.REWARD_COLORS.boon if ev.kind == "sinBlast" else TEINTES.choc, "vie": 0.32})
		if ev.kind == "bossSlam":
			_zoom(0.02)
		var part: float = ZONE_PARTICULES_PAR_GENRE.get(ev.kind, 1.0)
		if _zones_lot > ZONES_PLEINES_PAR_LOT:
			part *= ZONE_PART_ALLEGEE
		particules.gerbe(ev.x, ev.y, roundi(16.0 * part), ev.r * 3.0, 0.5, 4.0, TEINTES.gravats, 0.0, TAU, 4.0)
		particules.gerbe(ev.x, ev.y, roundi(10.0 * part), ev.r * 4.0, 0.35, 2.5, PAL.lava, 0.0, TAU, 5.0, true)
	var force := _secousse_de_zone(ev, g)
	if force > 0.0:
		_secouer(force)

## Distance du héros au bord de la zone qui frappe (0 dedans ; un anneau compte comme un disque).
func _ecart_zone(ev: Dictionary, g: Dictionary) -> float:
	var p: Dictionary = g.player
	if ev.shape == "line":
		return sqrt(D6Geo.point_band_dist2(p.x, p.y, ev.x, ev.y, ev.angle, ev.length, ev.width))
	var r = ev.get("r")
	return maxf(0.0, Vector2(p.x - ev.x, p.y - ev.y).length() - (r if r is float else 0.0))

func _secousse_de_zone(ev: Dictionary, g: Dictionary) -> float:
	var base: float = ZONE_SECOUSSE_PAR_GENRE.get(ev.kind, ZONE_SECOUSSE)
	if base <= 0.0:
		return 0.0
	var k := clampf((_ecart_zone(ev, g) - ZONE_PRES) / (ZONE_LOIN - ZONE_PRES), 0.0, 1.0)
	var force := minf(base * (1.0 - k * (1.0 - ZONE_LOIN_PART)), ZONE_SECOUSSE_LOT - _zones_secousse)
	if force <= 0.0:
		return 0.0
	_zones_secousse += force
	return force

func _sur_explosion(ev: Dictionary, _g: Dictionary) -> void:
	if not D6Js.truthy(ev.get("hero")):
		particules.gerbe(ev.x, ev.y, 26, 420.0, 0.6, 4.0, PAL.exploder, 0.0, TAU, 3.5)
		formes.anneau(ev.x, ev.y, 10.0, ev.get("r", 60.0), PAL.exploder, 4.0, 0.22)
		return
	# Bombe, piège, atterrissage du Bond, pot du Brasier : onde froide du héros.
	var style: Dictionary = SOUFFLE_HEROS.get(ev.get("kind"), SOUFFLE_HEROS.bombe)
	var couleur: Color = TEINTES.brasier if style.couleur == "" else PAL[style.couleur]
	formes.ajouter({"type": "choc", "x": ev.x, "y": ev.y, "r": ev.r, "couleur": couleur, "bord": TEINTES.ecume, "vie": 0.3})
	particules.gerbe(ev.x, ev.y, 18, ev.r * 3.5, 0.45, 3.0, couleur, 0.0, TAU, 5.0, true)
	particules.gerbe(ev.x, ev.y, 10, ev.r * 2.0, 0.6, 4.0, TEINTES.ardoise, 0.0, TAU, 4.0)
	_secouer(style.secousse)
	if style.zoom > 0.0:
		_zoom(style.zoom)

func _sur_mur(ev: Dictionary, _g: Dictionary) -> void:
	particules.gerbe(ev.x, ev.y, 14, 300.0, 0.4, 3.5, TEINTES.cendre, 0.0, TAU, 5.0)
	textes.ajouter(ev.x, ev.y - 30.0, "IMPACT", TEINTES.braise, 14, 0.6)
	_secouer(0.25)

func _sur_chargeur_mur(ev: Dictionary, _g: Dictionary) -> void:
	particules.gerbe(ev.x, ev.y, 20, 340.0, 0.5, 4.0, TEINTES.cendre, 0.0, TAU, 4.0)
	textes.ajouter(ev.x, ev.y - 34.0, "SONNÉ", PAL.crit, 15, 0.9)
	_secouer(0.6 if D6Js.truthy(ev.get("boss")) else 0.35)

func _sur_apparition(ev: Dictionary, _g: Dictionary) -> void:
	var boss := D6Js.truthy(ev.get("boss"))
	particules.gerbe(ev.x, ev.y, 40 if boss else 10, 300.0 if boss else 120.0, 0.6, 4.0, TEINTES.ombre, 0.0, TAU, 3.0)

func _sur_phase(ev: Dictionary, _g: Dictionary) -> void:
	formes.anneau(ev.x, ev.y, 20.0, 220.0, PAL.danger, 6.0, 0.45)
	_secouer(0.7)
	ecran.voile(0.6, PAL.danger.lightened(0.35))

# ---------------------------------------------------------------- kits du héros

func _sur_harpon(ev: Dictionary, _g: Dictionary) -> void:
	formes.ajouter({"type": "eclair", "x0": ev.x0, "y0": ev.y0, "x1": ev.x1, "y1": ev.y1, "graine": randf() * 1000.0, "couleur": TEINTES.harpon, "vie": 0.2})
	textes.ajouter(ev.x1, ev.y1 - 30.0, "ACCROCHÉ" if D6Js.truthy(ev.get("boss")) else "HARPONNÉ", TEINTES.harpon, 13, 0.6)
	_secouer(0.15)

func _sur_pulsation(ev: Dictionary, _g: Dictionary) -> void:
	formes.anneau(ev.x, ev.y, 12.0, ev.r, TEINTES.givre, 3.0, 0.3)

func _sur_competence(ev: Dictionary, g: Dictionary) -> void:
	var genre = ev.get("skill", "")
	if genre == "bond":
		# Envol du Bond : poussière au décollage.
		particules.gerbe(ev.x, ev.y, 14, 200.0, 0.4, 3.5, TEINTES.poussiere, 0.0, TAU, 5.0)
		formes.anneau(ev.x, ev.y, 10.0, 50.0, PAL.heroCape, 3.0, 0.2)
		_secouer(0.12)
		return
	var p: Dictionary = g.player
	var bouche := Vector2(p.x, p.y) + Vector2.from_angle(ev.angle) * 22.0
	particules.gerbe(bouche.x, bouche.y, 10, 300.0, 0.25, 2.5, PAL.lance, ev.angle, 1.4 if genre == "volee" else 0.9, 6.0, true)
	_secouer(0.1)

func _sur_gadget(ev: Dictionary, _g: Dictionary) -> void:
	var genre = ev.get("gadget", "nova")
	if genre == "cri":
		# Cri du bourreau : onde large et froide, sans souffle de cendres (il ne repousse pas).
		formes.anneau(ev.x, ev.y, 20.0, ev.r, PAL.heroCape, 6.0, 0.35)
		formes.anneau(ev.x, ev.y, 10.0, ev.r * 0.7, TEINTES.ecume, 3.0, 0.25)
		_secouer(0.35)
		_zoom(0.02)
	elif genre != "nova":
		# Bombe lancée, piège ou totem posé : petit anneau froid (l'effet vient à l'impact).
		formes.anneau(ev.x, ev.y, 8.0, 40.0, PAL.heroCape, 2.5, 0.2)
		particules.gerbe(ev.x, ev.y, 6, 140.0, 0.3, 2.5, PAL.lance, 0.0, TAU, 6.0)
	else:
		formes.ajouter({"type": "nova", "x": ev.x, "y": ev.y, "r": ev.r, "couleur": TEINTES.braise, "vie": 0.35})
		particules.gerbe(ev.x, ev.y, 30, ev.r * 4.0, 0.5, 3.5, TEINTES.cendre, 0.0, TAU, 5.0)
		_secouer(0.4)
		_zoom(0.03)

func _sur_super(ev: Dictionary, _g: Dictionary) -> void:
	# Onde de départ : la Nuée tire loin, mais son départ reste autour du héros.
	var r: float = ONDE_SUPER if ev.get("super") == "nuee" else ev.r * 1.3
	formes.ajouter({"type": "nova", "x": ev.x, "y": ev.y, "r": r, "couleur": PAL.superBar, "vie": 0.4})
	_secouer(0.5)
	ecran.voile(0.5)

func _sur_super_coup(ev: Dictionary, _g: Dictionary) -> void:
	var genre = ev.get("super", "")
	if genre == "sentence":
		_sur_sentence(ev)
	elif genre == "nuee":
		var dir := Vector2.from_angle(ev.angle)
		particules.gerbe(ev.x + dir.x * 18.0, ev.y + dir.y * 18.0, 3, 240.0, 0.15, 2.0, PAL.superBar, ev.angle, 0.5, 8.0, true)
	else:
		# Colère : le tourbillon lui-même est dessiné sous le héros, à sa portée réelle (monde/creatures/heros.gd).
		particules.gerbe(ev.x, ev.y, 4, ev.r * 3.0, 0.3, 2.5, PAL.superBar, 0.0, TAU, 6.0, true)

## Exécution : immense taillade dorée (le 3e coup fait le tour complet).
func _sur_sentence(ev: Dictionary) -> void:
	var tour: bool = ev.arc >= TAU - 1e-3
	formes.ajouter({"type": "taillade", "angle": ev.angle, "arc": ev.arc, "portee": ev.r, "indice": 1.0 if ev.get("step") == 2.0 else 0.0, "frappe": true, "couleur": PAL.superBar, "vie": 0.22})
	var dir: Vector2 = Vector2.from_angle(ev.angle) * (ev.r * 0.6)
	particules.gerbe(ev.x + dir.x, ev.y + dir.y, 14, 420.0, 0.35, 3.0, PAL.superBar, ev.angle, minf(TAU, ev.arc), 6.0, true)
	_secouer(0.7 if tour else 0.4)
	_zoom(0.06 if tour else 0.025)

# ---------------------------------------------------------------- butin, soins, étage

func _sur_ramassage(ev: Dictionary, _g: Dictionary) -> void:
	var est_or: bool = ev.kind == "gold"
	if est_or:
		textes.ajouter(ev.x, ev.y - 8.0, "+" + D6Js.num_str(ev.amount), PAL.gold, 12, 0.5)
	particules.gerbe(ev.x, ev.y, 4, 90.0, 0.3, 2.0, PAL.gold if est_or else PAL.heal, 0.0, TAU, 6.0)

func _sur_or(ev: Dictionary, _g: Dictionary) -> void:
	textes.ajouter(ev.x, ev.y - 20.0, "+%s or" % D6Js.num_str(ev.amount), PAL.gold, 12, 0.6)

func _sur_soin(ev: Dictionary, _g: Dictionary) -> void:
	_soins += ev.amount

## Âmes d'un élite (absent de fx.mjs, où seul le compteur du HUD bouge).
func _sur_ames(ev: Dictionary, _g: Dictionary) -> void:
	textes.ajouter(ev.x, ev.y - 36.0, "+" + Accords.compte(ev.amount, "Âme", "Âmes"), PAL.lance, 13, 0.9)

func _sur_benediction(_ev: Dictionary, _g: Dictionary) -> void:
	ecran.voile(0.35)

func _sur_etage(_ev: Dictionary, _g: Dictionary) -> void:
	effacer()
