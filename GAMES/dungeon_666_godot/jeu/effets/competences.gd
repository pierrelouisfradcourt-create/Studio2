extends RefCounted
## Effets des COMPÉTENCES NEUVES (combat V3, étape 4), rangés à part de effets.gd qui les branche
## dans sa table. Présentation pure : chaque fonction traduit UN événement de simulation en formes,
## particules, textes et secousses — avec ce que la vue Effets a déjà.
##   Revenant     parryStart, parry, parryEnd (Contre-taille), marked (Stigmate), sillageEnd
##   Bourreau     fissure (Faille), axeTurn, axeCatch (Hache du supplice), guardStart, guardBlock, guardEnd
##   Chasseresse  marked, markJump (Marque de la proie), traitShot (Trait de Nemrod)
## Les souffles (Stigmate, braises, contrecoup, leurre piégé) passent par l'événement `explode` de
## effets.gd, le leurre par les événements d'alliés d'ultimes.gd, les impulsions par `kitPulse`.
## Teintes : celles du héros, FROIDES (cyan, écume, blanc), jamais le rouge des dangers ; la marque
## du Stigmate est de braise claire (presque blanche), celle de la proie est cyan.

const Couleurs = preload("res://jeu/theme/couleurs.gd")
const PAL: Dictionary = Couleurs.PAL

const BRAISE_CLAIRE := Color("#ffd9a0")
const ECUME := Color("#e8fbff")
const GIVRE := Color("#bff8ff")
const ARDOISE := Color("#4a5a64")
const POUSSIERE := Color("#5a4a52")
const PAS_FISSURE := 60.0 # u entre deux gerbes de gravats le long de la fissure

## Les effets de ce fichier, à ajouter à la table de la vue : type d'événement -> fonction.
static func table(fx: Node) -> Dictionary:
	return {
		"parryStart": _garde_levee.bind(fx), "parry": _parade.bind(fx), "parryEnd": _garde_baissee.bind(fx),
		"marked": _marque.bind(fx), "markJump": _saut_de_marque.bind(fx), "sillageEnd": _fin_sillage.bind(fx),
		"fissure": _fissure.bind(fx), "axeTurn": _demi_tour.bind(fx), "axeCatch": _hache_rattrapee.bind(fx),
		"guardStart": _bouclier_leve.bind(fx), "guardBlock": _bouclier_touche.bind(fx), "guardEnd": _bouclier_baisse.bind(fx),
		"traitShot": _trait.bind(fx),
	}

# ---------------------------------------------------------------- Revenant

## Contre-taille : la taillade part, la garde se lève (un anneau clair se resserre sur lui).
static func _garde_levee(ev: Dictionary, _g: Dictionary, fx: Node) -> void:
	fx.formes.anneau(ev.x, ev.y, ev.get("range", 100.0), 26.0, ECUME, 3.0, 0.18)
	fx.particules.gerbe(ev.x, ev.y, 8, 320.0, 0.22, 2.5, ECUME, ev.get("angle", 0.0), ev.get("arc", 2.0), 7.0, true)

## Le coup est PARÉ : éclat blanc, le mot, puis l'onde de la riposte.
static func _parade(ev: Dictionary, _g: Dictionary, fx: Node) -> void:
	fx.textes.ajouter(ev.x, ev.y - 34.0, "PARÉ", ECUME, 17, 0.8)
	fx.formes.ajouter({"type": "choc", "x": ev.x, "y": ev.y, "r": ev.get("r", 120.0), "couleur": PAL.heroCape, "bord": ECUME, "vie": 0.28})
	var vers := atan2(ev.get("srcY", ev.y) - ev.y, ev.get("srcX", ev.x) - ev.x)
	fx.particules.gerbe(ev.x, ev.y, 16, 380.0, 0.3, 2.5, Color.WHITE, vers, 1.6, 7.0, true)
	fx._secouer(0.4)
	fx._zoom(0.04)

static func _garde_baissee(ev: Dictionary, _g: Dictionary, fx: Node) -> void:
	fx.formes.anneau(ev.x, ev.y, 26.0, 40.0, Color(ECUME, 0.6), 1.5, 0.2)

## Une marque se pose sur un ennemi : un anneau se referme sur lui (braise claire : Stigmate ; cyan : proie).
static func _marque(ev: Dictionary, _g: Dictionary, fx: Node) -> void:
	var proie: bool = ev.get("mark") == "proie"
	var teinte: Color = PAL.heroCape if proie else BRAISE_CLAIRE
	fx.formes.anneau(ev.x, ev.y, 70.0, 20.0, teinte, 3.0, 0.3)
	fx.particules.gerbe(ev.x, ev.y, 8, 160.0, 0.35, 2.5, teinte, 0.0, TAU, 6.0, true)
	fx.textes.ajouter(ev.x, ev.y - 40.0, "PROIE" if proie else "STIGMATE", teinte, 13, 0.7)

## « Curée » : la marque saute d'un mort au suivant.
static func _saut_de_marque(ev: Dictionary, _g: Dictionary, fx: Node) -> void:
	fx.formes.ajouter({"type": "eclair", "x0": ev.x0, "y0": ev.y0, "x1": ev.x1, "y1": ev.y1, "graine": randf() * 1000.0, "couleur": PAL.heroCape, "vie": 0.25})

static func _fin_sillage(ev: Dictionary, _g: Dictionary, fx: Node) -> void:
	fx.particules.gerbe(ev.x, ev.y, 8, 120.0, 0.45, 3.0, GIVRE, -PI / 2.0, 1.8, 4.0)

# ---------------------------------------------------------------- Bourreau

## Faille : la fissure court sur sa ligne — une lézarde noire aux lèvres de givre, des gravats, une secousse.
static func _fissure(ev: Dictionary, _g: Dictionary, fx: Node) -> void:
	var axe := Vector2.from_angle(ev.angle)
	fx.formes.ajouter({"type": "fissure", "x": ev.x, "y": ev.y, "angle": ev.angle, "longueur": ev.length, "largeur": ev.get("width", 60.0), "couleur": GIVRE, "graine": randf() * 1000.0, "vie": 0.7})
	var d := PAS_FISSURE * 0.5
	while d < ev.length:
		var p: Vector2 = Vector2(ev.x, ev.y) + axe * d
		fx.particules.gerbe(p.x, p.y, 5, 220.0, 0.45, 3.5, ARDOISE, -PI / 2.0, 2.2, 5.0)
		fx.particules.gerbe(p.x, p.y, 3, 160.0, 0.35, 2.5, ECUME, -PI / 2.0, 1.6, 6.0, true)
		d += PAS_FISSURE
	fx._secouer(0.45)
	fx._zoom(0.03)

static func _demi_tour(ev: Dictionary, _g: Dictionary, fx: Node) -> void:
	fx.formes.anneau(ev.x, ev.y, 6.0, 30.0, ECUME, 2.0, 0.18)
	fx.particules.gerbe(ev.x, ev.y, 5, 140.0, 0.25, 2.0, GIVRE, 0.0, TAU, 6.0, true)

static func _hache_rattrapee(ev: Dictionary, _g: Dictionary, fx: Node) -> void:
	fx.formes.anneau(ev.x, ev.y, 34.0, 14.0, PAL.heroCape, 2.5, 0.16)
	fx.particules.gerbe(ev.x, ev.y, 5, 110.0, 0.25, 2.0, ECUME, 0.0, TAU, 6.0, true)

## Garde de fer : le bouclier se lève (onde courte et épaisse), encaisse (étincelles vers le coup,
## le mot), se baisse.
static func _bouclier_leve(ev: Dictionary, _g: Dictionary, fx: Node) -> void:
	fx.formes.anneau(ev.x, ev.y, 14.0, 46.0, PAL.heroCape, 6.0, 0.25)
	fx.particules.gerbe(ev.x, ev.y, 10, 200.0, 0.35, 3.5, POUSSIERE, 0.0, TAU, 5.0)
	fx._secouer(0.25)

static func _bouclier_touche(ev: Dictionary, _g: Dictionary, fx: Node) -> void:
	var vers := atan2(ev.get("srcY", ev.y) - ev.y, ev.get("srcX", ev.x + 1.0) - ev.x)
	var p := Vector2(ev.x, ev.y) + Vector2.from_angle(vers) * 30.0
	fx.particules.gerbe(p.x, p.y, 10, 300.0, 0.25, 2.5, Color.WHITE, vers, 1.8, 7.0, true)
	fx.formes.anneau(p.x, p.y, 4.0, 26.0, ECUME, 2.5, 0.14)
	fx.textes.ajouter(ev.x, ev.y - 38.0, "BLOQUÉ", ECUME, 14, 0.6)
	fx._secouer(0.2)

static func _bouclier_baisse(ev: Dictionary, _g: Dictionary, fx: Node) -> void:
	fx.formes.anneau(ev.x, ev.y, 40.0, 54.0, Color(PAL.heroCape, 0.6), 2.0, 0.22)

# ---------------------------------------------------------------- Chasseresse

## Le Trait de Nemrod part : à pleine charge, une détonation froide à la bouche de l'arc.
static func _trait(ev: Dictionary, _g: Dictionary, fx: Node) -> void:
	var plein: bool = D6Js.truthy(ev.get("full"))
	var bouche := Vector2(ev.x, ev.y) + Vector2.from_angle(ev.angle) * 24.0
	fx.particules.gerbe(bouche.x, bouche.y, 18 if plein else 8, 460.0 if plein else 280.0, 0.3, 3.0, ECUME, ev.angle, 0.7, 6.0, true)
	fx.formes.anneau(bouche.x, bouche.y, 6.0, 44.0 if plein else 24.0, PAL.heroCape, 3.0, 0.18)
	if plein:
		fx._secouer(0.3)
		fx._recul(Vector2.from_angle(ev.angle + PI), 6.0)
